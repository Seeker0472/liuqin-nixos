# SPDX-License-Identifier: MIT
#
# Storage options and fileSystems generation for liuqin.
#
# The supported layout is the stock 256 GB GPT: NixOS root is the whole
# userdata partition (sda35, geometry 22065152+471789528 4K sectors) with the
# ext4 label LIUQIN_ROOT. The "custom" layout reserves a hook for a future
# root-in-userdata-subpartition setup and currently refuses evaluation.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  options.hardware.liuqin.storage = {
    layout = lib.mkOption {
      type = lib.types.enum [ "whole-userdata" "custom" ];
      default = "whole-userdata";
      description = ''
        Root storage layout. "whole-userdata" uses the entire stock userdata
        partition (sda35) as the NixOS root. "custom" is reserved for a
        root-in-userdata-subpartition layout and is not implemented yet.
      '';
    };

    rootDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-partlabel/userdata";
      description = "Block device holding the NixOS root filesystem.";
    };

    rootLabel = lib.mkOption {
      type = lib.types.str;
      default = "LIUQIN_ROOT";
      description = "ext4 label the initrd storage guard requires before mounting rw.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      fileSystems."/" = {
        device = cfg.storage.rootDevice;
        fsType = "ext4";
        options = [ "noatime" ];
      };

      # Grow the root filesystem to fill userdata on first boot. The flashed
      # rootfsImage is only as large as the NixOS closure; the partition is
      # fixed (the guard enforces its geometry), so only the filesystem
      # needs growing. ConditionPathExists=! marker makes this a one-shot:
      # resize2fs writes the marker via ExecStartPost. sda35 is already rw
      # by this point (the initrd guard unlocked it before sysroot.mount).
      systemd.services.liuqin-growfs-root = {
        description = "Grow the liuqin NixOS root filesystem to fill userdata";
        wantedBy = [ "multi-user.target" ];
        # systemd-tmpfiles-setup.service creates /var/lib/liuqin; the
        # ExecStartPost touch below depends on it, so order after it.
        after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
        unitConfig.ConditionPathExists = "!/var/lib/liuqin/growfs-done";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.e2fsprogs}/bin/resize2fs /dev/sda35";
          ExecStartPost = [ "${pkgs.coreutils}/bin/touch /var/lib/liuqin/growfs-done" ];
        };
      };
      systemd.tmpfiles.rules = [ "d /var/lib/liuqin 0755 root root -" ];
    }

    (lib.mkIf (cfg.storage.layout == "custom") {
      assertions = [{
        assertion = false;
        message = ''
          hardware.liuqin.storage.layout = "custom" (root inside a userdata
          subpartition) is a reserved option and not implemented yet. Use
          "whole-userdata" for now.'';
      }];
    })
  ]);
}
