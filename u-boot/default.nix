# SPDX-License-Identifier: MIT
#
# The U-Boot this device boots, built from the same tree the port is developed
# in rather than from a newer upstream release.
#
# Baseline: sm8450-mainline/u-boot, the fork's only branch caleb/rbx-integration,
# commit a4f9d7fccf2c (last pushed 2024-10-27). It is upstream master 9e1cd2f2cb86
# - nine days after v2024.10 - plus 199 Qualcomm phone bring-up commits, so no
# release tag names it and its Makefile still says 2024.10. This is the port's
# historical base: every file the port touches the tree already contains, so the
# port transfers as a plain patch series, with no hunk-level adaptation and no
# symbol renamed out from under it: this builds the same sources with the same
# configuration as the liuqin-dualboot dev tree (verify-port.sh proves the
# former byte for byte, $out/uboot.config the latter). The machine code still
# follows the toolchain - this package pins its own nixpkgs, the dev tree builds
# in the root flake's dev shell - so the two agree in behaviour, not in bytes.
#
#   patches/  the port's changes to files the baseline has, grouped by topic.
#             The groups are file-disjoint, so they apply cleanly in any order
#             and cannot fuzz into each other.
#   files/    the files the port adds, at the paths they belong at:
#             board/qualcomm/liuqin/ (the board), the two device trees and
#             cmd/partlog.c. Copied over the baseline.
#
# Both are cut from liuqin-dualboot/u-boot/source by ./verify-port.sh, which also
# re-checks that baseline + patches + files reproduces that tree byte for byte.
# The dev tree stays the place to hack and measure on hardware; this packaging
# adds nothing to it.
#
# Why this baseline rather than a release: each thing the port had to re-add on
# a newer tree is a silent failure mode on a board with no UART, where a lost
# hook looks exactly like bad hardware - a dark panel and a reset back into
# Android. The fork already carries all of them:
#   * the framebuffer mapping: enable_caches() ends with map_framebuffer()
#     ("Some boards don't include the splash region in the memory map..."), and
#     the whole early console writes into that ABL splash. Upstream v2026.07 has
#     neither the call nor the function, so the first character aborts;
#   * CLK_QCOM_SM8450 and its clock driver. The UFS bring-up has to enable the
#     controller's and PHY's clocks itself (the QMP UFS PHY driver never touches
#     them); newer upstream has no SM8450 GCC entry at all, leaving storage, GPT
#     and the A/B paths dead;
#   * the PMIC GPIO compatibles (pm8350/pm8350b/pm8350c/pmk8350/pmr735a) and
#     their input pull-up. U-Boot's PMIC pinconf cannot express bias, so without
#     it the volume-up key floats and reads randomly - it is the menu's only
#     input - and the PTN3222 reset is a PMIC GPIO too;
#   * the qcom,sm8450-smmu-500 id in qcom-hyp-smmu.c (apps_smmu/adreno SMMU),
#     DWC3_DEPCMD_STATUS as bits [15:12] rather than bit 15, and
#     pm8350_vreg_data, the rails the board's by-name regulator lookups use;
#   * dram.c's SMEM RAM-partition parse. This is what tells the board where its
#     DRAM is: the /memory node here is a placeholder the bootloader fills in, so
#     a newer tree that parses only that node computes a different map - and the
#     framebuffer mapping is derived from it.
#
# The ABL boot.img is packaged by ../pkgs/bootimg.nix, the same pipeline the
# kernel image uses, so the boot contract (identity ids, __symbols__ union,
# inert sink, base 0 / kernel_offset 0x8000 / dtb_offset 0x1f00000, the 8 MiB
# payload padding and the empty newc ramdisk) lives in exactly one place.
#
# Maintaining this: change the dev tree, then run ./verify-port.sh to re-cut
# patches/ and files/ and watch it prove the round trip. A change to a file the
# baseline has belongs in patches/ (add a patch or extend the matching one); a
# change to one of the port's own files is made in files/.
{ lib
, stdenv
, stdenvNoCC
, fetchFromGitHub
, callPackage
, hostPkgs
}:

