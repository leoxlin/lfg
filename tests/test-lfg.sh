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

skip_if_missing_shell() {
  local shell="$1"
  local test_name="$2"

  if command -v "$shell" >/dev/null 2>&1; then
    return 1
  fi

  echo "skip - $test_name not found"
  return 0
}

dump_output() {
  local output_file="$1"
  local stderr_file="${2:-}"

  echo "stdout:" >&2
  cat "$output_file" >&2 || true

  if [ -n "$stderr_file" ]; then
    echo "stderr:" >&2
    cat "$stderr_file" >&2 || true
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

if [ -n "${LFG_FZF_STDIN_LOG:-}" ]; then
  cat >> "$LFG_FZF_STDIN_LOG"
else
  cat >/dev/null
fi

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

write_fake_agents() {
  local bin_dir="$1"
  shift
  local agent

  for agent in "$@"; do
    cat > "$bin_dir/$agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'agent=%s\n' "$(basename "$0")"
printf 'pwd=%s\n' "$(pwd -P)"
EOF
    chmod +x "$bin_dir/$agent"
  done
}

shell_script_for() {
  local shell="$1"
  local script="$2"
  local start_dir="$3"
  local lfg_command="${4:-lfg fake-agent}"
  local output_file="${script%/*}/agent.out"
  local stderr_file="${script%/*}/lfg.err"

  case "$shell" in
    bash)
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$ROOT/lfg.bash" || exit 1
cd "$start_dir" || exit 1
$lfg_command > "$output_file" 2> "$stderr_file"
EOF
      ;;
    zsh)
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$ROOT/lfg.zsh" || exit 1
cd "$start_dir" || exit 1
$lfg_command > "$output_file" 2> "$stderr_file"
EOF
      ;;
    fish)
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$ROOT/functions/lfg.fish"
or exit 1
cd "$start_dir"
or exit 1
$lfg_command > "$output_file" 2> "$stderr_file"
EOF
      ;;
    *)
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"
}

run_shell_script() {
  local shell="$1"
  local script="$2"

  case "$shell" in
    bash) "$shell" --noprofile --norc "$script" ;;
    zsh) "$shell" -f "$script" ;;
    fish) "$shell" --no-config "$script" ;;
    *) fail "unknown shell: $shell" ;;
  esac
}

run_lfg_help_case() {
  local shell="$1"
  local tmp="$tmp_root/help-$shell"
  local output_file="$tmp/help.out"
  local stderr_file="$tmp/help.err"
  local script="$tmp/help.$shell"

  if skip_if_missing_shell "$shell" "help/$shell"; then
    return 0
  fi

  mkdir -p "$tmp"

  case "$shell" in
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
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"

  if ! run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "help/$shell failed"
  fi

  assert_file_contains "$output_file" "usage: lfg [entrypoint]" "help/$shell usage"
  assert_file_contains "$output_file" "lfg --update" "help/$shell update"
  assert_file_contains "$output_file" "lfg --version" "help/$shell version"
  assert_file_contains "$output_file" "lfg --help" "help/$shell help"

  if [ -s "$stderr_file" ]; then
    cat "$stderr_file" >&2 || true
    fail "help/$shell: expected empty stderr"
  fi

  echo "ok - help/$shell"
}

run_lfg_version_case() {
  local shell="$1"
  local tmp="$tmp_root/version-$shell"
  local output_file="$tmp/version.out"
  local stderr_file="$tmp/version.err"
  local script="$tmp/version.$shell"
  local source_dir version_file

  if skip_if_missing_shell "$shell" "version/$shell"; then
    return 0
  fi

  mkdir -p "$tmp"
  version_file="$tmp/VERSION"
  printf 'test-version\n' > "$version_file"

  case "$shell" in
    bash)
      cp "$ROOT/lfg.bash" "$tmp/lfg.bash"
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$tmp/lfg.bash" || exit 1
lfg --version > "$output_file" 2> "$stderr_file"
EOF
      ;;
    zsh)
      cp "$ROOT/lfg.zsh" "$tmp/lfg.zsh"
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$tmp/lfg.zsh" || exit 1
lfg --version > "$output_file" 2> "$stderr_file"
EOF
      ;;
    fish)
      mkdir -p "$tmp/install/functions"
      cp "$ROOT/functions/lfg.fish" "$tmp/install/functions/lfg.fish"
      cp "$ROOT/functions/worktree.fish" "$tmp/install/functions/worktree.fish"
      printf 'test-version\n' > "$tmp/install/VERSION"
      mkdir -p "$tmp/functions"
      ln -s "$tmp/install/functions/lfg.fish" "$tmp/functions/lfg.fish"
      ln -s "$tmp/install/functions/worktree.fish" "$tmp/functions/worktree.fish"
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$tmp/functions/lfg.fish"
or exit 1
lfg --version > "$output_file" 2> "$stderr_file"
EOF
      ;;
    *)
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"

  if ! run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "version/$shell failed"
  fi

  assert_eq "$(cat "$output_file")" "lfg test-version" "version/$shell output"

  if [ -s "$stderr_file" ]; then
    cat "$stderr_file" >&2 || true
    fail "version/$shell: expected empty stderr"
  fi

  echo "ok - version/$shell"
}

