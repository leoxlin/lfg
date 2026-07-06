#!/usr/bin/env bash
set -euo pipefail

LFG_INSTALL_DIR="${LFG_INSTALL_DIR:-$HOME/.config/lfg}"
LFG_REPO_URL="${LFG_REPO_URL:-https://github.com/leoxlin/lfg.git}"
LFG_REPO_REF="${LFG_REPO_REF:-main}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BASHRC="${HOME}/.bashrc"
FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"

REPO_ROOT=""
IS_LOCAL=false
REPO_FILES=(
  lfg.zsh
  lfg.bash
  lfg.plugin.zsh
  functions/lfg.fish
  functions/worktree.fish
  completions/lfg.fish
  completions/worktree.fish
)

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Install lfg shell integration.

Options:
  --install-dir   Override install directory (default: ~/.config/lfg)
  --repo-url      Override git repo URL for remote installs
                  (default: ${LFG_REPO_URL})
  --repo-ref      Override git ref (branch/tag) for remote installs
                  (default: ${LFG_REPO_REF})
  -h, --help      Show this help message

The current shell is auto-detected.
Set INSTALL_SHELL to zsh, bash, fish, oh-my-zsh, or a shell path to override detection.

Remote install:
  curl -sSL https://raw.githubusercontent.com/<user>/lfg/main/install.sh | bash
  curl -sSL https://raw.githubusercontent.com/<user>/lfg/main/install.sh | INSTALL_SHELL="$SHELL" bash
  curl -sSL https://raw.githubusercontent.com/<user>/lfg/main/install.sh | INSTALL_SHELL=fish bash

The remote installer downloads the files from the repository into
~/.config/lfg/repo and installs from there. Override the URL or ref with
the LFG_REPO_URL / LFG_REPO_REF environment variables or the --repo-url
/ --repo-ref options.
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

# Convert a GitHub repo URL into a raw.githubusercontent.com base URL.
# Supports https://github.com/owner/repo.git and git@github.com:owner/repo.git.
github_raw_base() {
  local url="$1"
  local ref="$2"
  local owner path repo

  if [[ "$url" =~ ^https://github\.com/([^/]+)/(.+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@github\.com:([^/]+)/(.+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  repo="${path%.git}"
  echo "https://raw.githubusercontent.com/$owner/$repo/$ref"
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

reset_install_dir() {
  rm -rf "$LFG_INSTALL_DIR"
  mkdir -p "$LFG_INSTALL_DIR"
}

# Fetch the repo files when running remotely.
fetch_repo() {
  if [ "$IS_LOCAL" = true ]; then
    return 0
  fi

  if [ -z "$LFG_REPO_URL" ]; then
    echo "error: LFG_REPO_URL is not set and install.sh is not running from a local clone." >&2
    echo "Set LFG_REPO_URL to the git URL of the lfg repository." >&2
    exit 1
  fi

  local repo_dir="$LFG_INSTALL_DIR/repo"
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir/functions" "$repo_dir/completions"

  local raw_base
  if raw_base="$(github_raw_base "$LFG_REPO_URL" "$LFG_REPO_REF")"; then
    echo "Downloading files from $raw_base"
    local file
    for file in "${REPO_FILES[@]}"; do
      mkdir -p "$repo_dir/$(dirname "$file")"
      download_file "$raw_base/$file" "$repo_dir/$file"
    done
  else
    echo "Cloning $LFG_REPO_URL"
    git clone --depth 1 "$LFG_REPO_URL" "$repo_dir"
  fi

  REPO_ROOT="$repo_dir"
}

add_line_to_file() {
  local line="$1"
  local file="$2"

  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -Fxq "$line" "$file"; then
    echo "Already present in $file"
  else
    echo "$line" >> "$file"
    echo "Added to $file"
  fi
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
  mkdir -p "$LFG_INSTALL_DIR"
  cp -f "$REPO_ROOT/$script_name" "$LFG_INSTALL_DIR/$script_name"
  if shell_has_lfg "$shell_name"; then
    echo "lfg is already installed for $shell_name; skipping ${config_file##*/} update"
  else
    add_line_to_file "source \"$LFG_INSTALL_DIR/$script_name\"" "$config_file"
  fi
}

install_fish() {
  echo "Installing lfg for fish"
  mkdir -p "$FISH_CONFIG_DIR/functions" "$FISH_CONFIG_DIR/completions"
  cp -f "$REPO_ROOT/functions/"*.fish "$FISH_CONFIG_DIR/functions/"
  cp -f "$REPO_ROOT/completions/"*.fish "$FISH_CONFIG_DIR/completions/"
}

install_oh_my_zsh() {
  echo "Installing lfg as an Oh My Zsh plugin"
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local plugin_dir="$zsh_custom/plugins/lfg"
  mkdir -p "$plugin_dir"
  cp -f "$REPO_ROOT/lfg.zsh" "$plugin_dir/lfg.zsh"
  cp -f "$REPO_ROOT/lfg.plugin.zsh" "$plugin_dir/lfg.plugin.zsh"
  echo "Plugin installed to $plugin_dir"
  if shell_has_lfg zsh; then
    echo "lfg is already installed for zsh"
  else
    echo "Add 'lfg' to the plugins array in your .zshrc if it is not already there."
  fi
}

METHOD="auto"

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --install-dir)
        LFG_INSTALL_DIR="$2"
        shift
        ;;
      --repo-url)
        LFG_REPO_URL="$2"
        shift
        ;;
      --repo-ref)
        LFG_REPO_REF="$2"
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

  if [ -n "${INSTALL_SHELL:-}" ]; then
    if shell_name="$(install_method_from_value "$INSTALL_SHELL")"; then
      echo "$shell_name"
      return 0
    fi

    echo "error: INSTALL_SHELL must be zsh, bash, fish, oh-my-zsh, or a path ending in zsh, bash, or fish." >&2
    exit 1
  fi

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
