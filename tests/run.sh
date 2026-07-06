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

assert_file_contains() {
  local file="$1"
  local expected="$2"
  local message="$3"

  assert_file_exists "$file" "$message"
  if ! grep -Fq "$expected" "$file"; then
    fail "$message: expected $file to contain '$expected'"
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

field() {
  local name="$1"
  local file="$2"

  awk -F= -v name="$name" '$1 == name { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

write_fake_fzf() {
  local bin_dir="$1"

  cat > "$bin_dir/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LFG_FZF_RESPONSES:?LFG_FZF_RESPONSES must point to queued fake fzf responses}"

cat >/dev/null

if [ ! -s "$LFG_FZF_RESPONSES" ]; then
  echo "fake fzf: no queued response" >&2
  exit 130
fi

line="$(sed -n '1p' "$LFG_FZF_RESPONSES")"
tail -n +2 "$LFG_FZF_RESPONSES" > "$LFG_FZF_RESPONSES.next"
mv "$LFG_FZF_RESPONSES.next" "$LFG_FZF_RESPONSES"

code="${line%%|*}"
output="${line#*|}"

if [ "$output" != "__EMPTY__" ]; then
  printf '%s\n' "$output"
fi

exit "$code"
EOF
  chmod +x "$bin_dir/fzf"
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

write_fake_update_curl() {
  local bin_dir="$1"

  cat > "$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LFG_FAKE_CURL_LOG:?LFG_FAKE_CURL_LOG must be set}"
: "${LFG_FAKE_INSTALLER:?LFG_FAKE_INSTALLER must be set}"

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
cp "$LFG_FAKE_INSTALLER" "$output"
EOF
  chmod +x "$bin_dir/curl"
}

setup_repo() {
  local tmp="$1"
  local source_dir="$tmp/src"
  local repo="$source_dir/repo"
  local existing_worktree="$source_dir/.agents/worktrees/repo-feat-existing"
  local start_worktree="$source_dir/.agents/worktrees/repo-feat-start"

  mkdir -p "$repo" || fail "creates test repo directory"
  git init -b main "$repo" >/dev/null || fail "initializes test repo"
  git -C "$repo" config user.email "tests@example.invalid"
  git -C "$repo" config user.name "lfg tests"
  printf "initial\n" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -m "initial" >/dev/null || fail "creates initial commit"

  mkdir -p "$(dirname "$existing_worktree")"
  git -C "$repo" worktree add -b feat/existing "$existing_worktree" main >/dev/null 2>&1 || fail "creates existing branch worktree"
  git -C "$repo" worktree add -b feat/start "$start_worktree" main >/dev/null 2>&1 || fail "creates starting worktree"
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
  local install_dir="$tmp/lfg"
  local output_file="$tmp/install.out"

  mkdir -p "$home" "$zdotdir" "$xdg_config_home"

  if ! HOME="$home" \
      ZDOTDIR="$zdotdir" \
      XDG_CONFIG_HOME="$xdg_config_home" \
      LFG_INSTALL_DIR="$install_dir" \
      INSTALL_SHELL="$install_shell" \
      SHELL="$shell_path" \
      bash "$ROOT/install.sh" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/$case_name failed"
  fi

  case "$expected_method" in
    zsh)
      assert_file_contains "$zdotdir/.zshrc" "source \"$install_dir/lfg.zsh\"" "install/$case_name zsh config"
      assert_file_contains_before "$zdotdir/.zshrc" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.zsh\"" "install/$case_name zsh hook before source"
      ;;
    bash)
      assert_file_contains "$home/.bashrc" "source \"$install_dir/lfg.bash\"" "install/$case_name bash config"
      assert_file_contains_before "$home/.bashrc" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.bash\"" "install/$case_name bash hook before source"
      ;;
    fish)
      assert_file_exists "$xdg_config_home/fish/functions/lfg.fish" "install/$case_name fish function"
      assert_file_exists "$xdg_config_home/fish/completions/lfg.fish" "install/$case_name fish completion"
      ;;
    oh-my-zsh)
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.zsh" "install/$case_name oh-my-zsh script"
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.plugin.zsh" "install/$case_name oh-my-zsh plugin"
      ;;
    *)
      fail "install/$case_name: unknown expected method"
      ;;
  esac

  echo "ok - install/$case_name"
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

