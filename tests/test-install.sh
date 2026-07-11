#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root=""

fail() {
  echo "not ok - $*" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp_root" ] && [ -d "$tmp_root" ]; then
    rm -rf "$tmp_root"
  fi
}
trap cleanup EXIT

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [ "$actual" != "$expected" ]; then
    fail "$message: expected '$expected', got '$actual'"
  fi
}

assert_file_exists() {
  local file="$1"
  local message="$2"

  if [ ! -f "$file" ]; then
    fail "$message: expected $file to exist"
  fi
}

assert_path_not_exists() {
  local path="$1"
  local message="$2"

  if [ -e "$path" ]; then
    fail "$message: expected $path not to exist"
  fi
}

assert_symlink_points_to() {
  local symlink="$1"
  local expected_target="$2"
  local message="$3"
  local actual_target

  if [ ! -L "$symlink" ]; then
    fail "$message: expected $symlink to be a symlink"
  fi

  actual_target="$(readlink "$symlink")"
  if [ "$actual_target" != "$expected_target" ]; then
    fail "$message: expected $symlink -> $expected_target, got $actual_target"
  fi
}

assert_install_dir_contains_release_tree() {
  local install_dir="$1"
  local message="$2"

  assert_file_exists "$install_dir/lfg.bash" "$message bash script"
  assert_file_exists "$install_dir/lfg.zsh" "$message zsh script"
  assert_file_exists "$install_dir/lfg.plugin.zsh" "$message oh-my-zsh plugin"
  assert_file_exists "$install_dir/functions/lfg.fish" "$message fish function"
  assert_file_exists "$install_dir/functions/worktree.fish" "$message fish worktree function"
  assert_file_exists "$install_dir/completions/lfg.entrypoints" "$message entrypoint completions"
  assert_file_exists "$install_dir/completions/lfg.fish" "$message fish lfg completions"
  assert_file_exists "$install_dir/completions/worktree.fish" "$message fish worktree completions"
  assert_file_exists "$install_dir/VERSION" "$message VERSION file"
}

assert_output_installs_release_tree() {
  local output_file="$1"
  local install_dir="$2"
  local message="$3"

  assert_file_contains "$output_file" "Installed: $install_dir/lfg.bash" "$message installed bash script"
  assert_file_contains "$output_file" "Installed: $install_dir/lfg.zsh" "$message installed zsh script"
  assert_file_contains "$output_file" "Installed: $install_dir/lfg.plugin.zsh" "$message installed plugin script"
  assert_file_contains "$output_file" "Installed: $install_dir/functions/lfg.fish" "$message installed fish function"
  assert_file_contains "$output_file" "Installed: $install_dir/completions/lfg.entrypoints" "$message installed entrypoint completions"
  assert_file_contains "$output_file" "Installed: $install_dir/VERSION" "$message installed VERSION file"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  local message="$3"

  assert_file_exists "$file" "$message"
  if ! grep -Fq -- "$expected" "$file"; then
    fail "$message: expected $file to contain '$expected'"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  local message="$3"

  assert_file_exists "$file" "$message"
  if grep -Fq -- "$unexpected" "$file"; then
    fail "$message: expected $file not to contain '$unexpected'"
  fi
}

assert_file_contains_before() {
  local file="$1"
  local first="$2"
  local second="$3"
  local message="$4"
  local first_line second_line

  assert_file_contains "$file" "$first" "$message first marker"
  assert_file_contains "$file" "$second" "$message second marker"

  first_line="$(grep -Fn "$first" "$file" | sed -n '1s/:.*//p')"
  second_line="$(grep -Fn "$second" "$file" | sed -n '1s/:.*//p')"

  if [ "$first_line" -ge "$second_line" ]; then
    fail "$message: expected '$first' before '$second'"
  fi
}

write_fake_command() {
  local bin_dir="$1"
  local command_name="$2"

  cat > "$bin_dir/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$bin_dir/$command_name"
}

