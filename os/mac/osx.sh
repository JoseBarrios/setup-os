#!/bin/bash
# macOS setup script: installs dev tools, hardens security, and sets up Git,
# SSH and GitHub with keys that live in 1Password (never on disk).
# Idempotent: safe to run again. Every run ends with a pass/fail summary and a
# list of anything that still needs you.
# When a command fails and Claude Code is installed, Claude is asked to debug it.
#
# Written for the bash 3.2 that ships with macOS (/bin/bash).

# Treat unset variables as errors (-u) and make pipelines fail if any part fails.
# No -e (errexit): failures go to the ERR trap below, which logs them and keeps going.
set -uo pipefail

###############################
#   SETTINGS                  #
###############################

GIT_NAME="JoseBarrios"
GIT_EMAIL="github@barrios.io"
GIT_EDITOR="vim"

# 1Password vault for the SSH key and the FileVault recovery key.
# Empty means "Personal", "Private" or "Employee", whichever exists first. The 1Password SSH agent
# serves keys from that vault by default. Override with: OP_VAULT=Work ./osx.sh
OP_VAULT="${OP_VAULT:-}"

# LocalHostName is stable; `hostname -s` can change with the network (DHCP/DNS),
# which would create a second key on every new network.
HOST_SHORT="$( (scutil --get LocalHostName 2>/dev/null || hostname -s) | tr -cd 'A-Za-z0-9._-')"
SSH_KEY_TITLE="SSH Key - ${HOST_SHORT}"
FILEVAULT_ITEM_TITLE="FileVault Recovery Key - ${HOST_SHORT}"

OP_AGENT_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
OP_SSH_SIGN="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
ALLOWED_SIGNERS="$HOME/.config/git/allowed_signers"

NVM_VERSION="v0.40.8"

TERMINAL_PROFILE="Solarized Dark xterm-256color"
TERMINAL_FONT="HackNFM-Regular"
TERMINAL_FONT_SIZE=14

BREW_FORMULAE=(cmake vim git gh gnupg pinentry-mac pyenv yamllint ripgrep)

# FileVault personal recovery keys look like XXXX-XXXX-XXXX-XXXX-XXXX-XXXX.
FV_KEY_REGEX='^[A-Z0-9]{4}(-[A-Z0-9]{4}){5}$'

# Counters for the final summary.
FAIL_COUNT=0
MANUAL_NOTES=""

SELF_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Generated artifacts (vim bundles, solarized, etc.) live in ~/setup/, outside
# the git repository, so they are never committed by accident.
SETUP_HOME="$HOME/setup"

###############################
#   ERROR HANDLING            #
###############################

# Runs on any failed command at the top level of this script (functions report
# their own failures). Logs the failure, asks Claude to diagnose it if Claude
# Code is installed, then lets the script continue.
# shellcheck disable=SC2329  # invoked by the ERR trap
function on_error {
    local exit_code=$?
    local line_number=$1
    local failed_command="${BASH_COMMAND}"

    echo ""
    echo "  [ERROR] Command failed on line $line_number (exit code $exit_code)"
    echo "  Failed command: $failed_command"
    FAIL_COUNT=$((FAIL_COUNT + 1))

    if command -v claude &>/dev/null; then
        echo "  Asking Claude to diagnose..."
        echo ""
        claude --print "A macOS setup script encountered an error. Help me debug it.

Script: $SELF_SCRIPT
Line $line_number failed with exit code $exit_code.
Failed command: $failed_command

System info:
- macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')
- Architecture: $(uname -m)
- Brew prefix: ${BREW_PREFIX:-unknown}

Provide a concise diagnosis and a fix. Do not rewrite the entire script." 2>/dev/null || \
            echo "  (Claude could not be reached, debug manually)"
        echo ""
    else
        echo "  Claude Code is not installed yet, so no automatic debugging."
    fi
}

trap 'on_error $LINENO' ERR

###############################
#   HELPERS                   #
###############################