run_worktree_version_case() {
  local shell="$1"
  local tmp="$tmp_root/worktree-version-$shell"
  local output_file="$tmp/version.out"
  local stderr_file="$tmp/version.err"
  local script="$tmp/version.$shell"
  local source_dir repo version_file

  if skip_if_missing_shell "$shell" "worktree-version/$shell"; then
    return 0
  fi

  mkdir -p "$tmp"
  version_file="$tmp/VERSION"
  printf 'test-version\n' > "$version_file"

  case "$shell" in
    bash)
      cp "$ROOT/lfg.bash" "$tmp/lfg.bash"
      cat > "$script" <<EOF
#!/usr/bin/env bash
set -o pipefail
source "$tmp/lfg.bash" || exit 1
worktree version > "$output_file" 2> "$stderr_file"
EOF
      ;;
    zsh)
      cp "$ROOT/lfg.zsh" "$tmp/lfg.zsh"
      cat > "$script" <<EOF
#!/usr/bin/env zsh
emulate -R zsh
set -o pipefail
source "$tmp/lfg.zsh" || exit 1
worktree version > "$output_file" 2> "$stderr_file"
EOF
      ;;
    fish)
      mkdir -p "$tmp/install/functions"
      cp "$ROOT/functions/lfg.fish" "$tmp/install/functions/lfg.fish"
      cp "$ROOT/functions/worktree.fish" "$tmp/install/functions/worktree.fish"
      printf 'test-version\n' > "$tmp/install/VERSION"
      mkdir -p "$tmp/functions"
      ln -s "$tmp/install/functions/lfg.fish" "$tmp/functions/lfg.fish"
      ln -s "$tmp/install/functions/worktree.fish" "$tmp/functions/worktree.fish"
      cat > "$script" <<EOF
#!/usr/bin/env fish
source "$tmp/functions/lfg.fish"
or exit 1
worktree version > "$output_file" 2> "$stderr_file"
EOF
      ;;
    *)
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"

  if ! run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "worktree-version/$shell failed"
  fi

  assert_eq "$(cat "$output_file")" "worktree test-version" "worktree-version/$shell output"

  if [ -s "$stderr_file" ]; then
    cat "$stderr_file" >&2 || true
    fail "worktree-version/$shell: expected empty stderr"
  fi

  echo "ok - worktree-version/$shell"
}

run_fzf_empty_env_var_case() {
  local shell="$1"
  local tmp source_dir repo bin_dir responses args_log output_file stderr_file script

  if skip_if_missing_shell "$shell" "fzf-empty-env/$shell"; then
    return 0
  fi

  tmp="$tmp_root/fzf-empty-env-$shell"
  source_dir="$tmp/src"
  repo="$source_dir/repo"
  bin_dir="$tmp/bin"
  responses="$tmp/fzf-responses"
  args_log="$tmp/fzf.args"
  output_file="$tmp/agent.out"
  stderr_file="$tmp/lfg.err"
  script="$tmp/case.$shell"

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  setup_repo "$tmp"
  printf '0|feat/existing\n' > "$responses"

  shell_script_for "$shell" "$script" "$repo"

  # shellcheck disable=SC2030
  if ! (
      export LFG_FZF_POINTER_COLOR=""
      PATH="$bin_dir:$ROOT/tests:$PATH" \
        LFG_SOURCE_DIR="$source_dir" \
        LFG_FZF_RESPONSES="$responses" \
        LFG_FZF_ARGS_LOG="$args_log" \
        FZF_DEFAULT_OPTS="--cycle" \
        run_shell_script "$shell" "$script"
    ); then
    dump_output "$output_file" "$stderr_file"
    fail "fzf-empty-env/$shell failed"
  fi

  assert_file_contains "$args_log" "FZF_DEFAULT_OPTS=--cycle --color=pointer:bright-blue" "fzf-empty-env/$shell pointer color fallback"

  echo "ok - fzf-empty-env/$shell"
}

