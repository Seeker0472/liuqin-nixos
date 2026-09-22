# SPDX-License-Identifier: MIT
# Small aarch64 RAM-initramfs for first hardware bring-up. It deliberately
# reports block devices and holds a read-only USB diagnostics shell; it is not
# an installer and never formats or writes a partition automatically.
{ runCommand
, busybox
, gptfdisk
, f2fsTools
, cpio
, gzip
, smokeInit
, gptCarve ? ../initramfs/liuqin-gpt-carve
, f2fsShrink ? ../initramfs/liuqin-f2fs-shrink
}:

runCommand "liuqin-smoke-initramfs" {
  nativeBuildInputs = [ cpio gzip ];
} ''
  staging=$(mktemp -d)
  trap 'rm -rf "$staging"' EXIT
  mkdir -p "$staging/bin" "$staging/proc" "$staging/sys" "$staging/dev"
  cp ${busybox}/bin/busybox "$staging/bin/busybox"
  # sgdisk is the explicit operator tool for GPT inspection/maintenance in
  # the live image. It is static aarch64 and is not invoked by /init.
  cp ${gptfdisk}/bin/sgdisk "$staging/bin/sgdisk"
  # F2FS must be resized before its GPT partition is shortened.  Ship the
  # static tools for explicit recovery work; PID 1 and the GPT helper never
  # invoke them.  resize.f2fs is a multicall symlink upstream.
  cp ${f2fsTools}/bin/fsck.f2fs "$staging/bin/fsck.f2fs"
  ln -s fsck.f2fs "$staging/bin/resize.f2fs"
  ln -s busybox "$staging/bin/sh"
  cp ${smokeInit} "$staging/init"
  cp ${gptCarve} "$staging/bin/liuqin-gpt-carve"
  cp ${f2fsShrink} "$staging/bin/liuqin-f2fs-shrink"
  chmod 0755 "$staging/init" "$staging/bin/busybox" "$staging/bin/sgdisk" \
    "$staging/bin/fsck.f2fs" "$staging/bin/liuqin-gpt-carve" \
    "$staging/bin/liuqin-f2fs-shrink"
  (cd "$staging" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9) > $out
''
