# Installation

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash
```

The installer detects the shell to configure. When piping into `bash`, it first
checks `INSTALL_SHELL`, then `$SHELL`, so users whose login shell is zsh or fish
are not forced into the Bash install path.

To pass the shell explicitly, set `INSTALL_SHELL`:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL="$SHELL" bash
```

For a specific shell:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL=zsh bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL=bash bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL=fish bash
```

## Local Install

Run the installer from a local clone:

```bash
git clone https://github.com/leoxlin/lfg.git ~/.config/lfg-repo
cd ~/.config/lfg-repo
./install.sh
```

The installer auto-detects the current shell unless `INSTALL_SHELL` is set:

```bash
./install.sh                        # auto-detect
INSTALL_SHELL=zsh ./install.sh      # install for zsh
INSTALL_SHELL=bash ./install.sh     # install for bash
INSTALL_SHELL=fish ./install.sh     # install for fish
INSTALL_SHELL=oh-my-zsh ./install.sh # install as an Oh My Zsh plugin
```

## Re-running the Installer

The installer replaces `LFG_INSTALL_DIR` on every run before downloading or
copying files, so stale files under `~/.config/lfg` do not survive reinstalling.

Shell configuration updates remain idempotent. Before modifying any shell
configuration, the installer runs the target shell and checks whether `lfg` is
already available. If it is, the installer prints a message and does not modify
your shell configuration files again.

## Remote Install

`install.sh` can be piped from a URL. It downloads the files from the repository
into `~/.config/lfg/repo` and installs from there.

Auto-detection order is:

1. `INSTALL_SHELL` (`zsh`, `bash`, `fish`, `oh-my-zsh`, or a path ending in `zsh`, `bash`, or `fish`),
2. `$SHELL`,
3. the shell running `install.sh`,
4. zsh as a final fallback.

Override the repository URL or ref with `LFG_REPO_URL` / `LFG_REPO_REF` or
`--repo-url` / `--repo-ref`:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh \
  | LFG_REPO_URL=https://github.com/leoxlin/lfg.git bash

curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh \
  | bash -s -- --repo-url https://github.com/leoxlin/lfg.git

curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh \
  | bash -s -- --repo-ref main
```

## Oh My Zsh Plugin

Install as a custom plugin:

```zsh
git clone https://github.com/leoxlin/lfg.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/lfg
```

Then add `lfg` to the plugins array in `~/.zshrc`:

```zsh
plugins=(... lfg)
```

The plugin entry point is `lfg.plugin.zsh`.

## Manual Install

Source the appropriate file for your shell from your shell configuration:

```zsh
source /path/to/lfg/lfg.zsh
```

```bash
source /path/to/lfg/lfg.bash
```

For fish, copy `functions/` and `completions/` into `~/.config/fish/` and reload.

## Supported Shells

`lfg` supports zsh, bash, and fish. Completions are provided for all three shells.

| Shell | Files | Completion |
|-------|-------|------------|
| zsh | `lfg.zsh` | zsh compsys (`compdef`) |
| bash | `lfg.bash` | bash `complete -F` |
| fish | `functions/lfg.fish`, `functions/worktree.fish` | `completions/lfg.fish`, `completions/worktree.fish` |
