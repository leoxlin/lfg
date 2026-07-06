# lfg

Jump into a git worktree and start a coding agent.

## Docs

- [Install](docs/INSTALL.md)
- [Usage](docs/USAGE.md)
- [Release](docs/RELEASE.md)

## Quick Start

Install:

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash
```

Then run:

```bash
lfg
```

Examples:

- `lfg` - launch the default agent in a picked branch.
- `lfg codex` - launch `codex` in a picked branch.
- `lfg claude feat/x` - launch `claude` in a worktree for branch `feat/x`.

See [Usage](docs/USAGE.md) for command behavior and environment variables.