function pass { echo "  [PASS] $1"; }
function fail { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
function info { echo "  [INFO] $1"; }

# Something only the user can do. Shown now and again in the final summary.
function manual {
    echo "  [MANUAL] $1"
    MANUAL_NOTES="${MANUAL_NOTES}  - $1"$'\n'
}

# True when a person is at the keyboard (stdin and stdout are a terminal).
function is_interactive { [ -t 0 ] && [ -t 1 ]; }

function verify_cmd {
    if command -v "$1" &>/dev/null; then pass "$1 is installed"; else fail "$1 is NOT installed"; fi
}

function verify_dir {
    if [ -d "$1" ]; then pass "$1 exists"; else fail "$1 does NOT exist"; fi
}

function verify_file {
    if [ -f "$1" ]; then pass "$1 exists"; else fail "$1 does NOT exist"; fi
}

# Usage: verify_git_config <key> <expected_value>
function verify_git_config {
    local actual
    actual="$(git config --global "$1" 2>/dev/null || true)"
    if [ "$actual" = "$2" ]; then pass "git $1 = $2"; else fail "git $1 expected '$2', got '$actual'"; fi
}

# Usage: verify_line_in_file <line> <file_path>
function verify_line_in_file {
    if grep -qxF -- "$1" "$2" 2>/dev/null; then pass "'$1' found in $2"; else fail "'$1' NOT found in $2"; fi
}

# Usage: verify_defaults <domain> <key> <expected_value>
function verify_defaults {
    local actual
    actual="$(defaults read "$1" "$2" 2>/dev/null || true)"
    if [ "$actual" = "$3" ]; then pass "$1 $2 = $3"; else fail "$1 $2 expected '$3', got '$actual'"; fi
}

# Append a line to a file unless the file already has it verbatim.
# Usage: append_line <line> <file_path>
function append_line {
    touch "$2"
    if ! grep -qxF -- "$1" "$2"; then
        printf '%s\n' "$1" >> "$2"
    fi
}

# Run brew without pyenv shims on PATH, so Homebrew never picks up a
# pyenv-managed Python. (Aliases don't work in scripts, hence a function.)
function brew_safe {
    if command -v pyenv &>/dev/null; then
        env PATH="${PATH//$(pyenv root)\/shims:/}" brew "$@"
    else
        brew "$@"
    fi
}

# Pull the RecoveryKey value out of an fdesetup plist.
# Usage: extract_recovery_key <plist_text>
function extract_recovery_key {
    local key
    key="$(printf '%s' "$1" | plutil -extract RecoveryKey raw -o - - 2>/dev/null)" || key=""
    if [ -z "$key" ]; then
        # Fallback for older plutil, or stray text before the XML.
        key="$(printf '%s\n' "$1" | sed -n '/<key>RecoveryKey<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}')"
    fi
    printf '%s' "$key"
}

# Save a secret to 1Password as a Password item.
# The item JSON is built by printf (a shell builtin) and piped to `op`, so the
# secret never appears in any process's command-line arguments.
# Usage: op_store_password <title> <secret>
function op_store_password {
    printf '{"title":"%s","category":"PASSWORD","fields":[{"id":"password","type":"CONCEALED","purpose":"PASSWORD","label":"password","value":"%s"}]}' "$1" "$2" \
        | op item create --vault "$OP_VAULT" - >/dev/null
}

# Make sure the SSH public key is on GitHub at the given API endpoint.
# Usage: add_github_key <user/keys|user/ssh_signing_keys> <label>
function add_github_key {
    local endpoint="$1" label="$2" existing
    if ! existing="$(gh api "$endpoint" --paginate --jq '.[].key' 2>/dev/null)"; then
        fail "Could not list your GitHub $label keys"
        return 0
    fi
    if grep -qxF -- "$SSH_PUBKEY" <<< "$existing"; then
        pass "SSH key is on GitHub ($label)"
    elif gh api "$endpoint" -f title="$HOST_SHORT" -f key="$SSH_PUBKEY" >/dev/null; then
        pass "Added SSH key to GitHub ($label)"
    else
        fail "Could not add the SSH key to GitHub ($label)"
    fi
}

function terminal_has_profile {
    [ "$(osascript -e "tell application \"Terminal\" to exists settings set \"$TERMINAL_PROFILE\"" 2>/dev/null)" = "true" ]
}

###############################
#   PRECHECKS                 #
###############################

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This script is for macOS."
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo. It asks for sudo when it needs it."
    exit 1
fi

mkdir -p "$SETUP_HOME"

echo "==> Some steps need admin rights. Enter your password once now:"
sudo -v

###########################
#   HOMEBREW              #
###########################
echo "==> Installing Homebrew..."

# Check the install locations too: on a re-run brew may be installed but not on
# this script's PATH yet, since bash doesn't read ~/.zprofile.
if ! command -v brew &>/dev/null && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
    # Download to a temp file first so a cut-off download is never executed.
    BREW_INSTALLER="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$BREW_INSTALLER"
    /bin/bash "$BREW_INSTALLER"
    rm -f "$BREW_INSTALLER"
fi

# Apple Silicon installs to /opt/homebrew, Intel to /usr/local.
if [ -x /opt/homebrew/bin/brew ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

append_line "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"" "$HOME/.zprofile"
eval "$("${BREW_PREFIX}/bin/brew" shellenv)"

brew update
# Warnings from brew doctor are common and not fatal.
brew doctor || true

verify_cmd brew

###########################
#   OH MY ZSH             #
###########################
# Installed before anything else edits ~/.zshrc: the Oh My Zsh installer moves an
# existing ~/.zshrc aside and writes its own, which would drop earlier lines.
echo "==> Installing Oh My Zsh..."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    OMZ_INSTALLER="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"
    # --unattended: don't change the login shell or start a new zsh.
    sh "$OMZ_INSTALLER" --unattended
    rm -f "$OMZ_INSTALLER"
fi

verify_dir "$HOME/.oh-my-zsh"

###########################
#   CLAUDE CODE           #
###########################
# Installed early so it can debug failures in the rest of the script.
echo "==> Installing Claude Code..."

if ! command -v claude &>/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
    CLAUDE_INSTALLER="$(mktemp)"
    curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_INSTALLER"
    /bin/bash "$CLAUDE_INSTALLER"
    rm -f "$CLAUDE_INSTALLER"
fi

# shellcheck disable=SC2016  # literal line for ~/.zshrc
append_line 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc"
export PATH="$HOME/.local/bin:$PATH"

verify_cmd claude

###########################
#   1PASSWORD + CLI       #
###########################
# The SSH key, commit signing and the FileVault recovery key all depend on this.
echo "==> Installing 1Password and 1Password CLI..."

# The cask fails if the app was installed outside Homebrew (e.g. downloaded), so
# check for the app on disk first.
if [ ! -d "/Applications/1Password.app" ]; then
    brew_safe install --cask 1password
else
    echo "  1Password.app already installed"
fi

if ! command -v op &>/dev/null; then
    brew_safe install --cask 1password-cli
fi

verify_dir "/Applications/1Password.app"
verify_cmd op

OP_READY=false
if command -v op &>/dev/null; then
    # If the app integration is already on, this only asks you to approve in 1Password.
    if ! op whoami &>/dev/null && [ -n "$(op account list 2>/dev/null || true)" ]; then
        eval "$(op signin)" || true
    fi
    if ! op whoami &>/dev/null && is_interactive; then
        open -a "1Password" 2>/dev/null || true
        echo ""
        echo "  1Password CLI is not signed in. In the 1Password app:"
        echo "    1. Sign in to your account."
        echo "    2. Settings > Developer: turn on 'Integrate with 1Password CLI' and 'Use the SSH agent'."
        OP_REPLY=""
        read -r -p "  Press Enter when done (or type s to skip the 1Password steps): " OP_REPLY
        if [ "$OP_REPLY" != "s" ]; then
            # With app integration this just authorizes this terminal session.
            eval "$(op signin)" || true
        fi
    fi
    if op whoami &>/dev/null; then
        OP_READY=true
    fi
fi

if [ "$OP_READY" = true ]; then
    if [ -z "$OP_VAULT" ]; then
        for vault in Personal Private Employee; do
            if op vault get "$vault" &>/dev/null; then
                OP_VAULT="$vault"
                break
            fi
        done
    fi
    if [ -n "$OP_VAULT" ] && op vault get "$OP_VAULT" &>/dev/null; then
        pass "1Password CLI is signed in (vault: $OP_VAULT)"
    else
        fail "No 1Password vault named Personal, Private or Employee. Re-run with OP_VAULT=<vault name>."
        OP_READY=false
    fi
else
    manual "Sign in to 1Password and turn on Settings > Developer > 'Integrate with 1Password CLI', then re-run. SSH key, signing and recovery key steps were skipped."
fi

###########################
#   MACOS SECURITY        #
###########################
echo "==> Configuring disk encryption (FileVault)..."

# Older versions of this script left the recovery key in this file. If it's
# here, move it into 1Password and delete it.
FV_LEGACY_DIR="$HOME/.filevault"
FV_LEGACY_KEY="$FV_LEGACY_DIR/recovery_key.plist"

if [ -f "$FV_LEGACY_KEY" ]; then
    if [ "$OP_READY" = true ]; then
        FV_OLD_PLIST="$(cat "$FV_LEGACY_KEY" 2>/dev/null || sudo cat "$FV_LEGACY_KEY")"
        FV_KEY="$(extract_recovery_key "$FV_OLD_PLIST")"
        if [[ $FV_KEY =~ $FV_KEY_REGEX ]] && op_store_password "$FILEVAULT_ITEM_TITLE" "$FV_KEY"; then
            rm -f "$FV_LEGACY_KEY" 2>/dev/null || sudo rm -f "$FV_LEGACY_KEY"
            rmdir "$FV_LEGACY_DIR" 2>/dev/null || true
            pass "Moved the FileVault recovery key from ~/.filevault into 1Password ($OP_VAULT / $FILEVAULT_ITEM_TITLE)"
        else
            fail "Could not move ~/.filevault/recovery_key.plist into 1Password (file left in place)"
        fi
        unset FV_OLD_PLIST FV_KEY
    else
        manual "A FileVault recovery key is waiting in ~/.filevault/recovery_key.plist. Sign in to 1Password and re-run to move it there."
    fi
fi

FV_STATUS="$(fdesetup status 2>/dev/null || true)"
case "$FV_STATUS" in
    *"FileVault is On"*)
        pass "FileVault is on"
        # Encryption runs in the background after it's turned on.
        case "$FV_STATUS" in
            *"Encryption in progress"*) info "Disk encryption still in progress: ${FV_STATUS##*Percent completed = }%" ;;
        esac
        ;;
    *Deferred*|*"will be enabled"*)
        manual "FileVault turns on at your next logout (set up by an older version of this script). Log out and back in, then re-run to move the recovery key into 1Password."
        ;;
    *)
        echo "  FileVault is off. Turning it on now."
        echo "  Enter your macOS login password when asked (typing may not show), then"
        echo "  approve the 'fdesetup would like to enable FileVault' window (it may open behind this one)."
        # Not deferred: the recovery key comes back right away on stdout, so it
        # can go straight to 1Password without ever being written to disk.
        FV_PLIST="$(sudo fdesetup enable -user "$USER" -outputplist)"
        FV_KEY="$(extract_recovery_key "${FV_PLIST:-}")"
        if [[ $FV_KEY =~ $FV_KEY_REGEX ]]; then
            if [ "$OP_READY" = true ] && op_store_password "$FILEVAULT_ITEM_TITLE" "$FV_KEY"; then
                pass "FileVault is on; recovery key saved to 1Password ($OP_VAULT / $FILEVAULT_ITEM_TITLE)"
            else
                # 1Password isn't ready: keep the key in an owner-only file so the
                # next run can move it into 1Password (see above).
                (umask 077; mkdir -p "$FV_LEGACY_DIR"; printf '%s\n' "$FV_PLIST" > "$FV_LEGACY_KEY")
                manual "FileVault is on, but its recovery key is in ~/.filevault/recovery_key.plist (only you can read it). Sign in to 1Password and re-run to move it there."
            fi
        elif [ -n "${FV_PLIST:-}" ]; then
            # fdesetup returned something we couldn't parse. Never discard it:
            # it may hold the only copy of the recovery key.
            (umask 077; mkdir -p "$FV_LEGACY_DIR"; printf '%s\n' "$FV_PLIST" > "$FV_LEGACY_KEY")
            fail "Could not read the FileVault recovery key from fdesetup's output"
            manual "fdesetup's output is saved in ~/.filevault/recovery_key.plist (only you can read it). Copy the recovery key into 1Password and delete the file, or make a new key with 'sudo fdesetup changerecovery -personal'."
        else
            fail "Could not turn on FileVault"
            manual "Turn on FileVault in System Settings > Privacy & Security and save the recovery key in 1Password."
        fi
        unset FV_PLIST FV_KEY
        ;;
