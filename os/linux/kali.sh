#!/bin/bash
# Kali Linux setup: updates packages, installs Ansible, Git, Vim and Node from
# apt, sets up Vim from this repo, and installs Claude Code.
# Run as your normal user from anywhere; it uses sudo when it needs to.
#
# First, change the default passwords if you haven't:
#   passwd            # your user
#   sudo passwd root  # root

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

sudo apt update
sudo apt full-upgrade -y

# Ansible comes from apt: `pip install --user` is blocked on Kali (PEP 668).
sudo apt install -y ansible git vim nodejs npm curl

# ~/.local/bin holds Claude Code and global npm tools such as prettier, so
# `npm install -g` works without sudo.
SHELL_RC="$HOME/.bashrc"
case "${SHELL:-}" in *zsh) SHELL_RC="$HOME/.zshrc" ;; esac
# shellcheck disable=SC2016  # literal line for the shell rc file
grep -qs 'HOME/.local/bin' "$SHELL_RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
export PATH="$HOME/.local/bin:$PATH"
npm config set prefix "$HOME/.local"

# Claude Code (native installer; it updates itself). It has 64-bit x86 and
# ARM builds only; dpkg reports the userland's architecture.
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
    amd64|arm64)
        if ! command -v claude >/dev/null 2>&1; then
            CLAUDE_INSTALLER="$(mktemp)"
            curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_INSTALLER" && bash "$CLAUDE_INSTALLER"
            rm -f "$CLAUDE_INSTALLER"
        fi
        ;;
    *)
        echo "Skipping Claude Code: it needs 64-bit x86 or ARM (this is $ARCH)."
        ;;
esac

# Vim plugins and config from this repo.
/bin/bash "$REPO_ROOT/app/vim/vim-setup.sh"

git config --global core.editor vim
