#!/bin/bash
# macOS setup script — installs dev tools, configures security, and sets up the environment.
# Designed to be idempotent: safe to run multiple times without side effects.

# Exit immediately on error (-e), treat unset variables as errors (-u),
# and ensure piped commands propagate failures (-o pipefail).
set -euo pipefail

# Counter to track how many verification tests fail during the setup.
FAIL_COUNT=0

###############################
#   VERIFICATION FUNCTIONS    #
###############################

# Verify that a CLI command is available on the system PATH.
# Increments FAIL_COUNT and suggests Claude debugging if the command is missing.
# Usage: verify_cmd <command_name>
function verify_cmd {
    if command -v "$1" &>/dev/null; then
        echo "  [PASS] $1 is installed"
    else
        echo "  [FAIL] $1 is NOT installed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # If Claude Code is already installed, remind the user it can help debug.
        if command -v claude &>/dev/null; then
            echo "  Claude Code is available — you can run 'claude' to debug this failure."
        fi
    fi
}

# Verify that a directory exists on disk.
# Usage: verify_dir <path>
function verify_dir {
    if [ -d "$1" ]; then
        echo "  [PASS] $1 exists"
    else
        echo "  [FAIL] $1 does NOT exist"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        if command -v claude &>/dev/null; then
            echo "  Claude Code is available — you can run 'claude' to debug this failure."
        fi
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
        if command -v claude &>/dev/null; then
            echo "  Claude Code is available — you can run 'claude' to debug this failure."
        fi
    fi
}