esac

echo "==> Configuring the application firewall..."
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"

# State 1 = on, 2 = on and blocking all incoming connections.
function firewall_on {
    local out
    out="$("$FW" --getglobalstate 2>/dev/null || true)"
    case "$out" in *"State = 1"*|*"State = 2"*) return 0 ;; *) return 1 ;; esac
}
# Wording differs by macOS version ("mode is on" / "mode enabled").
function stealth_on {
    local out
    out="$("$FW" --getstealthmode 2>/dev/null || true)"
    case "$out" in *"mode is on"*|*"mode enabled"*|*"Mode is on"*|*"Mode enabled"*) return 0 ;; *) return 1 ;; esac
}

if ! firewall_on; then
    sudo "$FW" --setglobalstate on >/dev/null
fi
if ! stealth_on; then
    sudo "$FW" --setstealthmode on >/dev/null
fi

if firewall_on; then pass "Firewall is on"; else fail "Firewall is NOT on"; fi
if stealth_on; then pass "Firewall stealth mode is on"; else fail "Firewall stealth mode is NOT on"; fi

echo "==> Checking Lockdown Mode..."
# Apple only supports turning Lockdown Mode on in System Settings, and doing so
# restarts the Mac. So this only checks it here; if it's off, the script opens
# the setting as its very last step, after the summary.
# LDMGlobalEnabled in the user's global preferences is 1 when it's on.
# (Undocumented by Apple; widely used by Mac admins to detect it.)
LOCKDOWN_PENDING=false
if [ "$(defaults read -g LDMGlobalEnabled 2>/dev/null || true)" = "1" ]; then
    pass "Lockdown Mode is on"
