## Usage

```
lfg [agent cmd] [branch_name]
```

- `entrypoint`: the command to run once inside the worktree (default: `${LFG_DEFAULT_AGENT_COMMAND:-claude}`).
  - `lfg`               → default agent in a picked branch
  - `lfg codex`         → `codex` in a picked branch
  - `lfg claude feat/x` → `claude` in worktree for branch `feat/x`

## Behavior

- Outside a git repo: pick one from `$LFG_SOURCE_DIR` via `fzf` (type to filter).
- With no branch: pick an existing worktree branch, or type a new name to create one.
- Creates/switches the worktree (under `$LFG_SOURCE_DIR/.agents/worktrees`, via the `lfgwt` helper) and launches the entrypoint there.
- `LFG_SOURCE_DIR` defaults to `~/src` if unset.

## Worktree helper

The `lfgwt` helper manages branch-specific worktrees.

```
lfgwt                         # interactive: pick branch/worktree
lfgwt add <branch_name>       # create or switch to a worktree
lfgwt cd <branch_name>        # change to or create a worktree
lfgwt list                    # list worktrees
lfgwt ls                      # alias for list
lfgwt prune                   # remove stale worktrees
lfgwt remove|rm <branch_name>
```

`cd` creates the worktree if it does not already exist.

### Conventions

- All commands must be run from inside a git repository and operate on that repo only.
- Branch-related commands (`add`, `cd`, `remove`/`rm`) take a single `<branch>` argument.
- Repo-wide commands (`list`, `ls`, `prune`) take no arguments.
- Worktrees are created under `$LFG_SOURCE_DIR/.agents/worktrees/<repo>-<branch>` and reused by branch.
- If `mise` is installed, entering a worktree auto-trusts its `mise` config when it is not already trusted. This prevents mise's `chpwd` hook from erroring.

## Pruning

`lfgwt prune` removes worktrees that are:

- missing their directory,
- older than `${LFG_PRUNE_OLDER_THAN_DAYS:-1}` day(s), or
- not backed by a remote branch.

## Environment variables

- `LFG_SOURCE_DIR` — root directory scanned for repos when `lfg` is run outside a git repo. Defaults to `~/src`.
- `LFG_PRUNE_OLDER_THAN_DAYS` — worktrees older than this many days are pruned. Defaults to `1`.
- `LFG_DEFAULT_AGENT_COMMAND` — agent launched by `lfg` when no entrypoint is given. Defaults to `claude`.
- `LFG_FZF_HIGHLIGHT_COLOR` — highlight color passed to fzf. Defaults to `green`.
- `LFG_INSTALL_DIR` — directory used by `install.sh`. Defaults to `~/.config/lfg`.

## Shell integration

Run `./install.sh` to symlink `lfg.zsh` into `~/.config/lfg` and source it from `~/.zshrc`, or source `lfg.zsh` manually from your shell configuration to load the `lfg` and `lfgwt` commands plus their zsh completions.
