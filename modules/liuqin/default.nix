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

    boot.debug = lib.mkEnableOption ''
      verbose debug boot parameters (earlycon=simplefb, ignore_loglevel,
      clk_ignore_unused, pd_ignore_unused, panic/pstore diagnostics). Keep
      off for daily use: clk/pd ignore flags keep every unclaimed clock and
      power domain alive and the tablet discharges while plugged in'';
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
        # ABL's framebuffer must stay the kernel's console, not the
        # simplefb driver's device.
        "initcall_blacklist=simplefb_driver_init"
        # The late DRM log console must be named explicitly; console=tty0
        # keeps /dev/console on the VT afterwards.
        "console=drm_log"
        "console=tty0"
      ]
      ++ lib.optionals cfg.boot.debug [
        "earlycon=simplefb"
        "ignore_loglevel"
        "clk_ignore_unused"
        "pd_ignore_unused"
        "initcall_debug"
        "mtdoops.dump_oops=1"
        "hung_task_panic=1"
        "softlockup_panic=1"
        "panic=0"
      ];

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
