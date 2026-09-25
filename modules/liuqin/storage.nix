# SPDX-License-Identifier: MIT
#
# Storage options and fileSystems generation for liuqin.
#
# A layout is identified by the GPT partition *label* that holds the NixOS
# root, never by a device node or a sector geometry: the root is mounted
# through /dev/disk/by-partlabel/<name>, and the initrd guard resolves the
# partition, its identity and its parent disk from that path at runtime.
#
#   whole-userdata   NixOS root is the whole stock userdata partition. Android
#                    and NixOS then cannot both keep /data.
#   linux-partition  NixOS root is a dedicated `linux` partition carved out of
#                    the tail of userdata by an operator-reviewed partitioning
#                    step before the filesystem is mounted. Android keeps its
#                    own userdata, so both systems boot and store data
#                    independently - this is the layout the dual-boot flow
#                    (U-Boot on boot_b, Android on boot_a) is built around.
#
# Partition numbers, start and size are capacity-specific (the stock 256 GB
# and 512 GB GPTs differ; this repository was originally written against a
# 256 GB unit, while the unit it is developed against is the 512 GB one: its
# main LUN is 473.83 GiB with userdata at 463.31 GiB) and must be measured on
# the device, so no geometry constant appears here.
#
# There is no creation recipe yet, and it is the one step between this tree and
# a first boot: the 2026-09-20 stock dump's MANIFEST has no `linux` partition,
# and Android's userdata is f2fs, which cannot be shrunk in place - see the
# installation section of README.md for what that implies.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;
in
{
  options.hardware.liuqin.storage = {
    layout = lib.mkOption {
      type = lib.types.enum [ "whole-userdata" "linux-partition" ];
      default = "whole-userdata";
      description = ''
        Root storage layout. "whole-userdata" uses the entire stock userdata
        partition as the NixOS root; "linux-partition" uses the dedicated
        `linux` partition carved out of userdata's tail after live geometry
        measurement and a GPT backup. The installer does not create or format
        either layout automatically.
      '';
    };

    rootDevice = lib.mkOption {
      type = lib.types.str;
      description = ''
        Block device holding the NixOS root filesystem. Defaults to the
        by-partlabel path of the partition the layout selects (userdata for
        "whole-userdata", linux for "linux-partition"); the initrd storage guard
        derives the partition, its partlabel and its parent disk from it.
      '';
    };

    rootLabel = lib.mkOption {
      type = lib.types.str;
      default = "LIUQIN_ROOT";
      description = "ext4 label the initrd storage guard requires before mounting rw.";
    };
  };

  config = lib.mkMerge [
    # The default root device depends on the layout, which an option default
    # cannot see, so it is set here; mkDefault keeps it overridable (e.g. for
    # a differently named partition). Defined outside the enable gate because
    # the option itself is declared unconditionally.
    {
      hardware.liuqin.storage.rootDevice = lib.mkDefault (
        if cfg.storage.layout == "whole-userdata"
        then "/dev/disk/by-partlabel/userdata"
        else "/dev/disk/by-partlabel/linux"
      );
    }

    (lib.mkIf cfg.enable {
      fileSystems."/" = {
        device = cfg.storage.rootDevice;
        fsType = "ext4";
        options = [ "noatime" ];
      };

      # Grow the filesystem to fill its partition on first boot. The operator
      # formats the target before nixos-install, so only the filesystem needs
      # growing; GPT geometry remains operator-selected.
      systemd.services.liuqin-growfs-root = {
        description = "Grow the liuqin NixOS root filesystem to fill its partition";
        wantedBy = [ "multi-user.target" ];
        # systemd-tmpfiles-setup.service creates /var/lib/liuqin; the
        # ExecStartPost touch below depends on it, so order after it.
        after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
        unitConfig.ConditionPathExists = "!/var/lib/liuqin/growfs-done-${cfg.storage.layout}";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.e2fsprogs}/bin/resize2fs ${cfg.storage.rootDevice}";
          ExecStartPost = [ "${pkgs.coreutils}/bin/touch /var/lib/liuqin/growfs-done-${cfg.storage.layout}" ];
        };
      };
      systemd.tmpfiles.rules = [ "d /var/lib/liuqin 0755 root root -" ];
    })
  ];
}
