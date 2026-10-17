# setup-os

Setup scripts for Jose's machines. Mac: `os/mac/osx.sh`, documented in `os/mac/README.md`. The new-Mac steps for Jose are in `README.md`.

## Rules

- This repo is public. Never commit secrets or private info: no personal emails, phone numbers, account IDs or hostnames. Git commits use github@barrios.io.
- Never use em dashes. Be succinct and direct.
- `osx.sh` must stay idempotent and run under macOS's `/bin/bash` 3.2. Update `os/mac/README.md` with any change to it.
- Secrets live only in 1Password: never on disk, in command-line arguments or in output.

## When Jose says "Set up this Mac"

Jose has done steps 1 to 4 of `README.md`. You can't answer password, sudo or browser prompts, so never run `osx.sh` or `sudo` yourself. Jose runs them in a second Terminal tab.

1. **Check the basics:** `claude --version`, `xcode-select -p`, `git --version`, and that `~/Developer/ai` is a git repo. If something is missing, point Jose to the `README.md` step that covers it.
2. **Set up `~/Developer/ai`.** It doesn't depend on the script. Follow its `README.md` and `vendors/claude/README.md`:
   - `git -C ~/Developer/ai config core.hooksPath scripts/hooks`
   - `claude plugin marketplace add ~/Developer/ai`, then `claude plugin install jose-skills@barrios-ai`
   - Make sure `~/.claude/CLAUDE.md` has the line `@~/Developer/ai/AGENTS.md`. Add it if missing and keep everything else in the file.
   - Skip `mcp/`: local MCP servers run on the hub Mac only. If Jose says this Mac is the new hub, stop and ask.
   - Don't edit files inside `~/Developer/ai`; its changes must be logged in its `CHANGELOG.md`. Tell Jose if something there looks wrong.
3. **Run the setup script.** Read `os/mac/README.md` and `os/mac/osx.sh`. Ask Jose to run `~/Developer/setup-os/os/mac/osx.sh` in the second tab, to turn on Advanced Data Protection at its prompt, and to type `s` at the Lockdown Mode prompt for now, since turning it on restarts the Mac. Explain prompts when asked. When something fails, read the output Jose pastes and fix the cause. If it's a bug in `osx.sh`, fix the script, check it with `bash -n` (and `shellcheck` if installed), and have Jose re-run it.
4. **Finish.** Once the script's summary shows no failures:
   - Switch this repo to SSH: `git -C ~/Developer/setup-os remote set-url origin git@github.com:JoseBarrios/setup-os.git`
   - Check each of these and report pass or fail:
     - `claude doctor` and `gh auth status`
     - `ssh -T git@github.com` prints "successfully authenticated" (it exits 1 even then)
     - `git -C ~/Developer/ai fetch` works (its `origin` is the private GitHub repo `JoseBarrios/ai`)
     - `fdesetup status` says FileVault is On
     - `git config --global user.email` is github@barrios.io, and `commit.gpgsign` is true
     - `claude plugin list` shows `jose-skills@barrios-ai`
5. **Hand off.** List what's left, including the script's "Still needs you" items. Last, Jose re-runs the script and presses Enter at the Lockdown Mode step. After the restart he runs it once more to confirm everything passes.
