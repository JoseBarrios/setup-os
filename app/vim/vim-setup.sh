#!/bin/bash
# Vim setup script — installs Vundle, creates directory structure, symlinks dotfiles,
# installs plugins, and configures solarized colors.
# Designed to be idempotent: safe to run multiple times without side effects.
# When an error occurs and Claude Code is available, it automatically asks Claude to debug.
#
# All generated artifacts (bundles, colors, backups, swap, undo) are stored in
# ~/setup/vim/ — NOT inside the git repository — to avoid accidentally committing them.
# Only the source .vimrc config lives in the repo.

# Treat unset variables as errors (-u) and ensure piped commands propagate failures (-o pipefail).
# We do NOT use -e (errexit) because we handle errors via an ERR trap instead,
# which lets the script continue after Claude provides debugging guidance.
set -uo pipefail

# Counter to track how many verification tests fail during setup.
FAIL_COUNT=0

# Path to the script itself — used to provide context to Claude when debugging errors.
SELF_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

###############################
#   ERROR HANDLING            #
###############################

# Automatic error handler — triggered on any command failure.
# Captures the failed command, exit code, and line number, then asks Claude to debug.
# The script does NOT exit — it logs the error and continues so the user can review.
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
        claude --print "A Vim setup script encountered an error. Help me debug it.

Script: $SELF_SCRIPT
Line $line_number failed with exit code $exit_code.
Failed command: $failed_command

System info:
- macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')
- Architecture: $(uname -m)

Provide a concise diagnosis and a fix. Do not rewrite the entire script." 2>/dev/null || \
            echo "  (Claude could not be reached — debug manually)"
        echo ""
    else
        echo "  Claude Code is not yet installed — install it to enable auto-debugging."
    fi
}

# Register the ERR trap. It fires on any command that returns a non-zero exit code.
# IMPORTANT: This does NOT cause the script to exit — it just calls on_error and continues.
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