run_fzf_pointer_color_case() {
  local shell="$1"
  local case_spec case_name pointer_color expected_color
  local tmp source_dir repo bin_dir responses args_log output_file stderr_file script

  if skip_if_missing_shell "$shell" "fzf-pointer/$shell"; then
    return 0
  fi

  for case_spec in "default||bright-blue" "custom|bright-magenta|bright-magenta"; do
    IFS='|' read -r case_name pointer_color expected_color <<< "$case_spec"

    tmp="$tmp_root/fzf-pointer-$case_name-$shell"
    source_dir="$tmp/src"
    repo="$source_dir/repo"
    bin_dir="$tmp/bin"
    responses="$tmp/fzf-responses"
    args_log="$tmp/fzf.args"
    output_file="$tmp/agent.out"
    stderr_file="$tmp/lfg.err"
    script="$tmp/case.$shell"

    mkdir -p "$bin_dir"
    write_fake_fzf "$bin_dir"
    setup_repo "$tmp"
    printf '0|feat/existing\n' > "$responses"

    shell_script_for "$shell" "$script" "$repo"

    # shellcheck disable=SC2031
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
          run_shell_script "$shell" "$script"
      ); then
        dump_output "$output_file" "$stderr_file"
        fail "fzf-pointer/$case_name/$shell failed"
    fi

    assert_file_contains "$args_log" "FZF_DEFAULT_OPTS=--cycle --color=pointer:$expected_color" "fzf-pointer/$case_name/$shell pointer color"

    echo "ok - fzf-pointer/$case_name/$shell"
  done
}

run_source_dir_requires_repo_case() {
  local shell="$1"
  local tmp="$tmp_root/source-dir-requires-repo-$shell"
  local source_dir="$tmp/src"
  local start_dir="$tmp/outside"
  local bin_dir="$tmp/bin"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"

  if skip_if_missing_shell "$shell" "source-dir-requires-repo/$shell"; then
    return 0
  fi

  mkdir -p "$source_dir" "$start_dir" "$bin_dir"
  write_fake_fzf "$bin_dir"
  shell_script_for "$shell" "$script" "$start_dir"

  if PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "source-dir-requires-repo/$shell unexpectedly succeeded"
  fi

  assert_file_contains "$stderr_file" "lfg: no git repositories found under $source_dir" "source-dir-requires-repo/$shell stderr"
  assert_file_contains "$stderr_file" "Set LFG_SOURCE_DIR to the folder that contains your cloned git repositories." "source-dir-requires-repo/$shell guidance"

  echo "ok - source-dir-requires-repo/$shell"
}

run_lfg_selection_case() {
  local shell="$1"
  local context="$2"
  local target="$3"
  local tmp="$tmp_root/$shell-$context-$target"
  local source_dir="$tmp/src"
  local repo="$source_dir/repo"
  local bin_dir="$tmp/bin"
  local responses="$tmp/fzf-responses"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"
  local start_dir branch expected_pwd expected_branch expected_is_worktree fzf_code

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  setup_repo "$tmp"

  case "$context" in
    outside) start_dir="$tmp/outside" ;;
    repo) start_dir="$repo" ;;
    worktree) start_dir="$source_dir/.agents/worktrees/repo-feat-start/repo" ;;
    *) fail "$shell/$context/$target: unknown context" ;;
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
    *) fail "$shell/$context/$target: unknown target" ;;
  esac

  : > "$responses"
  if [ "$context" = "outside" ]; then
    printf '0|%s\n%s|%s\n' "${repo##*/}" "$fzf_code" "$branch" > "$responses"
  elif [ "$context" = "repo" ]; then
    printf '%s|%s\n' "$fzf_code" "$branch" > "$responses"
  fi

  shell_script_for "$shell" "$script" "$start_dir"

  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "$shell/$context/$target failed"
  fi

  assert_eq "$(field pwd "$output_file")" "$expected_pwd" "$shell/$context/$target pwd"
  assert_eq "$(field branch "$output_file")" "$expected_branch" "$shell/$context/$target branch"
  assert_eq "$(field toplevel "$output_file")" "$expected_pwd" "$shell/$context/$target toplevel"
  assert_eq "$(field is_worktree "$output_file")" "$expected_is_worktree" "$shell/$context/$target worktree state"

  echo "ok - $shell/$context/$target"
}

