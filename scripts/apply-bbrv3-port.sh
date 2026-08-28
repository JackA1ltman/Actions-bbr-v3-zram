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
  # 上游开新系列(如 7.1 -> 7.2)时补丁文件必然缺席。BBRv3 的移植内容跨小版本
  # 基本不变，冲突通常只是行号偏移，直接硬退出会让整条流水线停摆到有人手工补文件。
  # 这里回退到版本号最大的那份旧补丁，配合下面的模糊应用去试；真冲突仍会失败。
  fallback_patch=$(ls "$repo_root"/patches/bbrv3-linux-*.patch 2>/dev/null \
    | sort -t- -k3 -V | tail -n 1)
  if [[ -z "$fallback_patch" ]]; then
    echo "BBRv3 patch not found for linux-$kernel_version.y: $patch_file" >&2
    echo "Add a matching patches/bbrv3-linux-$kernel_version.patch before building this kernel series." >&2
    exit 1
  fi
  echo "No patch for linux-$kernel_version.y; falling back to $(basename "$fallback_patch")." >&2
  echo "Refresh patches/bbrv3-linux-$kernel_version.patch from a successful build tree." >&2
  patch_file="$fallback_patch"
fi

# 先试精确应用；失败再退到带模糊匹配的 patch(1)。
# 上游 stable 常只改注释/SPDX 之类的上下文行(如 7.1.6 把 tcp_bbr.c 的 SPDX 改成
# "GPL-2.0 OR BSD-3-Clause")，精确应用会整条流水线挂掉，模糊匹配能自愈这类漂移；
# 真正的语义冲突仍然会失败。
if git apply --check "$patch_file" 2>/dev/null; then
  git apply "$patch_file"
else
  echo "Exact patch application failed; retrying with fuzzy matching." >&2
  if ! patch -p1 --forward --fuzz=3 --dry-run < "$patch_file"; then
    echo "BBRv3 patch does not apply to this tree even with fuzz." >&2
    echo "Refresh patches/bbrv3-linux-$kernel_version.patch against the current linux-$kernel_version.y tree." >&2
    exit 1
  fi
  patch -p1 --forward --fuzz=3 < "$patch_file"
  echo "WARNING: patch applied with fuzz; refresh the patch file when convenient." >&2
fi

if ! grep -q '^#define BBR_VERSION[[:space:]]*3' net/ipv4/tcp_bbr.c; then
  echo "BBRv3 patch applied, but BBR_VERSION=3 was not found." >&2
  exit 1
fi

echo "Applied BBRv3 port: $patch_file"