write_fake_fzf() {
  write_fake_command "$1" fzf
}

write_fake_gum() {
  write_fake_command "$1" gum
}

write_fake_brew() {
  local bin_dir="$1"

  cat > "$bin_dir/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ] || [ "$1" != "install" ]; then
  echo "fake brew: unexpected command: $*" >&2
  exit 1
fi

: "${LFG_FAKE_BREW_LOG:?LFG_FAKE_BREW_LOG must be set}"
: "${LFG_FAKE_BREW_BIN_DIR:?LFG_FAKE_BREW_BIN_DIR must be set}"

package="$2"
printf '%s\n' "$*" >> "$LFG_FAKE_BREW_LOG"
cat > "$LFG_FAKE_BREW_BIN_DIR/$package" <<'PKG'
#!/usr/bin/env bash
exit 0
PKG
chmod +x "$LFG_FAKE_BREW_BIN_DIR/$package"
EOF
  chmod +x "$bin_dir/brew"
}

write_minimal_path_command_links() {
  local bin_dir="$1"
  local command_name command_path

  for command_name in bash cat chmod date dirname rm mkdir cp grep find sort uniq sed git; do
    command_path="$(command -v "$command_name")" || fail "missing command for test setup: $command_name"
    ln -s "$command_path" "$bin_dir/$command_name"
  done
}

write_fake_release_curl() {
  local bin_dir="$1"

  cat > "$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LFG_FAKE_CURL_LOG:?LFG_FAKE_CURL_LOG must be set}"
: "${LFG_RELEASE_ARCHIVE_DIR:?LFG_RELEASE_ARCHIVE_DIR must be set}"

output=""
url=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf '%s\n' "$url" >> "$LFG_FAKE_CURL_LOG"

case "$url" in
  https://github.com/leoxlin/lfg/releases/download/latest/lfg-latest.tar.gz)
    cp "$LFG_RELEASE_ARCHIVE_DIR/lfg-latest.tar.gz" "$output"
    ;;
  https://github.com/leoxlin/lfg/releases/download/v2.0.0/lfg-2.0.0.tar.gz)
    cp "$LFG_RELEASE_ARCHIVE_DIR/lfg-2.0.0.tar.gz" "$output"
    ;;
  *)
    echo "fake curl: unexpected URL: $url" >&2
    exit 22
    ;;
esac
EOF
  chmod +x "$bin_dir/curl"
}

