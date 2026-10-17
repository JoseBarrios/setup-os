#!/bin/bash
# Raspberry Pi OS setup: updates packages, installs Git, Vim, CMake and Node
# from apt, sets up Vim from this repo, and installs Claude Code on 64-bit
# Raspberry Pi OS (Claude Code has no 32-bit ARM build).
# Run as your normal user from anywhere; it uses sudo when it needs to.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

sudo apt-get update
sudo apt-get dist-upgrade -y
sudo apt-get install -y vim git cmake nodejs npm curl
sudo apt-get clean

# ~/.local/bin holds Claude Code and global npm tools such as prettier, so
# `npm install -g` works without sudo.
SHELL_RC="$HOME/.bashrc"
case "${SHELL:-}" in *zsh) SHELL_RC="$HOME/.zshrc" ;; esac
# shellcheck disable=SC2016  # literal line for the shell rc file
grep -qs 'HOME/.local/bin' "$SHELL_RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
export PATH="$HOME/.local/bin:$PATH"
npm config set prefix "$HOME/.local"

# Claude Code (native installer; it updates itself). dpkg reports the
# userland: a 64-bit kernel can run 32-bit Raspberry Pi OS.
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if [ "$ARCH" = "arm64" ]; then
    if ! command -v claude >/dev/null 2>&1; then
        CLAUDE_INSTALLER="$(mktemp)"
        curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_INSTALLER" && bash "$CLAUDE_INSTALLER"
        rm -f "$CLAUDE_INSTALLER"
    fi
else
    echo "Skipping Claude Code: it needs 64-bit Raspberry Pi OS (this is $ARCH)."
fi

# Vim plugins and config from this repo (replaces the old vim-dots repo).
/bin/bash "$REPO_ROOT/app/vim/vim-setup.sh"

git config --global core.editor vim
