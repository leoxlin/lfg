#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
Usage: scripts/release.sh [version]

Create a release zip containing the installable lfg files.

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
zip_file="$dist_dir/$release_name.zip"

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
  matches=("$ROOT"/$pattern)
  if [ "${#matches[@]}" -eq 0 ]; then
    echo "error: release pattern matched no files: $pattern" >&2
    exit 1
  fi

  for path in "${matches[@]}"; do
    [ -f "$path" ] || continue
    release_files+=("${path#$ROOT/}")
  done
done
shopt -u nullglob

for file in "${release_files[@]}"; do
  mkdir -p "$stage_dir/$(dirname "$file")"
  cp -p "$ROOT/$file" "$stage_dir/$file"
done

rm -f "$zip_file"

if command -v python3 >/dev/null 2>&1; then
  python3 - "$tmp_dir" "$release_name" "$zip_file" <<'PY'
import os
import stat
import sys
import zipfile

tmp_dir, release_name, zip_file = sys.argv[1:]
root = os.path.join(tmp_dir, release_name)

with zipfile.ZipFile(zip_file, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        filenames.sort()
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            relpath = os.path.relpath(path, tmp_dir)
            info = zipfile.ZipInfo.from_file(path, relpath)
            mode = stat.S_IMODE(os.stat(path).st_mode)
            info.external_attr = mode << 16
            with open(path, "rb") as handle:
                archive.writestr(info, handle.read(), compress_type=zipfile.ZIP_DEFLATED)
PY
elif command -v zip >/dev/null 2>&1; then
  (cd "$tmp_dir" && zip -X -r "$zip_file" "$release_name" >/dev/null)
elif command -v bsdtar >/dev/null 2>&1; then
  (cd "$tmp_dir" && bsdtar -a -cf "$zip_file" "$release_name")
else
  echo "error: release build requires python3, zip, or bsdtar" >&2
  exit 1
fi

echo "Created $zip_file"
