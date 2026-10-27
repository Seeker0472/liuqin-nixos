# SPDX-License-Identifier: MIT
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.liuqin;
in
{
  config = lib.mkIf cfg.enable (
    let
      firmwareTree = pkgs.liuqinFirmware;
      firmwareMountOptions =
        "ro,lowerdir=${firmwareTree}/lib/firmware:/var/lib/firmware:/run/current-system/firmware";
    in
    {
      # The driver reports ABS_MT_POSITION in the panel's native portrait frame
      # (0..1799 x 0..2879), verified through evdev. The owner confirms touch
      # and pen working; see docs/PORTING-NOTES.md ("Touch and input") for status.
      # Static firmware is fixed to the OS2.0.4 assets; the optional FPC
      # package contains only board-independent firmware, not device secrets.
      hardware.firmware = lib.mkForce (
        [ firmwareTree ] ++ lib.optional cfg.fingerprint.enable pkgs.liuqinFpcFirmware
      );
      hardware.enableRedistributableFirmware = lib.mkForce false;

      # The touchscreen (nvt_ts) request_firmware() fires during probe, before
      # switch_root, so the firmware tree must be in the initrd too.
      # The initrd's /lib is a read-only symlink to the kernel module store, so
      # placing a second tree below /lib/firmware makes systemd's initrd image
      # builder fail. Use the same writable firmware_class.path that carries
      # the device-specific calibration files after switch-root.
      boot.initrd.systemd.contents."/var/lib/firmware".source = "${firmwareTree}/lib/firmware";

      # The firmware loader reads exactly one directory (firmware_class.path;
      # fw_path_para is a single char[256] with no ':') and /lib/firmware does
      # not exist on NixOS, so the board gets a union of the static asset tree,
      # per-device calibration records under /var/lib/firmware, and the NixOS
      # firmware package union (including optional FPC firmware).
      # The order of the two units below is load-bearing, not cosmetic.  The
      # ASoC card probe (triggered by the SoundWire/WCD938x modules udev loads
      # at ~10 s) loads the AudioReach topology
      # `qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin` through this parameter, and a
      # -ENOENT there fails snd_soc_register_card() for the rest of the boot:
      # no card means no playback *and* no capture device.  Until the switch
      # below runs, the loader keeps the path NixOS's activation script wrote
      # (the hardware.firmware environment, which carries the static topology);
      # a mount that fails leaves that environment in place instead of empty.
      # tmpfiles `w` line cannot express that order - tmpfiles-setup runs in
      # the initrd and again long before the union - so it pointed the loader
      # at the not-yet-mounted `/run/firmware` during every card probe.  The
      # parameter itself is compiled in
      # (CONFIG_FW_LOADER, asserted from vmlinux in pkgs/kernel/default.nix),
      # so the file always exists and a broken write fails the unit instead of
      # silently leaving every load to the default path.
      #
      # The mount keeps the ordering the board needs: before sound.target (the
      # CS35L41 protection firmware is requested during the first DAPM
      # power-up) and after the provisioner that writes the calibration
      # records.  A re-provision (e.g. after repairing the persist partition)
      # must be followed by a fresh mount: the overlay reads its lower layers
      # only once, so the union is PartOf the provisioner instead of keeping
      # the previous calibration view.  A missing store tree fails the mount
      # and with it every consumer in that transaction; the calibration records
      # are the provisioner's own fail-closed check (pkgs/persist-provision.nix
      # requires the stock crus_calr.bin before it writes them).
      systemd.mounts = [
        {
          description = "Firmware union (static, system and calibration trees)";
          what = "overlay";
          where = "/run/firmware";
          type = "overlay";
          # Keep the real per-device directory ahead of the system firmware
          # symlink farm. A symlink named cirrus in that layer terminates
          # overlay lookup and otherwise hides the later calibration directory.
          options = firmwareMountOptions;
          # overlayfs rejects lowerdir changes through mount(2) remount. Make
          # every option change a stop/start during switch-to-configuration.
          restartTriggers = [ firmwareMountOptions ];
          wantedBy = [ "sound.target" ];
          before = [ "sound.target" ];
          after = [
            "liuqin-persist-provision.service"
            "systemd-tmpfiles-setup.service"
          ];
          partOf = [ "liuqin-persist-provision.service" ];
          # A mount unit normally counts as a local file system: systemd adds
          # an implicit Before=local-fs.target.  That cycles here - the
          # provisioner this mount follows writes into /var/lib and is itself
          # After=local-fs.target - and systemd resolves such a cycle by
          # deleting a start job from it.  Take the default dependencies out
          # and state what this mount actually needs: the file system holding
          # the calibration lowerdir must be mounted (RequiresMountsFor pulls
          # the root mount in, which the initrd already did), and the union
          # must be stopped during shutdown, which is the automatic
          # umount.target relation a mount unit would otherwise get.
          # `systemd-analyze verify` on the generated unit is clean.
          unitConfig = {
            DefaultDependencies = false;
            # Fail closed before the mount syscall if the immutable tree is
            # absent. restartTriggers above handles live reconfiguration.
            AssertPathIsDirectory = "${firmwareTree}/lib/firmware";
            RequiresMountsFor = "/var/lib/firmware";
            Conflicts = [ "umount.target" ];
            Before = [ "umount.target" ];
          };
        }
      ];

      # NixOS activation sets firmware_class.path in the udevd snippet on
      # every switch. Retain a mounted union until its restart transaction;
      # the loader unit restores the system tree before unmount and selects
      # the replacement union only after it mounts successfully.
      system.activationScripts.liuqin-firmware-path = {
        deps = [ "udevd" ];
        text = ''
          if ${pkgs.util-linux}/bin/mountpoint -q /run/firmware; then
            ${pkgs.liuqinFirmwareLoaderPath}/bin/liuqin-firmware-loader-path /run/firmware
          fi
        '';
      };

      # The loader switch: only after the union (Requires/After above) so that
      # the card probe earlier in the boot still sees the activation script's
      # firmware environment, and before sound.target so the union's
      # calibration records are in place before the first DAPM power-up.
      systemd.services.liuqin-firmware-loader-path = {
        description = "Point the firmware loader at the firmware union";
        wantedBy = [ "sound.target" ];
        requires = [ "run-firmware.mount" ];
        partOf = [ "run-firmware.mount" ];
        after = [ "run-firmware.mount" ];
        before = [ "sound.target" ];
        # Keep the loader active until the mount's post-activation restart:
        # its ExecStop must run before the union disappears, not before
        # activation reselects it. After= reverses this order on shutdown.
        stopIfChanged = false;
        # The parameter exists whenever firmware_class is in the kernel; the
        # condition keeps a module-only build from creating a stray file.
        unitConfig.ConditionPathExists = "/sys/module/firmware_class/parameters/path";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.liuqinFirmwareLoaderPath}/bin/liuqin-firmware-loader-path /run/firmware";
          ExecStop = "${pkgs.liuqinFirmwareLoaderPath}/bin/liuqin-firmware-loader-path ${config.hardware.firmware}/lib/firmware";
        };
      };
    }
  );
}