run_install_idempotent_case() {
  local method="$1"
  local install_shell="$2"
  local tmp="$tmp_root/install-idempotent-$method"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$tmp/lfg"
  local first_output="$tmp/first.out"
  local second_output="$tmp/second.out"
  local config_file before

  mkdir -p "$home" "$zdotdir" "$xdg_config_home"

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    LFG_INSTALL_DIR="$install_dir" \
    INSTALL_SHELL="$install_shell" \
    bash "$ROOT/install.sh" > "$first_output" 2>&1

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
    LFG_INSTALL_DIR="$install_dir" \
    INSTALL_SHELL="$install_shell" \
    bash "$ROOT/install.sh" > "$second_output" 2>&1

  case "$method" in
    zsh)
      assert_file_contains "$config_file" "source \"$install_dir/lfg.zsh\"" "install/idempotent-$method zsh config"
      assert_file_contains_before "$config_file" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.zsh\"" "install/idempotent-$method zsh hook before source"
      assert_eq "$(cat "$config_file")" "$before" "install/idempotent-$method config unchanged"
      assert_file_contains "$second_output" "already installed" "install/idempotent-$method already installed message"
      ;;
    bash)
      assert_file_contains "$config_file" "source \"$install_dir/lfg.bash\"" "install/idempotent-$method bash config"
      assert_file_contains_before "$config_file" "function lfg_worktree_setup() {" "source \"$install_dir/lfg.bash\"" "install/idempotent-$method bash hook before source"
      assert_eq "$(cat "$config_file")" "$before" "install/idempotent-$method config unchanged"
      assert_file_contains "$second_output" "already installed" "install/idempotent-$method already installed message"
      ;;
    fish)
      assert_file_exists "$xdg_config_home/fish/functions/lfg.fish" "install/idempotent-$method fish function"
      assert_file_exists "$xdg_config_home/fish/completions/lfg.fish" "install/idempotent-$method fish completion"
      ;;
    oh-my-zsh)
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.zsh" "install/idempotent-$method oh-my-zsh script"
      assert_file_exists "$home/.oh-my-zsh/custom/plugins/lfg/lfg.plugin.zsh" "install/idempotent-$method oh-my-zsh plugin"
      ;;
  esac

  echo "ok - install/idempotent-$method"
}

run_install_replaces_install_dir_case() {
  local method="$1"
  local install_shell="$2"
  local tmp="$tmp_root/install-replaces-install-dir-$method"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$tmp/lfg"
  local first_output="$tmp/first.out"
  local second_output="$tmp/second.out"
  local stale_file="$install_dir/stale-file"
  local stale_dir="$install_dir/stale-dir"
  local installed_file

  mkdir -p "$home" "$zdotdir" "$xdg_config_home"

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
    LFG_INSTALL_DIR="$install_dir" \
    INSTALL_SHELL="$install_shell" \
    bash "$ROOT/install.sh" > "$first_output" 2>&1

  mkdir -p "$stale_dir"
  printf 'stale\n' > "$stale_file"
  printf 'stale\n' > "$stale_dir/old"

  HOME="$home" \
    ZDOTDIR="$zdotdir" \
    XDG_CONFIG_HOME="$xdg_config_home" \
    LFG_INSTALL_DIR="$install_dir" \
    INSTALL_SHELL="$install_shell" \
    bash "$ROOT/install.sh" > "$second_output" 2>&1

  assert_file_exists "$installed_file" "install/replaces-install-dir-$method copied script"
  if [ -e "$stale_file" ] || [ -e "$stale_dir" ]; then
    fail "install/replaces-install-dir-$method: expected stale install dir contents to be removed"
  fi

  echo "ok - install/replaces-install-dir-$method"
}