run_lfg_selection_cases() {
  local shell="$1"
  local target

  if skip_if_missing_shell "$shell" "$shell"; then
    return 0
  fi

  for target in main new existing; do
    run_lfg_selection_case "$shell" "outside" "$target"
    run_lfg_selection_case "$shell" "repo" "$target"
  done

  run_lfg_selection_case "$shell" "worktree" "current"
}

run_worktree_setup_hook_case() {
  local shell="$1"
  local tmp="$tmp_root/setup-hook-$shell"
  local source_dir="$tmp/src"
  local repo="$source_dir/repo"
  local hook_log="$tmp/hook.log"
  local output_file="$tmp/hook.out"
  local stderr_file="$tmp/hook.err"
  local script="$tmp/setup-hook.$shell"
  local expected_worktree="$source_dir/.agents/worktrees/repo-feat-existing/repo"

  if skip_if_missing_shell "$shell" "setup-hook/$shell"; then
    return 0
  fi

  setup_repo "$tmp"

  case "$shell" in
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
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"

  if ! run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "setup-hook/$shell failed"
  fi

  assert_eq "$(cat "$hook_log")" "$expected_worktree" "setup-hook/$shell hook path"
  assert_eq "$(tail -n1 "$output_file")" "$expected_worktree" "setup-hook/$shell entered worktree"

  echo "ok - setup-hook/$shell"
}

run_lfg_completion_file_case() {
  local shell="$1"
  local tmp="$tmp_root/completion-file-$shell"
  local completions_file="$tmp/entrypoint-completions.txt"
  local output_file="$tmp/completion.out"
  local script="$tmp/completion.$shell"
  local expected

  if skip_if_missing_shell "$shell" "completion-file/$shell"; then
    return 0
  fi

  mkdir -p "$tmp"
  {
    printf '# custom lfg entrypoint completions\n'
    printf '\n'
    printf 'custom-agent\n'
    printf 'another-agent extra fields are ignored\n'
  } > "$completions_file"

  case "$shell" in
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
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"

  if ! LFG_COMPLETIONS_FILE="$completions_file" run_shell_script "$shell" "$script"; then
    dump_output "$output_file"
    fail "completion-file/$shell failed"
  fi

  expected=$'custom-agent\nanother-agent'
  assert_eq "$(cat "$output_file")" "$expected" "completion-file/$shell entrypoint completions"

  echo "ok - completion-file/$shell"
}

run_lfg_completion_missing_file_case() {
  local shell="$1"
  local tmp="$tmp_root/completion-missing-file-$shell"
  local completions_file="$tmp/missing-entrypoint-completions.txt"
  local output_file="$tmp/completion.out"
  local script="$tmp/completion-missing.$shell"

  if skip_if_missing_shell "$shell" "completion-missing-file/$shell"; then
    return 0
  fi

  mkdir -p "$tmp"

  case "$shell" in
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
      fail "unknown shell: $shell"
      ;;
  esac

  chmod +x "$script"

  if ! LFG_COMPLETIONS_FILE="$completions_file" run_shell_script "$shell" "$script"; then
    dump_output "$output_file"
    fail "completion-missing-file/$shell failed"
  fi

  assert_eq "$(cat "$output_file")" "" "completion-missing-file/$shell entrypoint completions"

  echo "ok - completion-missing-file/$shell"
}

