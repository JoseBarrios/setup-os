# os/mac/osx.sh

> **New Mac?** Start with [New Mac: start here](../../README.md#new-mac-start-here). It gets Claude Code running first so Claude can help with this script.

Sets up a Mac for development: security settings, Homebrew and dev tools, a Vim-centred editor setup, and Git, SSH and GitHub with keys that live in 1Password. It is **idempotent**: re-run it any time, and it only changes what is missing.

## Quick Start

```bash
./os/mac/osx.sh
```

Run it as your normal user (not with `sudo`); it asks for your password once. The first run stops so you can sign in to 1Password. Each run ends with a pass/fail summary and a **Still needs you** list.

Optional: `OP_VAULT=<name> ./os/mac/osx.sh` picks the 1Password vault. By default it uses `Personal`, `Private` or `Employee`, whichever exists.

## What It Does

Steps run in this order.

| Step | What happens |
|---|---|
| Homebrew | Installs Homebrew (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel) and adds it to `~/.zprofile`. |
| Oh My Zsh | Installed before anything else writes to `~/.zshrc`, because its installer replaces that file. |
| Claude Code | Installed early so it can debug failures in the rest of the run. |
| 1Password | Installs the app and CLI (`op`). If the CLI isn't signed in, the script pauses and asks you to sign in and turn on **Settings > Developer > Integrate with 1Password CLI** and **Use the SSH agent**. |
| Disk encryption | Turns on FileVault full-disk encryption and reports progress while the disk encrypts. The recovery key goes straight into 1Password as `FileVault Recovery Key - <host>` and is never written to disk. If 1Password isn't ready, it is kept in `~/.filevault/recovery_key.plist` (owner-only) and moved into 1Password on the next run. |
| Firewall | Turns on the application firewall and stealth mode. |
| Lockdown Mode | Checks whether it's on. If not, it's turned on as the very last step (see below). |
| Advanced Data Protection | If the Mac is signed in to iCloud, checks whether you've confirmed it's on. If not, it's guided at the end (see below). |
| Packages | `cmake vim git gh gnupg pinentry-mac pyenv yamllint ripgrep`, plus the Hack Nerd Font. |
| pyenv | Adds pyenv's init lines to `~/.zshrc`. |
| Node | Installs nvm and the current Node.js LTS. nvm is the only Node manager. |
| GPG | Sets `pinentry-mac` for passphrase prompts. Kept for file encryption; Git signing uses SSH. |
| SSH | Creates an Ed25519 key in 1Password (`SSH Key - <host>`). The private key never touches disk; the 1Password agent serves it through `~/.ssh/config`. |
| Git | Sets your identity, editor and defaults, and signs commits and tags with the SSH key. |
| GitHub | Logs in with `gh`, adds GitHub's host keys to `known_hosts` (fetched over HTTPS), and uploads the public key as both an authentication key and a signing key. |
| Tests | Runs `ssh -T git@github.com` and makes a signed test commit, then verifies it. |
| Terminal | Imports Solarized Dark and sets it as the default profile, with Hack Nerd Font Mono 14pt. |
| Finder | Shows hidden files. |
| Vim | Runs `app/vim/vim-setup.sh` and installs coc.nvim's Node dependencies. |
| Advanced Data Protection (end) | After the summary, if you haven't confirmed it yet, opens your Apple Account in System Settings so you can turn it on, then asks you to confirm. |
| Lockdown Mode (last) | After the summary, opens System Settings > Privacy & Security so you can click **Lockdown Mode > Turn On > Turn On & Restart**. Re-run after the restart to confirm. |

### Lockdown Mode

Apple only supports turning Lockdown Mode on in System Settings, and doing so restarts the Mac, so the script runs it last and guides you through it. The script checks the result by reading `LDMGlobalEnabled` in your global preferences (`defaults read -g LDMGlobalEnabled` is `1` when it's on). Apple doesn't document that key, but Mac admins use it to detect Lockdown Mode.

While it's on: configuration profiles and MDM enrollment are blocked, some web fonts and web features are blocked, unknown FaceTime calls and most Messages attachments are blocked, and on Apple silicon laptops new wired accessories need approval while unlocked. Homebrew, Git, SSH and 1Password are unaffected.

### Advanced Data Protection

Without it, Apple holds the keys to most iCloud data, including iCloud Drive, Photos, Notes and device backups. With it, only your devices can decrypt that data. Turning it on once covers every device on your Apple Account.

Apple only supports turning it on by hand in **System Settings > your name > iCloud > Advanced Data Protection**. It needs two-factor authentication, a recovery contact or recovery key (keep the key in 1Password), and every device on the account up to date. Apple offers no way for a script to read whether it's on, so the script records your confirmation in `~/setup/.adp-confirmed` and shows it as confirmed on later runs. Delete that file to be asked again.

### Git Configuration

```
user.name             = JoseBarrios
user.email            = github@barrios.io
core.editor           = vim
init.defaultBranch    = main
pull.rebase           = true
rebase.autoStash      = true
push.autoSetupRemote  = true
fetch.prune           = true
merge.tool            = vimdiff
merge.conflictstyle   = zdiff3
mergetool.prompt      = false
mergetool.keepBackup  = false

# Signing (set once the 1Password SSH key exists)
gpg.format                 = ssh
user.signingkey            = <public key from 1Password>
gpg.ssh.program            = /Applications/1Password.app/Contents/MacOS/op-ssh-sign
gpg.ssh.allowedSignersFile = ~/.config/git/allowed_signers
commit.gpgsign             = true
tag.gpgsign                = true
```

The global ignore file (`~/.config/git/ignore`, or your existing `core.excludesFile`) gets `.DS_Store`, Vim swap files and `.env` files (but not `.env.example`).

## Not Automated

- **Existing private keys on disk** (`~/.ssh/id_ed25519`, `~/.ssh/id_rsa`) are left alone. Import them into 1Password and delete them if you still need them.

## Secrets

- Secrets never go into command-line arguments. The FileVault recovery key is piped to `op` as JSON built by a shell builtin.
- No private key is ever written to disk or printed.
- Nothing secret is sent to Claude when the error handler asks it to debug a failure.

## Error Handling

The script uses `set -uo pipefail` without `-e`. An `ERR` trap logs each failed command and, if Claude Code is installed, asks it to diagnose the failure with `claude --print`. The run then continues so you see every result. The exit code is `0` only if every check passed.

## Upgrading From the Previous Version

- If an older run left a recovery key in `~/.filevault/recovery_key.plist`, it is moved into 1Password and the file is deleted.
- If FileVault is waiting on a deferred enable from the old script, log out and back in, then re-run.
- Homebrew `node` from the old script is no longer installed but isn't removed; nvm's Node comes first on `PATH`.
- `gpg.program` from the old script is left in place but unused, since signing is now SSH.

## Repository Context

```
setup-os/
├── app/
│   ├── vim/
│   └── vimrc
├── os/
│   ├── linux/
│   │   ├── kali.sh
│   │   └── raspbian.sh
│   └── mac/
│       ├── osx.sh        ← this script
│       └── README.md
├── .gitignore
└── LICENSE (MIT)
```

## License

MIT, see [LICENSE](../../LICENSE).