run_install_auto_detect_case() {
  local case_name="$1"
  local install_shell="$2"
  local shell_path="$3"
  local expected_method="$4"
  local tmp="$tmp_root/install-$case_name"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/install.out"
  local -a install_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"

  install_args=(--install-dir "$install_dir")
  if [ -n "$install_shell" ]; then
    install_args+=(--install-shell "$install_shell")
  fi

  if ! HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      SHELL="$shell_path" \
      PATH="$bin_dir:$PATH" \
      bash "$ROOT/install.sh" "${install_args[@]}" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/$case_name failed"
  fi

  case "$expected_method" in
    zsh)
      assert_file_contains "$zdotdir/.zshrc" "source \"$install_dir/lfg.zsh\"" "install/$case_name zsh config"
      assert_file_contains_before "$zdotdir/.zshrc" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.zsh\"" "install/$case_name zsh hook before source"
      assert_file_exists "$install_dir/completions/lfg.entrypoints" "install/$case_name zsh entrypoint completions"
      ;;
    bash)
      assert_file_contains "$home/.bashrc" "source \"$install_dir/lfg.bash\"" "install/$case_name bash config"
      assert_file_contains_before "$home/.bashrc" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.bash\"" "install/$case_name bash hook before source"
      assert_file_exists "$install_dir/completions/lfg.entrypoints" "install/$case_name bash entrypoint completions"
      ;;
    fish)
      assert_file_exists "$xdg_config_home/fish/functions/lfg.fish" "install/$case_name fish function"
      assert_symlink_points_to "$xdg_config_home/fish/functions/lfg.fish" "$install_dir/functions/lfg.fish" "install/$case_name fish function symlink"
      assert_file_exists "$xdg_config_home/fish/completions/lfg.fish" "install/$case_name fish completion"
      assert_symlink_points_to "$xdg_config_home/fish/completions/lfg.fish" "$install_dir/completions/lfg.fish" "install/$case_name fish completion symlink"
      assert_file_exists "$xdg_config_home/fish/completions/lfg.entrypoints" "install/$case_name fish entrypoint completions"
      assert_symlink_points_to "$xdg_config_home/fish/completions/lfg.entrypoints" "$install_dir/completions/lfg.entrypoints" "install/$case_name fish entrypoint symlink"
      ;;
    oh-my-zsh)
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.zsh" "install/$case_name oh-my-zsh script"
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.plugin.zsh" "install/$case_name oh-my-zsh plugin"
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/completions/lfg.entrypoints" "install/$case_name oh-my-zsh entrypoint completions"
      ;;
    *)
      fail "install/$case_name: unknown expected method"
      ;;
  esac

  assert_install_dir_contains_release_tree "$install_dir" "install/$case_name release tree"
  assert_output_installs_release_tree "$output_file" "$install_dir" "install/$case_name output"
  case "$expected_method" in
    fish)
      assert_file_contains "$output_file" "Installed: $xdg_config_home/fish/functions/lfg.fish" "install/$case_name output fish function"
      assert_file_contains "$output_file" "Installed: $xdg_config_home/fish/completions/lfg.fish" "install/$case_name output fish completion"
      ;;
    oh-my-zsh)
      assert_file_contains "$output_file" "Installed: $home/.oh-my-zsh/custom/plugins/lfg/lfg.zsh" "install/$case_name output oh-my-zsh script"
      assert_file_contains "$output_file" "Installed: $home/.oh-my-zsh/custom/plugins/lfg/lfg.plugin.zsh" "install/$case_name output oh-my-zsh plugin"
      ;;
  esac

  echo "ok - install/$case_name"
}

run_install_rejects_dangerous_dir_case() {
  local case_name="$1"
  local install_dir="$2"
  local expected_message="$3"
  local tmp="$tmp_root/install-rejects-dangerous-${case_name}"
  local output_file="$tmp/install.out"

  mkdir -p "$tmp"

  if bash "$ROOT/install.sh" --install-dir "$install_dir" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/rejects-dangerous-${case_name}: expected $install_dir to fail"
  fi

  if ! grep -Fq "$expected_message" "$output_file"; then
    cat "$output_file" >&2 || true
    fail "install/rejects-dangerous-${case_name}: expected refusal message"
  fi

  echo "ok - install/rejects-dangerous-${case_name}"
}

run_install_rejects_args_case() {
  local arg="$1"
  local tmp="$tmp_root/install-rejects-${arg#--}"
  local output_file="$tmp/install.out"

  mkdir -p "$tmp"

  if bash "$ROOT/install.sh" "$arg" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/rejects-${arg#--}: expected $arg to fail"
  fi

  if ! grep -Fq "Unknown option: $arg" "$output_file"; then
    cat "$output_file" >&2 || true
    fail "install/rejects-${arg#--}: expected unknown option error"
  fi

  echo "ok - install/rejects-${arg#--}"
}

run_install_preserves_hook_case() {
  local method="$1"
  local install_shell="$2"
  local tmp="$tmp_root/install-preserves-hook-$method"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/install.out"
  local config_file hook_marker
  local -a install_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"
  install_args=(--install-dir "$install_dir" --install-shell "$install_shell")

  case "$method" in
    zsh) config_file="$zdotdir/.zshrc" ;;
    bash) config_file="$home/.bashrc" ;;
    *) fail "install/preserves-hook-$method: unknown method" ;;
  esac

  hook_marker="CUSTOM_HOOK_MARKER"
  mkdir -p "$(dirname "$config_file")"
  cat > "$config_file" <<EOF
