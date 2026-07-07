#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
Usage: scripts/release.sh [version]

Create a release tarball containing the installable lfg files.

Options:
  -h, --help  Show this help message

Set LFG_RELEASE_VERSION to override the version when no argument is provided.
Set LFG_DIST_DIR to override the output directory (default: dist).
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ $# -gt 1 ]; then
  echo "error: expected at most one version argument" >&2
  usage >&2
  exit 1
fi

version="${1:-${LFG_RELEASE_VERSION:-}}"
if [ -z "$version" ]; then
  version="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || true)"
fi
if [ -z "$version" ]; then
  version="dev"
fi

dist_dir="${LFG_DIST_DIR:-$ROOT/dist}"
mkdir -p "$dist_dir"
dist_dir="$(cd "$dist_dir" && pwd)"

release_name="lfg-$version"
archive_file="$dist_dir/$release_name.tar.gz"

release_patterns=(
  'lfg.*'
  'functions/*'
  'completions/*'
)

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/lfg-release.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

stage_dir="$tmp_dir/$release_name"
mkdir -p "$stage_dir"

release_files=()
shopt -s nullglob
for pattern in "${release_patterns[@]}"; do
  # shellcheck disable=SC2206
  matches=("$ROOT"/$pattern)
  if [ "${#matches[@]}" -eq 0 ]; then
    echo "error: release pattern matched no files: $pattern" >&2
    exit 1
  fi

  for path in "${matches[@]}"; do
    [ -f "$path" ] || continue
    release_files+=("${path#"$ROOT"/}")
  done
done
shopt -u nullglob

for file in "${release_files[@]}"; do
  mkdir -p "$stage_dir/$(dirname "$file")"
  cp -p "$ROOT/$file" "$stage_dir/$file"
done

printf '%s\n' "$version" > "$stage_dir/VERSION"

rm -f "$archive_file"

if command -v tar >/dev/null 2>&1; then
  (cd "$tmp_dir" && tar -czf "$archive_file" "$release_name")
else
  echo "error: release build requires tar" >&2
  exit 1
fi

echo "Created $archive_file"
