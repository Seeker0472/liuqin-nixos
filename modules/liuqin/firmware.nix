# SPDX-License-Identifier: MIT
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  options.hardware.liuqin.firmware = {
    vpu = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "./liuqin-firmware-vpu.tar.zst";
      description = ''
        Your own qcom/vpu/vpu20_4v.mbn (iris2 VPU firmware) as a zstd tar
        archive, taken from an official MIUI image. A path literal
        (`./liuqin-firmware-vpu.tar.zst`) needs no `nix-store --add-fixed`
        step. When null the hash-pinned archive has to be registered in the
        store; the requireFile error carries the same instructions.
      '';
    };

    cs35l41 = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "./liuqin-firmware-cs35l41.tar.zst";
      description = ''
        Your own CS35L41 Halo protection/calibration payloads as a zstd tar
        archive rooted at `cirrus/`, extracted from the stock ROM's vendor
        partition. A path literal needs no `nix-store --add-fixed` step. When
        null the hash-pinned archive has to be registered in the store.
      '';
    };

    bootImg = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "./boot.img";
      description = ''
        The downstream v0.3.1 release image whose ramdisk carries the bulk of
        the firmware tree (the 196 files under lib/firmware this port pins).
        When null the hash-pinned file has to be registered in the store with
        `nix-store --add-fixed sha256 boot.img`; the requireFile message
        carries the same instructions. Only this release image satisfies the
        pin - the boot.img of a v0.1.0 dump is a different build.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      # Rebuild the payload tree (and the firmware union that carries it) only
      # when the operator supplies their own archives; with both null the
      # override would return the plain derivation anyway, so the injected
      # cross build keeps serving the system unchanged.
      firmwareTree =
        if cfg.firmware.vpu == null && cfg.firmware.cs35l41 == null && cfg.firmware.bootImg == null then
          pkgs.liuqinFirmware
        else
          pkgs.liuqinFirmware.override {
            inherit (cfg.firmware) vpu cs35l41;
            releaseBootImg = cfg.firmware.bootImg;
          };
      firmwarePath = pkgs.liuqinFirmwarePath.override {
        liuqinFirmware = firmwareTree;
      };
    in
    {
      # TODO(touch-drift): with an external display connected the touchscreen is
      # mapped to the wrong output by Mutter and the finger coordinates drift.
      # Measured root cause: the touchscreen is an I2C device with neither USB
      # ids (0000:0000) nor a reported resolution, and the built-in DSI panel
      # reports no vendor/product either, so Mutter's "same vendor/product, same
      # size, built-in panel" heuristics have nothing to match on and it falls
      # back to the wrong logical monitor.  The driver itself is clean: it
      # reports ABS_MT_POSITION in the panel's native portrait frame
      # (0..1799 x 0..2879), verified by reading evdev directly.
      # Two fixes were tried and *reverted* - do not repeat them blindly:
      #   1. gsettings .../touchscreens/0000:0000/ output ['unknown','unknown',
      #      'unknown'] (or the 4-element form with 'DSI-1'): matches no monitor
      #      spec, the touchscreen ends up bound to nothing and goes dead.
      #   2. input_abs_set_res() for the finger device (to let libinput derive a
      #      size): the touch went dead at the evdev level, 0 events; cause
      #      unknown, the change was removed again.
      # See docs/PORTING-NOTES.md ("Touch and input") for the current status and
      # the remaining options (synthetic EDID for the DSI connector, or a
      # Mutter-side mapping).
      # --- Firmware the patched drivers request from userspace --------------
      # nvt_ts probes on the SPI bus very early and request_firmware() must
      # succeed there; the panel/keyboard/GPU/DSP payloads below come from the
      # operator's stock ROM dump (requireFile placeholders until pinned).
      hardware.firmware = [ firmwareTree ];
      hardware.enableRedistributableFirmware = lib.mkDefault true;

      # The touchscreen (nvt_ts) request_firmware() fires during probe, before
      # switch_root, so the firmware tree must be in the initrd too.
      # The initrd's /lib is a read-only symlink to the kernel module store, so
      # placing a second tree below /lib/firmware makes systemd's initrd image
      # builder fail. Use the same writable firmware_class.path that carries
      # the device-specific calibration files after switch-root.
      boot.initrd.systemd.contents."/var/lib/firmware".source =
        "${firmwareTree}/lib/firmware";

      # The firmware loader reads exactly one directory (firmware_class.path;
      # fw_path_para is a single char[256] with no ':') and /lib/firmware does
      # not exist on NixOS, so point it at an overlay of the three trees the
      # board needs: the vendor CS35L41 payloads (they must shadow
      # linux-firmware's same-named files in the system tree), the system
      # firmware tree and the per-device calibration records under
      # /var/lib/firmware.  See pkgs/firmware-path.nix; the unit only warns
      # when the persist data is absent, so a device without calibration still
      # boots.
      systemd.services.liuqin-firmware-path = {
        description = "Firmware union (overlay of vendor, system and calibration trees)";
        wantedBy = [ "sound.target" ];
        before = [ "sound.target" ];
        after = [ "liuqin-persist-provision.service" "local-fs.target" ];
        # A re-provision (e.g. after repairing the persist partition) must be
        # followed by a fresh mount: the overlay reads its lower layers only
        # once, so the union restarts together with the provisioner instead of
        # keeping the previous calibration view.
        partOf = [ "liuqin-persist-provision.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${firmwarePath}/bin/liuqin-firmware-path";
          ExecStop = "-${pkgs.util-linux}/bin/umount /run/firmware";
        };
      };
    }
  );
}