function lfg_worktree_setup() {
  printf '%s\n' "$hook_marker" > /dev/null
}
EOF

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    PATH="$bin_dir:$PATH" \
    bash "$ROOT/install.sh" "${install_args[@]}" > "$output_file" 2>&1

  assert_file_contains "$config_file" "$hook_marker" "install/preserves-hook-$method keeps custom hook"
  assert_file_contains "$config_file" "source \"$install_dir/lfg.$method\"" "install/preserves-hook-$method adds source line"
  assert_file_contains_before "$config_file" "$hook_marker" "source \"$install_dir/lfg.$method\"" "install/preserves-hook-$method hook before source"
  assert_file_not_contains "$config_file" "# Optional: customize setup before lfg enters a worktree." "install/preserves-hook-$method does not add no-op stub"

  echo "ok - install/preserves-hook-$method"
}

run_install_idempotent_case() {
  local method="$1"
  local install_shell="$2"
  local tmp="$tmp_root/install-idempotent-$method"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local first_output="$tmp/first.out"
  local second_output="$tmp/second.out"
  local bin_dir="$tmp/bin"
  local config_file before
  local -a install_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"
  install_args=(--install-dir "$install_dir" --install-shell "$install_shell")

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    PATH="$bin_dir:$PATH" \
    bash "$ROOT/install.sh" "${install_args[@]}" > "$first_output" 2>&1

  case "$method" in
    zsh) config_file="$zdotdir/.zshrc" ;;
    bash) config_file="$home/.bashrc" ;;
    fish) config_file="" ;;
    oh-my-zsh) config_file="" ;;
    *) fail "install/idempotent-$method: unknown method" ;;
  esac

  before=""
  if [ -n "$config_file" ]; then
    before="$(cat "$config_file")"
  fi

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    PATH="$bin_dir:$PATH" \
    bash "$ROOT/install.sh" "${install_args[@]}" > "$second_output" 2>&1

  case "$method" in
    zsh)
      assert_file_contains "$config_file" "source \"$install_dir/lfg.zsh\"" "install/idempotent-$method zsh config"
      assert_file_contains_before "$config_file" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.zsh\"" "install/idempotent-$method zsh hook before source"
      assert_eq "$(cat "$config_file")" "$before" "install/idempotent-$method config unchanged"
      assert_file_contains "$second_output" "already installed" "install/idempotent-$method already installed message"
      assert_file_exists "$install_dir/completions/lfg.entrypoints" "install/idempotent-$method entrypoint completions"
      ;;
    bash)
      assert_file_contains "$config_file" "source \"$install_dir/lfg.bash\"" "install/idempotent-$method bash config"
      assert_file_contains_before "$config_file" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.bash\"" "install/idempotent-$method bash hook before source"
      assert_eq "$(cat "$config_file")" "$before" "install/idempotent-$method config unchanged"
      assert_file_contains "$second_output" "already installed" "install/idempotent-$method already installed message"
      assert_file_exists "$install_dir/completions/lfg.entrypoints" "install/idempotent-$method entrypoint completions"
      ;;
    fish)
      assert_file_exists "$xdg_config_home/fish/functions/lfg.fish" "install/idempotent-$method fish function"
      assert_symlink_points_to "$xdg_config_home/fish/functions/lfg.fish" "$install_dir/functions/lfg.fish" "install/idempotent-$method fish function symlink"
      assert_file_exists "$xdg_config_home/fish/completions/lfg.fish" "install/idempotent-$method fish completion"
      assert_symlink_points_to "$xdg_config_home/fish/completions/lfg.fish" "$install_dir/completions/lfg.fish" "install/idempotent-$method fish completion symlink"
      assert_file_exists "$xdg_config_home/fish/completions/lfg.entrypoints" "install/idempotent-$method fish entrypoint completions"
      assert_symlink_points_to "$xdg_config_home/fish/completions/lfg.entrypoints" "$install_dir/completions/lfg.entrypoints" "install/idempotent-$method fish entrypoint symlink"
      ;;
    oh-my-zsh)
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.zsh" "install/idempotent-$method oh-my-zsh script"
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.plugin.zsh" "install/idempotent-$method oh-my-zsh plugin"
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/completions/lfg.entrypoints" "install/idempotent-$method oh-my-zsh entrypoint completions"
      ;;
  esac

  assert_install_dir_contains_release_tree "$install_dir" "install/idempotent-$method release tree"
  assert_output_installs_release_tree "$second_output" "$install_dir" "install/idempotent-$method output"

  echo "ok - install/idempotent-$method"
}

