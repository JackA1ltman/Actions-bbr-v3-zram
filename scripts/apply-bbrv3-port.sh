#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
patch_file="${BBRV3_PATCH:-$repo_root/patches/bbrv3-linux-7.0.patch}"

if [[ ! -f "$patch_file" ]]; then
  echo "BBRv3 patch not found: $patch_file" >&2
  exit 1
fi

git apply --check "$patch_file"
git apply "$patch_file"

if ! grep -q '^#define BBR_VERSION[[:space:]]*3' net/ipv4/tcp_bbr.c; then
  echo "BBRv3 patch applied, but BBR_VERSION=3 was not found." >&2
  exit 1
fi

echo "Applied BBRv3 port: $patch_file"
