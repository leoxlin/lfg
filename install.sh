#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.config/lfg"
INSTALL_VERSION="latest"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BASHRC="${HOME}/.bashrc"
FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"

REPO_ROOT=""
IS_LOCAL=false

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Install lfg shell integration.

Options:
  --install-dir DIR      Override install directory (default: ~/.config/lfg)
  --install-shell SHELL  Shell to configure. Accepts zsh, bash, fish, oh-my-zsh,
                         or a shell path ending in zsh, bash, or fish. If unset,
                         install.sh checks \$SHELL, then the shell running
                         install.sh, then falls back to zsh.
  --install-version VER  Remote install release version (default: latest). Use
                         values like 0.1.0; tags with a leading v are accepted.
  -h, --help             Show this help message

Remote install:
  curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash
  curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash -s -- --install-shell fish
  curl -sSL https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh | bash -s -- --install-version 0.1.0

Local install:
  ./install.sh
  ./install.sh --install-dir ~/.local/share/lfg
  ./install.sh --install-shell oh-my-zsh

The remote installer downloads the latest GitHub release archive by default.
Remote installs only support github.com/leoxlin/lfg.
EOF
}

# Detect whether the script is being run from a local file or via curl/pipe.
detect_source() {
  local script_path="${BASH_SOURCE[0]:-}"

  if [ -n "$script_path" ] && [ -f "$script_path" ]; then
    IS_LOCAL=true
    REPO_ROOT="$(cd "$(dirname "$script_path")" && pwd)"
  fi
}

# Download a single file when running remotely.
download_file() {
  local url="$1"
  local dest="$2"

  if ! curl -fsSL "$url" -o "$dest"; then
    echo "error: failed to download $url" >&2
    exit 1
  fi
}

release_tag_for_version() {
  local version="$1"

  if [ "$version" = "latest" ]; then
    echo "latest"
  elif [[ "$version" == v* ]]; then
    echo "$version"
  else
    echo "v$version"
  fi
}

extract_release_archive() {
  local archive_file="$1"
  local dest_dir="$2"
  local extract_dir="$3"

  mkdir -p "$extract_dir" "$dest_dir"

  if ! command -v tar >/dev/null 2>&1; then
    echo "error: release install requires tar" >&2
    exit 1
  fi

  tar -xzf "$archive_file" -C "$extract_dir"

  local git_dir source_dir
  source_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | sort | sed -n '1p')"
  if [ -z "$source_dir" ]; then
    source_dir="$extract_dir"
  fi

  cp -R "$source_dir"/. "$dest_dir"/
}

reset_install_dir() {
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
}

# Fetch the repo files when running remotely.
fetch_repo() {
  if [ "$IS_LOCAL" = true ]; then
    return 0
  fi

  local repo_dir="$INSTALL_DIR/repo"
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir"

  local release_tag asset_version release_url archive_file extract_dir

  release_tag="$(release_tag_for_version "$INSTALL_VERSION")"
  asset_version="${release_tag#v}"
  release_url="https://github.com/leoxlin/lfg/releases/download/$release_tag/lfg-$asset_version.tar.gz"
  archive_file="$INSTALL_DIR/lfg-$asset_version.tar.gz"
  extract_dir="$INSTALL_DIR/release"

  echo "Downloading $release_url"
  download_file "$release_url" "$archive_file"
  extract_release_archive "$archive_file" "$repo_dir" "$extract_dir"

  REPO_ROOT="$repo_dir"
}

add_source_block_to_file() {
  local source_line="$1"
  local file="$2"

  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -Fxq "$source_line" "$file"; then
    echo "Already present in $file"
  else
    {
      echo ""
      echo "function lfg_worktree_setup() {"
      echo "  # Optional: customize setup before lfg enters a worktree."
      echo "  :"
      echo "}"
      echo "$source_line"
    } >> "$file"
    echo "Added to $file"
  fi
}

