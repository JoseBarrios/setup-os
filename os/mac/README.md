# os/mac/osx.sh

> **New Mac?** Start with [New Mac: start here](../../README.md#new-mac-start-here). It gets Claude Code running first so Claude can help with this script.

Sets up a Mac for development and for Claude: security settings, Homebrew and dev tools, the Claude desktop app, Claude Code and Chrome, a Vim-centred editor setup, and Git, SSH and GitHub with keys that live in 1Password. Then it pulls `~/Developer/ai` from GitHub and configures Claude Code from it. On a desktop Mac (like a Mac mini) it also keeps the Mac awake, so Claude on it stays reachable from your phone. It is **idempotent**: re-run it any time, and it only changes what is missing.

## Quick Start

```bash
./os/mac/osx.sh
```

Run it as your normal user (not with `sudo`); it asks for your password once. On a standard (non-administrator) account it asks for an administrator instead; see [Standard accounts](#standard-accounts). The first run stops so you can sign in to 1Password. Each run ends with a pass/fail summary and a **Still needs you** list.

Optional overrides:

- `OP_VAULT=<name>` picks the 1Password vault. By default it uses `Personal`, `Private` or `Employee`, whichever exists.
- `AI_REPO=<owner/name>` picks the GitHub repo cloned into `~/Developer/ai`. Default: `JoseBarrios/ai`.
- `KEEP_AWAKE=1` keeps any Mac awake, laptops included; `KEEP_AWAKE=0` skips it. Default: desktop Macs only. See [Keep awake](#keep-awake).

## What It Does

Steps run in this order.

| Step | What happens |
|---|---|
| Homebrew | Installs Homebrew (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel) and adds it to `~/.zprofile`. Installs it only from an administrator account, and runs `brew update` only from the account that owns it. |
| Oh My Zsh | Installed before anything else writes to `~/.zshrc`, because its installer replaces that file. |
| Claude Code | Installed early (native installer, `~/.local/bin/claude`, updates itself) so it can debug failures in the rest of the run. |
| 1Password | Installs the app and CLI (`op`). If the CLI isn't signed in, the script pauses and asks you to sign in and turn on **Settings > Developer > Integrate with 1Password CLI** and **Use the SSH agent**. If it's signed in but can't read your vaults (1Password is locked, or refused this terminal), the check fails and asks you to unlock 1Password and re-run; the SSH key and signing checks wait for that. |
| Disk encryption | Turns on FileVault full-disk encryption and reports progress while the disk encrypts. The recovery key goes straight into 1Password as `FileVault Recovery Key - <host>` and is never written to disk. If 1Password isn't ready, it is kept in `~/.filevault/recovery_key.plist` (owner-only) and moved into 1Password on the next run. On a standard account it only checks; turning it on needs an administrator account. |
| Firewall | Turns on the application firewall and stealth mode. |
| Lockdown Mode | Checks whether it's on. If not, it's turned on as the very last step (see below). |
| Advanced Data Protection | If the Mac is signed in to iCloud, checks whether you've confirmed it's on. If not, it's guided at the end (see below). |
| Packages | `cmake vim git gh gnupg pinentry-mac pyenv yamllint ripgrep jq shellcheck`, plus uv and the Hack Nerd Font. `jq` edits Claude Code's settings, `shellcheck` lints this script. Missing formulae install in one go. `uv` runs Python MCP servers (`uvx`); Homebrew always installs the newest uv, usually only days old, so the script installs a pinned release at least 7 days old (`UV_VERSION`) from GitHub into `~/.local/bin`, checked by SHA-256. To update it, set `UV_VERSION` and its SHA-256s to a newer release at least 7 days old and re-run: the copy in `~/.local/bin` is replaced. Any other uv, like Homebrew's, is left as is. The font cask only installs for Homebrew's owner, so other accounts get the same release from GitHub, checked by SHA-256. |
| Claude apps | Installs the Claude desktop app and Google Chrome (skipped if already in `/Applications`; both update themselves). Checks Chrome for Claude in Chrome and, if it's missing, tells you where to get it. |
| Keep awake | Desktop Macs only: turns system sleep off, starts the Mac again after a power cut, installs Amphetamine (administrator accounts only), and opens Claude and Amphetamine at login. See [Keep awake](#keep-awake). |
| pyenv | Adds pyenv's init lines to `~/.zshrc`. |
| Node | Installs nvm and the newest Node.js LTS published at least 7 days ago (from nodejs.org's release list), and makes it nvm's default. nvm is the only Node manager, and its Node comes first on `PATH`, even when Homebrew's owner has installed `node`. |
| GPG | Sets `pinentry-mac` for passphrase prompts. Kept for file encryption; Git signing uses SSH. |
| SSH | Creates an Ed25519 key in 1Password (`SSH Key - <host>`). The private key never touches disk; the 1Password agent serves it through `~/.ssh/config`. |
| Git | Sets your identity, editor and defaults, and signs commits and tags with the SSH key. See [Git Configuration](#git-configuration). |
| GitHub | Logs in with `gh`, adds GitHub's host keys to `known_hosts` (fetched over HTTPS), and uploads the public key as both an authentication key and a signing key. |
| Tests | Runs `ssh -T git@github.com` and makes a signed test commit, then verifies it. |
| This repo over SSH | A new Mac clones this repo over HTTPS. Once SSH to GitHub works, its remote is switched to `git@github.com:JoseBarrios/setup-os.git` so you can push. |
| AI repo | Clones `~/Developer/ai` over SSH, or brings the copy that's there up to date, runs its `scripts/setup.sh`, then turns on its hourly GitHub sync. See [The AI repo](#the-ai-repo). |
| Claude Code config | Merges secret deny rules into `~/.claude/settings.json`, makes every session follow `~/Developer/ai/AGENTS.md`, and installs your skills as the `jose-skills` plugin. See [Claude Code](#claude-code). Also checks that Claude Code is logged in. |
| Terminal | Imports Solarized Dark and sets it as the default profile, with Hack Nerd Font Mono 14pt. |
| Finder | Shows hidden files. |
| Vim | Runs `app/vim/vim-setup.sh`: Vundle plugins, Solarized, coc.nvim (built with npm) and prettier. Its failures count in this script's summary. |
| ai repo sync | Checks that `~/Developer/ai` has its hourly GitHub sync on and no sync problem. If not, it's handled at the end (see [The AI repo](#the-ai-repo)). |
| Advanced Data Protection (end) | After the summary, if you haven't confirmed it yet, opens your Apple Account in System Settings so you can turn it on, then asks you to confirm. |
| ai repo sync (end) | If needed, starts Claude Code with **Sync the ai repo** (Opus 5.5, max effort). Answer its questions, then type `/exit` to continue. |
| Lockdown Mode (last) | After the summary, opens System Settings > Privacy & Security so you can click **Lockdown Mode > Turn On > Turn On & Restart**. Re-run after the restart to confirm. |

### Lockdown Mode

Apple only supports turning Lockdown Mode on in System Settings, and doing so restarts the Mac, so the script runs it last and guides you through it. The script checks the result by reading `LDMGlobalEnabled` in your global preferences (`defaults read -g LDMGlobalEnabled` is `1` when it's on). Apple doesn't document that key, but Mac admins use it to detect Lockdown Mode.

While it's on: configuration profiles and MDM enrollment are blocked, some web fonts and web features are blocked, unknown FaceTime calls and most Messages attachments are blocked, and on Apple silicon laptops new wired accessories need approval while unlocked. Homebrew, Git, SSH and 1Password are unaffected.

### Advanced Data Protection

Without it, Apple holds the keys to most iCloud data, including iCloud Drive, Photos, Notes and device backups. With it, only your devices can decrypt that data. Turning it on once covers every device on your Apple Account.

Apple only supports turning it on by hand in **System Settings > your name > iCloud > Advanced Data Protection**. It needs two-factor authentication, a recovery contact or recovery key (keep the key in 1Password), and every device on the account up to date. Apple offers no way for a script to read whether it's on, so the script records your confirmation in `~/setup/.adp-confirmed` and shows it as confirmed on later runs. Delete that file to be asked again.

### Keep awake

Claude on your phone can use this Mac only while the Mac is awake and the Claude app is running. On a desktop Mac (no battery), the script:

- Turns system sleep off (`pmset -a sleep 0`). The display still sleeps.
- Starts the Mac again after a power cut (`pmset -a autorestart 1`).
- Installs [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) from the Mac App Store with `mas`, which needs you signed in to the App Store. `mas` needs sudo, so on a standard account the summary asks you to install it from the App Store. Its settings can't be scripted, so the first time, set it to start a session when it launches, **Indefinitely**.
- Adds a login item (`~/Library/LaunchAgents/local.setup-os.login-apps.plist`) that opens Claude and Amphetamine each time you log in, and opens them now.

Laptops are skipped, since they'd drain the battery. `KEEP_AWAKE=1` turns this on for any Mac (laptops have no power-cut setting, so that step is skipped); `KEEP_AWAKE=0` skips it but doesn't undo an earlier run.

After a restart (a power cut or a macOS update), Claude is offline until you log in on the Mac: FileVault, which this script turns on, turns off automatic login.

### Standard accounts

The script also runs from a standard (non-administrator) account, such as a separate account for Claude on a Mac an administrator already set up. It doesn't ask for your password at the start. Instead:

- Each step that needs an administrator (the firewall, `pmset`) opens a macOS window asking for an administrator's name and password, and only when the setting isn't already on. The command goes to `osascript` as an argument, so the password is typed into macOS, never into the script.
- Homebrew belongs to the account that installed it. From any other account, missing packages and apps install as that account (`sudo -u <owner> -i brew install ...`), after an administrator approves in the same window. Missing formulae install in one go; each missing app (1Password, its CLI, Claude, Chrome) asks separately. Homebrew's output appears when the install finishes. Only its owner's account runs `brew update`, though Homebrew may update itself, as its owner, before an install.
- If Homebrew isn't installed, the summary asks you to install it from an administrator account.
- FileVault is only checked. If it's off, the summary asks you to turn it on from an administrator account, since `fdesetup` asks for the password of the account it enables.
- Amphetamine is listed under **Still needs you**, to install from the App Store.

Clicking **Cancel** in the window, or running without a terminal (stdin and stdout not a terminal), skips that step, and its check fails.

### The AI repo

`~/Developer/ai` holds your skills, shared agent instructions (`AGENTS.md`) and scheduled task prompts. It's private, so it's cloned over SSH, after your key is on GitHub.

If `~/Developer/ai` already exists, the script never overwrites your work:

| State | What the script does |
|---|---|
| Behind GitHub, nothing uncommitted | Fast-forwards to GitHub. |
| Behind GitHub, uncommitted changes | Nothing. Asks you to commit them first. |
| Behind GitHub, which adds files that already exist here (untracked or gitignored, e.g. in `private/`) | Nothing. Lists the files so you can move them aside. |
| Commits that aren't on GitHub | Nothing. Asks you to push them. |
| Both sides changed | Nothing. Points you to **Sync the ai repo** (see [README](../../README.md#sync-developerai)), which merges both sides. |
| No remote (copied with a git bundle) | Adds GitHub as `origin`, then as above. |
| HTTPS remote, with or without a token in it | Switches it to SSH, then as above. Remote URLs are printed without tokens. |
| History unrelated to GitHub's | Nothing (it only adds `origin`). Points you to **Sync the ai repo**, which backs this copy up to a branch and merges it with GitHub. |
| Empty folder | Clones into it. |
| Not a git repo | Nothing. Asks you to move it aside. |

A branch that tracks nothing is set to track GitHub's; one that already tracks a branch is left as is.

It also runs the repo's `scripts/setup.sh`, which that repo asks for once per clone (re-running it is safe): it turns on the repo's git hooks, pins its commit identity to github@barrios.io, turns on object checks on fetch, links `op-sa` into `~/.local/bin` and creates `private/` with an empty blocklist. It sets `core.hooksPath` to `scripts/hooks` too, for a copy without `scripts/setup.sh`, so the repo's secret scan runs before each commit (the check fails if the hook is missing or not executable). Then it runs the repo's `scripts/install-sync.sh`: a launchd job (`io.barrios.ai-sync`) that syncs with GitHub every hour. It fast-forwards when behind, pushes when ahead, never merges or force-pushes, and shows a notification when it needs you. If neither this copy nor GitHub has `scripts/install-sync.sh` yet, **Still needs you** says so; re-run once the ai repo on GitHub has it. If only GitHub has it, the copy wasn't pulled, and the end of the run offers **Sync the ai repo**. `private/` is gitignored, so a new Mac never gets it from GitHub; copy what you need from another Mac.

Near the end, the script checks that the sync job is loaded and hasn't flagged a problem (`~/Library/Logs/ai-sync.last` is empty). If it has, or the copy needs a merge, an interactive run ends (before Lockdown Mode, which restarts the Mac) by starting Claude Code in this repo with **Sync the ai repo**: Claude backs up the Mac's copy to a GitHub branch, merges it with GitHub without losing anything, and turns on the job, following [`CLAUDE.md`](../../CLAUDE.md). It isn't started just because `scripts/install-sync.sh` is missing, since Claude can't turn on a job that isn't in the repo.

### Claude Code

All of this is user-level config, so it applies in every folder:

- **`~/.claude/settings.json`** gets a `$schema` and these deny rules, merged with what's there (other keys are kept, nothing is duplicated, and an existing file is backed up as `settings.json.bak.<time>` when it changes):

  ```
  Read(~/.ssh/**)  Read(~/.gnupg/**)  Read(~/.filevault/**)  Read(//**/.env)  Read(//**/.env.*)
  ```

  They stop Claude's file tools (Read, Edit, Write) from opening keys, the FileVault fallback file or `.env` files. `//` starts at the root of the disk, so the `.env` rules cover every folder, not just the one Claude starts in.
- **`~/.claude/CLAUDE.md`** gets the line `@~/Developer/ai/AGENTS.md`, so every session follows your shared rules. Anything else in the file is kept.
- **Skills:** `claude plugin marketplace add ~/Developer/ai --scope user`, then `claude plugin install jose-skills@barrios-ai --scope user`. Only a user-scope install counts, so the skills load in every folder. The marketplace is read in place, so skills you pull or edit load in the next session.

Local MCP servers in `~/Developer/ai/mcp/` aren't installed: they run on the hub Mac only.

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
- **Signing in** to the Claude app, Claude Code and Claude in Chrome. The summary reminds you about the app when it's first installed, and lists Claude Code until it's logged in and Claude in Chrome until it's installed.
- **Amphetamine:** signing in to the App Store so it can install (on a standard account, installing it from the App Store yourself), and its settings (see [Keep awake](#keep-awake)).

## Secrets

- Secrets never go into command-line arguments. The FileVault recovery key is piped to `op` as JSON built by a shell builtin.
- No private key is ever written to disk or printed.
- On a standard account, an administrator's password goes into a macOS window, never into the script, its arguments or its output.
- Nothing secret is sent to Claude when the error handler asks it to debug a failure.

## Error Handling

The script uses `set -uo pipefail` without `-e`. An `ERR` trap logs each failed command and, if Claude Code is installed, asks it to diagnose the failure with `claude --print`. The run then continues so you see every result. The exit code is `0` only if every check passed.

## Upgrading From the Previous Version

- If an older run left a recovery key in `~/.filevault/recovery_key.plist`, it is moved into 1Password and the file is deleted.
- If FileVault is waiting on a deferred enable from the old script, log out and back in, then re-run.
- Homebrew `node` from the old script is no longer installed but isn't removed; nvm's Node comes first on `PATH`.
- `gpg.program` from the old script is left in place but unused, since signing is now SSH.
- A `~/Developer/ai` copied with a git bundle (no remote) gets GitHub as its remote; see [The AI repo](#the-ai-repo).
- Old YouCompleteMe or tern_for_vim checkouts in `~/setup/vim/bundle` are no longer rebuilt. `.vimrc` doesn't load them; delete them if you like.

## Repository Context

```
setup-os/
├── app/
│   └── vim/
│       ├── .vimrc         ← linked to ~/.vimrc
│       └── vim-setup.sh
├── os/
│   ├── linux/
│   │   ├── kali.sh
│   │   └── raspbian.sh
│   └── mac/
│       ├── osx.sh        ← this script
│       └── README.md
├── CLAUDE.md
├── README.md
├── .gitignore
└── LICENSE (MIT)
```

## License

MIT, see [LICENSE](../../LICENSE).
