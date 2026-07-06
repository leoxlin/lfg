#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.config/lfg"
INSTALL_VERSION="latest"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BASHRC="${HOME}/.bashrc"
FISH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish"

REPO_ROOT=""
IS_LOCAL=false

#######################################
# Logging helper
#######################################
logger() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

#######################################
# Usage and argument parsing
#######################################
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
EOF
}

require_option_value() {
  local option="$1"
  local value="${2:-}"

  if [ -z "$value" ]; then
    logger "ERROR" "$option requires a value"
    exit 1
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --install-dir)
        require_option_value "$1" "${2:-}"
        INSTALL_DIR="$2"
        logger "INFO" "Install directory set to: $INSTALL_DIR"
        shift
        ;;
      --install-shell)
        require_option_value "$1" "${2:-}"
        if ! METHOD="$(install_method_from_value "$2")"; then
          logger "ERROR" "--install-shell must be zsh, bash, fish, oh-my-zsh, or a path ending in zsh, bash, or fish."
          exit 1
        fi
        logger "INFO" "Install shell/method set to: $METHOD"
        shift
        ;;
      --install-version)
        require_option_value "$1" "${2:-}"
        INSTALL_VERSION="$2"
        logger "INFO" "Install version set to: $INSTALL_VERSION"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        logger "ERROR" "Unknown option: $1"
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

#######################################
# Source detection
#######################################
detect_source() {
  local script_path="${BASH_SOURCE[0]:-}"

  if [ -n "$script_path" ] && [ -f "$script_path" ]; then
    IS_LOCAL=true
    REPO_ROOT="$(cd "$(dirname "$script_path")" && pwd)"
    logger "INFO" "Running from local repository: $REPO_ROOT"
  else
    logger "INFO" "Running via remote curl/pipe install"
  fi
}

#######################################
# Release download and extraction
#######################################
release_tag_for_version() {
  local version="$1"

  if [[ "$version" == v* ]]; then
    echo "$version"
  else
    echo "v$version"
  fi
}

# Resolve the "latest" version to an actual release tag name via the GitHub API.
# Prints the version without a leading v (e.g. "0.4.0").
resolve_latest_version() {
  local api_url="https://api.github.com/repos/leoxlin/lfg/releases/latest"
  local tag_name

  logger "INFO" "Resolving latest release from GitHub"
  if ! tag_name="$(curl -fsSL "$api_url" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"; then
    logger "ERROR" "Failed to fetch latest release information from GitHub"
    exit 1
  fi

  if [ -z "$tag_name" ]; then
    logger "ERROR" "Could not determine latest release tag from GitHub response"
    exit 1
  fi

  logger "INFO" "Latest release tag: $tag_name"
  echo "${tag_name#v}"
}

# Download a single file when running remotely.
download_file() {
  local url="$1"
  local dest="$2"

  logger "INFO" "Downloading: $url"
  if ! curl -fsSL "$url" -o "$dest"; then
    logger "ERROR" "Failed to download $url"
    exit 1
  fi
  logger "INFO" "Downloaded to: $dest"
}

extract_release_archive() {
  local archive_file="$1"
  local dest_dir="$2"
  local extract_dir="$3"

  logger "INFO" "Extracting release archive: $archive_file"
  mkdir -p "$extract_dir" "$dest_dir"

  if ! command -v tar >/dev/null 2>&1; then
    logger "ERROR" "Release install requires tar, but tar was not found in PATH"
    exit 1
  fi

  tar -xzf "$archive_file" -C "$extract_dir"

  local source_dir
  source_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | sort | sed -n '1p')"
  if [ -z "$source_dir" ]; then
    source_dir="$extract_dir"
  fi

  logger "INFO" "Archive extracted to: $source_dir"
  copy_release_tree_from_repo "$source_dir" "$dest_dir"
}

install_file() {
  local source_file="$1"
  local dest_file="$2"

  mkdir -p "$(dirname "$dest_file")"
  cp -f "$source_file" "$dest_file"
  logger "INFO" "Installed: $dest_file"
}

copy_release_tree_from_repo() {
  local source_dir="$1"
  local dest_dir="$2"
  local source_file relative_file

  logger "INFO" "Copying release files from $source_dir to $dest_dir"
  while IFS= read -r source_file; do
    relative_file="${source_file#$source_dir/}"
    install_file "$source_file" "$dest_dir/$relative_file"
  done < <(find "$source_dir" -type f \( -name 'lfg.*' -o -path "$source_dir/functions/*" -o -path "$source_dir/completions/*" \) | sort)
  logger "INFO" "Copied release files to: $dest_dir"
}

reset_install_dir() {
  logger "INFO" "Resetting install directory: $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  logger "INFO" "Install directory ready: $INSTALL_DIR"
}