run_install_remote_release_case() {
  local case_name="$1"
  local release_version="$2"
  local expected_url="$3"
  local tmp="$tmp_root/install-remote-release-$case_name"
  local home="$tmp/home"
  local zdotdir="$tmp/zdot"
  local xdg_config_home="$tmp/xdg"
  local install_dir="$tmp/lfg"
  local bin_dir="$tmp/bin"
  local archive_dir="$tmp/archives"
  local curl_log="$tmp/curl.log"
  local output_file="$tmp/install.out"
  local -a env_args

  mkdir -p "$home" "$zdotdir" "$xdg_config_home" "$bin_dir" "$archive_dir"
  write_fake_release_curl "$bin_dir"

  LFG_DIST_DIR="$archive_dir" "$ROOT/scripts/release.sh" latest >/dev/null
  LFG_DIST_DIR="$archive_dir" "$ROOT/scripts/release.sh" 2.0.0 >/dev/null

  env_args=(
    "HOME=$home"
    "ZDOTDIR=$zdotdir"
    "XDG_CONFIG_HOME=$xdg_config_home"
    "LFG_INSTALL_DIR=$install_dir"
    "INSTALL_SHELL=zsh"
    "SHELL=/bin/zsh"
    "PATH=$bin_dir:$PATH"
    "LFG_FAKE_CURL_LOG=$curl_log"
    "LFG_RELEASE_ARCHIVE_DIR=$archive_dir"
  )

  if [ -n "$release_version" ]; then
    env_args+=("LFG_RELEASE_VERSION=$release_version")
  fi

  if ! env "${env_args[@]}" bash -s -- < "$ROOT/install.sh" > "$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "install/remote-release-$case_name failed"
  fi

  assert_file_exists "$install_dir/lfg.zsh" "install/remote-release-$case_name installed zsh script"
  assert_file_contains "$curl_log" "$expected_url" "install/remote-release-$case_name downloaded expected release"

  echo "ok - install/remote-release-$case_name"
}

run_install_cases() {
  local removed_arg

  run_install_auto_detect_case "current-shell-zsh" "" "/bin/zsh" "zsh"
  run_install_auto_detect_case "install-shell-fish" "/usr/bin/fish" "/bin/zsh" "fish"
  run_install_auto_detect_case "install-shell-oh-my-zsh" "oh-my-zsh" "/bin/zsh" "oh-my-zsh"

  run_install_idempotent_case "zsh" "zsh"
  run_install_idempotent_case "bash" "bash"
  run_install_idempotent_case "fish" "fish"
  run_install_idempotent_case "oh-my-zsh" "oh-my-zsh"

  run_install_replaces_install_dir_case "zsh" "zsh"
  run_install_replaces_install_dir_case "bash" "bash"

  run_install_remote_release_case "latest" "" "https://github.com/leoxlin/lfg/releases/download/latest/lfg-latest.tar.gz"
  run_install_remote_release_case "specific" "v2.0.0" "https://github.com/leoxlin/lfg/releases/download/v2.0.0/lfg-2.0.0.tar.gz"

  for removed_arg in --zsh --bash --fish --oh-my-zsh --repo-url --repo-ref; do
    run_install_rejects_args_case "$removed_arg"
  done
}

shell_script_for() {
  local shell_name="$1"
  local script="$2"
  local start_dir="$3"
  local lfg_args="$4"
  local output_file="$5"
  local stderr_file="$6"

  case "$shell_name" in
    bash)
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$ROOT/lfg.bash" || exit 1
cd "$start_dir" || exit 1
lfg fake-agent $lfg_args > "$output_file" 2> "$stderr_file"
EOF
      ;;
    zsh)
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$ROOT/lfg.zsh" || exit 1
cd "$start_dir" || exit 1
lfg fake-agent $lfg_args > "$output_file" 2> "$stderr_file"
EOF
      ;;
    fish)
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$ROOT/functions/lfg.fish"
or exit 1
cd "$start_dir"
or exit 1
lfg fake-agent $lfg_args > "$output_file" 2> "$stderr_file"
EOF
      ;;
    *)
      fail "unknown shell: $shell_name"
      ;;
  esac

  chmod +x "$script"
}

run_shell_script() {
  local shell_name="$1"
  local shell_bin="$2"
  local script="$3"

  case "$shell_name" in
    bash) "$shell_bin" --noprofile --norc "$script" ;;
    zsh) "$shell_bin" -f "$script" ;;
    fish) "$shell_bin" --no-config "$script" ;;
    *) fail "unknown shell: $shell_name" ;;
  esac
}

