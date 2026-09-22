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
#                    the tail of userdata by the explicit `sgdisk` operation
#                    in the read-only-by-default live bring-up image
#                    (liuqin-nixos/README.md). Android keeps its own userdata,
#                    so both systems boot and store data independently - this
#                    is the layout the dual-boot flow (U-Boot on boot_b,
#                    Android on boot_a) is built around.
#
# Partition numbers, start and size are capacity-specific (the stock 256 GB
# and 512 GB GPTs differ; this repository was originally written against a
# 256 GB unit) and must be measured on the device
# (liuqin-dualboot/docs/TESTING.md phase 5), so no geometry constant appears
# here.
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
        `linux` partition carved out of userdata's tail with the explicit
        `sgdisk` operation in the live bring-up image after live geometry
        measurement and GPT backup.
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

      # Grow the root filesystem to fill its partition on first boot. The
      # flashed rootfsImage is only as large as the NixOS closure; the
      # partition itself is fixed by the GPT, so only the filesystem needs
      # growing. The one-shot marker is per layout, so switching layouts
      # grows the new root exactly once: ConditionPathExists=! makes resize2fs
      # a one-shot and ExecStartPost writes the marker. The configured root
      # device is already rw by this point (the initrd guard unlocked it
      # before sysroot.mount).
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
