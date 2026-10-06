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
    ./usb-shell.nix
    ./usb.nix
    ./camera.nix
  ];

  options.hardware.liuqin = {
    enable = lib.mkEnableOption "Xiaomi Pad 6 Pro (liuqin) hardware support";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.liuqinKernel;
      description = ''
        The liuqin kernel: one build carrying every board feature (USB3
        peripheral, Type-C host/OTG, DP Alt Mode, MiPPS). Override this only
        when testing a custom kernel.
      '';
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
          "uboot"  U-Boot boots the extlinux configuration NixOS installs at
                   /boot/extlinux/extlinux.conf on the `linux` partition
                   (NixOS' generic-extlinux-compatible loader): the label
                   list, kernel, initrd, device tree and kernel command line
                   all come from that one file, so any generation NixOS keeps
                   can be booted from the device menu.
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

    debugTransport = lib.mkOption {
      type = lib.types.enum [ "ssh" "usb" "both" "none" ];
      default = "ssh";
      description = ''
        Debug transport for the installed system. "ssh" is the normal
        network path, "usb" enables the legacy USB NCM/ECM root shell,
        "both" enables both paths, and "none" disables both services.
        Enabling SSH also defaults `PasswordAuthentication` off, so the
        path is key-only unless the machine configuration says otherwise.
        The RAM installer keeps its USB rescue channel independently so it
        remains available when the installed system cannot bring up Wi-Fi.
        SSH keys and user access policy remain the responsibility of the
        machine configuration.
      '';
    };

    sensors = {
      enable = (lib.mkEnableOption ''
        Qualcomm SSC sensor stack (SLPI lifecycle, hexagonrpcd, iio-sensor-proxy)'')
        // { default = true; };

      sscConfigHash = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          sha256 (SRI form) of liuqin-ssc-config.tar.zst: the stock ROM's
          vendor/etc/sensors/config, optionally with sns_reg.conf and
          sns_reg_version, archived deterministically. Operator-only data; see
          docs/PORTING-NOTES.md. Config-only archives are accepted and the
          audited plain-text registry contract is synthesized. The build fails
          with a clear error while unset.'';
      };
    };
  };

  config =
    lib.mkIf cfg.enable {
      nixpkgs.overlays = [ (import ../../overlay.nix) ];

      boot.kernelPackages = pkgs.linuxPackagesFor cfg.package;

      # Post-mortem forensics on a unit with no reachable debug UART.  The
      # PMIC vWDT resets ~20s after the kernel stops petting it; the lockup
      # detectors (enabled in kernel/config.nix) bark earlier and panic, and
      # the panic text plus the stuck task's stack land in the ramoops pstore
      # dump, which survives the reset.  ftrace_dump_on_oops pushes an armed
      # tracer's ring buffer into that same dump.
      boot.kernel.sysctl = {
        "kernel.watchdog_thresh" = 5;
        "kernel.ftrace_dump_on_oops" = 1;
      };

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
          # The panel console.  With DRM_CLIENT_DEFAULT_FBDEV (see
          # kernel/liuqin-firstboot.config) fbcon binds on the DSI panel, so
          # console=tty0 gives the kernel log *and* a getty on the panel, and a
          # compositor takes DRM master from it normally.  The downstream
          # "drm_log" client is deliberately NOT named here any more: it
          # implements no terminal, so it cleared the panel and printed nothing
          # at the default loglevel, and the compositor's buffers never reached
          # it either (measured on the unit; the RAM installer never used it).
          "console=tty0"
          # CS35L41 calibration is per-device state, provisioned from the
          # persist partition at boot; /lib/firmware is the read-only store
          # tree, so the firmware loader gets one extra writable path.
          "firmware_class.path=/var/lib/firmware"
          # TEO chooses the idle state from the timer deadline instead of
          # menu's heuristics, which is the better default on a
          # battery-powered device.  kernel/liuqin-firstboot.config builds it
          # in and says "chosen at runtime", but nothing ever chose it: the
          # kernel came up on menu (drivers/cpuidle/cpuidle.c exposes the
          # choice as cpuidle.governor=).
          "cpuidle.governor=teo"
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

      # NixOS' default loglevel=4 hides nearly the whole kernel log, and the
      # panel is this board's only early failure channel - the RAM installer
      # keeps the kernel's own default for exactly that reason.  Consumers can
      # still lower it.
      boot.consoleLogLevel = lib.mkDefault 7;

      # Keep the installed system's normal debug path on the network. The
      # legacy USB gadget remains an explicit opt-in (or can be selected
      # together with SSH); the installer has its own unconditional USB
      # rescue channel and is not governed by this option.
      services.openssh.enable = lib.mkDefault (
        cfg.debugTransport == "ssh" || cfg.debugTransport == "both"
      );
      # NixOS defaults this to true, and an sshd that accepts passwords is
      # not something a hardware module should turn on by itself: the tablet
      # sits on Wi-Fi and user passwords here start as placeholders. Still
      # only a default, so a machine that wants password auth can say so.
      services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
      hardware.liuqin.usbShell.enable = lib.mkDefault (
        cfg.debugTransport == "usb" || cfg.debugTransport == "both"
      );

      # U-Boot boots NixOS through NixOS' own extlinux loader: it writes the
      # generation list to /boot/extlinux/extlinux.conf on the `linux`
      # partition, next to the kernel, initrd and device tree each label points
      # at. The device menu's two NixOS entries (liuqin-dualboot's liuqin.env)
      # then either take the default generation or list them all.
      boot.loader.generic-extlinux-compatible = lib.mkIf (cfg.boot.loader == "uboot") {
        enable = true;
        # One menu entry per generation; the panel lists them by name, so a few
        # are worth keeping for rollback. Measure /boot before raising this.
        configurationLimit = lib.mkDefault 8;
      };

      # The generation menu falls back to DEFAULT - the generation installed
      # last - once its countdown runs out; the timeout is what the loader
      # module writes into extlinux.conf.
      #
      # 100, not 10: extlinux's TIMEOUT counts tenths of a second (U-Boot's
      # boot/pxe_utils.c divides it by 10 before menu_create(), which takes
      # seconds - common/menu.c), and the loader module passes
      # boot.loader.timeout through verbatim. 10 would therefore be a
      # one-second countdown, not enough to pick a generation with the volume
      # and power buttons.
      boot.loader.timeout = lib.mkIf (cfg.boot.loader == "uboot") (lib.mkDefault 100);

      # The loader copies each generation's <toplevel>/dtbs into /boot, and that
      # tree holds every device tree the kernel builds. Only this board's
      # belongs there, and an explicit name is what turns the entry into a
      # plain FDT line instead of a directory the loader has to guess in.
      hardware.deviceTree = lib.mkIf (cfg.boot.loader == "uboot") {
        name = "qcom/sm8475-xiaomi-liuqin.dtb";
        filter = "*liuqin*.dtb";
      };

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

      # ABL's path has no menu of ours: its boot.img carries the kernel and a
      # fixed command line. The U-Boot path above has one, through NixOS'
      # extlinux loader.
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