run_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local context="$3"
  local target="$4"
  local tmp="$tmp_root/$shell_name-$context-$target"
  local source_dir="$tmp/src"
  local repo="$source_dir/repo"
  local bin_dir="$tmp/bin"
  local responses="$tmp/fzf-responses"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell_name"
  local start_dir branch expected_pwd expected_branch expected_is_worktree lfg_args fzf_code

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  setup_repo "$tmp"

  case "$context" in
    outside) start_dir="$tmp/outside" ;;
    repo) start_dir="$repo" ;;
    worktree) start_dir="$source_dir/.agents/worktrees/repo-feat-start" ;;
    *) fail "$shell_name/$context/$target: unknown context" ;;
  esac
  mkdir -p "$start_dir"

  case "$target" in
    main)
      branch="main"
      expected_pwd="$repo"
      expected_branch="main"
      expected_is_worktree="false"
      fzf_code="0"
      ;;
    new)
      branch="feat/new"
      expected_pwd="$source_dir/.agents/worktrees/repo-feat-new"
      expected_branch="feat/new"
      expected_is_worktree="true"
      fzf_code="1"
      ;;
    existing)
      branch="feat/existing"
      expected_pwd="$source_dir/.agents/worktrees/repo-feat-existing"
      expected_branch="feat/existing"
      expected_is_worktree="true"
      fzf_code="0"
      ;;
    current)
      branch="feat/start"
      expected_pwd="$source_dir/.agents/worktrees/repo-feat-start"
      expected_branch="feat/start"
      expected_is_worktree="true"
      fzf_code="0"
      ;;
    *) fail "$shell_name/$context/$target: unknown target" ;;
  esac

  : > "$responses"
  lfg_args=""
  if [ "$context" = "outside" ]; then
    printf '0|%s\n%s|%s\n' "$repo" "$fzf_code" "$branch" > "$responses"
  elif [ "$context" = "repo" ]; then
    printf '%s|%s\n' "$fzf_code" "$branch" > "$responses"
  fi

  shell_script_for "$shell_name" "$script" "$start_dir" "$lfg_args" "$output_file" "$stderr_file"

  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell_name" "$shell_bin" "$script"; then
    echo "stdout:" >&2
    cat "$output_file" >&2 || true
    echo "stderr:" >&2
    cat "$stderr_file" >&2 || true
    fail "$shell_name/$context/$target failed"
  fi

  assert_eq "$(field pwd "$output_file")" "$expected_pwd" "$shell_name/$context/$target pwd"
  assert_eq "$(field branch "$output_file")" "$expected_branch" "$shell_name/$context/$target branch"
  assert_eq "$(field toplevel "$output_file")" "$expected_pwd" "$shell_name/$context/$target toplevel"
  assert_eq "$(field is_worktree "$output_file")" "$expected_is_worktree" "$shell_name/$context/$target worktree state"

  echo "ok - $shell_name/$context/$target"
}

run_shell_cases() {
  local shell_name="$1"
  local shell_bin="$2"
  local target

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - $shell_name not found"
    return 0
  fi

  for target in main new existing; do
    run_case "$shell_name" "$shell_bin" "outside" "$target"
    run_case "$shell_name" "$shell_bin" "repo" "$target"
  done

  run_case "$shell_name" "$shell_bin" "worktree" "current"
}

run_worktree_setup_hook_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local tmp="$tmp_root/setup-hook-$shell_name"
  local source_dir="$tmp/src"
  local repo="$source_dir/repo"
  local hook_log="$tmp/hook.log"
  local output_file="$tmp/hook.out"
  local stderr_file="$tmp/hook.err"
  local script="$tmp/setup-hook.$shell_name"
  local expected_worktree="$source_dir/.agents/worktrees/repo-feat-existing"

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - setup-hook/$shell_name not found"
    return 0
  fi

  setup_repo "$tmp"

  case "$shell_name" in
    bash)
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
function lfg_worktree_setup() {
  printf '%s\n' "\$1" > "$hook_log"
}
source "$ROOT/lfg.bash" || exit 1
cd "$repo" || exit 1
worktree cd feat/existing > "$output_file" 2> "$stderr_file"
pwd >> "$output_file"
EOF
      ;;
    zsh)
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
function lfg_worktree_setup() {
  printf '%s\n' "\$1" > "$hook_log"
}
source "$ROOT/lfg.zsh" || exit 1
cd "$repo" || exit 1
worktree cd feat/existing > "$output_file" 2> "$stderr_file"
pwd >> "$output_file"
EOF
      ;;
    fish)
      cat > "$script" <<EOF
