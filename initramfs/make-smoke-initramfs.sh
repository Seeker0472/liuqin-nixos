#!/usr/bin/env bash
# Pack the liuqin smoke-test initramfs: a *static* aarch64 busybox plus
# liuqin-smoke-init, as the gzipped cpio that bootimg.nix takes as `ramdisk`.
#
#   nix build 'github:NixOS/nixpkgs/nixos-unstable#legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform.pkgsStatic.busybox'
#   ./make-smoke-initramfs.sh result/bin/busybox
#
# The busybox must be static and aarch64: a dynamic one would need a loader and
# libs inside the initramfs, and the target is the tablet's CPU.  The cpio must
# carry the files at the archive's top level (/init, /bin/busybox).
set -eu

busybox=${1:?usage: make-smoke-initramfs.sh <aarch64-static-busybox> [out.cpio.gz]}
init=$(dirname "$(realpath "$0")")/liuqin-smoke-init
out=${2:-$(pwd)/liuqin-smoke-initramfs.cpio.gz}

[ -r "$busybox" ] || { echo "no such busybox: $busybox" >&2; exit 1; }
[ -r "$init" ] || { echo "missing liuqin-smoke-init next to this script" >&2; exit 1; }

# static and aarch64, or the tablet will not run it
file -b "$busybox" | grep -q aarch64 || { echo "busybox is not aarch64" >&2; exit 1; }
file -b "$busybox" | grep -q "statically linked" || {
	echo "busybox is not static; a dynamic one needs a loader and libs in the initramfs" >&2
	exit 1
}

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/bin" "$staging/proc" "$staging/sys" "$staging/dev"
cp "$busybox" "$staging/bin/busybox"
cp "$init" "$staging/init"
chmod 0755 "$staging/init" "$staging/bin/busybox"

( cd "$staging" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$out"
echo "wrote $out ($(stat -c %s "$out") bytes)"
