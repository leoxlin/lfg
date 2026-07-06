# Installation

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash
```

Remote installs download the latest GitHub release archive by default. To
install a specific release or configure a specific shell, use the environment
variables documented by `install.sh --help`.

## Local Install

Run the installer from a local clone:

```bash
git clone https://github.com/leoxlin/lfg.git lfg-repo
cd lfg-repo
./install.sh
```

The installer auto-detects the current shell unless a shell override is passed
with an environment variable documented by `install.sh --help`.

## Re-running the Installer

The installer replaces the install directory on every run before downloading or
copying files, so stale files from previous installs do not survive
reinstalling.

Shell configuration updates remain idempotent. Before modifying any shell
configuration, the installer runs the target shell and checks whether `lfg` is
already available. If it is, the installer prints a message and does not modify
your shell configuration files again.

When configuring zsh or bash and `LFG_SOURCE_DIR` is unset, the installer
shallowly scans visible folders directly under `$HOME` for a source directory
containing immediate child git repositories. If it finds one, it prompts before
adding `export LFG_SOURCE_DIR=<found-dir>` to the shell rc file before the
`lfg` source line. If it does not find one, it prints a warning with the export
line to add manually.

## Remote Install

`install.sh` can be piped from a URL. Remote installs download the release
archive from `github.com/leoxlin/lfg`, stage the files under the install
directory, and install from there.

Remote installs only support `github.com/leoxlin/lfg`.

## Updating

Run:

```bash
lfg update
```

`lfg update` reruns the remote installer and downloads the latest release by
default. Use the release environment variable documented by `install.sh --help`
to update to a specific release.

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