# Verify that a git global config key matches an expected value.
# Usage: verify_git_config <key> <expected_value>
function verify_git_config {
    # Read the current value; default to empty string if the key is unset.
    local actual
    actual="$(git config --global "$1" 2>/dev/null || true)"
    if [ "$actual" = "$2" ]; then
        echo "  [PASS] git $1 = $2"
    else
        echo "  [FAIL] git $1 expected '$2', got '$actual'"
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

# Verify a macOS defaults (plist) boolean value.
# Usage: verify_defaults <domain> <key> <expected_value>
function verify_defaults {
    local actual
    actual="$(defaults read "$1" "$2" 2>/dev/null || true)"
    if [ "$actual" = "$3" ]; then
        echo "  [PASS] $1 $2 = $3"
    else
        echo "  [FAIL] $1 $2 expected '$3', got '$actual'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Create the temporary working directory for setup artifacts.
# -p ensures no error if the directory already exists (idempotent).
mkdir -p ~/OSSetup

# Change into the working directory. Exit if it fails (e.g., permission denied).
cd ~/OSSetup || exit 1

###########################
#   MACOS SECURITY        #
###########################
# Configure macOS security settings early so the machine is hardened
# before installing third-party software.

# --- FileVault (full-disk encryption) ---
# FileVault encrypts the entire startup disk to protect data at rest.
# `fdesetup status` reports "FileVault is On." or "FileVault is Off.".
echo "==> Configuring FileVault (full-disk encryption)..."
if fdesetup status | grep -q "FileVault is On."; then
    # FileVault is already enabled — nothing to do.
    echo "  [PASS] FileVault is already enabled"
else
    # Enable FileVault with deferred mode: encryption begins at next logout.
    # -defer writes the recovery key to a plist so it can be escrowed later.
    # This requires the current user's password (prompted interactively).
    echo "  FileVault is OFF. Enabling with deferred activation..."
    sudo fdesetup enable -defer /tmp/filevault_recovery_key.plist
    echo "  FileVault will activate on next logout/restart."
    echo "  IMPORTANT: Save your recovery key from /tmp/filevault_recovery_key.plist"
    echo "  [PASS] FileVault enable command succeeded (pending next logout)"
fi

# --- Lockdown Mode ---
# Lockdown Mode is an extreme, optional protection for users who may be targeted
# by sophisticated cyberattacks. It limits attack surface by disabling certain
# features (message attachment types, JIT compilation, incoming FaceTime, etc.).
# Available on macOS Ventura (13.0) and later.
echo "==> Configuring Lockdown Mode..."

# Get the major macOS version number (e.g., "14" for Sonoma, "13" for Ventura).
MACOS_VERSION="$(sw_vers -productVersion | cut -d. -f1)"

if [ "$MACOS_VERSION" -ge 13 ]; then
    # Check the current Lockdown Mode state from the global Apple security domain.
    # LDMGlobalEnabled = 1 means on, 0 or missing means off.
    LOCKDOWN_STATUS="$(defaults read com.apple.security.lockdownmode LDMGlobalEnabled 2>/dev/null || echo "0")"
    if [ "$LOCKDOWN_STATUS" = "1" ]; then
        # Lockdown Mode is already enabled — nothing to do.
        echo "  [PASS] Lockdown Mode is already enabled"
    else
        # Enable Lockdown Mode by writing to the Apple security preferences domain.
        # A reboot is required for the change to take full effect.
        echo "  Lockdown Mode is OFF. Enabling..."
        sudo defaults write com.apple.security.lockdownmode LDMGlobalEnabled -bool true
        echo "  Lockdown Mode enabled. A REBOOT is required to fully activate."
        echo "  [PASS] Lockdown Mode enable command succeeded (pending reboot)"
    fi
else
    # Lockdown Mode is not available on macOS versions before Ventura (13).
    echo "  [SKIP] Lockdown Mode requires macOS 13 (Ventura) or later. Current: $MACOS_VERSION"
fi

###########################
#   BREW                  #
###########################
# Homebrew is the package manager for macOS — used to install all dev tools.
echo "==> Installing Homebrew..."

# Only install if the `brew` command is not already available.
if ! command -v brew &>/dev/null; then
    # Download and run the official Homebrew installer.
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Detect the correct Homebrew prefix based on CPU architecture.
# Apple Silicon (M1+) installs to /opt/homebrew; Intel installs to /usr/local.
if [ -f /opt/homebrew/bin/brew ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

# Add Homebrew's shell environment setup to .zprofile so it loads on login.
# grep -qxF checks if the exact line already exists to avoid duplicate entries.
grep -qxF "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"" "$HOME/.zprofile" || \
    (echo; echo "eval \"\$(${BREW_PREFIX}/bin/brew shellenv)\"") >> "$HOME/.zprofile"

# Load Homebrew into the current shell session so `brew` works immediately.
eval "$(${BREW_PREFIX}/bin/brew shellenv)"

# Fetch the latest package metadata from Homebrew's repositories.
brew update

# Run Homebrew's self-diagnostic checks. Allow non-zero exit (warnings are common).
brew doctor || true

# Test: Verify brew is now available.
verify_cmd brew

###########################
#   NODE + CLAUDE CODE    #
###########################
# Install Node.js first because Claude Code's installer depends on it.
# Claude Code is installed as early as possible so it's available for debugging.

echo "==> Installing Node..."
# brew install is idempotent — if node is already installed, this is a no-op.
brew install node
# Test: Verify both node and npm (Node Package Manager) are available.
verify_cmd node
verify_cmd npm

echo "==> Installing Claude Code..."
# Only install Claude Code if it's not already on the PATH.
if ! command -v claude &>/dev/null; then
    # Download and run the official Claude Code installer, then launch initial setup.
    curl -fsSL https://claude.ai/install.sh | bash && claude
fi

# Ensure Claude Code's install directory is on the PATH in future shell sessions.
# grep -qxF prevents adding the line if it's already present (idempotent).
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# Also export the PATH in the current session so `claude` is available now.
export PATH="$HOME/.local/bin:$PATH"

# Test: Verify claude command is available.
verify_cmd claude

###########################
#   CORE BREW PACKAGES    #
###########################
# Install essential development tools via Homebrew.
echo "==> Installing core brew packages..."

# CMake — cross-platform build system generator (needed for YouCompleteMe, etc.).
brew install cmake

# Vim — terminal-based text editor (Homebrew version is newer than macOS built-in).
brew install vim

# Git — version control system (Homebrew version is newer than macOS built-in).
brew install git

# Test: Verify each core tool is available.
verify_cmd cmake
verify_cmd vim
verify_cmd git

###########################
#   PYTHON (pyenv)        #
###########################
# pyenv lets you install and switch between multiple Python versions.
echo "==> Installing pyenv..."

# Install pyenv via Homebrew.
brew install pyenv

# Create a shell alias that strips pyenv shims from PATH before running brew.
# This prevents Homebrew from accidentally using a pyenv-managed Python.
alias brew='env PATH="${PATH//$(pyenv root)\/shims:/}" brew'

# Test: Verify pyenv is available.
verify_cmd pyenv

###########################
#   FONTS                 #
###########################
# Nerd Fonts patch developer-targeted fonts with a large number of glyphs (icons).
# Hack Nerd Font is used by terminal and Vim for powerline symbols and devicons.
echo "==> Installing fonts..."

# Install the Hack Nerd Font as a macOS cask (GUI application/resource).
# brew install --cask is idempotent — skips if already installed.
brew install --cask font-hack-nerd-font

###########################
#   LINTERS               #
###########################
# Linters analyze code for errors, style issues, and best practices.
echo "==> Installing linters..."

# yamllint — linter for YAML files (used for CI configs, Kubernetes manifests, etc.).
brew install yamllint

# Test: Verify yamllint is available.
verify_cmd yamllint

# CloudFront linter (disabled — uncomment if working with AWS CloudFormation).
# brew install cfn-lint

###########################
#   RIPGREP               #
###########################
# RipGrep (rg) — extremely fast recursive text search tool, used by Vim plugins.
echo "==> Installing RipGrep..."

# Install ripgrep via Homebrew.
brew install rg

# Test: Verify rg is available.
verify_cmd rg

###########################
#   GPG                   #
###########################
# GnuPG is used for signing Git commits and encrypting/decrypting files.
echo "==> Installing GPG..."

# Install GnuPG (the `gpg` command) via Homebrew.
brew install gnupg

# Install pinentry-mac — a macOS-native PIN entry dialog for GPG passphrase prompts.
brew install pinentry-mac

# Test: Verify both tools are available.
verify_cmd gpg
verify_cmd pinentry-mac

# Ensure the GnuPG config directory exists before writing to its config files.
mkdir -p ~/.gnupg

# Tell gpg-agent to use pinentry-mac for passphrase prompts instead of the terminal.
# Only add the line if it's not already present (idempotent).
grep -qxF "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" ~/.gnupg/gpg-agent.conf 2>/dev/null || \
    echo "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf

# Restart gpg-agent so it picks up the new config. Ignore errors if it's not running.
killall gpg-agent 2>/dev/null || true

# Test: Verify the pinentry line is present in the config file.
verify_line_in_file "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" ~/.gnupg/gpg-agent.conf

###########################
#   GIT CONFIG            #
###########################
# Configure Git's global settings. git config --global is idempotent —
# it overwrites the existing value for each key, so re-running is safe.
echo "==> Configuring Git..."

# Use GnuPG for commit signing.
git config --global gpg.program gpg

# Use vimdiff as the merge resolution tool.
git config --global merge.tool vimdiff

# Show a three-way diff (ours / base / theirs) during merge conflicts.
git config --global merge.conflictstyle diff3

# Don't prompt before launching the merge tool for each conflicted file.
git config --global mergetool.prompt false

# Use merge (not rebase) when pulling — creates merge commits for diverged branches.
git config --global pull.rebase false

# Set the global Git identity for commits.
git config --global user.name "JoseBarrios"
git config --global user.email github@barrios.io

# Test: Verify each git config value matches what we set.
verify_git_config "gpg.program" "gpg"
verify_git_config "merge.tool" "vimdiff"
verify_git_config "merge.conflictstyle" "diff3"
verify_git_config "mergetool.prompt" "false"
verify_git_config "pull.rebase" "false"
verify_git_config "user.name" "JoseBarrios"
verify_git_config "user.email" "github@barrios.io"

###########################
#   NVM                   #
###########################
# NVM (Node Version Manager) allows installing and switching between Node.js versions.
echo "==> Installing NVM..."

# Only install if the ~/.nvm directory doesn't exist yet (idempotent).
if [ ! -d "$HOME/.nvm" ]; then
    # Download and run the official NVM install script (v0.39.7).
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# Test: Verify the NVM directory was created.
verify_dir "$HOME/.nvm"

###########################
#   BLUECLOTH (vim-preview) #
###########################
# bluecloth is a Ruby gem that renders Markdown — required by the vim-preview plugin.
echo "==> Installing bluecloth gem..."

# Only install the gem if it's not already present (idempotent).
if ! gem list -i bluecloth &>/dev/null; then
    # sudo is required because system Ruby's gem directory is root-owned.
    sudo gem install bluecloth
fi

# Test: Verify the gem is installed.
if gem list -i bluecloth &>/dev/null; then
    echo "  [PASS] bluecloth gem is installed"
else
    echo "  [FAIL] bluecloth gem is NOT installed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

###########################
#   SOLARIZED             #
###########################
# Solarized is a popular color scheme for terminals and editors.
echo "==> Installing Solarized color scheme..."

# Only clone the repo if it doesn't already exist (idempotent).
if [ ! -d ~/OSSetup/solarized ]; then
    # Clone the Solarized repo which contains terminal profiles and editor themes.
    git clone https://github.com/altercation/solarized.git
    # Open the Solarized Dark terminal profile in Terminal.app to make it available.
    # Only done on first install to avoid opening it every time the script runs.
    open ~/OSSetup/solarized/osx-terminal.app-colors-solarized/xterm-256color/Solarized\ Dark\ xterm-256color.terminal
fi

# Test: Verify the solarized directory exists.
verify_dir ~/OSSetup/solarized

###########################
#   FINDER CONFIG         #
###########################
# Configure macOS Finder to show hidden files (dotfiles) by default.
echo "==> Configuring Finder..."

# Write the preference to show hidden files. This is idempotent — writing the
# same value again has no effect.
defaults write com.apple.finder AppleShowAllFiles -bool true

# Test: Verify the setting was applied (defaults read returns "1" for true).
verify_defaults com.apple.finder AppleShowAllFiles "1"

###########################
#   OH MY ZSH             #
###########################
# Oh My Zsh is a framework for managing Zsh configuration with plugins and themes.
echo "==> Installing Oh My Zsh..."

# Only install if the ~/.oh-my-zsh directory doesn't exist yet (idempotent).
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    # Download and run the official installer.
    # --unattended prevents it from changing the default shell or starting a new session.
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Test: Verify the Oh My Zsh directory was created.
verify_dir "$HOME/.oh-my-zsh"

###########################
#   VIM SETUP             #
###########################
# Run the separate Vim setup script which installs Vundle, plugins, and symlinks.
echo "==> Running VIM setup..."
/bin/bash app/vim/vim-setup.sh

# Install dependencies for the coc.nvim plugin (VS Code-like completion for Vim).
# Only run if the coc.nvim plugin directory exists (it's installed by Vundle).
if [ -d ~/.vim/bundle/coc.nvim ]; then
    # Change to the plugin directory and install its Node.js dependencies.
    cd ~/.vim/bundle/coc.nvim && npm install
fi

###########################
#   SUMMARY               #
###########################
# Print a final report of all verification tests.
echo ""
echo "==============================="
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "  ALL TESTS PASSED"
else
    echo "  $FAIL_COUNT TEST(S) FAILED"
    echo "  Run 'claude' to debug failures."
fi
echo "==============================="
