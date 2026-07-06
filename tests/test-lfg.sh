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
  if ! grep -Fq -- "$expected" "$file"; then
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

if [ -n "${LFG_FZF_ARGS_LOG:-}" ]; then
  printf 'FZF_DEFAULT_OPTS=%s\n' "${FZF_DEFAULT_OPTS:-}" >> "$LFG_FZF_ARGS_LOG"
  printf '%s\n' "$*" >> "$LFG_FZF_ARGS_LOG"
fi

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
  local existing_worktree="$source_dir/.agents/worktrees/repo-feat-existing/repo"
  local start_worktree="$source_dir/.agents/worktrees/repo-feat-start/repo"

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

run_lfg_help_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local tmp="$tmp_root/help-$shell_name"
  local output_file="$tmp/help.out"
  local stderr_file="$tmp/help.err"
  local script="$tmp/help.$shell_name"

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - help/$shell_name not found"
    return 0
  fi

  mkdir -p "$tmp"

  case "$shell_name" in
    bash)
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$ROOT/lfg.bash" || exit 1
lfg --help > "$output_file" 2> "$stderr_file"
EOF
      ;;
    zsh)
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$ROOT/lfg.zsh" || exit 1
lfg --help > "$output_file" 2> "$stderr_file"
EOF
      ;;
    fish)
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$ROOT/functions/lfg.fish"
or exit 1
lfg --help > "$output_file" 2> "$stderr_file"
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
    fail "help/$shell_name failed"
  fi

  assert_file_contains "$output_file" "usage: lfg [entrypoint]" "help/$shell_name usage"
  assert_file_contains "$output_file" "lfg --update" "help/$shell_name update"
  assert_file_contains "$output_file" "lfg --help" "help/$shell_name help"

  if [ -s "$stderr_file" ]; then
    cat "$stderr_file" >&2 || true
    fail "help/$shell_name: expected empty stderr"
  fi

  echo "ok - help/$shell_name"
}

run_fzf_pointer_color_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local case_spec case_name pointer_color expected_color
  local tmp source_dir repo bin_dir responses args_log output_file stderr_file script

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - fzf-pointer/$shell_name not found"
    return 0
  fi

  for case_spec in "default||bright-blue" "custom|bright-magenta|bright-magenta"; do
    IFS='|' read -r case_name pointer_color expected_color <<< "$case_spec"

    tmp="$tmp_root/fzf-pointer-$case_name-$shell_name"
    source_dir="$tmp/src"
    repo="$source_dir/repo"
    bin_dir="$tmp/bin"
    responses="$tmp/fzf-responses"
    args_log="$tmp/fzf.args"
    output_file="$tmp/agent.out"
    stderr_file="$tmp/lfg.err"
    script="$tmp/case.$shell_name"

    mkdir -p "$bin_dir"
    write_fake_fzf "$bin_dir"
    setup_repo "$tmp"
    printf '0|feat/existing\n' > "$responses"

    shell_script_for "$shell_name" "$script" "$repo" "" "$output_file" "$stderr_file"

    if ! (
        if [ -n "$pointer_color" ]; then
          export LFG_FZF_POINTER_COLOR="$pointer_color"
        else
          unset LFG_FZF_POINTER_COLOR
        fi
        PATH="$bin_dir:$ROOT/tests:$PATH" \
          LFG_SOURCE_DIR="$source_dir" \
          LFG_FZF_RESPONSES="$responses" \
          LFG_FZF_ARGS_LOG="$args_log" \
          FZF_DEFAULT_OPTS="--cycle" \
          run_shell_script "$shell_name" "$shell_bin" "$script"
      ); then
        echo "stdout:" >&2
        cat "$output_file" >&2 || true
        echo "stderr:" >&2
        cat "$stderr_file" >&2 || true
        fail "fzf-pointer/$case_name/$shell_name failed"
    fi

    assert_file_contains "$args_log" "FZF_DEFAULT_OPTS=--cycle --color=pointer:$expected_color" "fzf-pointer/$case_name/$shell_name pointer color"

    echo "ok - fzf-pointer/$case_name/$shell_name"
  done
}

run_source_dir_requires_repo_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local tmp="$tmp_root/source-dir-requires-repo-$shell_name"
  local source_dir="$tmp/src"
  local start_dir="$tmp/outside"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell_name"

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - source-dir-requires-repo/$shell_name not found"
    return 0
  fi

  mkdir -p "$source_dir" "$start_dir" "$bin_dir"
  write_fake_fzf "$bin_dir"
  shell_script_for "$shell_name" "$script" "$start_dir" "" "$output_file" "$stderr_file"

  if PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      run_shell_script "$shell_name" "$shell_bin" "$script"; then
    echo "stdout:" >&2
    cat "$output_file" >&2 || true
    echo "stderr:" >&2
    cat "$stderr_file" >&2 || true
    fail "source-dir-requires-repo/$shell_name unexpectedly succeeded"
  fi

  assert_file_contains "$stderr_file" "lfg: no git repositories found under $source_dir" "source-dir-requires-repo/$shell_name stderr"
  assert_file_contains "$stderr_file" "Set LFG_SOURCE_DIR to the folder that contains your cloned git repositories." "source-dir-requires-repo/$shell_name guidance"

  echo "ok - source-dir-requires-repo/$shell_name"
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
    worktree) start_dir="$source_dir/.agents/worktrees/repo-feat-start/repo" ;;
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
      expected_pwd="$source_dir/.agents/worktrees/repo-feat-new/repo"
      expected_branch="feat/new"
      expected_is_worktree="true"
      fzf_code="1"
      ;;
    existing)
      branch="feat/existing"
      expected_pwd="$source_dir/.agents/worktrees/repo-feat-existing/repo"
      expected_branch="feat/existing"
      expected_is_worktree="true"
      fzf_code="0"
      ;;
    current)
      branch="feat/start"
      expected_pwd="$source_dir/.agents/worktrees/repo-feat-start/repo"
      expected_branch="feat/start"
      expected_is_worktree="true"
      fzf_code="0"
      ;;
    *) fail "$shell_name/$context/$target: unknown target" ;;
  esac

  : > "$responses"
  lfg_args=""
  if [ "$context" = "outside" ]; then
    printf '0|%s\n%s|%s\n' "${repo##*/}" "$fzf_code" "$branch" > "$responses"
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
  local expected_worktree="$source_dir/.agents/worktrees/repo-feat-existing/repo"

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

