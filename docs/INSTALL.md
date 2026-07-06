# Installation

## Dependencies

Runtime dependencies:

- `git`
- `fzf`
- zsh, bash, or fish
- the agent command you want `lfg` to launch, such as `claude` or `codex`

Installer and update dependencies:

- `bash` to run `install.sh`
- `curl` for the quick install command and `lfg --update`
- `tar` for remote release installs

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash
```

Use `install.sh --help` to see shell and version options.

## Local Install

Run the installer from a local clone:

```bash
git clone https://github.com/leoxlin/lfg.git lfg-repo
cd lfg-repo
./install.sh
```

The installer auto-detects your shell unless you pass `--install-shell`.

## Re-running the Installer

Re-running the installer replaces `~/.config/lfg`, then updates shell config
only when `lfg` is not already available. Each run prints files as it installs
them.

For zsh and bash, the installer may also offer to add `LFG_SOURCE_DIR` if it can
infer your source directory.

## Remote Install

`install.sh` can be piped from a URL. Remote installs download the release
archive from `github.com/leoxlin/lfg` into `~/.config/lfg`.

Remote installs only support `github.com/leoxlin/lfg`.

## Updating

Run:

```bash
lfg --update
```

`lfg --update` reruns the remote installer and lets it install the latest
release.

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

Keep `completions/lfg.entrypoints` under the same parent as `lfg.zsh` or
`lfg.bash` for the bundled entrypoint completion suggestions. For fish, copy
`functions/` and `completions/` into `~/.config/fish/` and reload;
`completions/lfg.entrypoints` is installed as the bundled entrypoint completion
file.

## Supported Shells

`lfg` supports zsh, bash, and fish. Completions are provided for all three shells.

| Shell | Files | Completion |
|-------|-------|------------|
| zsh | `lfg.zsh`, `completions/lfg.entrypoints` | zsh compsys (`compdef`) |
| bash | `lfg.bash`, `completions/lfg.entrypoints` | bash `complete -F` |
| fish | `functions/lfg.fish`, `functions/worktree.fish` | `completions/lfg.fish`, `completions/worktree.fish`, `completions/lfg.entrypoints` |
