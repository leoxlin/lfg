# lfg

Jump into a git worktree and start a coding agent.

## Install

### Quick install (bash)

```bash
curl -sSL https://raw.githubusercontent.com/<user>/lfg/main/install.sh | bash
```

### Clone and run the installer

```bash
git clone https://github.com/<user>/lfg.git ~/.config/lfg-repo
cd ~/.config/lfg-repo
./install.sh
```

### Shell-specific install

```bash
./install.sh --zsh
./install.sh --bash
./install.sh --fish
./install.sh --oh-my-zsh
```

### Oh My Zsh plugin

```zsh
git clone https://github.com/<user>/lfg.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/lfg
```

Then add `lfg` to the plugins array in `~/.zshrc`:

```zsh
plugins=(... lfg)
```

### Manual install

Source the file for your shell:

```zsh
source /path/to/lfg/lfg.zsh
```

```bash
source /path/to/lfg/lfg.bash
```

For fish, copy `functions/` and `completions/` into `~/.config/fish/`.

Then restart your shell or reload your configuration.

## Usage

```
lfg [agent] [branch]
```

- `lfg` — launch the default agent in a picked branch.
- `lfg codex` — launch `codex` in a picked branch.
- `lfg claude feat/x` — launch `claude` in worktree for branch `feat/x`.

## Supported shells

zsh, bash, and fish are supported. Completions are provided for all three shells.

Tab-completion is available for the agent entrypoints: `claude`, `claude-code`, `codex`, `aider`, `gemini`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LFG_DEFAULT_AGENT_COMMAND` | `claude` | Agent launched when none is specified. |
| `LFG_PRUNE_OLDER_THAN_DAYS` | `1` | Prune worktrees older than this many days. |
| `LFG_FZF_HIGHLIGHT_COLOR` | `green` | fzf highlight color. |
| `LFG_SOURCE_DIR` | `~/src` | Directory scanned for repos outside a git repo. |
| `LFG_INSTALL_DIR` | `~/.config/lfg` | Directory used by `install.sh`. |
| `LFG_REPO_URL` | `https://github.com/leoxlin/lfg.git` | Git URL cloned by `install.sh` when run remotely. |
