#!/bin/bash
# macOS setup script — installs dev tools, configures security, and sets up the environment.
# Designed to be idempotent: safe to run multiple times without side effects.
# When an error occurs and Claude Code is available, it automatically asks Claude to debug.

# Treat unset variables as errors (-u) and ensure piped commands propagate failures (-o pipefail).
# We do NOT use -e (errexit) because we handle errors via an ERR trap instead,
# which lets the script continue after Claude provides debugging guidance.
set -uo pipefail

# Counter to track how many verification tests fail during the setup.
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
        # Use --print for non-interactive single-shot output.
        # Provide the script source, the failed line, and system context.
        claude --print "A macOS setup script encountered an error. Help me debug it.

Script: $SELF_SCRIPT
Line $line_number failed with exit code $exit_code.
Failed command: $failed_command

System info:
- macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')
- Architecture: $(uname -m)
- Brew prefix: ${BREW_PREFIX:-unknown}

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

# Verify that a CLI command is available on the system PATH.
# Increments FAIL_COUNT if the command is missing.
# Usage: verify_cmd <command_name>
function verify_cmd {
    if command -v "$1" &>/dev/null; then
        echo "  [PASS] $1 is installed"
    else
        echo "  [FAIL] $1 is NOT installed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
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

# Wrapper function for brew that strips pyenv shims from PATH.
# This prevents Homebrew from accidentally using a pyenv-managed Python.
# Note: shell aliases do not work in non-interactive scripts, so a function is used.
function brew_safe {
    if command -v pyenv &>/dev/null; then
        env PATH="${PATH//$(pyenv root)\/shims:/}" brew "$@"
    else
        brew "$@"
    fi
}

# Resolve the absolute path to the repository root (two levels up from this script).
# This ensures all relative paths work regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# All generated artifacts (vim bundles, solarized, etc.) live in ~/setup/ —
# outside the git repository — to avoid accidentally committing them.
# -p ensures no error if the directory already exists (idempotent).
SETUP_HOME="$HOME/setup"
mkdir -p "$SETUP_HOME"

# Change into the artifacts directory. Exit if it fails (e.g., permission denied).
cd "$SETUP_HOME" || exit 1

###########################
#   MACOS SECURITY        #
###########################
# Configure macOS security settings early so the machine is hardened
# before installing third-party software.

# --- FileVault (full-disk encryption) ---
# FileVault encrypts the entire startup disk to protect data at rest.
# `fdesetup status` reports "FileVault is On." or "FileVault is Off.".
# The status check may require root on some configurations, so we guard with || true.
echo "==> Configuring FileVault (full-disk encryption)..."
if fdesetup status 2>/dev/null | grep -q "FileVault is On."; then
    # FileVault is already enabled — nothing to do.
    echo "  [PASS] FileVault is already enabled"
else
    # Enable FileVault with deferred mode: encryption begins at next logout.
    # -defer writes the recovery key to a plist so it can be escrowed later.
    # This requires the current user's password (prompted interactively).

    # Store the recovery key plist in a secure, user-owned location (not /tmp/).
    # /tmp/ is world-readable and any local user could read the recovery key.
    FILEVAULT_KEY_DIR="$HOME/.filevault"
    mkdir -p "$FILEVAULT_KEY_DIR"
    # Restrict permissions so only the owner can read/write/traverse this directory.
    chmod 700 "$FILEVAULT_KEY_DIR"
    FILEVAULT_KEY_PATH="$FILEVAULT_KEY_DIR/recovery_key.plist"

    echo "  FileVault is OFF. Enabling with deferred activation..."
    sudo fdesetup enable -defer "$FILEVAULT_KEY_PATH"
    # Restrict the recovery key file so only the owner can read it.
    chmod 600 "$FILEVAULT_KEY_PATH"
    echo "  FileVault will activate on next logout/restart."
    echo "  [PASS] FileVault enable command succeeded (pending next logout)"

    # Flag that the recovery key needs to be saved to 1Password after it's set up.
    FILEVAULT_KEY_PENDING=true
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
    # Download the official Homebrew installer to a temp file so we can verify
    # it downloaded completely before executing it. Piping curl directly to bash
    # risks executing a truncated or corrupted script.
    BREW_INSTALLER="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$BREW_INSTALLER"
    /bin/bash "$BREW_INSTALLER"
    rm -f "$BREW_INSTALLER"
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
#   1PASSWORD + CLI       #
###########################
# 1Password is a password manager. The CLI (`op`) allows storing and retrieving
# secrets from the command line, which we use to securely store keys generated
# during setup (FileVault recovery key, GPG keys, etc.).
echo "==> Installing 1Password and 1Password CLI..."

# Install the 1Password desktop app (GUI).
# brew --cask fails if the app exists but wasn't installed via Homebrew (e.g., App Store).
# Check for the .app bundle on disk first to avoid this error.
if [ ! -d "/Applications/1Password.app" ]; then
    brew install --cask 1password
else
    echo "  1Password.app already exists, skipping cask install"
fi

# Install the 1Password CLI (`op` command). Idempotent — skips if already installed.
if ! command -v op &>/dev/null; then
    brew install 1password-cli
fi

# Test: Verify both are available.
verify_cmd op

# Check if the user is signed in to 1Password CLI.
# `op account list` returns non-zero or empty output if not signed in.
# The user must sign in interactively before we can store secrets.
if op account list 2>/dev/null | grep -q "."; then
    echo "  [PASS] 1Password CLI is signed in"
    OP_SIGNED_IN=true
else
    echo "  [INFO] 1Password CLI is not signed in."
    echo "  Run 'eval \$(op signin)' to sign in, then re-run this script to store secrets."
    OP_SIGNED_IN=false
fi

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
    # Download the installer to a temp file, verify it downloaded fully, then execute.
    CLAUDE_INSTALLER="$(mktemp)"
    curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_INSTALLER"
    /bin/bash "$CLAUDE_INSTALLER"
    rm -f "$CLAUDE_INSTALLER"
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

# Test: Verify pyenv is available.
verify_cmd pyenv

###########################
#   FONTS                 #
###########################
# Nerd Fonts patch developer-targeted fonts with a large number of glyphs (icons).
# Hack Nerd Font is used by terminal and Vim for powerline symbols and devicons.
echo "==> Installing fonts..."

# Install the Hack Nerd Font as a macOS cask (GUI application/resource).
# brew --cask fails if the font was installed outside Homebrew.
# Check if it's already listed by brew or exists in the system font directory.
if ! brew_safe list --cask font-hack-nerd-font &>/dev/null && \
   ! ls ~/Library/Fonts/Hack*Nerd* &>/dev/null 2>&1; then
    brew_safe install --cask font-hack-nerd-font
else
    echo "  Hack Nerd Font already installed, skipping cask install"
fi

###########################
#   LINTERS               #
###########################
# Linters analyze code for errors, style issues, and best practices.
echo "==> Installing linters..."

# yamllint — linter for YAML files (used for CI configs, Kubernetes manifests, etc.).
brew_safe install yamllint

# Test: Verify yamllint is available.
verify_cmd yamllint

# CloudFront linter (disabled — uncomment if working with AWS CloudFormation).
# brew_safe install cfn-lint

###########################
#   RIPGREP               #
###########################
# RipGrep (rg) — extremely fast recursive text search tool, used by Vim plugins.
echo "==> Installing RipGrep..."

# Install ripgrep via Homebrew.
brew_safe install rg

# Test: Verify rg is available.
verify_cmd rg

###########################
#   GPG                   #
###########################
# GnuPG is used for signing Git commits and encrypting/decrypting files.
echo "==> Installing GPG..."

# Install GnuPG (the `gpg` command) via Homebrew.
brew_safe install gnupg

# Install pinentry-mac — a macOS-native PIN entry dialog for GPG passphrase prompts.
brew_safe install pinentry-mac

# Test: Verify both tools are available.
verify_cmd gpg
verify_cmd pinentry-mac

# Ensure the GnuPG config directory exists before writing to its config files.
# GnuPG requires 700 permissions on this directory — it warns or fails otherwise.
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Tell gpg-agent to use pinentry-mac for passphrase prompts instead of the terminal.
# Only add the line if it's not already present (idempotent).
grep -qxF "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" ~/.gnupg/gpg-agent.conf 2>/dev/null || \
    echo "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf

# Restart gpg-agent so it picks up the new config. Ignore errors if it's not running.
killall gpg-agent 2>/dev/null || true

# Test: Verify the pinentry line is present in the config file.
verify_line_in_file "pinentry-program ${BREW_PREFIX}/bin/pinentry-mac" ~/.gnupg/gpg-agent.conf

###########################
#   STORE SECRETS IN 1PW  #
###########################
# Now that GPG and 1Password are both installed, store any generated secrets.
# This section runs after GPG setup so keys exist, and after 1Password setup
# so the `op` CLI is available.
echo "==> Storing secrets in 1Password..."

if [ "${OP_SIGNED_IN:-false}" = "true" ]; then

    # --- Store FileVault recovery key ---
    # The recovery key plist is generated when FileVault is first enabled.
    # We store it in 1Password and then securely delete the local copy.
    if [ "${FILEVAULT_KEY_PENDING:-false}" = "true" ] && [ -f "${FILEVAULT_KEY_PATH:-}" ]; then
        echo "  Saving FileVault recovery key to 1Password..."
        # Read the recovery key from the deferred plist file.
        FILEVAULT_KEY_CONTENT="$(cat "$FILEVAULT_KEY_PATH")"
        # Create a Secure Note in 1Password with the recovery key content.
        # --vault defaults to the user's Personal vault if not specified.
        op item create \
            --category "Secure Note" \
            --title "FileVault Recovery Key - $(hostname)" \
            --vault "Personal" \
            "notesPlain=$FILEVAULT_KEY_CONTENT" 2>/dev/null \
            && echo "  [PASS] FileVault recovery key saved to 1Password" \
            || echo "  [FAIL] Could not save FileVault recovery key to 1Password"
        # Securely delete the local copy now that it's in 1Password.
        # rm -P overwrites the file before deleting on macOS (secure delete).
        rm -P "$FILEVAULT_KEY_PATH" 2>/dev/null || rm -f "$FILEVAULT_KEY_PATH"
        echo "  Local copy of recovery key has been securely deleted."
    fi

    # --- Store GPG private key ---
    # Export the GPG private key for the configured Git email and store it in 1Password.
    # Only export if a key exists for the configured email address.
    GPG_EMAIL="github@barrios.io"
    if gpg --list-secret-keys "$GPG_EMAIL" &>/dev/null; then
        # Check if this key is already stored in 1Password to avoid duplicates (idempotent).
        if ! op item get "GPG Private Key - $(hostname)" --vault "Personal" &>/dev/null; then
            echo "  Exporting GPG private key to 1Password..."
            # Export the ASCII-armored private key to a temp file with restricted permissions.
            GPG_KEY_TMP="$(mktemp)"
            chmod 600 "$GPG_KEY_TMP"
            gpg --export-secret-keys --armor "$GPG_EMAIL" > "$GPG_KEY_TMP"
            # Store the exported key as a Secure Note in 1Password.
            op item create \
                --category "Secure Note" \
                --title "GPG Private Key - $(hostname)" \
                --vault "Personal" \
                "notesPlain=$(cat "$GPG_KEY_TMP")" 2>/dev/null \
                && echo "  [PASS] GPG private key saved to 1Password" \
                || echo "  [FAIL] Could not save GPG private key to 1Password"
            # Securely delete the temp file containing the exported private key.
            rm -P "$GPG_KEY_TMP" 2>/dev/null || rm -f "$GPG_KEY_TMP"
        else
            echo "  [PASS] GPG private key already exists in 1Password"
        fi
    else
        echo "  [SKIP] No GPG key found for $GPG_EMAIL — generate one and re-run to store it."
    fi

    # --- Store SSH key ---
    # If an SSH key exists, store it in 1Password for backup.
    if [ -f "$HOME/.ssh/id_ed25519" ]; then
        if ! op item get "SSH Private Key - $(hostname)" --vault "Personal" &>/dev/null; then
            echo "  Saving SSH private key to 1Password..."
            op item create \
                --category "Secure Note" \
                --title "SSH Private Key - $(hostname)" \
                --vault "Personal" \
                "notesPlain=$(cat "$HOME/.ssh/id_ed25519")" 2>/dev/null \
                && echo "  [PASS] SSH private key saved to 1Password" \
                || echo "  [FAIL] Could not save SSH private key to 1Password"
        else
            echo "  [PASS] SSH private key already exists in 1Password"
        fi
    elif [ -f "$HOME/.ssh/id_rsa" ]; then
        if ! op item get "SSH Private Key - $(hostname)" --vault "Personal" &>/dev/null; then
            echo "  Saving SSH private key (RSA) to 1Password..."
            op item create \
                --category "Secure Note" \
                --title "SSH Private Key - $(hostname)" \
                --vault "Personal" \
                "notesPlain=$(cat "$HOME/.ssh/id_rsa")" 2>/dev/null \
                && echo "  [PASS] SSH private key saved to 1Password" \
                || echo "  [FAIL] Could not save SSH private key to 1Password"
        else
            echo "  [PASS] SSH private key already exists in 1Password"
        fi
    else
        echo "  [SKIP] No SSH key found at ~/.ssh/id_ed25519 or ~/.ssh/id_rsa"
    fi

else
    echo "  [SKIP] 1Password CLI is not signed in — secrets will not be stored."
    echo "  Sign in with 'eval \$(op signin)' and re-run the script to store secrets."
    if [ "${FILEVAULT_KEY_PENDING:-false}" = "true" ]; then
        echo "  IMPORTANT: FileVault recovery key is at ${FILEVAULT_KEY_PATH:-unknown}."
        echo "  Save it manually and then delete the file."
    fi
fi

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
    # Download the installer to a temp file, verify it downloaded fully, then execute.
    NVM_INSTALLER="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh -o "$NVM_INSTALLER"
    bash "$NVM_INSTALLER"
    rm -f "$NVM_INSTALLER"
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
if [ ! -d "$SETUP_HOME/solarized" ]; then
    # Clone the Solarized repo which contains terminal profiles and editor themes.
    git clone https://github.com/altercation/solarized.git
    # Open the Solarized Dark terminal profile in Terminal.app to make it available.
    # Only done on first install to avoid opening it every time the script runs.
    open "$SETUP_HOME/solarized/osx-terminal.app-colors-solarized/xterm-256color/Solarized Dark xterm-256color.terminal"
fi

# Test: Verify the solarized directory exists.
verify_dir "$SETUP_HOME/solarized"

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
    # Download the installer to a temp file, verify it downloaded fully, then execute.
    # --unattended prevents it from changing the default shell or starting a new session.
    OMZ_INSTALLER="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"
    sh "$OMZ_INSTALLER" "" --unattended
    rm -f "$OMZ_INSTALLER"
fi

# Test: Verify the Oh My Zsh directory was created.
verify_dir "$HOME/.oh-my-zsh"

###########################
#   VIM SETUP             #
###########################
# Run the separate Vim setup script which installs Vundle, plugins, and symlinks.
# Use the absolute path derived from the repo root so it works from any working directory.
echo "==> Running VIM setup..."
/bin/bash "$REPO_ROOT/app/vim/vim-setup.sh"

# Install dependencies for the coc.nvim plugin (VS Code-like completion for Vim).
# Only run if the coc.nvim plugin directory exists (it's installed by Vundle).
# Use a subshell so the `cd` doesn't change the working directory for the rest of the script.
# The bundle directory is in ~/setup/vim/ (not the repo) since artifacts live there.
if [ -d "$SETUP_HOME/vim/bundle/coc.nvim" ]; then
    (cd "$SETUP_HOME/vim/bundle/coc.nvim" && npm install)
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
