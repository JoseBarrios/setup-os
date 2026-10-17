# setup-os

Setup scripts for my machines. The Mac script is [`os/mac/osx.sh`](os/mac/osx.sh); [`os/mac/README.md`](os/mac/README.md) explains what it does.

## New Mac: start here

Steps 1 and 2 get Claude Code running with this repo. In steps 3 and 4, Claude helps you run the script, which installs everything else, pulls `~/Developer/ai` from GitHub and sets up Claude from it.

### 1. By hand

1. Finish Setup Assistant. If it offers FileVault, choose **Not Now**: the script turns it on and saves the recovery key in 1Password.
2. Name the Mac in **System Settings > General > About > Name**. The SSH key and FileVault recovery key are saved in 1Password under this name.
3. Update macOS in **System Settings > General > Software Update**.
4. Install [1Password](https://1password.com/downloads/mac) and sign in. In **Settings > Developer**, turn on **Use the SSH agent** and **Integrate with 1Password CLI**.

Skip the Claude app and Chrome: the script installs both.

### 2. Install Claude Code and get this repo

In Terminal, install Apple's Command Line Tools (for git). Click **Install** in the window that opens and wait for it to finish. If it says they're already installed, carry on:

```sh
xcode-select --install
```

Install Claude Code:

```sh
curl -fsSL https://claude.ai/install.sh | bash
grep -qs '.local/bin' ~/.zprofile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
export PATH="$HOME/.local/bin:$PATH"
claude --version
```

Get this repo. It's public, so no SSH key is needed yet:

```sh
mkdir -p ~/Developer
git clone https://github.com/JoseBarrios/setup-os.git ~/Developer/setup-os
```

### 3. Start Claude Code

```sh
cd ~/Developer/setup-os
claude
```

Log in when the browser opens, then type **Set up this Mac**. Claude follows [`CLAUDE.md`](CLAUDE.md).

### 4. Run the setup script with Claude

Claude can't type passwords, so you run the script in a second Terminal tab (⌘T) while Claude explains each prompt and fixes anything that fails. `script` saves everything it shows to a log in `~/setup/logs`, so Claude reads the log instead of you pasting output:

```sh
mkdir -p ~/setup/logs && script -q -F ~/setup/logs/osx-$(date +%Y%m%d-%H%M%S).log ~/Developer/setup-os/os/mac/osx.sh
```

Once your SSH key is on GitHub, the script pulls `~/Developer/ai` (private, so over SSH), turns on its hourly GitHub sync, and sets up Claude Code from it: every session follows its `AGENTS.md`, and your skills install as a plugin. `private/` in that repo isn't in git, so copy anything you need from it from another Mac.

On a desktop Mac like a Mac mini, it also turns sleep off, installs Amphetamine (on an administrator account) and opens the Claude app at login, so Claude on your phone can always reach this Mac. After a restart, log in on the Mac to bring Claude back: FileVault turns off automatic login.

At the Advanced Data Protection prompt, press Enter and turn it on; it doesn't restart the Mac. If an ai repo sync prompt appears, press Enter: Claude Code syncs `~/Developer/ai` with GitHub in that tab; type `/exit` when it's done. At the Lockdown Mode prompt, type `s` for now: turning it on restarts the Mac. After the script, Claude checks everything and lists what's left, such as signing in to the Claude app, adding Claude in Chrome and setting up Amphetamine.

Last, run the script again the same way and press Enter at the Lockdown Mode step. After the restart, run it once more: it should end with **ALL CHECKS PASSED** and nothing under **Still needs you**.

## Already set up

Re-run the script any time: it pulls new commits into `~/Developer/ai` and applies any changes made to this repo.

```sh
git -C ~/Developer/setup-os pull
~/Developer/setup-os/os/mac/osx.sh
```

It never overwrites work in `~/Developer/ai`. If that copy has commits GitHub doesn't, uncommitted changes, or a history that doesn't match GitHub's, it says so under **Still needs you** and leaves it as is. Then follow [Sync `~/Developer/ai`](#sync-developerai).

## Sync `~/Developer/ai`

Both Macs sync `~/Developer/ai` through the private GitHub repo `JoseBarrios/ai`. Whenever a Mac's copy needs it, `osx.sh` ends by starting Claude Code with **Sync the ai repo**. To run it on its own:

```sh
cd ~/Developer/setup-os
claude
```

Then type **Sync the ai repo**. Claude backs up the Mac's copy to a GitHub branch, merges it with GitHub without losing anything from either side, and installs the hourly job. It follows [`CLAUDE.md`](CLAUDE.md).

After that, the hourly job keeps the Mac in step. If both Macs change at once, it shows a notification: re-run `osx.sh`, or type **Sync the ai repo** again.
