# SPDX-License-Identifier: MIT
#
# NixOS module for Xiaomi Pad 6 Pro (liuqin, SM8475). All options live under
# hardware.liuqin; submodules wire boot params, storage, initrd, desktop
# hardware and the GNOME session policy.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  imports = [
    ./storage.nix
    ./hardware.nix
    ./gnome.nix
    ./initrd-guard.nix
  ];

  options.hardware.liuqin = {
    enable = lib.mkEnableOption "Xiaomi Pad 6 Pro (liuqin) hardware support";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.liuqinKernel;
      description = "Kernel package (linuxManualConfig with liuqin patches).";
    };

    boot.loader = lib.mkOption {
      type = lib.types.enum [ "abl" "uboot" ];
      default = "abl";
      description = ''
        Who loads the kernel.

          "abl"    ABL's fastboot loads a boot.img from a boot slot; the kernel
                   command line travels in the Android boot header
                   (pkgs/bootimg.nix), and the installer writes userdata or the
                   `linux` partition.
          "uboot"  U-Boot's `boot_linux` reads /boot/Image, /boot/initrd.img and
                   /boot/liuqin.dtb from the `linux` partition and calls booti.
                   The command line is baked into the DTB (pkgs/bootdir.nix)
                   because U-Boot deliberately passes none: it only overwrites
                   /chosen/bootargs when a $bootargs variable exists.
      '';
    };

    boot.debug = lib.mkEnableOption ''
      verbose debug boot parameters (ignore_loglevel, clk_ignore_unused,
      pd_ignore_unused, panic/pstore diagnostics, keep_bootcon).
      earlycon=simplefb is part of the base cmdline (downstream product
      native-bootargs), not gated here. Keep this off for daily use:
      clk/pd ignore flags keep every unclaimed clock and power domain alive
      and the tablet discharges while plugged in, and keep_bootcon keeps
      simplefb0 writing into the bootloader framebuffer all session, which
      a desktop compositor cannot draw over'';

    sensors = {
      enable = (lib.mkEnableOption ''
        Qualcomm SSC sensor stack (SLPI lifecycle, hexagonrpcd, iio-sensor-proxy)'')
        // { default = true; };

      sscConfigHash = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          sha256 (SRI form) of liuqin-ssc-config.tar.zst: the stock ROM's
          vendor/etc/sensors/config, archived deterministically. Operator-only
          data; see docs/PORTING-NOTES.md. The build fails with a clear error
          while unset.'';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ (import ../../overlay.nix) ];

    boot.kernelPackages = pkgs.linuxPackagesFor cfg.package;

    boot.kernelParams =
      [
        # The SLPI must not auto-boot before the sensor registry is served.
        "qcom_q6v5_pas.slpi_auto_boot=0"
        # UFS enumeration and the storage guard take a moment.
        "rootwait"
        # ABL's framebuffer and display ownership must stay intact while the
        # mainline kernel starts.  The bring-up logs prove that re-running the
        # SMMU stream-table init or SM8450 display-clock init blanks the panel
        # before userspace can take over; simplefb itself must also stay out of
        # the DRM path.  Keep these exact kallsyms names in one parameter so
        # boot.img and U-Boot/DTB paths cannot drift.
        "initcall_blacklist=simplefb_driver_init,arm_smmu_init,disp_cc_sm8450_driver_init"
        # Early console on the ABL simple-framebuffer. Part of the
        # downstream product cmdline (build-bootimg.sh:44): without it
        # there is no output at all before the DSI panel driver loads.
        # keep_bootcon is deliberately NOT in the base string: downstream
        # removed it on purpose (build-bootimg.sh:40-44) because it keeps
        # simplefb0 writing into the bootloader framebuffer all session,
        # which a desktop compositor cannot draw over; it is debug-gated
        # below instead.
        "earlycon=simplefb"
        # The late DRM log console must be named explicitly; console=tty0
        # keeps /dev/console on the VT afterwards.
        "console=drm_log"
        "console=tty0"
        # Same log, but machine-readable: patch 0011's console keeps it in a
        # DRAM ring that survives a reset, so a boot that dies without a usable
        # panel still leaves its log where U-Boot (liuqin_rdump) can collect it.
        # The address has to match that command; 0x9f000000..0x9fd00000 is free
        # DRAM between the mpss and adsp reservations.
        "bootlog=0x9f000000,0x100000"
        # CS35L41 calibration is per-device state, provisioned from the
        # persist partition at boot; /lib/firmware is the read-only store
        # tree, so the firmware loader gets one extra writable path.
        "firmware_class.path=/var/lib/firmware"
      ]
      ++ lib.optionals cfg.boot.debug [
        "ignore_loglevel"
        "keep_bootcon"
        "clk_ignore_unused"
        "pd_ignore_unused"
        "initcall_debug"
        "mtdoops.dump_oops=1"
        "hung_task_panic=1"
        "softlockup_panic=1"
        "panic=0"
      ];

    # /boot payload for the U-Boot loader path. lib.mkLiuqinImages copies it
    # into the rootfs image's /boot when boot.loader = "uboot"; nothing
    # references it otherwise, so it is not built for the ABL path.
    system.build.liuqinBootDir = pkgs.liuqinBootdir {
      kernel = cfg.package;
      dtb = pkgs.liuqinKernelDtb;
      initrd = config.system.build.initialRamdisk + "/initrd";
      bootargs = lib.concatStringsSep " " (
        config.boot.kernelParams
        ++ [ "init=${config.system.build.toplevel}/init" ]
      );
    };

    # systemd-based stage 1 is the only supported initrd here.
    boot.initrd.systemd.enable = lib.mkDefault true;

    # No bootloader menu on this device: the boot.img carries the kernel,
    # and boot.loader.generic-extlinux-compatible et al. do not apply.
    boot.loader.grub.enable = lib.mkDefault false;

    # The PMIC RTC is not writable by HLOS; chrony needs the no-RTC escape
    # hatch so a cold boot months behind real time still converges.
    services.chrony = lib.mkIf config.services.chrony.enable {
      extraConfig = ''
        nocerttimecheck 1
        authselectmode ignore
      '';
    };
  };
}
