#!/bin/bash
# Claude setup script: makes ~/Developer/ai (Jose's "ai" repo: skills, scheduled task prompts,
# local MCP servers, standing instructions) the default folder for Claude on this Mac.
#   1. Clones the repo (private, needs `gh auth login`) and hardens the clone with its scripts/setup.sh.
#   2. ~/.claude/CLAUDE.md imports the repo's AGENTS.md, so every Claude Code session starts
#      with the standing instructions, whatever project it runs in.
#   3. ~/.claude/settings.json lists the repo under permissions.additionalDirectories, so Claude Code
#      can read and edit it from any project without prompts.
#   4. The repo is added as a local plugin marketplace (barrios-ai) and the jose-skills plugin is
#      installed from it. A local marketplace is read in place: skills load straight from the
#      working copy, so a git pull updates them.
#   5. An `ai` shell function starts Claude Code inside the repo from anywhere.
# Designed to be idempotent: safe to run multiple times without side effects.
# When an error occurs and Claude Code is available, it automatically asks Claude to debug.
#
# Not covered here, done once per Mac in the Claude desktop app: the app's user folder (set it to
# ~/Developer/ai) and the folders attached to scheduled tasks that need this computer.
# See ~/Developer/ai/documents/claude-setup.md.

# Treat unset variables as errors (-u) and ensure piped commands propagate failures (-o pipefail).
# We do NOT use -e (errexit) because we handle errors via an ERR trap instead,
# which lets the script continue after Claude provides debugging guidance.
set -uo pipefail

# Counter to track how many verification tests fail during setup.
FAIL_COUNT=0

# Path to the script itself, used to provide context to Claude when debugging errors.
SELF_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

###############################
#   CONFIGURATION             #
###############################

# GitHub owner/repo of the ai repo (private).
AI_REPO="JoseBarrios/ai"

# Where the repo lives on every Mac. Other tools depend on this exact path (Claude desktop,
# launchd, Hermes, the hybrid-memory MCP server), so it is not configurable.
AI_HOME="$HOME/Developer/ai"

# Claude Code's user-level configuration.
CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"

# The import line added to ~/.claude/CLAUDE.md. Written with ~ so the file is identical on every Mac.
IMPORT_LINE="@~/Developer/ai/AGENTS.md"

# Shell function added to ~/.zshrc. The subshell keeps the caller's working directory.
AI_FUNCTION='ai() { (cd "$HOME/Developer/ai" && claude "$@"); }'
ZSHRC="$HOME/.zshrc"

###############################
#   ERROR HANDLING            #
###############################

# Automatic error handler, triggered on any command failure.
# Captures the failed command, exit code, and line number, then asks Claude to debug.
# The script does NOT exit: it logs the error and continues so the user can review.
function on_error {
    local exit_code=$?
    local line_number=$1
    local failed_command="${BASH_COMMAND}"

    echo ""
    echo "  [ERROR] Command failed on line $line_number (exit code $exit_code)"
    echo "  Failed command: $failed_command"
    FAIL_COUNT=$((FAIL_COUNT + 1))

    # If Claude Code is available, automatically ask it to diagnose the failure.
    if command -v claude &>/dev/null; then
        echo "  Asking Claude to diagnose..."
        echo ""
        # Use --print for non-interactive single-shot output.
        claude --print "A Claude setup script on macOS encountered an error. Help me debug it.

Script: $SELF_SCRIPT
Line $line_number failed with exit code $exit_code.
Failed command: $failed_command

System info:
- macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')
- Architecture: $(uname -m)

Provide a concise diagnosis and a fix. Do not rewrite the entire script." 2>/dev/null || \
            echo "  (Claude could not be reached, debug manually)"
        echo ""
    else
        echo "  Claude Code is not yet installed, install it to enable auto-debugging."
    fi
}

# Register the ERR trap. It fires on any command that returns a non-zero exit code.
# IMPORTANT: This does NOT cause the script to exit, it just calls on_error and continues.
trap 'on_error $LINENO' ERR

###############################
#   VERIFICATION FUNCTIONS    #
###############################

