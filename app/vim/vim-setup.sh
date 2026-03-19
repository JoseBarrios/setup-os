#!/bin/bash
# Vim setup script — installs Vundle, creates directory structure, symlinks dotfiles,
# installs plugins, and configures solarized colors.
# Designed to be idempotent: safe to run multiple times without side effects.

# Exit immediately on error (-e), treat unset variables as errors (-u),
# and ensure piped commands propagate failures (-o pipefail).
set -euo pipefail

# Counter to track how many verification tests fail during setup.
FAIL_COUNT=0

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

# Space-separated list of files/folders to symlink from the home directory.
# Each entry "X" will create ~/.X -> $dir/X.
files=".vimrc vim"

# Base directory containing the app/vim dotfiles (relative to where osx.sh runs).
dir="${PWD}/app"

# Path to the vim configuration directory inside the dotfiles.
vim="$dir/vim"

# Backup directory where existing dotfiles are moved before symlinking.
olddir="$vim/old"

# Vim subdirectories for color schemes, backups, bundles, swap files, and undo history.
vimcolors="$vim/colors"
vimbackups="$vim/backups"
vimbundle="$vim/bundle"
vimswaps="$vim/swaps"
vimundo="$vim/undo"

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

# --- Create all required Vim directories ---
echo "==> Creating VIM directories..."

# Main vim config directory.
makeDirectory "$vim"

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
verify_dir "$vim"
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

# --- Create symlinks from home directory to dotfiles ---
echo "==> Creating symlinks..."

# Change to the dotfiles base directory. Exit if it fails.
cd "$dir" || exit 1

# Loop through each file/folder that should be symlinked.
for file in $files; do
    # The actual file/folder inside the dotfiles directory.
    target="$dir/$file"

    # The symlink location in the home directory (e.g., ~/.vimrc, ~/.vim).
    link=~/."$file"

    # Check if a symlink already exists and points to the correct target.
    # If so, skip it entirely — no need to back up or recreate (idempotent).
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
        echo "Symlink for $file already exists and is correct"
        continue
    fi

    # If something exists at the link path (file, directory, or broken symlink),
    # back it up to the old directory before creating our symlink.
    if [ -e "$link" ] || [ -L "$link" ]; then
        echo "Moving existing ~/.$file to $olddir"
        mv "$link" "$olddir/"
    fi

    # Create the symlink. -s = symbolic link, -f = overwrite if exists.
    echo "Creating symlink to $file in home directory."
    ln -sf "$target" "$link"
done

# Test: Verify each symlink points to the correct target.
for file in $files; do
    verify_symlink ~/."$file" "$dir/$file"
done

# --- Install Solarized color scheme for Vim ---
echo "==> Installing solarized colors..."

# Only install if the solarized.vim color file doesn't exist yet (idempotent).
if [ ! -f "$vimcolors/solarized.vim" ]; then
    echo "Installing solarized colors for VIM"

    # Clone the vim-colors-solarized repo (contains the .vim color file).
    git clone https://github.com/altercation/vim-colors-solarized.git

    # Copy the color scheme file to our Vim colors directory.
    cp ./vim-colors-solarized/colors/solarized.vim "$vimcolors"

    # Clean up the cloned repo — we only needed the one file.
    rm -rf vim-colors-solarized
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

    # Run YCM's Python-based install script to compile the native components.
    python install.py

    # Run YCM's install script with all language completers, including clangd for C/C++.
    ./install.py -all --clangd-completer

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