run_lfg_smart_mode_case() {
  local shell="$1"
  local tmp="$tmp_root/smart-mode-$shell"
  local source_dir="$tmp/src"
  local bin_dir="$tmp/bin"
  local responses="$tmp/fzf-responses"
  local args_log="$tmp/fzf.args"
  local stdin_log="$tmp/fzf.stdin"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"
  local start_dir

  if skip_if_missing_shell "$shell" "smart-mode/$shell"; then
    return 0
  fi

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_agents "$bin_dir" kimi codex
  setup_repo "$tmp"
  start_dir="$source_dir/.agents/worktrees/repo-feat-start/repo"

  printf '0|kimi\n' > "$responses"

  shell_script_for "$shell" "$script" "$start_dir" "lfg"

  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_SMART_MODE=1 \
      LFG_FZF_RESPONSES="$responses" \
      LFG_FZF_ARGS_LOG="$args_log" \
      LFG_FZF_STDIN_LOG="$stdin_log" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "smart-mode/$shell failed"
  fi

  assert_eq "$(field agent "$output_file")" "kimi" "smart-mode/$shell launched picked entrypoint"
  assert_eq "$(field pwd "$output_file")" "$start_dir" "smart-mode/$shell launched in current worktree"
  assert_file_contains "$stdin_log" "kimi" "smart-mode/$shell offered kimi"
  assert_file_contains "$stdin_log" "codex" "smart-mode/$shell offered codex"
  assert_file_contains "$args_log" "--border-label= Select an agent " "smart-mode/$shell border label"
  assert_file_contains "$args_log" "--prompt=agent> " "smart-mode/$shell prompt"

  echo "ok - smart-mode/$shell"
}

run_lfg_smart_mode_no_entrypoints_case() {
  local shell="$1"
  local tmp="$tmp_root/smart-mode-empty-$shell"
  local source_dir="$tmp/src"
  local bin_dir="$tmp/bin"
  local completions_file="$tmp/entrypoints"
  local responses="$tmp/fzf-responses"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"
  local start_dir

  if skip_if_missing_shell "$shell" "smart-mode-empty/$shell"; then
    return 0
  fi

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  setup_repo "$tmp"
  start_dir="$source_dir/.agents/worktrees/repo-feat-start/repo"

  printf 'lfg-test-missing-agent\n' > "$completions_file"
  : > "$responses"

  shell_script_for "$shell" "$script" "$start_dir" "lfg"

  if PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_SMART_MODE=1 \
      LFG_COMPLETIONS_FILE="$completions_file" \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "smart-mode-empty/$shell unexpectedly succeeded"
  fi

  assert_file_contains "$stderr_file" "lfg: no available agent entrypoints found on PATH" "smart-mode-empty/$shell stderr"

  echo "ok - smart-mode-empty/$shell"
}

run_lfg_smart_mode_explicit_entrypoint_case() {
  local shell="$1"
  local tmp="$tmp_root/smart-mode-explicit-$shell"
  local source_dir="$tmp/src"
  local bin_dir="$tmp/bin"
  local responses="$tmp/fzf-responses"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"
  local start_dir

  if skip_if_missing_shell "$shell" "smart-mode-explicit/$shell"; then
    return 0
  fi

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  setup_repo "$tmp"
  start_dir="$source_dir/.agents/worktrees/repo-feat-start/repo"

  # Empty queue: if the picker ran, fake fzf would exit 130 and fail the run.
  : > "$responses"

  shell_script_for "$shell" "$script" "$start_dir" "lfg fake-agent"

  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_SMART_MODE=1 \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "smart-mode-explicit/$shell failed"
  fi

  assert_eq "$(field pwd "$output_file")" "$start_dir" "smart-mode-explicit/$shell launched explicit entrypoint"

  echo "ok - smart-mode-explicit/$shell"
}

run_recency_ranking_case() {
  local shell="$1"
  local tmp="$tmp_root/recency-$shell"
  local source_dir="$tmp/src"
  local repo2="$source_dir/repo2"
  local bin_dir="$tmp/bin"
  local responses="$tmp/fzf-responses"
  local stdin_log="$tmp/fzf.stdin"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"
  local start_dir="$tmp/outside"

  if skip_if_missing_shell "$shell" "recency/$shell"; then
    return 0
  fi

  mkdir -p "$bin_dir" "$start_dir"
  write_fake_fzf "$bin_dir"
  setup_repo "$tmp"

  mkdir -p "$repo2" || fail "recency/$shell: creates second repo directory"
  git init -b main "$repo2" >/dev/null || fail "recency/$shell: initializes second repo"
  git -C "$repo2" config user.email "tests@example.invalid"
  git -C "$repo2" config user.name "lfg tests"
  printf "second\n" > "$repo2/README.md"
  git -C "$repo2" add README.md
  git -C "$repo2" commit -m "initial" >/dev/null || fail "recency/$shell: creates second repo commit"

  shell_script_for "$shell" "$script" "$start_dir"

  # Run 1: pick repo + branch feat/existing.
  printf '0|repo\n0|feat/existing\n' > "$responses"
  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "recency/$shell run 1 failed"
  fi

  # Run 2: pick repo2 + branch main.
  printf '0|repo2\n0|main\n' > "$responses"
  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "recency/$shell run 2 failed"
  fi

  # Run 3: capture offered candidates; repo pick lists first, branch pick second.
  printf '0|repo\n0|main\n' > "$responses"
  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_FZF_RESPONSES="$responses" \
      LFG_FZF_STDIN_LOG="$stdin_log" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "recency/$shell run 3 failed"
  fi

  assert_eq "$(sed -n '1p' "$stdin_log")" "repo2" "recency/$shell most recent repo first"
  assert_eq "$(sed -n '3p' "$stdin_log")" "feat/existing" "recency/$shell most recent branch first"

  echo "ok - recency/$shell"
}