run_install_replaces_install_dir_case() {
  local method="$1"
  local install_shell="$2"
  local tmp="$tmp_root/install-replaces-install-dir-$method"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local first_output="$tmp/first.out"
  local second_output="$tmp/second.out"
  local bin_dir="$tmp/bin"
  local stale_file="$install_dir/stale-file"
  local stale_dir="$install_dir/stale-dir"
  local installed_file
  local -a install_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"
  install_args=(--install-dir "$install_dir" --install-shell "$install_shell")

  case "$method" in
    zsh)
      installed_file="$install_dir/lfg.zsh"
      ;;
    bash)
      installed_file="$install_dir/lfg.bash"
      ;;
    *)
      fail "install/replaces-install-dir-$method: unknown method"
      ;;
  esac

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    PATH="$bin_dir:$PATH" \
    bash "$ROOT/install.sh" "${install_args[@]}" > "$first_output" 2>&1

  mkdir -p "$stale_dir"
  printf 'stale\n' > "$stale_file"
  printf 'stale\n' > "$stale_dir/old"

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    PATH="$bin_dir:$PATH" \
    bash "$ROOT/install.sh" "${install_args[@]}" > "$second_output" 2>&1

  assert_file_exists "$installed_file" "install/replaces-install-dir-$method copied script"
  assert_install_dir_contains_release_tree "$install_dir" "install/replaces-install-dir-$method release tree"
  if [ -e "$stale_file" ] || [ -e "$stale_dir" ]; then
    fail "install/replaces-install-dir-$method: expected stale install dir contents to be removed"
  fi

  echo "ok - install/replaces-install-dir-$method"
}

run_install_source_dir_prompt_case() {
  local tmp="$tmp_root/install-source-dir-prompt"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/install.out"
  local source_dir="$home/Code/Projects"

  mkdir -p \
    "$home/.hidden/nested/repo/.git" \
    "$home/Code/Other/repo/.git" \
    "$source_dir/repo-one/.git" \
    "$source_dir/repo-two/.git" \
    "$bin_dir" \
    "$zdotdir" \
    "$xdg_config_home"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"

  if ! printf 'y\n' | env -u LFG_SOURCE_DIR \
      HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir:$PATH" \
      bash "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/source-dir-prompt failed"
  fi

  assert_file_contains "$output_file" "Detected source directory: $source_dir" "install/source-dir-prompt found source dir"
  assert_file_contains "$zdotdir/.zshrc" "export LFG_SOURCE_DIR=$source_dir" "install/source-dir-prompt zsh source dir"
  assert_file_contains_before "$zdotdir/.zshrc" "export LFG_SOURCE_DIR=$source_dir" "source \"$install_dir/lfg.zsh\"" "install/source-dir-prompt source dir before lfg source"
  assert_install_dir_contains_release_tree "$install_dir" "install/source-dir-prompt release tree"

  echo "ok - install/source-dir-prompt"
}