find_home_source_dir() {
  local git_dir source_dir

  if [ ! -d "$HOME" ]; then
    return 1
  fi

  source_dir="$(
    find "$HOME"/*/*/.git -prune -print 2>/dev/null \
      | while IFS= read -r git_dir; do dirname "$(dirname "$git_dir")"; done \
      | sort \
      | uniq -c \
      | sort -k1,1nr -k2,2 \
      | sed -n '1s/^[[:space:]]*[0-9][0-9]*[[:space:]]//p'
  )"

  [ -n "$source_dir" ] || return 1
  echo "$source_dir"
}

prompt_reply() {
  local prompt="$1"

  if [ ! -t 0 ] && { : >/dev/tty; } 2>/dev/null; then
    printf "%s" "$prompt" >/dev/tty
    IFS= read -r PROMPT_REPLY </dev/tty || PROMPT_REPLY=""
  else
    printf "%s" "$prompt"
    IFS= read -r PROMPT_REPLY || PROMPT_REPLY=""
  fi
}

prompt_to_install_fzf_with_brew() {
  prompt_reply "fzf is required but was not found. Install it with 'brew install fzf'? [y/N] "
  case "$PROMPT_REPLY" in
    y|Y|yes|YES|Yes)
      brew install fzf
      ;;
    *)
      echo "error: fzf is required. Install fzf and rerun install.sh." >&2
      exit 1
      ;;
  esac
}

check_dependencies() {
  if ! command -v fzf >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      prompt_to_install_fzf_with_brew
    else
      echo "error: fzf is required. Install fzf and rerun install.sh." >&2
      exit 1
    fi
  fi
}

maybe_add_lfg_source_dir_to_file() {
  local file="$1"
  local found_dir prompt source_line

  if [ -n "${LFG_SOURCE_DIR:-}" ]; then
    return 0
  fi

  if [ -f "$file" ] && grep -Eq '(^|[[:space:]])(export[[:space:]]+)?LFG_SOURCE_DIR=' "$file"; then
    return 0
  fi

  found_dir="$(find_home_source_dir)" || found_dir=""

  if [ -n "$found_dir" ]; then
    printf -v source_line "export LFG_SOURCE_DIR=%q" "$found_dir"
    prompt="Add '$source_line' to $file? [y/N] "
    echo "Found source directory: $found_dir"
    prompt_reply "$prompt"
    case "$PROMPT_REPLY" in
      y|Y|yes|YES|Yes)
        ;;
      *)
        echo "Skipped LFG_SOURCE_DIR shell configuration update."
        return 0
        ;;
    esac
  else
    cat <<'EOF'
=======================================
WARNING: Could not find a sources dir

lfg requires a source dir with all your
local git repos to function.

Set this in your shell profile
`export LFG_SOURCE_DIR=<source_dir>`
=======================================
EOF
    return 0
  fi

  printf -v source_line "export LFG_SOURCE_DIR=%q" "$found_dir"
  mkdir -p "$(dirname "$file")"
  {
    echo ""
    echo "$source_line"
  } >> "$file"
  echo "Added LFG_SOURCE_DIR to $file"
}

shell_has_lfg() {
  local shell_name="$1"
  local shell_bin

  shell_bin="$(command -v "$shell_name" 2>/dev/null)" || return 1

  case "$shell_name" in
    bash)
      "$shell_bin" -i -c 'command -v lfg' >/dev/null 2>&1
      ;;
    zsh)
      "$shell_bin" -i -c 'whence lfg' >/dev/null 2>&1
      ;;
    fish)
      "$shell_bin" -i -c 'type lfg' >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

install_zsh() {
  install_source_shell zsh lfg.zsh "$ZSHRC"
}

install_bash() {
  install_source_shell bash lfg.bash "$BASHRC"
}

