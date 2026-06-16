#!/usr/bin/env bash
set -euo pipefail

kernel_version="${1:-}"
arch="${2:-$(uname -m)}"
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
workdir="${BBRV3_MAX_WORKDIR:-$repo_root/kernel-max}"

if [[ -z "$kernel_version" ]]; then
  raw_version=$(curl -fsSL https://www.kernel.org/finger_banner |
    awk -F: '/latest stable version/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
  if [[ "$raw_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    kernel_version="${raw_version}.0"
  else
    kernel_version="$raw_version"
  fi
fi

case "$arch" in
  aarch64|arm64)
    build_arch="arm64"
    config_arch="arm64"
    ;;
  x86_64)
    build_arch="x86_64"
    config_arch="x86_64"
    ;;
  *)
    echo "Unsupported arch: $arch" >&2
    exit 1
    ;;
esac

if ! [[ "$kernel_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unexpected kernel version: $kernel_version" >&2
  exit 1
fi

branch=$(echo "$kernel_version" | grep -oE '^[0-9]+\.[0-9]+')
mkdir -p "$workdir"

if [[ ! -d "$workdir/linux/.git" ]]; then
  git clone --depth=1 --branch "linux-$branch.y" \
    https://github.com/gregkh/linux.git "$workdir/linux"
fi

cd "$workdir/linux"
git fetch --depth=1 origin "linux-$branch.y"
git reset --hard FETCH_HEAD
git clean -fdx

bash "$repo_root/scripts/apply-bbrv3-port.sh"
bash "$repo_root/scripts/apply-bbrv3-max-profile.sh"

grep -v "MODULE_DESCRIPTION" net/ipv4/tcp_bbr.c > net/ipv4/tcp_bbr.c.tmp
mv net/ipv4/tcp_bbr.c.tmp net/ipv4/tcp_bbr.c
echo 'MODULE_DESCRIPTION("TCP BBR v3 Max - aggressive throughput profile by Joey");' >> net/ipv4/tcp_bbr.c

IFS='.' read -r v p s <<< "$kernel_version"
sed -i "s/^VERSION *=.*/VERSION = $v/" Makefile
sed -i "s/^PATCHLEVEL *=.*/PATCHLEVEL = $p/" Makefile
sed -i "s/^SUBLEVEL *=.*/SUBLEVEL = $s/" Makefile

export GITHUB_WORKSPACE="$repo_root"
export KERNEL_VERSION="$kernel_version"
bash "$repo_root/scripts/prepare-kernel-config.sh" "$config_arch"

if [[ "$build_arch" == "arm64" ]]; then
  make ARCH=arm64 bindeb-pkg -j"$(nproc)" LOCALVERSION=-joeyblog-bbrv3-max KDEB_COMPRESS=gzip skipdbg=true
else
  make bindeb-pkg -j"$(nproc)" LOCALVERSION=-joeyblog-bbrv3-max KDEB_COMPRESS=gzip skipdbg=true
fi

if find "$workdir" -maxdepth 1 \( -name '*-dbg*.deb' -o -name '*-dbgsym*.deb' \) | grep -q .; then
  echo "ERROR: debug deb package was generated." >&2
  find "$workdir" -maxdepth 1 \( -name '*-dbg*.deb' -o -name '*-dbgsym*.deb' \) -print >&2
  exit 1
fi

find "$workdir" -maxdepth 1 -name 'linux-*.deb' -print | sort
