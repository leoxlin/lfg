# Installation

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash
```

For a specific shell:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash -s -- --zsh
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash -s -- --bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash -s -- --fish
```

## Local Install

Clone the repository and run the installer:

```bash
git clone https://github.com/leoxlin/lfg.git ~/.config/lfg-repo
cd ~/.config/lfg-repo
./install.sh
```

The installer auto-detects the current shell unless a method flag is passed:

```bash
./install.sh              # auto-detect
./install.sh --zsh        # install for zsh
./install.sh --bash       # install for bash
./install.sh --fish       # install for fish
./install.sh --oh-my-zsh  # install as an Oh My Zsh plugin
```

## Remote Install

`install.sh` can be piped from a URL. It clones the repository into `~/.config/lfg/repo` and installs from there.

Override the repository URL with `LFG_REPO_URL` or `--repo-url`:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh \
  | LFG_REPO_URL=https://github.com/leoxlin/lfg.git bash

curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh \
  | bash -s -- --repo-url https://github.com/leoxlin/lfg.git
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
| fish | `functions/lfg.fish`, `functions/lfgwt.fish` | `completions/lfg.fish`, `completions/lfgwt.fish` |