install_release_tree() {
  if [ "$IS_LOCAL" = true ]; then
    logger "INFO" "Installing release tree from local repository"
    copy_release_tree_from_repo "$REPO_ROOT" "$INSTALL_DIR"
    REPO_ROOT="$INSTALL_DIR"
    return 0
  fi

  local requested_version release_tag asset_version release_url archive_file extract_dir

  requested_version="$INSTALL_VERSION"
  if [ "$requested_version" = "latest" ]; then
    requested_version="$(resolve_latest_version)"
  fi

  release_tag="$(release_tag_for_version "$requested_version")"
  asset_version="${release_tag#v}"
  release_url="https://github.com/leoxlin/lfg/releases/download/$release_tag/lfg-$asset_version.tar.gz"
  archive_file="$INSTALL_DIR/lfg-$asset_version.tar.gz"
  extract_dir="$INSTALL_DIR/release"

  logger "INFO" "Resolved release URL: $release_url"
  download_file "$release_url" "$archive_file"
  extract_release_archive "$archive_file" "$INSTALL_DIR" "$extract_dir"
  rm -rf "$archive_file" "$extract_dir"
  logger "INFO" "Cleaned up temporary release files"

  REPO_ROOT="$INSTALL_DIR"
}

#######################################
# Shell configuration
#######################################
add_source_block_to_file() {
  local source_line="$1"
  local file="$2"

  logger "INFO" "Adding lfg source block to: $file"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -Fxq "$source_line" "$file"; then
    logger "INFO" "Source line already present in: $file"
  else
    {
      echo ""
      echo "function lfg_worktree_setup() {"
      echo "  # Optional: customize setup before lfg enters a worktree."
      echo "  :"
      echo "}"
      echo "$source_line"
    } >> "$file"
    logger "INFO" "Added lfg source block to: $file"
  fi
}

find_home_source_dir() {
  local git_dir source_dir

  if [ ! -d "$HOME" ]; then
    return 1
  fi

  logger "INFO" "Searching $HOME for the most common parent directory of git repositories"
  source_dir="$(
    find "$HOME"/*/*/.git -prune -print 2>/dev/null \
      | while IFS= read -r git_dir; do dirname "$(dirname "$git_dir")"; done \
      | sort \
      | uniq -c \
      | sort -k1,1nr -k2,2 \
      | sed -n '1s/^[[:space:]]*[0-9][0-9]*[[:space:]]//p'
  )"

  [ -n "$source_dir" ] || return 1
  logger "INFO" "Detected source directory: $source_dir"
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
      logger "INFO" "Installing fzf via Homebrew"
      brew install fzf
      logger "INFO" "fzf installed via Homebrew"
      ;;
    *)
      logger "ERROR" "fzf is required. Install fzf and rerun install.sh."
      exit 1
      ;;
  esac
}

check_dependencies() {
  logger "INFO" "Checking dependencies"
  if ! command -v fzf >/dev/null 2>&1; then
    logger "WARN" "fzf not found in PATH"
    if command -v brew >/dev/null 2>&1; then
      logger "INFO" "Homebrew detected; offering to install fzf"
      prompt_to_install_fzf_with_brew
    else
      logger "ERROR" "fzf is required. Install fzf and rerun install.sh."
      exit 1
    fi
  else
    logger "INFO" "fzf is available"
  fi
}

maybe_add_lfg_source_dir_to_file() {
  local file="$1"
  local found_dir prompt source_line

  if [ -n "${LFG_SOURCE_DIR:-}" ]; then
    logger "INFO" "LFG_SOURCE_DIR is already set in the environment: $LFG_SOURCE_DIR"
    return 0
  fi

  if [ -f "$file" ] && grep -Eq '(^|[[:space:]])(export[[:space:]]+)?LFG_SOURCE_DIR=' "$file"; then
    logger "INFO" "LFG_SOURCE_DIR already configured in: $file"
    return 0
  fi

  found_dir="$(find_home_source_dir)" || found_dir=""

  if [ -n "$found_dir" ]; then
    printf -v source_line "export LFG_SOURCE_DIR=%q" "$found_dir"
    prompt="Add '$source_line' to $file? [y/N] "
    prompt_reply "$prompt"
    case "$PROMPT_REPLY" in
      y|Y|yes|YES|Yes)
        ;;
      *)
        logger "WARN" "Skipped LFG_SOURCE_DIR shell configuration update"
        return 0
        ;;
    esac
  else
    logger "WARN" "Could not find a sources directory under $HOME"
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
  logger "INFO" "Added LFG_SOURCE_DIR to: $file"
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
  logger "INFO" "=== Installing lfg for zsh ==="
  install_source_shell zsh lfg.zsh "$ZSHRC"
}