# Verify that a directory exists on disk.
# Usage: verify_dir <path>
function verify_dir {
    if [ -d "$1" ]; then
        echo "  [PASS] $1 exists"
    else
        echo "  [FAIL] $1 does NOT exist"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Verify that a regular file exists on disk.
# Usage: verify_file <path>
function verify_file {
    if [ -f "$1" ]; then
        echo "  [PASS] $1 exists"
    else
        echo "  [FAIL] $1 does NOT exist"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Verify that a specific line exists verbatim in a file.
# Usage: verify_line_in_file <line> <file_path>
function verify_line_in_file {
    # -q = quiet, -x = match whole line, -F = fixed string (no regex).
    if grep -qxF "$1" "$2" 2>/dev/null; then
        echo "  [PASS] '$1' found in $2"
    else
        echo "  [FAIL] '$1' NOT found in $2"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Verify that a string appears anywhere in a file (for JSON values, which carry indentation and commas).
# Usage: verify_string_in_file <string> <file_path>
function verify_string_in_file {
    if grep -qF "$1" "$2" 2>/dev/null; then
        echo "  [PASS] '$1' found in $2"
    else
        echo "  [FAIL] '$1' NOT found in $2"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

###########################
#   CLONE THE AI REPO     #
###########################
echo "==> Cloning the ai repo to $AI_HOME..."

# The parent directory must exist before cloning. -p is idempotent.
mkdir -p "$HOME/Developer"

if [ -d "$AI_HOME/.git" ]; then
    # Already cloned. Keep the working copy as it is: pulling is the hourly sync task's job.
    echo "  [PASS] $AI_HOME is already a git clone"
elif [ -e "$AI_HOME" ]; then
    # Something else is in the way. Never delete or overwrite it.
    echo "  [FAIL] $AI_HOME exists but is not a git clone. Move it aside and re-run."
    FAIL_COUNT=$((FAIL_COUNT + 1))
elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
    # gh clones with its stored login and the protocol from `gh config get git_protocol`.
    gh repo clone "$AI_REPO" "$AI_HOME"
else
    echo "  [SKIP] gh is not signed in and the repo is private. Run 'gh auth login', then re-run this script."
fi

# Test: Verify the clone is in place.
verify_dir "$AI_HOME/.git"

###########################
#   HARDEN THE CLONE      #
###########################
# The repo's own setup script turns on its secret-scanning hooks, pins the commit identity
# to github@barrios.io and enables object checks. Safe to re-run.
echo "==> Hardening the clone (hooks, pinned identity, object checks)..."

if [ -f "$AI_HOME/scripts/setup.sh" ]; then
    # Subshell so the cd does not change the working directory for the rest of this script.
    (cd "$AI_HOME" && sh scripts/setup.sh)
    # Test: Verify the hooks are wired up (set by scripts/setup.sh).
    if [ "$(git -C "$AI_HOME" config core.hooksPath 2>/dev/null)" = "scripts/hooks" ]; then
        echo "  [PASS] git hooks are on"
    else
        echo "  [FAIL] git core.hooksPath is not scripts/hooks"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  [SKIP] $AI_HOME/scripts/setup.sh not found (clone missing or incomplete)"
fi

###########################
#   STANDING INSTRUCTIONS #
###########################
# ~/.claude/CLAUDE.md is loaded by every Claude Code session on this Mac. Importing the repo's
# AGENTS.md (vendor-neutral, tracked in git) makes the standing instructions follow the repo.
# User-scope imports load without an approval dialog in Claude Code. In Claude desktop (Cowork)
# sessions the import only loads when the session folder is the repo itself.
echo "==> Importing the repo's standing instructions into Claude Code..."

mkdir -p "$CLAUDE_DIR"

if grep -qxF "$IMPORT_LINE" "$CLAUDE_MD" 2>/dev/null; then
    echo "  [PASS] $CLAUDE_MD already imports AGENTS.md"
else
    # Append only. Never overwrite whatever else the user keeps in the user-level CLAUDE.md.
    {
        if [ -s "$CLAUDE_MD" ]; then echo ""; fi
        echo "# Standing instructions, kept in the ai repo (added by setup-os)"
        echo "$IMPORT_LINE"
    } >> "$CLAUDE_MD"
fi

# Test: Verify the import line is present.
verify_line_in_file "$IMPORT_LINE" "$CLAUDE_MD"

###########################
#   FILE ACCESS           #
###########################
# permissions.additionalDirectories in the user settings gives Claude Code read access to the
# repo from any project (edits follow the session's permission mode). It grants file access only;
# the repo's instructions come from the import above and its skills from the plugin below.
echo "==> Granting Claude Code file access to the repo from any project..."

if command -v python3 &>/dev/null; then
    # Merge into the existing JSON rather than overwriting it. Malformed JSON stops here so nothing is lost.
    python3 - "$CLAUDE_SETTINGS" "$AI_HOME" <<'PY'
import json, os, sys

path, ai_home = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(path):
    with open(path) as f:
        text = f.read()
    if text.strip():
        settings = json.loads(text)
perms = settings.setdefault("permissions", {})
dirs = perms.setdefault("additionalDirectories", [])
if ai_home in dirs:
    print("  [PASS] %s already in permissions.additionalDirectories" % ai_home)
else:
    dirs.append(ai_home)
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("  Added %s to permissions.additionalDirectories" % ai_home)
PY
else
    echo "  [SKIP] python3 not found. Add \"$AI_HOME\" to permissions.additionalDirectories in $CLAUDE_SETTINGS by hand."
fi

# Test: Verify the path is in the settings file.
verify_string_in_file "\"$AI_HOME\"" "$CLAUDE_SETTINGS"

###########################
#   SKILLS PLUGIN         #
###########################
# The repo root is a plugin marketplace (barrios-ai) whose jose-skills plugin is the skills/ folder.
# Added as a local path, the marketplace is read in place, so the skills are the working copy.
echo "==> Installing the jose-skills plugin from the repo..."

if ! command -v claude &>/dev/null; then
    echo "  [SKIP] claude is not installed. Install Claude Code and re-run."
elif [ ! -f "$AI_HOME/.claude-plugin/marketplace.json" ]; then
    echo "  [SKIP] $AI_HOME/.claude-plugin/marketplace.json not found (clone missing or incomplete)"
else
    # Idempotent: a marketplace named barrios-ai that is already added (from any source) is kept.
    if claude plugin marketplace list 2>/dev/null | grep -q "barrios-ai"; then
        echo "  [PASS] barrios-ai marketplace already added"
    else
        claude plugin marketplace add "$AI_HOME"
    fi

    if claude plugin list 2>/dev/null | grep -q "jose-skills"; then
        echo "  [PASS] jose-skills plugin already installed"
    else
        claude plugin install jose-skills@barrios-ai
    fi

    # Test: Verify the plugin shows up as installed.
    if claude plugin list 2>/dev/null | grep -q "jose-skills"; then
        echo "  [PASS] jose-skills is installed"
    else
        echo "  [FAIL] jose-skills is NOT installed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

###########################
#   SHELL COMMAND         #
###########################
# `ai` starts Claude Code inside the repo from any directory; extra arguments pass through
# (for example `ai --continue`). The subshell keeps the caller's working directory.
echo "==> Adding the 'ai' shell command..."

# The file may not exist yet on a fresh Mac. touch is idempotent.
touch "$ZSHRC"

# grep -qxF prevents adding the function if it is already present (idempotent).
grep -qxF "$AI_FUNCTION" "$ZSHRC" || \
    printf '\n# Start Claude Code in the ai repo from anywhere (added by setup-os)\n%s\n' "$AI_FUNCTION" >> "$ZSHRC"

# Test: Verify the function line is present.
verify_line_in_file "$AI_FUNCTION" "$ZSHRC"

###########################
#   SUMMARY               #
###########################
# Print a final report of all verification tests.
echo ""
echo "==============================="
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "  CLAUDE SETUP: ALL TESTS PASSED"
else
    echo "  CLAUDE SETUP: $FAIL_COUNT TEST(S) FAILED"
    echo "  Run 'claude' to debug failures."
fi
echo "==============================="
echo "  Open a new terminal (or 'source ~/.zshrc') to use the 'ai' command."
