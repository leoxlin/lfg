# Usage

```text
lfg [entrypoint] [branch_name]
```

- `entrypoint`: the command to run once inside the worktree. Defaults to `${LFG_DEFAULT_AGENT_COMMAND:-claude}`.
- `branch_name`: the branch to use. If omitted, `lfg` opens an interactive picker.

Examples:

- `lfg` - launch the default agent in a picked branch.
- `lfg codex` - launch `codex` in a picked branch.
- `lfg claude feat/x` - launch `claude` in a worktree for branch `feat/x`.

## Behavior

- Outside a git repo, `lfg` asks you to pick one from `$LFG_SOURCE_DIR` with `fzf`.
- With no branch, `lfg` asks you to pick an existing worktree branch or type a new branch name to create one.
- If already inside a linked worktree and no branch is requested, `lfg` launches the agent in the current directory.
- Otherwise, `lfg` creates or switches to the requested worktree through `worktree`, then launches the agent there.
- Worktrees are created under `$LFG_SOURCE_DIR/.agents/worktrees/<repo>-<branch>` and reused by branch.
- If `mise` is installed, entering a worktree auto-trusts its `mise` config when it is not already trusted. This prevents `mise`'s `chpwd` hook from erroring.

## Worktree Helper

The `worktree` helper manages branch-specific worktrees. `wt` is an alias for `worktree`.

```text
worktree                         # interactive: pick branch/worktree
worktree add <branch_name>       # create or switch to a worktree
worktree cd <branch_name>        # change to or create a worktree
worktree list                    # list worktrees
worktree ls                      # alias for list
worktree prune                   # remove stale worktrees
worktree remove|rm <branch_name> # remove a worktree
```

`cd` creates the worktree if it does not already exist.

## Worktree Conventions

- All `worktree` commands must be run from inside a git repository and operate on that repo only.
- Branch-related commands (`add`, `cd`, `remove`/`rm`) take a single `<branch_name>` argument.
- Repo-wide commands (`list`, `ls`, `prune`) take no arguments.
- Worktree paths replace `/` in branch names with `-`.
- When creating a new branch, `worktree` starts from `origin/HEAD`, then falls back to `main`, `origin/main`, `master`, `origin/master`, and finally `HEAD`.

## Pruning

`worktree prune` removes worktrees that are:

- missing their directory,
- older than `${LFG_PRUNE_OLDER_THAN_DAYS:-1}` day(s), or
- not backed by a remote branch.

After removals, it runs `git worktree prune` from the main checkout.

## Completion

Tab completion is available for the agent entrypoints:

- `claude`
- `claude-code`
- `codex`
- `aider`
- `gemini`

Branch completion is available for branch arguments where the shell supports it.

## Configuration

Configure `lfg` with environment variables.

| Variable | Default | Description |
|----------|---------|-------------|
| `LFG_DEFAULT_AGENT_COMMAND` | `claude` | Agent launched by `lfg` when no entrypoint is given. |
| `LFG_PRUNE_OLDER_THAN_DAYS` | `1` | Worktrees older than this many days are pruned. |
| `LFG_FZF_HIGHLIGHT_COLOR` | `green` | Highlight color passed to `fzf`. |
| `LFG_SOURCE_DIR` | `~/src` | Root directory scanned for repos when `lfg` is run outside a git repo. |
| `LFG_INSTALL_DIR` | `~/.config/lfg` | Directory used by `install.sh`. Remote installs clone into `$LFG_INSTALL_DIR/repo`. |
| `LFG_REPO_URL` | `https://github.com/leoxlin/lfg.git` | Git URL cloned by `install.sh` when run remotely. |
| `INSTALL_SHELL` | unset | Shell selected by `install.sh` auto-detection. Accepts `zsh`, `bash`, `fish`, `oh-my-zsh`, or a path ending in `zsh`, `bash`, or `fish`. |

Set a different default agent:

```zsh
export LFG_DEFAULT_AGENT_COMMAND=codex
```

Scan a different source directory when launching outside a git repo:

```zsh
export LFG_SOURCE_DIR=~/Source
```

Keep worktrees longer before pruning:

```zsh
export LFG_PRUNE_OLDER_THAN_DAYS=7
```

Install for the shell in `$SHELL` when piping the installer into Bash:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL="$SHELL" bash
```

Install for a specific shell:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL=fish bash
```

## Related Docs

- [Installation](INSTALL.md)