else
    LOCKDOWN_PENDING=true
    manual "Turn on Lockdown Mode in System Settings > Privacy & Security (it restarts the Mac), then re-run to confirm."
fi

echo "==> Checking Advanced Data Protection for iCloud..."
# Without it, Apple holds the keys to most iCloud data (iCloud Drive, Photos,
# Notes, device backups). Apple only lets you turn it on by hand in System
# Settings, and offers no way for a script to read whether it's on. So the
# script guides you through it at the end and remembers your confirmation in
# ~/setup/.adp-confirmed. Turning it on once covers your whole Apple Account.
ADP_MARKER="$SETUP_HOME/.adp-confirmed"
ADP_PENDING=false
ICLOUD_ACCOUNTS="$(defaults read MobileMeAccounts Accounts 2>/dev/null || true)"
case "$ICLOUD_ACCOUNTS" in
    *AccountID*)
        if [ -s "$ADP_MARKER" ]; then
            pass "Advanced Data Protection: you confirmed it's on ($(head -n 1 "$ADP_MARKER")); scripts can't check it"
        else
            ADP_PENDING=true
            manual "Turn on Advanced Data Protection: System Settings > your name > iCloud > Advanced Data Protection > Turn On, then re-run and confirm."
        fi
        ;;
    *)
        info "Not signed in to iCloud on this Mac, so Advanced Data Protection doesn't apply yet"
        ;;