run_install_local_version_case() {
  local tmp="$tmp_root/install-local-version"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/install.out"

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"

  if ! HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir:$PATH" \
      bash "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/local-version failed"
  fi

  assert_install_dir_contains_release_tree "$install_dir" "install/local-version release tree"
  assert_file_contains "$install_dir/VERSION" "local" "install/local-version VERSION content"
  assert_file_contains "$output_file" "Installed: $install_dir/VERSION" "install/local-version output VERSION"

  echo "ok - install/local-version"
}

run_install_remote_from_temp_case() {
  local tmp="$tmp_root/install-remote-from-temp"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local archive_dir="$tmp/archives"
  local curl_log="$tmp/curl.log"
  local output_file="$tmp/install.out"
  local temp_install_script="$tmp/install.sh"
  local -a env_args
  local -a install_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir" "$archive_dir"
  write_fake_release_curl "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"

  cp "$ROOT/install.sh" "$temp_install_script"

  LFG_DIST_DIR="$archive_dir" "$ROOT/scripts/release.sh" latest >/dev/null

  env_args=(
    "HOME=$home"
    "ZDOTDIR=$zdotdir"
    "XDG_CONFIG_HOME=$xdg_config_home"
    "SHELL=/bin/zsh"
    "PATH=$bin_dir:$PATH"
    "LFG_FAKE_CURL_LOG=$curl_log"
    "LFG_RELEASE_ARCHIVE_DIR=$archive_dir"
  )
  install_args=(--install-dir "$install_dir" --install-shell zsh)

  if ! env "${env_args[@]}" bash "$temp_install_script" "${install_args[@]}" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/remote-from-temp failed"
  fi

  assert_file_contains "$output_file" "Running via remote curl/pipe install" "install/remote-from-temp detected remote"
  assert_file_not_contains "$output_file" "Running from local repository" "install/remote-from-temp did not detect local"
  assert_install_dir_contains_release_tree "$install_dir" "install/remote-from-temp release tree"
  assert_file_contains "$curl_log" "https://github.com/leoxlin/lfg/releases/download/latest/lfg-latest.tar.gz" "install/remote-from-temp downloaded expected release"

  echo "ok - install/remote-from-temp"
}

run_install_remote_release_case() {
  local case_name="$1"
  local release_version="$2"
  local expected_url="$3"
  local tmp="$tmp_root/install-remote-release-$case_name"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local archive_dir="$tmp/archives"
  local curl_log="$tmp/curl.log"
  local output_file="$tmp/install.out"
  local -a env_args
  local -a install_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir" "$archive_dir"
  write_fake_release_curl "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_gum "$bin_dir"

  LFG_DIST_DIR="$archive_dir" "$ROOT/scripts/release.sh" 2.0.0 >/dev/null
  LFG_DIST_DIR="$archive_dir" "$ROOT/scripts/release.sh" latest >/dev/null

  env_args=(
    "HOME=$home"
    "ZDOTDIR=$zdotdir"
    "XDG_CONFIG_HOME=$xdg_config_home"
    "SHELL=/bin/zsh"
    "PATH=$bin_dir:$PATH"
    "LFG_FAKE_CURL_LOG=$curl_log"
    "LFG_RELEASE_ARCHIVE_DIR=$archive_dir"
  )
  install_args=(--install-dir "$install_dir" --install-shell zsh)

  if [ -n "$release_version" ]; then
    install_args+=(--install-version "$release_version")
  fi

  if ! env "${env_args[@]}" bash -s -- "${install_args[@]}" < "$ROOT/install.sh" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/remote-release-$case_name failed"
  fi

  local expected_version="${release_version:-latest}"
  expected_version="${expected_version#v}"

  assert_install_dir_contains_release_tree "$install_dir" "install/remote-release-$case_name release tree"
  assert_output_installs_release_tree "$output_file" "$install_dir" "install/remote-release-$case_name output"
  assert_path_not_exists "$install_dir/repo" "install/remote-release-$case_name does not stage repo under install dir"
  assert_path_not_exists "$install_dir/release" "install/remote-release-$case_name cleans extract dir"
  assert_file_contains "$curl_log" "$expected_url" "install/remote-release-$case_name downloaded expected release"
  assert_file_contains "$install_dir/VERSION" "$expected_version" "install/remote-release-$case_name VERSION content"

  echo "ok - install/remote-release-$case_name"
}

