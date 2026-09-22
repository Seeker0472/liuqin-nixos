# SPDX-License-Identifier: MIT
#
# /boot payload for the U-Boot loader path (hardware.liuqin.boot.loader = "uboot").
#
# U-Boot's `boot_linux` (liuqin-dualboot/.../liuqin.env) reads exactly these
# three files from /boot on the "linux" partition and calls `booti` with the
# DTB, deliberately leaving $bootargs unset. U-Boot only overwrites
# /chosen/bootargs when that variable exists, so the kernel command line has to
# travel inside the DTB - that is what this derivation bakes in.
#
# No boot.img, no mkbootimg and no ABL boot-header contract is involved here:
# that machinery (pkgs/bootimg.nix) belongs to the ABL path, which loads the
# kernel from a boot partition instead of from the filesystem.
{ runCommand
, dtc
, kernel
, dtb
, initrd
, bootargs
}:

runCommand "liuqin-bootdir"
{
  nativeBuildInputs = [ dtc ];
  inherit bootargs;
} ''
  mkdir -p $out
  cp ${kernel}/Image $out/Image
  cp ${initrd} $out/initrd.img
  cp ${dtb}/sm8475-xiaomi-liuqin.dtb $out/liuqin.dtb
  chmod u+w $out/liuqin.dtb

  # Overwrite whatever the kernel's own DTS carries. fdtput needs write access
  # (the store copy is read-only) and the string is passed as a single value.
  fdtput -t s $out/liuqin.dtb /chosen bootargs "$bootargs"

  # Assert it landed: a silent failure here would boot a kernel with the wrong
  # console/root parameters, which on this device is indistinguishable from a
  # hang on the panel.
  got=$(fdtget $out/liuqin.dtb /chosen bootargs)
  [ "$got" = "$bootargs" ] || {
    echo "bootdir: /chosen/bootargs is '$got', expected '$bootargs'" >&2
    exit 1
  }

  # Sizes the U-Boot script's load addresses were chosen for (see liuqin.env):
  # the initrd shares DRAM with ABL's splash framebuffer below 0xb8000000.
  initrd_size=$(stat -c %s $out/initrd.img)
  # linux_initrd_addr=0xa7400000 and linux_fdt_addr=0xb2000000 leave 172 MiB
  # for the initrd while keeping it below the separately loaded DTB.  The
  # kernel is at 0xb3000000; the DTB therefore also stays below the kernel.
  [ "$initrd_size" -lt 180355072 ] || {
    echo "bootdir: initrd is $initrd_size bytes; the load address only leaves" >&2
    echo "172 MiB before the U-Boot DTB - move linux_initrd_addr first" >&2
    exit 1
  }
''