esac
unset ICLOUD_ACCOUNTS

###########################
#   CORE BREW PACKAGES    #
###########################
echo "==> Installing core brew packages..."

for pkg in "${BREW_FORMULAE[@]}"; do
    brew_safe list --formula "$pkg" &>/dev/null || brew_safe install "$pkg"
done

verify_cmd cmake
verify_cmd vim
verify_cmd git
verify_cmd gh
verify_cmd gpg
verify_cmd pinentry-mac
verify_cmd pyenv
verify_cmd yamllint
verify_cmd rg

echo "==> Installing fonts..."
# Hack Nerd Font gives Terminal and Vim their powerline symbols and icons.
# The cask fails if the font was installed by hand, so check for it first.
if ! brew_safe list --cask font-hack-nerd-font &>/dev/null && \
   ! ls "$HOME"/Library/Fonts/Hack*Nerd* &>/dev/null; then
    brew_safe install --cask font-hack-nerd-font
else
    echo "  Hack Nerd Font already installed"
fi

###########################
#   PYTHON (pyenv)        #
###########################
echo "==> Configuring pyenv in ~/.zshrc..."

# Without these lines pyenv is installed but its Pythons are never on PATH.
if ! grep -q 'pyenv init' "$HOME/.zshrc" 2>/dev/null; then
    # shellcheck disable=SC2016  # literal lines for ~/.zshrc
    {
        echo ''
        echo '# pyenv (added by setup-os)'
        echo 'export PYENV_ROOT="$HOME/.pyenv"'
        echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
        echo 'eval "$(pyenv init - zsh)"'
    } >> "$HOME/.zshrc"
fi

if grep -q 'pyenv init' "$HOME/.zshrc" 2>/dev/null; then
    pass "pyenv is initialized in ~/.zshrc"
else
    fail "pyenv init is NOT in ~/.zshrc"
fi

###########################
#   NODE (nvm)            #
###########################
# nvm is the only Node manager (no Homebrew node), so there is one `node` on PATH.
echo "==> Installing nvm and Node.js LTS..."

export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    NVM_INSTALLER="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" -o "$NVM_INSTALLER"
    # PROFILE tells the installer which shell file gets the nvm lines.
    PROFILE="$HOME/.zshrc" bash "$NVM_INSTALLER"
    rm -f "$NVM_INSTALLER"
fi

verify_file "$NVM_DIR/nvm.sh"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    # nvm is a big shell function whose internal checks return non-zero by
    # design, and it doesn't support `set -u`. Pause both while it runs.
    trap - ERR
    set +u
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    if nvm install --lts && nvm alias default 'lts/*' >/dev/null; then
        nvm use default >/dev/null
        pass "Node.js LTS installed with nvm ($(node --version 2>/dev/null))"
    else
        fail "nvm could not install Node.js LTS"
    fi
    set -u
    trap 'on_error $LINENO' ERR
fi

verify_cmd node
verify_cmd npm

###########################
#   GPG                   #
###########################
# Kept for file encryption. Git commits are signed with the SSH key instead.
echo "==> Configuring GPG..."

# GnuPG warns or fails unless its directory is 700.
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"

