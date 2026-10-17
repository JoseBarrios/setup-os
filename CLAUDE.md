# setup-os

Setup scripts for Jose's machines. Mac: `os/mac/osx.sh`, documented in `os/mac/README.md`. The new-Mac steps for Jose are in `README.md`.

## Rules

- This repo is public. Never commit secrets or private info: no personal emails, phone numbers, account IDs or hostnames. Git commits use github@barrios.io.
- Never use em dashes. Be succinct and direct.
- `osx.sh` must stay idempotent and run under macOS's `/bin/bash` 3.2. Update `os/mac/README.md` with any change to it.
- Secrets live only in 1Password: never on disk, in command-line arguments or in output.
- `~/Developer/ai` has its own rules (its `AGENTS.md`); every change there needs a `CHANGELOG.md` entry. Change it only when following "Sync the ai repo" below. Never force-push, rewrite or delete its history, or run `git reset --hard` there. Tell Jose if something there looks wrong.

## When Jose says "Set up this Mac"

Jose has done steps 1 and 2 of `README.md`. You can't answer password, sudo or browser prompts, so never run `osx.sh` or `sudo` yourself. Jose runs them in a second Terminal tab.

1. **Check the basics:** `claude --version`, `xcode-select -p` and `git --version`. If something is missing, point Jose to the `README.md` step that covers it.
2. **Run the setup script.** Read `os/mac/README.md` and `os/mac/osx.sh`. Ask Jose to run `~/Developer/setup-os/os/mac/osx.sh` in the second tab, to turn on Advanced Data Protection at its prompt, to press Enter at the ai repo sync prompt if it shows one (it starts a second Claude Code session in that tab that runs "Sync the ai repo"), and to type `s` at the Lockdown Mode prompt for now, since turning it on restarts the Mac. Explain prompts when asked. When something fails, read the output Jose pastes and fix the cause. If it's a bug in `osx.sh`, fix the script, check it with `bash -n` and `shellcheck`, and have Jose re-run it.
3. **The AI repo.** The script clones `~/Developer/ai` or fast-forwards it, and never overwrites local work. If it reports uncommitted changes, local commits, both sides changed or unrelated history there, show Jose what differs (`git -C ~/Developer/ai status -sb`, `git -C ~/Developer/ai log --oneline HEAD...origin/main`) and, once he agrees, follow "Sync the ai repo" below. Skip `mcp/`: local MCP servers run on the hub Mac only. If Jose says this Mac is the new hub, stop and ask.
4. **Finish.** Once the script's summary shows no failures, check each of these and report pass or fail:
   - `claude doctor`, `claude auth status` and `gh auth status`
   - `ssh -T git@github.com` prints "successfully authenticated" (it exits 1 even then)
   - `fdesetup status` says FileVault is On
   - `git config --global user.email` is github@barrios.io, and `commit.gpgsign` is true
   - `git -C ~/Developer/setup-os remote get-url origin` and `git -C ~/Developer/ai remote get-url origin` start with `git@github.com:`
   - `git -C ~/Developer/ai fetch` works (its `origin` is the private GitHub repo `JoseBarrios/ai`), and `git -C ~/Developer/ai status -sb` then shows `main...origin/main` with nothing ahead or behind
   - `launchctl print gui/$(id -u)/io.barrios.ai-sync` finds the ai repo's hourly GitHub sync (the script installs it with `~/Developer/ai/scripts/install-sync.sh`)
   - `~/.claude/CLAUDE.md` has the line `@~/Developer/ai/AGENTS.md`
   - `claude plugin list` shows `jose-skills@barrios-ai`
   - On a desktop Mac (`pmset -g batt` lists no `InternalBattery`): `pmset -g` shows `sleep 0` and `autorestart 1`, `/Applications/Amphetamine.app` exists, and `~/Library/LaunchAgents/local.setup-os.login-apps.plist` exists
5. **Hand off.** List what's left, including the script's "Still needs you" items (signing in to the Claude app, adding Claude in Chrome and Amphetamine's settings, if listed). Last, Jose re-runs the script and presses Enter at the Lockdown Mode step. After the restart he runs it once more to confirm everything passes.

## When Jose says "Sync the ai repo"

Bring this Mac's `~/Developer/ai` in line with GitHub (`JoseBarrios/ai`) and turn on its hourly sync. Work in `~/Developer/ai` and follow its `AGENTS.md`. Never force-push, rewrite or delete history or branches, run `git reset --hard`, or touch `private/`.

1. If `git status` shows uncommitted changes, show them to Jose and commit only what he approves, each with its `CHANGELOG.md` line.
2. Make sure `origin` points to `JoseBarrios/ai` on GitHub (SSH if this Mac's GitHub SSH key works, otherwise HTTPS through `gh`), and that commits there use github@barrios.io.
3. Back up this Mac's work: push `HEAD` to a new branch named `backup/<LocalHostName>-<YYYY-MM-DD>`.
4. `git fetch origin`, then bring `main` and `origin/main` together:
   - Behind: fast-forward.
   - Ahead: push.
   - Diverged: merge `origin/main` (add `--allow-unrelated-histories` if they share no history). Resolve every conflict so neither side loses a change. In `CHANGELOG.md`, keep every entry from both sides, grouped by date, newest first. Where the two versions disagree and the changelogs don't say which is newer, ask Jose. Add a `CHANGELOG.md` line describing the merge, run `scripts/check-secrets.sh`, then commit and push.

   Done when `git status -sb` shows `main...origin/main` with nothing ahead or behind.
5. If `gh` isn't installed or logged in, set it up with Jose. Then run `scripts/install-sync.sh` and `scripts/sync.sh`, and show him the last lines of `~/Library/Logs/ai-sync.log`.
6. Bring this repo's `master` in line with `origin/master` the same way: fast-forward or push. If it has diverged, stop and tell Jose.
7. Report what was merged, anything uncertain, and the backup branch name.
