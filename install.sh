#!/usr/bin/env bash
set -euo pipefail

LFG_INSTALL_DIR="${LFG_INSTALL_DIR:-$HOME/.config/lfg}"
LFG_REPO_URL="${LFG_REPO_URL:-https://github.com/leoxlin/lfg.git}"
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
  --zsh           Install for zsh (source lfg.zsh in ~/.zshrc)
  --bash          Install for bash (source lfg.bash in ~/.bashrc)
  --fish          Install for fish (copy functions/completions)
  --oh-my-zsh     Install as an Oh My Zsh plugin
  --install-dir   Override install directory (default: ~/.config/lfg)
  --repo-url      Override git repo URL for remote installs
                  (default: ${LFG_REPO_URL})
  -h, --help      Show this help message

If no shell option is given, the current shell is auto-detected.

Remote install:
  curl -sSL https://raw.githubusercontent.com/<user>/lfg/main/install.sh | bash
  curl -sSL https://raw.githubusercontent.com/<user>/lfg/main/install.sh | bash -s -- --fish

The remote installer clones the repository into ~/.config/lfg/repo and
installs from there. Override the URL with the LFG_REPO_URL environment
variable or the --repo-url option.
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

# Fetch the repo when running remotely.
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
  echo "Cloning $LFG_REPO_URL"
  rm -rf "$repo_dir"
  git clone --depth 1 "$LFG_REPO_URL" "$repo_dir"
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

install_zsh() {
  echo "Installing lfg for zsh"
  mkdir -p "$LFG_INSTALL_DIR"
  ln -sf "$REPO_ROOT/lfg.zsh" "$LFG_INSTALL_DIR/lfg.zsh"
  add_line_to_file "source \"$LFG_INSTALL_DIR/lfg.zsh\"" "$ZSHRC"
}

install_bash() {
  echo "Installing lfg for bash"
  mkdir -p "$LFG_INSTALL_DIR"
  ln -sf "$REPO_ROOT/lfg.bash" "$LFG_INSTALL_DIR/lfg.bash"
  add_line_to_file "source \"$LFG_INSTALL_DIR/lfg.bash\"" "$BASHRC"
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
  echo "Add 'lfg' to the plugins array in your .zshrc if it is not already there."
}

METHOD="auto"

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --zsh) METHOD="zsh" ;;
      --bash) METHOD="bash" ;;
      --fish) METHOD="fish" ;;
      --oh-my-zsh) METHOD="oh-my-zsh" ;;
      --install-dir)
        LFG_INSTALL_DIR="$2"
        shift
        ;;
      --repo-url)
        LFG_REPO_URL="$2"
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
  if [ -n "${ZSH_VERSION:-}" ]; then
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

main() {
  parse_args "$@"
  detect_source
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