install_bash() {
  logger "INFO" "=== Installing lfg for bash ==="
  install_source_shell bash lfg.bash "$BASHRC"
}

install_source_shell() {
  local shell_name="$1"
  local script_name="$2"
  local config_file="$3"

  logger "INFO" "Checking lfg source file: $INSTALL_DIR/$script_name"
  if [ ! -f "$INSTALL_DIR/$script_name" ]; then
    logger "ERROR" "Required source file not found: $INSTALL_DIR/$script_name"
    exit 1
  fi

  maybe_add_lfg_source_dir_to_file "$config_file"
  if shell_has_lfg "$shell_name"; then
    logger "INFO" "lfg is already installed for $shell_name; skipping ${config_file##*/} update"
  else
    add_source_block_to_file "source \"$INSTALL_DIR/$script_name\"" "$config_file"
  fi
}

install_fish() {
  logger "INFO" "=== Installing lfg for fish ==="
  local source_file

  logger "INFO" "Installing fish functions to: $FISH_CONFIG_DIR/functions"
  for source_file in "$INSTALL_DIR/functions/"*.fish; do
    if [ -e "$source_file" ]; then
      install_file "$source_file" "$FISH_CONFIG_DIR/functions/${source_file##*/}"
    fi
  done

  logger "INFO" "Installing fish completions to: $FISH_CONFIG_DIR/completions"
  for source_file in "$INSTALL_DIR/completions/"*.fish; do
    if [ -e "$source_file" ]; then
      install_file "$source_file" "$FISH_CONFIG_DIR/completions/${source_file##*/}"
    fi
  done

  install_file "$INSTALL_DIR/completions/lfg.entrypoints" "$FISH_CONFIG_DIR/completions/lfg.entrypoints"
  logger "INFO" "fish configuration complete"
}

oh_my_zsh_plugin_dir() {
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  echo "$zsh_custom/plugins/lfg"
}

install_oh_my_zsh() {
  logger "INFO" "=== Installing lfg as an Oh My Zsh plugin ==="
  local plugin_dir

  plugin_dir="$(oh_my_zsh_plugin_dir)"
  logger "INFO" "Oh My Zsh plugin directory: $plugin_dir"

  install_file "$INSTALL_DIR/lfg.zsh" "$plugin_dir/lfg.zsh"
  install_file "$INSTALL_DIR/lfg.plugin.zsh" "$plugin_dir/lfg.plugin.zsh"
  install_file "$INSTALL_DIR/completions/lfg.entrypoints" "$plugin_dir/completions/lfg.entrypoints"

  logger "INFO" "Plugin installed to: $plugin_dir"
  if shell_has_lfg zsh; then
    logger "INFO" "lfg is already loaded for zsh"
  else
    logger "WARN" "Add 'lfg' to the plugins array in your .zshrc if it is not already there"
  fi
}

#######################################
# Shell detection and dispatch
#######################################
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

detect_shell() {
  local shell_name

  if [ -n "${SHELL:-}" ] && shell_name="$(install_method_from_value "$SHELL")"; then
    logger "INFO" "Detected shell from \$SHELL: $shell_name"
    echo "$shell_name"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    logger "INFO" "Detected shell from running shell: zsh"
    echo "zsh"
  elif [ -n "${BASH_VERSION:-}" ]; then
    logger "INFO" "Detected shell from running shell: bash"
    echo "bash"
  elif [ -n "${FISH_VERSION:-}" ]; then
    logger "INFO" "Detected shell from running shell: fish"
    echo "fish"
  else
    logger "WARN" "Could not detect shell; defaulting to zsh"
    echo "zsh"
  fi
}

#######################################
# Main entry point
#######################################
METHOD="auto"

main() {
  logger "INFO" "=== Starting lfg installation ==="
  logger "INFO" "Install directory: $INSTALL_DIR"
  logger "INFO" "Requested version: $INSTALL_VERSION"

  parse_args "$@"
  check_dependencies
  detect_source
  reset_install_dir
  install_release_tree

  if [ "$METHOD" = "auto" ]; then
    logger "INFO" "No shell specified; auto-detecting shell"
    METHOD="$(detect_shell)"
  fi

  logger "INFO" "Installing for shell/method: $METHOD"

  case "$METHOD" in
    zsh) install_zsh ;;
    bash) install_bash ;;
    fish) install_fish ;;
    oh-my-zsh) install_oh_my_zsh ;;
    *)
      logger "ERROR" "Unknown install method: $METHOD"
      exit 1
      ;;
  esac

  logger "INFO" "=== lfg installation complete ==="
}

main "$@"
