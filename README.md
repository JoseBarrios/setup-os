# setup-os

Setup scripts for my machines. The Mac script is [`os/mac/osx.sh`](os/mac/osx.sh); [`os/mac/README.md`](os/mac/README.md) explains what it does.

## New Mac: start here

Steps 1 to 4 get Claude Code running with this repo and `~/Developer/ai`. In step 5, Claude helps with the rest.

### 1. By hand

1. Finish Setup Assistant. If it offers FileVault, choose **Not Now**: the script turns it on and saves the recovery key in 1Password.
2. Name the Mac in **System Settings > General > About > Name**. The SSH key and FileVault recovery key are saved in 1Password under this name.
3. Update macOS in **System Settings > General > Software Update**.
4. Install [1Password](https://1password.com/downloads/mac) and sign in. In **Settings > Developer**, turn on **Use the SSH agent** and **Integrate with 1Password CLI**.
5. Install the [Claude app](https://claude.ai/download) and sign in.

### 2. Install Claude Code and get this repo

In Terminal, install Apple's Command Line Tools (for git). Click **Install** in the window that opens and wait for it to finish:

```sh
xcode-select --install
```

Then:

```sh
# Claude Code
curl -fsSL https://claude.ai/install.sh | bash
grep -qs '.local/bin' ~/.zprofile || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
export PATH="$HOME/.local/bin:$PATH"
claude --version

# This repo. It's public, so no SSH key is needed yet.
mkdir -p ~/Developer
git clone https://github.com/JoseBarrios/setup-os.git ~/Developer/setup-os
```

### 3. Copy `~/Developer/ai` from another Mac

It's a private GitHub repo (`JoseBarrios/ai`), but this Mac can't sign in to GitHub until the setup script runs, so copy it as a git bundle. On a Mac that has it:

```sh
cd ~/Developer/ai
git status        # commit and push anything pending first
git bundle create ~/Desktop/ai.bundle --all
```

AirDrop `ai.bundle` to the new Mac. If the Macs use different Apple IDs, set AirDrop on the new Mac to **Everyone for 10 Minutes**. Then on the new Mac:

```sh
git clone ~/Downloads/ai.bundle ~/Developer/ai
git -C ~/Developer/ai remote set-url origin git@github.com:JoseBarrios/ai.git
rm ~/Downloads/ai.bundle
```

Delete `ai.bundle` from the other Mac's Desktop too. `private/` isn't in the bundle on purpose. After the setup script, this copy syncs through GitHub like the others.

### 4. Start Claude Code

```sh
cd ~/Developer/setup-os
claude
```

Log in when the browser opens, then type **Set up this Mac**. Claude follows [`CLAUDE.md`](CLAUDE.md).

### 5. Run the setup script with Claude

Claude first sets up `~/Developer/ai`: its git hooks, your skills as a Claude Code plugin, and `~/.claude/CLAUDE.md` so every session follows `AGENTS.md`.

Claude can't type passwords, so you run the script in a second Terminal tab (⌘T) while Claude explains each prompt and fixes anything that fails:

```sh
~/Developer/setup-os/os/mac/osx.sh
```

At the Advanced Data Protection prompt, press Enter and turn it on; it doesn't restart the Mac. At the ai repo sync prompt, press Enter: Claude Code syncs `~/Developer/ai` with GitHub in that tab; type `/exit` when it's done. At the Lockdown Mode prompt, type `s` for now: turning it on restarts the Mac. After the script, Claude switches this repo to SSH, checks everything and lists what's left.

Last, run the script again and press Enter at the Lockdown Mode step. After the restart, run it once more: it should end with **ALL CHECKS PASSED** and nothing under **Still needs you**.

## Sync `~/Developer/ai`

Both Macs sync `~/Developer/ai` through the private GitHub repo `JoseBarrios/ai`. Whenever a Mac's copy needs it, `osx.sh` ends by starting Claude Code with **Sync the ai repo**. To run it on its own:

```sh
cd ~/Developer/setup-os
claude
```

Then type **Sync the ai repo**. Claude backs up the Mac's copy to a GitHub branch, merges it with GitHub without losing anything from either side, and installs the hourly job. It follows [`CLAUDE.md`](CLAUDE.md).

After that, the hourly job keeps the Mac in step. If both Macs change at once, it shows a notification: re-run `osx.sh`, or type **Sync the ai repo** again.
