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
                   (pkgs/bootimg.nix). Initial installation is always performed
                   from the RAM installer image; no host-side fastboot writer is
                   part of this repository.
          "uboot"  U-Boot's `boot_linux` reads /boot/Image, /boot/initrd.img and
                   /boot/liuqin.dtb from the `linux` partition and calls booti.
                   The command line is baked into the DTB (pkgs/bootdir.nix)
                   because U-Boot deliberately passes none: it only overwrites
                   /chosen/bootargs when a $bootargs variable exists.
      '';
    };

    boot.debug = lib.mkEnableOption ''
      verbose debug boot parameters (ignore_loglevel, clk_ignore_unused,
      pd_ignore_unused, panic diagnostics, keep_bootcon).
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

  config =
    lib.mkIf cfg.enable {
      nixpkgs.overlays = [ (import ../../overlay.nix) ];

      boot.kernelPackages = pkgs.linuxPackagesFor cfg.package;

      boot.kernelParams =
        [
          # The SLPI must not auto-boot before the sensor registry is served.
          "qcom_q6v5_pas.slpi_auto_boot=0"
          # UFS enumeration and the storage guard take a moment.
          "rootwait"
          # ABL's framebuffer must stay out of the DRM path while the mainline
          # display stack starts.  The SMMU/display-clock blacklist that went
          # with the bring-up profiles is gone: disabling those initcalls
          # crashes this unit, so nothing offers or uses it any more (see
          # docs/PORTING-NOTES.md).  Keep this exact parameter in one place so
          # boot.img and U-Boot/DTB paths cannot drift.
          "initcall_blacklist=simplefb_driver_init"
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
          "hung_task_panic=1"
          "softlockup_panic=1"
          "panic=0"
        ];

      # /boot payload for the U-Boot loader path. The flake exposes it through
      # mkLiuqinBootImages when boot.loader = "uboot".
      system.build.liuqinBootDir = lib.mkIf (cfg.boot.loader == "uboot") (
        pkgs.liuqinBootdir {
          kernel = cfg.package;
          dtb = pkgs.liuqinKernelDtb;
          initrd = config.system.build.initialRamdisk + "/initrd";
          bootargs = lib.concatStringsSep " " (
            config.boot.kernelParams
            ++ [ "init=${config.system.build.toplevel}/init" ]
          );
        }
      );

      # systemd-based stage 1 is the only supported initrd here.
      boot.initrd.systemd.enable = lib.mkDefault true;
      # The device kernel has UFS, SCSI, ext4, IOMMU and the USB/input path
      # built in. NixOS' generic initrd module list contains PC-only entries
      # such as ata_piix; asking module-rebuild to resolve that list makes a
      # device-specific kernel fail before the root guard can run. Keep the
      # normal image minimal and require an explicit override for an optional
      # module on a custom hardware variant.
      boot.initrd.includeDefaultModules = lib.mkForce false;
      boot.initrd.availableKernelModules = lib.mkForce [ ];
      boot.initrd.kernelModules = lib.mkForce [ ];

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