# Use the macOS passphrase dialog instead of a terminal prompt.
append_line "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" "$HOME/.gnupg/gpg-agent.conf"
# Restart gpg-agent so it picks up the change. Fine if it wasn't running.
gpgconf --kill gpg-agent 2>/dev/null || true

verify_line_in_file "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" "$HOME/.gnupg/gpg-agent.conf"

###########################
#   SSH (1Password)       #
###########################
# The private key is generated inside 1Password and served by its SSH agent.
# It never exists as a file on this Mac.
echo "==> Configuring SSH with the 1Password agent..."

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"

if grep -qiE '^[[:space:]]*IdentityAgent' "$HOME/.ssh/config"; then
    echo "  ~/.ssh/config already sets an IdentityAgent, leaving it as is"
else
    if [ -s "$HOME/.ssh/config" ]; then
        cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak.$(date +%Y%m%d%H%M%S)"
    fi
    # The ~ is meant literally: ssh expands it itself.
    # shellcheck disable=SC2088
    printf '\n# 1Password SSH agent (added by setup-os)\nHost *\n  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"\n' \
        >> "$HOME/.ssh/config"
fi

if grep -qiE '^[[:space:]]*IdentityAgent' "$HOME/.ssh/config"; then
    pass "SSH config uses an SSH agent"
else
    fail "SSH config has no IdentityAgent"
fi

if [ -S "$OP_AGENT_SOCK" ]; then
    pass "1Password SSH agent is running"
else
    manual "Turn on 1Password > Settings > Developer > 'Use the SSH agent', then re-run."
fi

SSH_PUBKEY=""
if [ "$OP_READY" = true ]; then
    if op item get "$SSH_KEY_TITLE" --vault "$OP_VAULT" &>/dev/null; then
        echo "  '$SSH_KEY_TITLE' already exists in 1Password"
    else
        echo "  Creating Ed25519 key '$SSH_KEY_TITLE' in 1Password..."
        op item create --category ssh --title "$SSH_KEY_TITLE" --vault "$OP_VAULT" >/dev/null
    fi
    # Keep only "<type> <key>", dropping any comment.
    SSH_PUBKEY="$(op read "op://$OP_VAULT/$SSH_KEY_TITLE/public key" 2>/dev/null | awk '{print $1" "$2}' || true)"
    case "$SSH_PUBKEY" in
        ssh-*) pass "SSH key in 1Password: $SSH_PUBKEY" ;;
        *)     fail "Could not read the public key of '$SSH_KEY_TITLE' from 1Password"; SSH_PUBKEY="" ;;
    esac
fi

for old_key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    if [ -f "$old_key" ]; then
        info "$old_key is a private key on disk. Not touched; import it into 1Password and delete it if you still need it."
    fi
done

###########################
#   GIT CONFIG            #
###########################
# `git config --global` overwrites each key, so re-running is safe.
echo "==> Configuring Git..."

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global core.editor "$GIT_EDITOR"
git config --global init.defaultBranch main
# Rebase local commits on pull instead of making merge commits; stash and
# restore uncommitted changes automatically.
git config --global pull.rebase true
git config --global rebase.autoStash true
git config --global push.autoSetupRemote true
git config --global fetch.prune true
git config --global merge.tool vimdiff
# Like diff3 (ours / base / theirs) but without lines common to both sides.
git config --global merge.conflictstyle zdiff3
git config --global mergetool.prompt false
git config --global mergetool.keepBackup false

verify_git_config "user.name" "$GIT_NAME"
verify_git_config "user.email" "$GIT_EMAIL"
verify_git_config "core.editor" "$GIT_EDITOR"
verify_git_config "init.defaultBranch" "main"
verify_git_config "pull.rebase" "true"
verify_git_config "rebase.autoStash" "true"
verify_git_config "push.autoSetupRemote" "true"
verify_git_config "fetch.prune" "true"
verify_git_config "merge.tool" "vimdiff"
verify_git_config "merge.conflictstyle" "zdiff3"
verify_git_config "mergetool.prompt" "false"
verify_git_config "mergetool.keepBackup" "false"

# Global ignore file: an existing core.excludesFile wins, otherwise git's default.
GIT_IGNORE_GLOBAL="$(git config --global --path core.excludesFile 2>/dev/null || echo "$HOME/.config/git/ignore")"
mkdir -p "$(dirname "$GIT_IGNORE_GLOBAL")"
for pattern in '.DS_Store' '*.swp' '*.swo' '.env' '.env.*' '!.env.example'; do
    append_line "$pattern" "$GIT_IGNORE_GLOBAL"
done
verify_line_in_file ".env" "$GIT_IGNORE_GLOBAL"