#!/usr/bin/env fish
function lfg_worktree_setup
    printf '%s\n' "\$argv[1]" > "$hook_log"
end
source "$ROOT/functions/lfg.fish"
or exit 1
cd "$repo"
or exit 1
worktree cd feat/existing > "$output_file" 2> "$stderr_file"
pwd >> "$output_file"
EOF
      ;;
    *)
      fail "unknown shell: $shell_name"
      ;;
  esac

  chmod +x "$script"

  if ! run_shell_script "$shell_name" "$shell_bin" "$script"; then
    echo "stdout:" >&2
    cat "$output_file" >&2 || true
    echo "stderr:" >&2
    cat "$stderr_file" >&2 || true
    fail "setup-hook/$shell_name failed"
  fi

  assert_eq "$(cat "$hook_log")" "$expected_worktree" "setup-hook/$shell_name hook path"
  assert_eq "$(tail -n1 "$output_file")" "$expected_worktree" "setup-hook/$shell_name entered worktree"

  echo "ok - setup-hook/$shell_name"
}

run_lfg_update_bash_case() {
  local tmp="$tmp_root/lfg-update-bash"
  local bin_dir="$tmp/bin"
  local fake_installer="$tmp/install.sh"
  local curl_log="$tmp/curl.log"
  local capture="$tmp/update.env"
  local script="$tmp/update.bash"
  local output_file="$tmp/update.out"
  local stderr_file="$tmp/update.err"

  mkdir -p "$bin_dir"
  write_fake_update_curl "$bin_dir"

  cat > "$fake_installer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LFG_UPDATE_CAPTURE:?LFG_UPDATE_CAPTURE must be set}"

{
  printf 'install_shell=%s\n' "${INSTALL_SHELL:-}"
  printf 'install_dir=%s\n' "${LFG_INSTALL_DIR:-}"
  printf 'release_version=%s\n' "${LFG_RELEASE_VERSION:-}"
} > "$LFG_UPDATE_CAPTURE"
EOF

  cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/lfg.bash"
export LFG_INSTALL_DIR="$tmp/install-dir"
export LFG_RELEASE_VERSION="2.0.0"
lfg --update > "$output_file" 2> "$stderr_file"
EOF
  chmod +x "$script"

  if ! PATH="$bin_dir:$PATH" \
      LFG_FAKE_CURL_LOG="$curl_log" \
      LFG_FAKE_INSTALLER="$fake_installer" \
      LFG_UPDATE_CAPTURE="$capture" \
      bash --noprofile --norc "$script"; then
    echo "stdout:" >&2
    cat "$output_file" >&2 || true
    echo "stderr:" >&2
    cat "$stderr_file" >&2 || true
    fail "lfg/update-bash failed"
  fi

  assert_file_contains "$curl_log" "https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh" "lfg/update-bash downloaded installer"
  assert_eq "$(field install_shell "$capture")" "bash" "lfg/update-bash install shell"
  assert_eq "$(field install_dir "$capture")" "$tmp/install-dir" "lfg/update-bash install dir"
  assert_eq "$(field release_version "$capture")" "2.0.0" "lfg/update-bash release version"

  echo "ok - lfg/update-bash"
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/lfg-tests.XXXXXX")"

run_install_cases

run_lfg_update_bash_case

run_worktree_setup_hook_case "bash" "bash"
run_worktree_setup_hook_case "zsh" "zsh"
run_worktree_setup_hook_case "fish" "fish"

run_shell_cases "bash" "bash"
run_shell_cases "zsh" "zsh"
run_shell_cases "fish" "fish"

echo "ok - shell tests complete"