install_source_shell() {
  local shell_name="$1"
  local script_name="$2"
  local config_file="$3"

  echo "Installing lfg for $shell_name"
  mkdir -p "$INSTALL_DIR/completions"
  cp -f "$REPO_ROOT/$script_name" "$INSTALL_DIR/$script_name"
  cp -f "$REPO_ROOT/completions/lfg.entrypoints" "$INSTALL_DIR/completions/lfg.entrypoints"
  maybe_add_lfg_source_dir_to_file "$config_file"
  if shell_has_lfg "$shell_name"; then
    echo "lfg is already installed for $shell_name; skipping ${config_file##*/} update"
  else
    add_source_block_to_file "source \"$INSTALL_DIR/$script_name\"" "$config_file"
  fi
}

install_fish() {
  echo "Installing lfg for fish"
  mkdir -p "$FISH_CONFIG_DIR/functions" "$FISH_CONFIG_DIR/completions"
  cp -f "$REPO_ROOT/functions/"*.fish "$FISH_CONFIG_DIR/functions/"
  cp -f "$REPO_ROOT/completions/"*.fish "$FISH_CONFIG_DIR/completions/"
  cp -f "$REPO_ROOT/completions/lfg.entrypoints" "$FISH_CONFIG_DIR/completions/lfg.entrypoints"
}

install_oh_my_zsh() {
  echo "Installing lfg as an Oh My Zsh plugin"
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local plugin_dir="$zsh_custom/plugins/lfg"
  mkdir -p "$plugin_dir/completions"
  cp -f "$REPO_ROOT/lfg.zsh" "$plugin_dir/lfg.zsh"
  cp -f "$REPO_ROOT/lfg.plugin.zsh" "$plugin_dir/lfg.plugin.zsh"
  cp -f "$REPO_ROOT/completions/lfg.entrypoints" "$plugin_dir/completions/lfg.entrypoints"
  echo "Plugin installed to $plugin_dir"
  if shell_has_lfg zsh; then
    echo "lfg is already installed for zsh"
  else
    echo "Add 'lfg' to the plugins array in your .zshrc if it is not already there."
  fi
}

METHOD="auto"

require_option_value() {
  local option="$1"
  local value="${2:-}"

  if [ -z "$value" ]; then
    echo "error: $option requires a value" >&2
    exit 1
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --install-dir)
        require_option_value "$1" "${2:-}"
        INSTALL_DIR="$2"
        shift
        ;;
      --install-shell)
        require_option_value "$1" "${2:-}"
        if ! METHOD="$(install_method_from_value "$2")"; then
          echo "error: --install-shell must be zsh, bash, fish, oh-my-zsh, or a path ending in zsh, bash, or fish." >&2
          exit 1
        fi
        shift
        ;;
      --install-version)
        require_option_value "$1" "${2:-}"
        INSTALL_VERSION="$2"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

detect_shell() {
  local shell_name

  if [ -n "${SHELL:-}" ] && shell_name="$(install_method_from_value "$SHELL")"; then
    echo "$shell_name"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    echo "zsh"
  elif [ -n "${BASH_VERSION:-}" ]; then
    echo "bash"
  elif [ -n "${FISH_VERSION:-}" ]; then
    echo "fish"
  else
    # Default to zsh for lack of better information.
    echo "zsh"
  fi
}

install_method_from_value() {
  local value="$1"
  local method="${value##*/}"

  case "$method" in
    zsh|bash|fish|oh-my-zsh)
      echo "$method"
      ;;
    *)
      return 1
      ;;
  esac
}

main() {
  parse_args "$@"
  check_dependencies
  detect_source
  reset_install_dir
  fetch_repo

  if [ "$METHOD" = "auto" ]; then
    METHOD="$(detect_shell)"
  fi

  case "$METHOD" in
    zsh) install_zsh ;;
    bash) install_bash ;;
    fish) install_fish ;;
    oh-my-zsh) install_oh_my_zsh ;;
    *)
      echo "Unknown install method: $METHOD" >&2
      exit 1
      ;;
  esac

  echo "Done."
}

main "$@"
