# SPDX-License-Identifier: MIT
#
# Initrd storage guard for liuqin: the persistent root is only ever opened
# after the configured root partition passes an identity check (it must be
# the partition its PARTNAME and filesystem label claim), and every other sd*
# node is forced read-only before the root device is opened rw.
#
# Everything about the root device is derived at runtime from
# hardware.liuqin.storage.rootDevice: the partition node, the partlabel name
# matched against the partition's uevent and the parent disk (via sysfs). No
# partition number, start or size is baked in — those differ per capacity
# variant (256 GB vs 512 GB) and per layout.
#
# The guard command itself lives in pkgs/storage-guard.nix
# (writeShellApplication): this module owns the unit, the ordering, the
# identity options and the marker contract, and passes the root device, the
# label and the marker size/sha256 to it as arguments.
#
# This is the declarative equivalent of the downstream 1216-line busybox
# init's storage section: same checks, same fail-closed behavior, expressed
# as systemd initrd units instead of shell control flow. The probe mount is
# read-only (ro,noload); the rw mount happens via sysroot.mount only after
# this unit succeeds (sysroot.mount Requires/After the guard below).
{ config, lib, pkgs, utils, ... }:

let
  cfg = config.hardware.liuqin;

  # hardware.liuqin.storage.rootDevice is a /dev/disk/by-partlabel/<name>
  # path; the guard takes the partition name from its last component at
  # runtime and matches it against the partition's uevent. That only means
  # something for exactly that path shape, so anything else is rejected at
  # evaluation time instead of failing later inside the initrd.
  partName = lib.removePrefix "/dev/disk/by-partlabel/" cfg.storage.rootDevice;
  partNameOk =
    lib.hasPrefix "/dev/disk/by-partlabel/" cfg.storage.rootDevice
    && builtins.match "[^/\n]+" partName != null;
  rootDeviceUnit = "dev-disk-by\\x2dpartlabel-${partName}.device";

  # The root marker: a real regular file (not an environment.etc symlink).
  # The guard verifies content, ownership, mode and size, mirroring the
  # downstream init's marker contract (regular file, 644 root:root, exact
  # sha256).  The bytes live in lib/liuqin-root-marker.nix, shared with the
  # RAM installer that writes the file straight after nixos-install.
  marker = import ../../lib/liuqin-root-marker.nix { inherit lib; };
  markerContent = marker.content;
  markerSha256 = marker.sha256;
  markerSize = marker.size;
  markerArgument = marker.escaped;

in
{
  options.hardware.liuqin.rootMarkerContent = lib.mkOption {
    type = lib.types.str;
    default = markerContent;
    readOnly = true;
      description = ''
        Exact content (with trailing newline) of /etc/liuqin-nixos-root, the
        identity marker the initrd storage guard requires on the rootfs.
        config/installer.nix writes the same bytes after nixos-install, from
        its own literal: the two are independent and must agree, since a
        mismatch makes the guard fail the first boot before tmpfiles can
        repair the file.
      '';
    };

  config = lib.mkIf cfg.enable {
    # The guard resolves /dev/disk/by-partlabel/<name> at runtime, so the
    # root device must have exactly that shape; anything else would derive a
    # bogus partition name and bypass the identity check.
    assertions = [
      {
        assertion = partNameOk;
        message = ''
          hardware.liuqin.storage.rootDevice is "${cfg.storage.rootDevice}",
          but the initrd storage guard derives the partition name and its
          parent disk from a /dev/disk/by-partlabel/<name> path.
          Set it to e.g. "/dev/disk/by-partlabel/userdata".'';
      }
    ];

    # The marker the guard requires is provisioned by activation, not by an
    # installer: nixos-install runs the target's activation inside the target
    # (it calls `switch-to-configuration boot` via nixos-enter), and so does
    # every later nixos-rebuild, so the installed system writes its own marker
    # from the same source the guard checks. environment.etc would place a
    # symlink, which the guard rejects, so the file is written directly; the
    # tmpfiles rule below is then only drift repair.
    system.activationScripts.liuqin-root-marker.text = ''
      printf '${markerArgument}' > /etc/liuqin-nixos-root
      chmod 0644 /etc/liuqin-nixos-root
      chown root:root /etc/liuqin-nixos-root
    '';
    systemd.tmpfiles.rules = [
      "f+ /etc/liuqin-nixos-root 0644 root root - ${markerArgument}"
    ];

    # Never hand out a root shell in the initrd: a guard failure drops to
    # emergency.target, and that must not be a sidestep around the checks.
    boot.initrd.systemd.emergencyAccess = lib.mkDefault false;

    boot.initrd.systemd = {
      enable = true;
      # The initrd systemd image does not infer these paths from the shell
      # text in ExecStart. The guard package and every command it puts on its
      # own PATH (its runtimeInputs) must be copied into the image explicitly.
      storePaths = [
        pkgs.liuqinStorageGuard
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.util-linux
      ];
      extraBin = {
        blockdev = "${pkgs.util-linux}/bin/blockdev";
        findfs = "${pkgs.util-linux}/bin/findfs";
        sha256sum = "${pkgs.coreutils}/bin/sha256sum";
        stat = "${pkgs.coreutils}/bin/stat";
        cut = "${pkgs.coreutils}/bin/cut";
      };
      services.liuqin-storage-guard = {
        description = "liuqin persistent-root identity guard";
        wantedBy = [ "initrd.target" ];
        before = [ "sysroot.mount" "initrd-fs.target" ];
        # The legacy udev-settle unit is not provided by this systemd/NixOS
        # generation. Waiting for the actual by-partlabel device gives the
        # guard the udev ordering it needs without a dangling dependency.
        after = [ rootDeviceUnit ];
        wants = [ rootDeviceUnit ];
        unitConfig = {
          DefaultDependencies = false;
          # A missing UFS partition must become a visible dependency failure,
          # not leave the guard job pending forever behind the .device unit.
          JobTimeoutSec = "30s";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # systemd splits the ExecStart line itself and cannot see the
          # argument boundaries the module has: a space in a configured device
          # path or label would become another argument. Quotes are not enough
          # either - systemd expands $ and % in a word after unquoting it - so
          # every value goes through utils.escapeSystemdExecArg, which quotes
          # and escapes both.
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.liuqinStorageGuard}/bin/liuqin-storage-guard"
            "--root" (utils.escapeSystemdExecArg cfg.storage.rootDevice)
            "--label" (utils.escapeSystemdExecArg cfg.storage.rootLabel)
            "--marker-size" (utils.escapeSystemdExecArg (toString markerSize))
            "--marker-sha256" (utils.escapeSystemdExecArg markerSha256)
          ];
        };
      };

      # Hard ordering: sysroot.mount cannot even be enqueued before the
      # guard succeeds. OnFailure= alone cannot recall an already-queued
      # mount job, so the mount itself Requires/After the guard.
      mounts = [
        {
          what = config.fileSystems."/".device;
          where = "/sysroot";
          type = config.fileSystems."/".fsType;
          options = lib.concatStringsSep ","
            (config.fileSystems."/".options or [ ]);
          requires = [ "liuqin-storage-guard.service" ];
          after = [ "liuqin-storage-guard.service" ];
        }
      ];
    };
  };
}