run_recency_entrypoint_case() {
  local shell="$1"
  local tmp="$tmp_root/recency-entrypoint-$shell"
  local source_dir="$tmp/src"
  local bin_dir="$tmp/bin"
  local responses="$tmp/fzf-responses"
  local stdin_log="$tmp/fzf.stdin"
  local output_file="$tmp/agent.out"
  local stderr_file="$tmp/lfg.err"
  local script="$tmp/case.$shell"
  local start_dir

  if skip_if_missing_shell "$shell" "recency-entrypoint/$shell"; then
    return 0
  fi

  mkdir -p "$bin_dir"
  write_fake_fzf "$bin_dir"
  write_fake_agents "$bin_dir" kimi codex
  setup_repo "$tmp"
  start_dir="$source_dir/.agents/worktrees/repo-feat-start/repo"

  shell_script_for "$shell" "$script" "$start_dir" "lfg"

  # Run 1: pick kimi, which records it as the most recent entrypoint.
  printf '0|kimi\n' > "$responses"
  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_SMART_MODE=1 \
      LFG_FZF_RESPONSES="$responses" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "recency-entrypoint/$shell run 1 failed"
  fi

  # Run 2: pick codex; the offered candidates must rank kimi first.
  printf '0|codex\n' > "$responses"
  if ! PATH="$bin_dir:$ROOT/tests:$PATH" \
      LFG_SOURCE_DIR="$source_dir" \
      LFG_SMART_MODE=1 \
      LFG_FZF_RESPONSES="$responses" \
      LFG_FZF_STDIN_LOG="$stdin_log" \
      run_shell_script "$shell" "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "recency-entrypoint/$shell run 2 failed"
  fi

  assert_eq "$(sed -n '1p' "$stdin_log")" "kimi" "recency-entrypoint/$shell most recent entrypoint first"
  assert_eq "$(field agent "$output_file")" "codex" "recency-entrypoint/$shell launched picked entrypoint"

  echo "ok - recency-entrypoint/$shell"
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

install_shell=""
install_dir=""
install_version=""

while [ $# -gt 0 ]; do
  case "$1" in
    --install-shell)
      install_shell="$2"
      shift 2
      ;;
    --install-dir)
      install_dir="$2"
      shift 2
      ;;
    --install-version)
      install_version="$2"
      shift 2
      ;;
    *)
      echo "unexpected installer arg: $1" >&2
      exit 1
      ;;
  esac
done

{
  printf 'install_shell=%s\n' "$install_shell"
  printf 'install_dir=%s\n' "$install_dir"
  printf 'install_version=%s\n' "$install_version"
} > "$LFG_UPDATE_CAPTURE"
EOF

  cat > "$script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$ROOT/lfg.bash"
lfg --update > "$output_file" 2> "$stderr_file"
EOF
  chmod +x "$script"

  if ! PATH="$bin_dir:$PATH" \
      LFG_FAKE_CURL_LOG="$curl_log" \
      LFG_FAKE_INSTALLER="$fake_installer" \
      LFG_UPDATE_CAPTURE="$capture" \
      bash --noprofile --norc "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "lfg/update-bash failed"
  fi

  assert_file_contains "$curl_log" "https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh" "lfg/update-bash downloaded installer"
  assert_eq "$(field install_shell "$capture")" "bash" "lfg/update-bash install shell"
  assert_eq "$(field install_dir "$capture")" "$ROOT" "lfg/update-bash install dir"
  assert_eq "$(field install_version "$capture")" "" "lfg/update-bash lets installer choose latest release"

  echo "ok - lfg/update-bash"
}

