# lfg

Jump into a git worktree and start a coding agent.

## Install

```zsh
git clone https://github.com/<user>/lfg.git ~/.config/lfg-repo
cd ~/.config/lfg-repo
./install.sh
```

Then restart your shell or run `source ~/.config/lfg/lfg.zsh`.

## Usage

```
lfg [agent] [branch]
```

- `lfg` — launch the default agent in a picked branch.
- `lfg codex` — launch `codex` in a picked branch.
- `lfg claude feat/x` — launch `claude` in worktree for branch `feat/x`.

## Supported agents

Tab-completion is available for: `claude`, `claude-code`, `codex`, `aider`, `gemini`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `LFG_DEFAULT_AGENT_COMMAND` | `claude` | Agent launched when none is specified. |
| `LFG_PRUNE_OLDER_THAN_DAYS` | `1` | Prune worktrees older than this many days. |
| `LFG_FZF_HIGHLIGHT_COLOR` | `green` | fzf highlight color. |
| `LFG_SOURCE_DIR` | `~/src` | Directory scanned for repos outside a git repo. |
