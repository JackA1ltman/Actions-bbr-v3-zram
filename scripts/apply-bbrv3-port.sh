#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

kernel_version=$(awk '
  /^VERSION[[:space:]]*=/ { version = $3 }
  /^PATCHLEVEL[[:space:]]*=/ { patchlevel = $3 }
  END {
    if (version == "" || patchlevel == "") {
      exit 1
    }
    print version "." patchlevel
  }
' Makefile)

patch_file="${BBRV3_PATCH:-$repo_root/patches/bbrv3-linux-$kernel_version.patch}"

if [[ ! -f "$patch_file" ]]; then
  echo "BBRv3 patch not found for linux-$kernel_version.y: $patch_file" >&2
  echo "Add a matching patches/bbrv3-linux-$kernel_version.patch before building this kernel series." >&2
  exit 1
fi

git apply --check "$patch_file"
git apply "$patch_file"

if ! grep -q '^#define BBR_VERSION[[:space:]]*3' net/ipv4/tcp_bbr.c; then
  echo "BBRv3 patch applied, but BBR_VERSION=3 was not found." >&2
  exit 1
fi

echo "Applied BBRv3 port: $patch_file"