run_install_dependencies_brew_fzf_case() {
  local tmp="$tmp_root/install-dependencies-brew-fzf"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local stale_file="$install_dir/stale-file"
  local bin_dir="$tmp/bin"
  local brew_log="$tmp/brew.log"
  local output_file="$tmp/install.out"
  local bash_bin

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$install_dir" "$bin_dir"
  printf 'stale\n' > "$stale_file"
  write_fake_brew "$bin_dir"
  write_fake_gum "$bin_dir"
  write_minimal_path_command_links "$bin_dir"

  bash_bin="$(command -v bash)" || fail "install/dependencies-brew-fzf: bash not found"

  if ! printf 'y\n' | HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir" \
      LFG_FAKE_BREW_LOG="$brew_log" \
      LFG_FAKE_BREW_BIN_DIR="$bin_dir" \
      "$bash_bin" "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/dependencies-brew-fzf failed"
  fi

  assert_file_contains "$output_file" "Install it with 'brew install fzf'?" "install/dependencies-brew-fzf prompt"
  assert_file_contains "$brew_log" "install fzf" "install/dependencies-brew-fzf brew command"
  assert_path_not_exists "$stale_file" "install/dependencies-brew-fzf replaces install dir after dependency install"
  assert_install_dir_contains_release_tree "$install_dir" "install/dependencies-brew-fzf release tree"

  echo "ok - install/dependencies-brew-fzf"
}

run_install_dependencies_missing_fzf_case() {
  local tmp="$tmp_root/install-dependencies-missing-fzf"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local stale_file="$install_dir/stale-file"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/install.out"
  local bash_bin

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$install_dir" "$bin_dir"
  printf 'stale\n' > "$stale_file"
  write_minimal_path_command_links "$bin_dir"

  bash_bin="$(command -v bash)" || fail "install/dependencies-missing-fzf: bash not found"

  if HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir" \
      "$bash_bin" "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/dependencies-missing-fzf: expected missing fzf to fail"
  fi

  assert_file_contains "$output_file" "fzf is required. Install fzf and rerun install.sh." "install/dependencies-missing-fzf error"
  assert_file_exists "$stale_file" "install/dependencies-missing-fzf keeps install dir before dependency checks pass"

  echo "ok - install/dependencies-missing-fzf"
}

run_install_dependencies_brew_reject_case() {
  local tmp="$tmp_root/install-dependencies-brew-reject"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local stale_file="$install_dir/stale-file"
  local bin_dir="$tmp/bin"
  local brew_log="$tmp/brew.log"
  local output_file="$tmp/install.out"
  local bash_bin

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$install_dir" "$bin_dir"
  printf 'stale\n' > "$stale_file"
  write_fake_brew "$bin_dir"
  write_fake_gum "$bin_dir"
  write_minimal_path_command_links "$bin_dir"

  bash_bin="$(command -v bash)" || fail "install/dependencies-brew-reject: bash not found"

  if printf 'n\n' | HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir" \
      LFG_FAKE_BREW_LOG="$brew_log" \
      LFG_FAKE_BREW_BIN_DIR="$bin_dir" \
      "$bash_bin" "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/dependencies-brew-reject: expected rejected brew install to fail"
  fi

  assert_file_contains "$output_file" "Install it with 'brew install fzf'?" "install/dependencies-brew-reject prompt"
  assert_path_not_exists "$brew_log" "install/dependencies-brew-reject does not run brew"
  assert_file_exists "$stale_file" "install/dependencies-brew-reject keeps install dir before dependency checks pass"

  echo "ok - install/dependencies-brew-reject"
}