run_lfg_completion_file_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local tmp="$tmp_root/completion-file-$shell_name"
  local completions_file="$tmp/entrypoint-completions.txt"
  local output_file="$tmp/completion.out"
  local script="$tmp/completion.$shell_name"
  local expected

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - completion-file/$shell_name not found"
    return 0
  fi

  mkdir -p "$tmp"
  {
    printf '# custom lfg entrypoint completions\n'
    printf '\n'
    printf 'custom-agent\n'
    printf 'another-agent extra fields are ignored\n'
  } > "$completions_file"

  case "$shell_name" in
    bash)
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$ROOT/lfg.bash" || exit 1
_lfg_entrypoint_completions > "$output_file"
EOF
      ;;
    zsh)
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$ROOT/lfg.zsh" || exit 1
_lfg_entrypoint_completions > "$output_file"
EOF
      ;;
    fish)
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$ROOT/completions/lfg.fish"
or exit 1
__lfg_entrypoint_completions > "$output_file"
EOF
      ;;
    *)
      fail "unknown shell: $shell_name"
      ;;
  esac

  chmod +x "$script"

  if ! LFG_COMPLETIONS_FILE="$completions_file" run_shell_script "$shell_name" "$shell_bin" "$script"; then
    echo "stdout:" >&2
    cat "$output_file" >&2 || true
    fail "completion-file/$shell_name failed"
  fi

  expected=$'custom-agent\nanother-agent'
  assert_eq "$(cat "$output_file")" "$expected" "completion-file/$shell_name entrypoint completions"

  echo "ok - completion-file/$shell_name"
}

run_lfg_completion_missing_file_case() {
  local shell_name="$1"
  local shell_bin="$2"
  local tmp="$tmp_root/completion-missing-file-$shell_name"
  local completions_file="$tmp/missing-entrypoint-completions.txt"
  local output_file="$tmp/completion.out"
  local script="$tmp/completion-missing.$shell_name"

  if ! command -v "$shell_bin" >/dev/null 2>&1; then
    echo "skip - completion-missing-file/$shell_name not found"
    return 0
  fi

  mkdir -p "$tmp"

  case "$shell_name" in
    bash)
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$ROOT/lfg.bash" || exit 1
_lfg_entrypoint_completions > "$output_file" || true
EOF
      ;;
    zsh)
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$ROOT/lfg.zsh" || exit 1
_lfg_entrypoint_completions > "$output_file" || true
EOF
      ;;
    fish)
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$ROOT/completions/lfg.fish"
or exit 1
__lfg_entrypoint_completions > "$output_file"; or true
EOF
      ;;
    *)
      fail "unknown shell: $shell_name"
      ;;
  esac

  chmod +x "$script"

  if ! LFG_COMPLETIONS_FILE="$completions_file" run_shell_script "$shell_name" "$shell_bin" "$script"; then
    echo "stdout:" >&2
    cat "$output_file" >&2 || true
    fail "completion-missing-file/$shell_name failed"
  fi

  assert_eq "$(cat "$output_file")" "" "completion-missing-file/$shell_name entrypoint completions"

  echo "ok - completion-missing-file/$shell_name"
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

run_lfg_update_bash_case

run_lfg_help_case "bash" "bash"
run_lfg_help_case "zsh" "zsh"
run_lfg_help_case "fish" "fish"

run_fzf_pointer_color_case "bash" "bash"
run_fzf_pointer_color_case "zsh" "zsh"
run_fzf_pointer_color_case "fish" "fish"

run_source_dir_requires_repo_case "bash" "bash"
run_source_dir_requires_repo_case "zsh" "zsh"
run_source_dir_requires_repo_case "fish" "fish"

run_lfg_completion_file_case "bash" "bash"
run_lfg_completion_file_case "zsh" "zsh"
run_lfg_completion_file_case "fish" "fish"

run_lfg_completion_missing_file_case "bash" "bash"
run_lfg_completion_missing_file_case "zsh" "zsh"
run_lfg_completion_missing_file_case "fish" "fish"

run_worktree_setup_hook_case "bash" "bash"
run_worktree_setup_hook_case "zsh" "zsh"
run_worktree_setup_hook_case "fish" "fish"

run_shell_cases "bash" "bash"
run_shell_cases "zsh" "zsh"
run_shell_cases "fish" "fish"

echo "ok - lfg tests complete"
