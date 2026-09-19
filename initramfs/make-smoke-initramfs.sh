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

busybox=${1:?usage: make-smoke-initramfs.sh <aarch64-static-busybox> [out.cpio.gz] [e2fsprogs]}
# Static e2fsprogs (optional): gives the smoke init mke2fs, so the new linux
# partition can be formatted on the device - where the partition offset is
# known - instead of through fastboot flash, which did not survive that path.
e2fs=${3:-}
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
# The kernel execve()s /init and resolves its interpreter from the initramfs,
# before any userspace exists: without /bin/sh a "#!/bin/sh" init dies with
# "Failed to execute /init (error -2)" and panics, and the smoke script never
# runs a single line. The script's shebang names busybox directly for the same
# reason; this symlink is what any other #!/bin/sh helper would need.
ln -s busybox "$staging/bin/sh"
if [ -n "$e2fs" ]; then
	mkdir -p "$staging/sbin"
	cp "$e2fs/sbin/mke2fs" "$staging/sbin/mke2fs"
	ln -s mke2fs "$staging/sbin/mkfs.ext4"
	file -b "$staging/sbin/mke2fs" | grep -q "statically linked" || {
		echo "mke2fs is not static; it would need a loader in the initramfs" >&2
		exit 1
	}
fi
cp "$init" "$staging/init"
chmod 0755 "$staging/init" "$staging/bin/busybox"

( cd "$staging" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$out"
echo "wrote $out ($(stat -c %s "$out") bytes)"
