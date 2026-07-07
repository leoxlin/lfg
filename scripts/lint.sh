#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
}

cd "$ROOT"

command -v shellcheck >/dev/null 2>&1 || fail "shellcheck is required for linting"
command -v bash >/dev/null 2>&1 || fail "bash is required for linting"
command -v zsh >/dev/null 2>&1 || fail "zsh is required for linting"
command -v fish >/dev/null 2>&1 || fail "fish is required for linting"

echo "==> shellcheck"
shellcheck lfg.bash install.sh scripts/release.sh scripts/lint.sh tests/test-lfg.sh tests/test-install.sh

echo "==> bash -n"
bash -n lfg.bash
bash -n install.sh
bash -n scripts/release.sh
bash -n scripts/lint.sh
bash -n tests/test-lfg.sh
bash -n tests/test-install.sh

echo "==> zsh -n"
zsh -n lfg.zsh

echo "==> fish -n"
fish -n functions/lfg.fish
fish -n functions/worktree.fish
fish -n completions/lfg.fish
fish -n completions/worktree.fish

echo "==> lint ok"