let
  # The proven image carries a ramdisk, so match its shape: a deterministic
  # empty newc archive (gzip mtime 0, no names, no timestamps).
  emptyRamdisk = stdenvNoCC.mkDerivation {
    pname = "liuqin-uboot-empty-ramdisk";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [ hostPkgs.python3 ];
    buildPhase = ''
      runHook preBuild
      python3 - ramdisk.cpio.gz <<'PYEOF'
import gzip


def pad4(data):
    return data + b"\0" * (-len(data) % 4)


def entry(name, mode, data=b""):
    namez = name.encode() + b"\0"
    fields = [1, mode, 0, 0, 2, 0, len(data), 0, 0, 0, 0, len(namez), 0]
    return (b"070701" + b"".join(b"%08X" % f for f in fields) + namez +
            pad4(data))


raw = entry(".", 0o040755) + entry("TRAILER!!!", 0)
with open("ramdisk.cpio.gz", "wb") as fh:
    fh.write(gzip.compress(raw, compresslevel=9, mtime=0))
PYEOF
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp ramdisk.cpio.gz $out/
      runHook postInstall
    '';
  };

  uboot = stdenv.mkDerivation {
    pname = "liuqin-uboot";
    version = "2024.10+a4f9d7fc";

    src = fetchFromGitHub {
      owner = "sm8450-mainline";
      repo = "u-boot";
      rev = "a4f9d7fccf2cd2fc68b8496d723cd92fd16ff80f";
      hash = "sha256-VG4TxrLaom56o4RaCHyDGe06paFIUq5A+a+Do16rKE4=";
    };

    patches = [
      ./patches/0001-kconfig-symbols.patch
      ./patches/0002-mach-board-hooks.patch
      ./patches/0003-host-pwd.patch
      ./patches/0004-console-and-input.patch
      ./patches/0005-ufs-sm8475.patch
      ./patches/0006-usb2-phy.patch
      ./patches/0007-usb-dwc3.patch
      ./patches/0008-fastboot-hooks.patch
      ./patches/0009-fastboot-gadget-pool.patch
      ./patches/0010-pinctrl-gpio-regulator-smmu.patch
      ./patches/0011-partlog-command.patch
      ./patches/0012-bootmenu-redisplay.patch
      ./patches/0013-pxe-extlinux-key-menu.patch
    ];

    postPatch = ''
      cp -a ${./files}/. .
      patchShebangs tools scripts
    '';

    nativeBuildInputs = with hostPkgs; [
      bc
      bison
      dtc
      flex
      gawk
      gnugrep
      gzip
      openssl
      perl
      python3
      which
      xxd
      zstd
    ];
    # U-Boot builds host tools (dtc wrappers, mkimage, ...) with the build
    # platform's compiler; the target compiler comes from the cross stdenv.
    depsBuildBuild = [ hostPkgs.gccStdenv.cc ];

    hardeningDisable = [ "all" ];
    enableParallelBuilding = true;

    makeFlags = [
      "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
      "DTC=${lib.getExe hostPkgs.dtc}"
      "HOSTCFLAGS=-fcommon"
    ];

    # Verbatim from liuqin-dualboot/u-boot/build.sh: this is the configuration
    # the port's behaviour was measured with, so it is reproduced rather than
    # re-derived. Only the paths differ (the source tree is the build directory
    # here, and the default environment file is resolved against it).
    #
    # CMD_EFICONFIG is disabled on purpose: with it enabled bootmenu_create() runs
    # efi_bootmgr_update_media_device_boot_option() and auto-adds a UEFI boot entry
    # for every block device, titled "scsi N" (efi_disk_get_device_name()).
    # CMD_BOOTEFI_BOOTMGR is disabled as well: efi_disk_create() runs
    # efi_bootmgr_update_media_device_boot_option() for every block device it finds
    # (e.g. on "scsi scan"), which writes non-volatile Boot#### EFI variables and
    # makes efi_var_to_file() log "No EFI system partition" + "Failed to persist
    # EFI variables" for each one. This board has no ESP and needs no UEFI boot
    # options. ("bootefi <addr>" is still available via CMD_BOOTEFI.)
    #
    # ENV_MIN/MAX_ENTRIES: the readback channel exports console dumps through the
    # environment (fastboot.con*, up to CONFIG_CONSOLE_RECORD's 64 KiB worth).
    # U-Boot's hashed env stops accepting variables at CONFIG_ENV_MAX_ENTRIES (512
    # by default) and silently drops the rest, which makes those exports look empty.
    #
    # The payload's text_offset is forced to 0 by the SYS_BOARD="liuqin"
    # conditional default of LNX_KRNL_IMG_TEXT_OFFSET_BASE (unprompted symbol,
    # so it cannot be overridden here).
    configurePhase = ''
      runHook preConfigure

      make ''${makeFlags} O=$NIX_BUILD_TOP/build -j$NIX_BUILD_CORES qcom_defconfig
      ./scripts/config --file $NIX_BUILD_TOP/build/.config \
        -d TOOLS_MKEFICAPSULE \
        -d CMD_EFICONFIG -d CMD_BOOTEFI_BOOTMGR \
        -d CMD_SAVEENV -d CMD_GPT -d CMD_GPT_RENAME \
        -d CMD_EXT4_WRITE -d EXT4_WRITE -d FAT_WRITE -d CMD_DFU -d DFU -d DFU_OVER_USB \
        -d DFU_WRITE_ALT -d DFU_SCSI -d DFU_MMC -d CMD_USB_MASS_STORAGE \
        -d USB_FUNCTION_MASS_STORAGE -d CMD_PARTLOG -d CMD_SCSI -d CMD_MMC -d CMD_UFS -d CMD_USB \
        -d FASTBOOT_OEM_RUN -d CMD_I2C -d CMD_EEPROM \
        -d CMD_NVEDIT_EFI -d EFI_CAPSULE_SUPPORT -d EFI_CAPSULE_ON_DISK \
        -d EFI_CAPSULE_FIRMWARE \
        -d EFI_CAPSULE_FIRMWARE_MANAGEMENT -d EFI_CAPSULE_FIRMWARE_RAW \
        -e ARMV8_SWITCH_TO_EL1 \
        --set-val DEFAULT_ENV_FILE "\"$PWD/board/qualcomm/liuqin/liuqin.env\"" \
        --set-val DEFAULT_DEVICE_TREE '"qcom/sm8450-xiaomi-liuqin"' \
        --set-val SYS_BOARD '"liuqin"' \
        -e PANIC_HANG -e CMD_PAUSE -e BOOTSTD -e BOOTSTD_IGNORE_BOOTABLE \
        -e BOOT_RETRY --set-val BOOT_RETRY_TIME 30 \
        -e VIDEO_SIMPLE -e VIDEO -e DM_VIDEO -e DISPLAY \
        -e VIDEO_FONT_16X32 -d VIDEO_FONT_8X16 -d VIDEO_FONT_4X6 -d VIDEO_FONT_SUN12X22 \
        -d REQUIRE_SERIAL_CONSOLE \
        -e LIUQIN_EARLY_VIDEO -e PRE_CONSOLE_BUFFER \
        --set-val PRE_CON_BUF_ADDR 0xb9400000 --set-val PRE_CON_BUF_SZ 8192 \
        --set-val SYS_FDT_PAD 0x400000 \
        -e CONSOLE_RECORD --set-val CONSOLE_RECORD_OUT_SIZE 65536 \
        --set-val CONSOLE_RECORD_IN_SIZE 512 \
        --set-val ENV_MIN_ENTRIES 4096 --set-val ENV_MAX_ENTRIES 4096 \
        -e BLK -e PARTITIONS \
        -e CMD_SYSBOOT \
        -d USB_FUNCTION_ACM -e USB_GADGET_DOWNLOAD \
        -e USB_GADGET -e DM_USB_GADGET -e USB_DWC3_GADGET \
        -e SYS_I2C_GENI
      make ''${makeFlags} O=$NIX_BUILD_TOP/build olddefconfig

      # The result is not checked against anything: the list above is the
      # measured one, and a silent drift in it (a renamed or re-gated symbol)
      # shows up on hardware rather than here. $out/uboot.config is the record of
      # what this build actually used.

      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      make ''${makeFlags} O=$NIX_BUILD_TOP/build -j$NIX_BUILD_CORES DEVICE_TREE=qcom/sm8450-xiaomi-liuqin
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp $NIX_BUILD_TOP/build/u-boot-nodtb.bin $out/
      # The configuration this image was actually built with: the reference for
      # comparing against a dev-tree build, and the record of what was measured.
      cp $NIX_BUILD_TOP/build/.config $out/uboot.config
      # The DTB the ABL packaging puts in the image's dtb slot.
      cp $NIX_BUILD_TOP/build/dts/upstream/src/arm64/qcom/sm8450-xiaomi-liuqin.dtb $out/
      runHook postInstall
    '';

    dontStrip = true;
  };

  bootimg = callPackage ../pkgs/bootimg.nix {
    # The DTB surgery runs gawk on the build host, so take it from the host
    # package set rather than the cross one.
    inherit (hostPkgs) gawk;
    payload = "${uboot}/u-boot-nodtb.bin";
    baseDtb = "${uboot}/sm8450-xiaomi-liuqin.dtb";
    version = "2024.10+a4f9d7fc+liuqin";
    # Measured: this ABL never entered the 1.4 MiB payload, the same payload
    # zero-padded to 8 MiB boots and drives the panel.
    padPayloadMiB = 8;
    # U-Boot's DTB has no /chosen/bootargs contract to overlay.
    cmdlineOverlay = false;
    ramdisk = "${emptyRamdisk}/ramdisk.cpio.gz";
  };
in
{
  inherit uboot bootimg;
}
