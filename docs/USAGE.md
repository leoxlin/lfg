# Usage

```text
lfg [entrypoint]
lfg --help
lfg --update
```

- `entrypoint`: the command to run once inside the worktree. Defaults to `${LFG_DEFAULT_AGENT_COMMAND:-claude}`.

Examples:

- `lfg` - launch the default agent in a picked branch.
- `lfg codex` - launch `codex` in a picked branch.
- `lfg --help` - show usage.
- `lfg --update` - download and install the latest lfg release.

## Behavior

- Outside a git repo, `lfg` asks you to pick one from `$LFG_SOURCE_DIR` with `fzf`; the selector uses a rounded border labeled `Select a repo` around the `repo> ` prompt.
- When not already inside a linked worktree, `lfg` asks you to pick an existing worktree branch or type a new branch name to create one; the selector uses a rounded border labeled `Select or create worktree branch` around the `worktree> ` prompt.
- `lfg` appends `--color=pointer:<pointer-color>` to `FZF_DEFAULT_OPTS` for its `fzf` selectors so the selection pointer is colored by `LFG_FZF_POINTER_COLOR`.
- If already inside a linked worktree, `lfg` launches the agent in the current directory.
- Otherwise, `lfg` creates or switches to the selected worktree through `worktree`, then launches the agent there.
- `lfg --help` prints usage and exits without selecting a repo, entering a worktree, or launching an entrypoint.
- `lfg --update` reruns the remote installer and downloads the latest GitHub release by default.
- Worktrees are created under `$LFG_SOURCE_DIR/.agents/worktrees/<repo>-<branch>/<repo>` and reused by branch.
- If a `lfg_worktree_setup` function exists, `lfg` calls it with the worktree path before entering a worktree.

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
- older than `${LFG_PRUNE_OLDER_THAN_DAYS:-7}` day(s), or
- not backed by a remote branch.

After removals, it runs `git worktree prune` from the main checkout.

## Completion

Tab completion is available for `--help`, `--update`, and entrypoint completion
suggestions. By default, entrypoint completion suggestions use the bundled
`completions/lfg.entrypoints` file.

Options:

- `--help`
- `--update`

Bundled entrypoint completions:

- `claude`
- `antigravity`
- `codex`
- `cursor`
- `kimi`
- `kimi-code`
- `opencode`
- `pi`
- `aider`
- `gemini`

Set `LFG_COMPLETIONS_FILE` to load entrypoint completion suggestions from
another file. The file is newline-delimited; blank lines and lines starting
with `#` are ignored. If the configured or bundled file is unreadable,
entrypoint completion is empty.

## Configuration

Configure `lfg` with environment variables.

| Variable | Default | Description |
|----------|---------|-------------|
| `LFG_DEFAULT_AGENT_COMMAND` | `claude` | Agent launched by `lfg` when no entrypoint is given. |
| `LFG_PRUNE_OLDER_THAN_DAYS` | `7` | Worktrees older than this many days are pruned. |
| `LFG_FZF_POINTER_COLOR` | `bright-blue` | Color for the fzf selection pointer. Passed as `pointer:<color>`. |
| `LFG_SOURCE_DIR` | `~/src` | Root directory scanned for repos when `lfg` is run outside a git repo. |
| `LFG_COMPLETIONS_FILE` | bundled `completions/lfg.entrypoints` | Newline-delimited file of `lfg` entrypoint completion suggestions. Blank lines and lines starting with `#` are ignored. |
| `LFG_INSTALL_DIR` | `~/.config/lfg` | Directory replaced by `install.sh` on every run. Remote installs stage release files in `$LFG_INSTALL_DIR/repo`. |
| `LFG_RELEASE_VERSION` | `latest` | Release version installed by remote installs and `lfg --update`. Use values like `0.1.0`; tags with a leading `v` are also accepted. |
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

Run custom setup before entering a worktree by defining `lfg_worktree_setup`
before sourcing `lfg`. The function receives the target worktree path as its
first argument. If it returns non-zero, `lfg` does not enter the worktree.

No-op hook for zsh or bash:

```bash
function lfg_worktree_setup() {
  # Optional: customize setup before lfg enters a worktree.
  :
}

source "$HOME/.config/lfg/lfg.zsh" # or lfg.bash
```

No-op hook for fish:

```fish
function lfg_worktree_setup
end
```

With the fish installer, define this in `~/.config/fish/config.fish`; fish
autoloads `lfg` from `~/.config/fish/functions/`. For a manual fish install,
define the hook before `source /path/to/lfg/functions/lfg.fish`.

To keep the previous `mise trust` behavior, define the hook like this before
sourcing `lfg`:

```bash
function lfg_worktree_setup() {
  local worktree_path="$1"

  command -v mise >/dev/null 2>&1 || return 0

  if mise trust --show -C "$worktree_path" 2>/dev/null | grep -q ': untrusted'; then
    mise trust -y -q -C "$worktree_path"
  fi
}
```

Fish equivalent:

```fish
function lfg_worktree_setup
    set -l worktree_path $argv[1]

    if not command -v mise >/dev/null 2>&1
        return 0
    end

    if mise trust --show -C "$worktree_path" 2>/dev/null | string match -q '*: untrusted*'
        mise trust -y -q -C "$worktree_path"
    end
end
```

Install for the shell in `$SHELL` when piping the installer into Bash:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL="$SHELL" bash
```

Install for a specific shell:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | INSTALL_SHELL=fish bash
```

Install or update to a specific release:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | LFG_RELEASE_VERSION=0.1.0 bash
LFG_RELEASE_VERSION=0.1.0 lfg --update
```

## Related Docs

- [Installation](INSTALL.md)
- [Release](RELEASE.md)