# Sign commits and tags with the 1Password SSH key.
if [ -n "$SSH_PUBKEY" ]; then
    mkdir -p "$(dirname "$ALLOWED_SIGNERS")"
    append_line "$GIT_EMAIL namespaces=\"git\" $SSH_PUBKEY" "$ALLOWED_SIGNERS"

    git config --global gpg.format ssh
    git config --global user.signingkey "$SSH_PUBKEY"
    git config --global gpg.ssh.program "$OP_SSH_SIGN"
    git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true

    verify_git_config "gpg.format" "ssh"
    verify_git_config "user.signingkey" "$SSH_PUBKEY"
    verify_git_config "gpg.ssh.program" "$OP_SSH_SIGN"
    verify_git_config "gpg.ssh.allowedSignersFile" "$ALLOWED_SIGNERS"
    verify_git_config "commit.gpgsign" "true"
    verify_git_config "tag.gpgsign" "true"
else
    manual "Commit signing is not set up (no SSH key from 1Password yet). Re-run after signing in to 1Password."
fi

###########################
#   GITHUB                #
###########################
echo "==> Connecting GitHub..."

GH_READY=false
if gh auth status -h github.com &>/dev/null; then
    GH_READY=true
elif is_interactive; then
    echo "  Log in to GitHub in your browser:"
    if gh auth login -h github.com -p ssh -w --skip-ssh-key -s admin:public_key,admin:ssh_signing_key; then
        GH_READY=true
    fi
fi

if [ "$GH_READY" = true ]; then
    pass "GitHub CLI is logged in"

    # Add GitHub's host keys from its API (over HTTPS) so the first SSH
    # connection doesn't ask you to trust an unverified fingerprint.
    if ! ssh-keygen -F github.com &>/dev/null; then
        GH_HOST_KEYS="$(gh api meta --jq '.ssh_keys[]' 2>/dev/null || true)"
        if [ -n "$GH_HOST_KEYS" ]; then
            printf '%s\n' "$GH_HOST_KEYS" | sed 's/^/github.com /' >> "$HOME/.ssh/known_hosts"
        fi
    fi
    if ssh-keygen -F github.com &>/dev/null; then
        pass "GitHub host keys are in ~/.ssh/known_hosts"
    else
        fail "GitHub host keys are NOT in ~/.ssh/known_hosts"
    fi

    if [ -n "$SSH_PUBKEY" ]; then
        # Adding keys needs extra token scopes; ask for them only if missing.
        if ! gh api user/keys &>/dev/null || ! gh api user/ssh_signing_keys &>/dev/null; then
            if is_interactive; then
                echo "  GitHub needs permission to manage your SSH keys:"
                gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key || true
            fi
        fi
        add_github_key "user/keys" "authentication"
        add_github_key "user/ssh_signing_keys" "signing"

        if [ -S "$OP_AGENT_SOCK" ]; then
            # ssh -T exits 1 even on success, so check its message instead.
            SSH_TEST="$(ssh -T -o ConnectTimeout=10 git@github.com 2>&1 || true)"
            case "$SSH_TEST" in
                *"successfully authenticated"*) pass "SSH to GitHub works" ;;
                *) fail "SSH to GitHub failed: $SSH_TEST" ;;
            esac

            # Sign a throwaway commit (1Password asks you to approve), then verify
            # it with plain ssh-keygen, which needs no agent.
            SIGN_TMP="$(mktemp -d)"
            if git -C "$SIGN_TMP" init -q && \
               git -C "$SIGN_TMP" commit -q --allow-empty -m "setup-os signing test" && \
               git -C "$SIGN_TMP" -c gpg.ssh.program=ssh-keygen verify-commit HEAD &>/dev/null; then
                pass "Signed and verified a test commit"
            else
                fail "Commit signing test failed (approve the 1Password prompt and check the SSH agent is on)"
            fi
            rm -rf "$SIGN_TMP"
        fi
    fi
else
    manual "Run 'gh auth login', then re-run to add your SSH key to GitHub."
fi

###########################
#   TERMINAL              #
###########################
echo "==> Installing Solarized and configuring Terminal.app..."

SOLARIZED_DIR="$SETUP_HOME/solarized"
if [ ! -d "$SOLARIZED_DIR" ]; then
    git clone https://github.com/altercation/solarized.git "$SOLARIZED_DIR"
fi
verify_dir "$SOLARIZED_DIR"

# Opening the .terminal file imports the profile into Terminal.app.
if ! terminal_has_profile; then
    open "$SOLARIZED_DIR/osx-terminal.app-colors-solarized/xterm-256color/${TERMINAL_PROFILE}.terminal"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if terminal_has_profile; then break; fi
        sleep 1
    done
fi