run_install_dependencies_brew_gum_case() {
  local tmp="$tmp_root/install-dependencies-brew-gum"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local brew_log="$tmp/brew.log"
  local output_file="$tmp/install.out"
  local bash_bin

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$install_dir" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_brew "$bin_dir"
  write_minimal_path_command_links "$bin_dir"

  bash_bin="$(command -v bash)" || fail "install/dependencies-brew-gum: bash not found"

  if ! printf 'y\n' | HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir" \
      LFG_FAKE_BREW_LOG="$brew_log" \
      LFG_FAKE_BREW_BIN_DIR="$bin_dir" \
      "$bash_bin" "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/dependencies-brew-gum failed"
  fi

  assert_file_contains "$output_file" "Install it with 'brew install gum'?" "install/dependencies-brew-gum prompt"
  assert_file_contains "$brew_log" "install gum" "install/dependencies-brew-gum brew command"
  assert_install_dir_contains_release_tree "$install_dir" "install/dependencies-brew-gum release tree"

  echo "ok - install/dependencies-brew-gum"
}

run_install_dependencies_missing_gum_case() {
  local tmp="$tmp_root/install-dependencies-missing-gum"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$home/lfg"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/install.out"
  local bash_bin

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$install_dir" "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_minimal_path_command_links "$bin_dir"

  bash_bin="$(command -v bash)" || fail "install/dependencies-missing-gum: bash not found"

  if HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      PATH="$bin_dir" \
      "$bash_bin" "$ROOT/install.sh" --install-dir "$install_dir" --install-shell zsh > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/dependencies-missing-gum: expected missing gum to fail"
  fi

  assert_file_contains "$output_file" "gum is required. Install gum and rerun install.sh." "install/dependencies-missing-gum error"

  echo "ok - install/dependencies-missing-gum"
}

run_install_dependencies_cases() {
  run_install_dependencies_brew_fzf_case
  run_install_dependencies_missing_fzf_case
  run_install_dependencies_brew_reject_case
  run_install_dependencies_brew_gum_case
  run_install_dependencies_missing_gum_case
}

run_install_cases() {
  local removed_arg

  run_install_dependencies_cases

  run_install_auto_detect_case "current-shell-zsh" "" "/bin/zsh" "zsh"
  run_install_auto_detect_case "install-shell-fish" "/usr/bin/fish" "/bin/zsh" "fish"
  run_install_auto_detect_case "install-shell-oh-my-zsh" "oh-my-zsh" "/bin/zsh" "oh-my-zsh"

  run_install_idempotent_case "zsh" "zsh"
  run_install_idempotent_case "bash" "bash"
  run_install_idempotent_case "fish" "fish"
  run_install_idempotent_case "oh-my-zsh" "oh-my-zsh"

  run_install_replaces_install_dir_case "zsh" "zsh"
  run_install_replaces_install_dir_case "bash" "bash"

  run_install_preserves_hook_case "zsh" "zsh"
  run_install_preserves_hook_case "bash" "bash"

  run_install_rejects_dangerous_dir_case "root" "/" "Refusing to install to root directory"
  run_install_rejects_dangerous_dir_case "home" "$HOME" "Refusing to install directly into \$HOME"

  run_install_source_dir_prompt_case

  run_install_local_version_case

  run_install_remote_from_temp_case

  run_install_remote_release_case "latest" "" "https://github.com/leoxlin/lfg/releases/download/latest/lfg-latest.tar.gz"
  run_install_remote_release_case "specific" "v2.0.0" "https://github.com/leoxlin/lfg/releases/download/v2.0.0/lfg-2.0.0.tar.gz"

  for removed_arg in --zsh --bash --fish --oh-my-zsh --repo-url --repo-ref; do
    run_install_rejects_args_case "$removed_arg"
  done
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/lfg-install-tests.XXXXXX")"

run_install_cases

echo "ok - install tests complete"