# Verify that a symlink at $1 points to target $2.
# Usage: verify_symlink <link_path> <expected_target>
function verify_symlink {
    # -L checks if the path is a symbolic link.
    # readlink returns the path the symlink points to.
    if [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; then
        echo "  [PASS] $1 -> $2"
    else
        echo "  [FAIL] symlink $1 -> $2 is incorrect or missing"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Verify that a CLI command is available on the system PATH.
# Usage: verify_cmd <command_name>
function verify_cmd {
    if command -v "$1" &>/dev/null; then
        echo "  [PASS] $1 is installed"
    else
        echo "  [FAIL] $1 is NOT installed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

#################
#   VARIABLES   #
#################

# Resolve the absolute path to the repo's app/vim/ directory based on this script's location.
# This ensures paths are correct regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# The repo's app/ directory — contains the source .vimrc config file (read-only, committed).
REPO_APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Path to the source .vimrc in the repository.
REPO_VIMRC="$SCRIPT_DIR/.vimrc"

# All generated vim artifacts live in ~/setup/vim/ — outside the git repo.
# This prevents bundles, colors, swap files, etc. from being accidentally committed.
VIM_HOME="$HOME/setup/vim"

# Backup directory where existing dotfiles are moved before symlinking.
olddir="$VIM_HOME/old"

# Vim subdirectories for color schemes, backups, bundles, swap files, and undo history.
vimcolors="$VIM_HOME/colors"
vimbackups="$VIM_HOME/backups"
vimbundle="$VIM_HOME/bundle"
vimswaps="$VIM_HOME/swaps"
vimundo="$VIM_HOME/undo"

#################
#   FUNCTIONS   #
#################

# Create a directory if it doesn't already exist. Idempotent — reports status either way.
# Usage: makeDirectory <path>
function makeDirectory {
    if [ ! -d "$1" ]; then
        # -p creates parent directories as needed and doesn't error if they exist.
        mkdir -p "$1"
        echo "Created directory: $1"
    else
        echo "Directory $1 already exists"
    fi
}

#############
#   MAIN    #
#############

# --- Create all required Vim directories under ~/setup/vim/ ---
echo "==> Creating VIM directories in ~/setup/vim/..."

# Main vim artifact directory (will be symlinked as ~/.vim).
makeDirectory "$VIM_HOME"

# Directory for color scheme files (.vim).
makeDirectory "$vimcolors"

# Backup directory for pre-existing dotfiles we replace with symlinks.
makeDirectory "$olddir"

# Directory where Vim stores swap files (crash recovery).
makeDirectory "$vimswaps"

# Directory where Vim stores backup copies of edited files.
makeDirectory "$vimbackups"

# Directory where Vim stores persistent undo history across sessions.
makeDirectory "$vimundo"

# Directory for Vundle-managed plugin bundles.
makeDirectory "$vimbundle"

# Test: Verify all directories were created.
verify_dir "$VIM_HOME"
verify_dir "$vimcolors"
verify_dir "$olddir"
verify_dir "$vimswaps"
verify_dir "$vimbackups"
verify_dir "$vimundo"
verify_dir "$vimbundle"

# --- Install Vundle (Vim plugin manager) ---
echo "==> Installing Vundle..."

# Only clone if Vundle isn't already installed (idempotent).
if [ ! -d "$vimbundle/Vundle.vim" ]; then
    # Clone the Vundle repository into the bundle directory.
    git clone https://github.com/gmarik/Vundle.vim.git "$vimbundle/Vundle.vim"
fi

# Test: Verify Vundle directory exists.
verify_dir "$vimbundle/Vundle.vim"

# --- Create symlinks from home directory ---
echo "==> Creating symlinks..."

# Symlink ~/.vimrc -> the repo's source .vimrc (config is versioned in git).
VIMRC_LINK="$HOME/.vimrc"
if [ -L "$VIMRC_LINK" ] && [ "$(readlink "$VIMRC_LINK")" = "$REPO_VIMRC" ]; then
    # Symlink already correct — skip (idempotent).
    echo "Symlink for .vimrc already exists and is correct"
else
    # Back up any existing .vimrc before replacing it.
    if [ -e "$VIMRC_LINK" ] || [ -L "$VIMRC_LINK" ]; then
        echo "Moving existing ~/.vimrc to $olddir"
        mv "$VIMRC_LINK" "$olddir/"
    fi
    echo "Creating symlink ~/.vimrc -> $REPO_VIMRC"
    ln -sf "$REPO_VIMRC" "$VIMRC_LINK"
fi

# Symlink ~/.vim -> ~/setup/vim/ (artifacts directory, outside the git repo).
VIM_LINK="$HOME/.vim"
if [ -L "$VIM_LINK" ] && [ "$(readlink "$VIM_LINK")" = "$VIM_HOME" ]; then
    # Symlink already correct — skip (idempotent).
    echo "Symlink for .vim already exists and is correct"
else
    # Back up any existing .vim before replacing it.
    if [ -e "$VIM_LINK" ] || [ -L "$VIM_LINK" ]; then
        echo "Moving existing ~/.vim to $olddir"
        mv "$VIM_LINK" "$olddir/"
    fi
    echo "Creating symlink ~/.vim -> $VIM_HOME"
    ln -sf "$VIM_HOME" "$VIM_LINK"
fi

# Test: Verify both symlinks point to the correct targets.
verify_symlink "$VIMRC_LINK" "$REPO_VIMRC"
verify_symlink "$VIM_LINK" "$VIM_HOME"

# --- Install Solarized color scheme for Vim ---
echo "==> Installing solarized colors..."

# Only install if the solarized.vim color file doesn't exist yet (idempotent).
if [ ! -f "$vimcolors/solarized.vim" ]; then
    echo "Installing solarized colors for VIM"

    # Use a temporary directory for the clone to avoid polluting the working directory.
    # This also prevents rm -rf from accidentally deleting the wrong relative path.
    SOLARIZED_TMP="$(mktemp -d)"

    # Clone the vim-colors-solarized repo (contains the .vim color file).
    git clone https://github.com/altercation/vim-colors-solarized.git "$SOLARIZED_TMP/vim-colors-solarized"

    # Copy the color scheme file to our Vim colors directory.
    cp "$SOLARIZED_TMP/vim-colors-solarized/colors/solarized.vim" "$vimcolors"

    # Clean up the cloned repo — we only needed the one file.
    rm -rf "$SOLARIZED_TMP"
fi

# Test: Verify the solarized color file exists.
verify_file "$vimcolors/solarized.vim"

# --- Install Vim plugins via Vundle ---
echo "==> Installing vim plugins..."

# Run Vim in ex mode to execute PluginInstall (reads plugins from .vimrc),
# then quit all buffers. Vundle installs missing plugins and skips existing ones.
vim +PluginInstall +qall

# --- Configure individual plugins that need extra setup ---
echo "==> Configuring plugins..."

# tern_for_vim — JavaScript code analysis engine for Vim.
# Only configure if the plugin was installed by Vundle.
if [ -d "$vimbundle/tern_for_vim/" ]; then
    # pushd saves the current directory and changes to the plugin directory.
    pushd "$vimbundle/tern_for_vim/"

    # Install tern's Node.js dependencies. npm install is idempotent —
    # it only installs/updates packages that are missing or outdated.
    npm install

    # popd restores the previous working directory.
    popd

    # Test: Verify npm installed its dependencies (lock file exists).
    verify_file "$vimbundle/tern_for_vim/node_modules/.package-lock.json"
fi

# YouCompleteMe — fast, fuzzy code completion engine for Vim.
# Only configure if the plugin was installed by Vundle.
if [ -d "$vimbundle/YouCompleteMe/" ]; then
    # Change to the YCM plugin directory.
    pushd "$vimbundle/YouCompleteMe/"

    # Initialize and update all of YCM's git submodules recursively.
    git submodule update --init --recursive

    # YCM requires cmake for building and macvim for full feature support.
    # brew install is idempotent — skips already-installed packages.
    brew install cmake macvim

    # Run YCM's install script with all language completers, including clangd for C/C++.
    # Use python3 explicitly — macOS no longer ships a bare `python` binary.
    python3 install.py --all --clangd-completer

    # Restore the previous working directory.
    popd
fi

# --- Install Prettier (code formatter used by vim-prettier plugin) ---
echo "==> Installing prettier..."

# Only install globally if prettier is not already on the PATH (idempotent).
if ! command -v prettier &>/dev/null; then
    # -g installs prettier globally so it's available system-wide.
    npm install prettier -g
fi

# Test: Verify prettier is available.
verify_cmd prettier

###########################
#   SUMMARY               #
###########################
# Print a final report showing how many tests passed or failed.
echo ""
echo "==============================="
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "  VIM SETUP: ALL TESTS PASSED"
else
    echo "  VIM SETUP: $FAIL_COUNT TEST(S) FAILED"
    # If Claude Code is installed, remind the user it can help debug.
    if command -v claude &>/dev/null; then
        echo "  Run 'claude' to debug failures."
    fi
fi
echo "==============================="
