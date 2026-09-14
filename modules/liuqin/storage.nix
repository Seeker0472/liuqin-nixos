# SPDX-License-Identifier: MIT
#
# Storage options and fileSystems generation for liuqin.
#
# The supported layout is the stock 256 GB GPT: NixOS root is the whole
# userdata partition (sda35, geometry 22065152+471789528 4K sectors) with the
# ext4 label LIUQIN_ROOT. The "custom" layout reserves a hook for a future
# root-in-userdata-subpartition setup and currently refuses evaluation.
{ config, lib, ... }:

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