run_lfg_update_fish_case() {
  local tmp="$tmp_root/lfg-update-fish"
  local bin_dir="$tmp/bin"
  local fake_installer="$tmp/install.sh"
  local curl_log="$tmp/curl.log"
  local capture="$tmp/update.env"
  local script="$tmp/update.fish"
  local output_file="$tmp/update.out"
  local stderr_file="$tmp/update.err"

  if skip_if_missing_shell fish "lfg/update-fish"; then
    return 0
  fi

  mkdir -p "$bin_dir" "$tmp/functions"
  write_fake_update_curl "$bin_dir"

  cat > "$fake_installer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${LFG_UPDATE_CAPTURE:?LFG_UPDATE_CAPTURE must be set}"

install_shell=""
install_dir=""
install_version=""

while [ $# -gt 0 ]; do
  case "$1" in
    --install-shell)
      install_shell="$2"
      shift 2
      ;;
    --install-dir)
      install_dir="$2"
      shift 2
      ;;
    --install-version)
      install_version="$2"
      shift 2
      ;;
    *)
      echo "unexpected installer arg: $1" >&2
      exit 1
      ;;
  esac
done

{
  printf 'install_shell=%s\n' "$install_shell"
  printf 'install_dir=%s\n' "$install_dir"
  printf 'install_version=%s\n' "$install_version"
} > "$LFG_UPDATE_CAPTURE"
EOF

  # Install fish functions into a fake install dir and symlink them, matching a
  # real install layout, so _lfg_update computes the install dir correctly.
  mkdir -p "$tmp/install/functions"
  cp "$ROOT/functions/lfg.fish" "$tmp/install/functions/lfg.fish"
  cp "$ROOT/functions/worktree.fish" "$tmp/install/functions/worktree.fish"
  ln -s "$tmp/install/functions/lfg.fish" "$tmp/functions/lfg.fish"
  ln -s "$tmp/install/functions/worktree.fish" "$tmp/functions/worktree.fish"

  cat > "$script" <<EOF
#!/usr/bin/env fish
source "$tmp/functions/lfg.fish"
or exit 1
lfg --update > "$output_file" 2> "$stderr_file"
EOF
  chmod +x "$script"

  if ! PATH="$bin_dir:$PATH" \
      LFG_FAKE_CURL_LOG="$curl_log" \
      LFG_FAKE_INSTALLER="$fake_installer" \
      LFG_UPDATE_CAPTURE="$capture" \
      fish --no-config "$script"; then
    dump_output "$output_file" "$stderr_file"
    fail "lfg/update-fish failed"
  fi

  assert_file_contains "$curl_log" "https://raw.githubusercontent.com/leoxlin/lfg/main/install.sh" "lfg/update-fish downloaded installer"
  assert_eq "$(field install_shell "$capture")" "fish" "lfg/update-fish install shell"
  assert_eq "$(field install_dir "$capture")" "$tmp/install" "lfg/update-fish install dir"
  assert_eq "$(field install_version "$capture")" "" "lfg/update-fish lets installer choose latest release"

  echo "ok - lfg/update-fish"
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/lfg-tests.XXXXXX")"
export LFG_STORE_DIR="$tmp_root/store"
shells=(bash zsh fish)

for shell in "${shells[@]}"; do
  run_lfg_selection_cases "$shell"
  run_source_dir_requires_repo_case "$shell"
  run_worktree_setup_hook_case "$shell"
  run_lfg_completion_file_case "$shell"
  run_lfg_completion_missing_file_case "$shell"
  run_lfg_smart_mode_case "$shell"
  run_lfg_smart_mode_no_entrypoints_case "$shell"
  run_lfg_smart_mode_explicit_entrypoint_case "$shell"
  run_recency_ranking_case "$shell"
  run_recency_entrypoint_case "$shell"
  run_lfg_help_case "$shell"
  run_lfg_version_case "$shell"
  run_worktree_version_case "$shell"
  run_fzf_pointer_color_case "$shell"
  run_fzf_empty_env_var_case "$shell"
done

run_lfg_update_bash_case
run_lfg_update_fish_case

echo "ok - lfg tests complete"