# Set font and default profile through Terminal itself (AppleScript). Editing
# its plist directly gets overwritten when Terminal quits.
if terminal_has_profile; then
    osascript \
        -e "tell application \"Terminal\"" \
        -e "set s to settings set \"$TERMINAL_PROFILE\"" \
        -e "set font name of s to \"$TERMINAL_FONT\"" \
        -e "set font size of s to $TERMINAL_FONT_SIZE" \
        -e "set default settings to s" \
        -e "try" \
        -e "set startup settings to s" \
        -e "end try" \
        -e "end tell" >/dev/null
    TERMINAL_ACTUAL_FONT="$(osascript -e "tell application \"Terminal\" to get font name of settings set \"$TERMINAL_PROFILE\"" 2>/dev/null || true)"
    if [ "$TERMINAL_ACTUAL_FONT" = "$TERMINAL_FONT" ]; then
        pass "Terminal uses '$TERMINAL_PROFILE' with $TERMINAL_FONT ${TERMINAL_FONT_SIZE}pt"
    else
        fail "Terminal font is '$TERMINAL_ACTUAL_FONT', expected $TERMINAL_FONT (is Hack Nerd Font installed?)"
    fi
else
    fail "Terminal profile '$TERMINAL_PROFILE' was not imported"
fi

###########################
#   FINDER                #
###########################
echo "==> Configuring Finder..."

# Show hidden files. Finder only picks this up after a restart.
if [ "$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || true)" != "1" ]; then
    defaults write com.apple.finder AppleShowAllFiles -bool true
    killall Finder 2>/dev/null || true
fi

verify_defaults com.apple.finder AppleShowAllFiles "1"

###########################
#   VIM                   #
###########################
echo "==> Running Vim setup..."
/bin/bash "$REPO_ROOT/app/vim/vim-setup.sh"

# coc.nvim (VS Code style completion) needs its Node dependencies.
if [ -d "$SETUP_HOME/vim/bundle/coc.nvim" ]; then
    (cd "$SETUP_HOME/vim/bundle/coc.nvim" && npm install)
fi

###########################
#   SUMMARY               #
###########################
echo ""
echo "==============================="
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "  ALL CHECKS PASSED"
else
    echo "  $FAIL_COUNT CHECK(S) FAILED"
    echo "  Run 'claude' to debug failures."
fi
if [ -n "$MANUAL_NOTES" ]; then
    echo ""
    echo "  Still needs you:"
    printf '%s' "$MANUAL_NOTES"
fi
echo "==============================="

###############################
#   ADVANCED DATA PROTECTION  #
###############################
# Before Lockdown Mode, which restarts the Mac.
if [ "$ADP_PENDING" = true ] && is_interactive; then
    echo ""
    echo "==> Turn on Advanced Data Protection for iCloud"
    echo "  In the window that opens: your name > iCloud > Advanced Data Protection > Turn On."
    echo "  It needs a recovery contact or recovery key (keep the key in 1Password), and every"
    echo "  device on your Apple Account must be up to date. It doesn't restart the Mac."
    ADP_REPLY=""
    read -r -p "  Press Enter to open the setting (or type s to skip for now): " ADP_REPLY
    if [ "$ADP_REPLY" != "s" ]; then
        open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
        ADP_DONE=""
        read -r -p "  Type y once it shows Advanced Data Protection is on (Enter to skip): " ADP_DONE
        if [ "$ADP_DONE" = "y" ] || [ "$ADP_DONE" = "Y" ]; then
            mkdir -p "$SETUP_HOME" && date +%Y-%m-%d > "$ADP_MARKER"
            echo "  Saved. Later runs show it as confirmed."
        fi
    fi
fi

###########################
#   LOCKDOWN MODE (LAST)  #
###########################
# Last on purpose: turning it on restarts the Mac. Lockdown Mode blocks
# configuration profiles / MDM enrollment, some web fonts and features, and
# unapproved wired accessories while locked. Brew, git, ssh and 1Password work.
if [ "$LOCKDOWN_PENDING" = true ] && is_interactive; then
    echo ""
    echo "==> Last step: turn on Lockdown Mode"
    echo "  This restarts your Mac, so save your work first. In the window that opens:"
    echo "    Privacy & Security > Lockdown Mode > Turn On > Turn on Lockdown Mode > Turn On & Restart"
    echo "  After the restart, re-run this script to confirm it's on."
    LOCKDOWN_REPLY=""
    read -r -p "  Press Enter to open the setting (or type s to skip for now): " LOCKDOWN_REPLY
    if [ "$LOCKDOWN_REPLY" != "s" ]; then
        open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    fi
fi

if [ "$FAIL_COUNT" -eq 0 ]; then
    exit 0
else
    exit 1
fi
