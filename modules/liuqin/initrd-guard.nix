# SPDX-License-Identifier: MIT
#
# Initrd storage guard for liuqin: the persistent root is only ever opened
# after the userdata partition passes an immutable identity check (GPT
# geometry, PARTNAME, filesystem label), and every other sd* node is forced
# read-only before the root device is opened rw.
#
# This is the declarative equivalent of the downstream 1216-line busybox
# init's storage section: same checks, same fail-closed behavior, expressed
# as systemd initrd units instead of shell control flow. The probe mount is
# read-only (ro,noload); the rw mount happens via sysroot.mount only after
# this unit succeeds (sysroot.mount Requires/After the guard below).
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;

  # The root marker: a real regular file (not an environment.etc symlink)
  # written onto the rootfs by systemd-tmpfiles at boot. The guard verifies
  # content, ownership, mode and size, mirroring the downstream init's
  # marker contract (regular file, 644 root:root, exact sha256).
  markerContent = "LIUQIN_NIXOS_ROOT_V1\n";
  markerSha256 = builtins.hashString "sha256" markerContent;

  guardScript = pkgs.writeShellScript "liuqin-storage-guard" ''
    set -eu

    export PATH=${lib.makeBinPath (with pkgs; [
      coreutils
      util-linux
      gnugrep
    ])}

    dev=/dev/sda35
    parent=/dev/sda
    sys=/sys/block/sda

    fail() {
      echo "liuqin-storage-guard: $*" >&2
      # Never leave anything writable on failure.
      for node in /dev/sd[a-z] /dev/sd*[0-9]*; do
        [ -b "$node" ] && blockdev --setro "$node" 2>/dev/null || true
      done
      exit 1
    }

    [ -b "$parent" ] || fail "sda is absent"
    [ -b "$dev" ] || fail "sda35 is absent"
    [ "$(readlink -f "$parent")" = "$parent" ] || fail "sda is a symlink"
    [ "$(readlink -f "$dev")" = "$dev" ] || fail "sda35 is a symlink"

    # Immutable GPT geometry of the stock 256 GB layout.
    [ "$(cat "$sys/size")" = 493854720 ] || fail "sda size"
    [ "$(cat "$sys/queue/logical_block_size")" = 4096 ] || fail "sda logical block size"
    [ "$(cat "$sys/sda35/partition")" = 35 ] || fail "sda35 partition number"
    [ "$(cat "$sys/sda35/start")" = 22065152 ] || fail "sda35 start"
    [ "$(cat "$sys/sda35/size")" = 471789528 ] || fail "sda35 size"
    grep -qx 'PARTNAME=userdata' "$sys/sda35/uevent" || fail "sda35 PARTNAME"

    # The label must resolve to exactly this partition.
    label_path=$(findfs LABEL=${cfg.storage.rootLabel} 2>/dev/null || true)
    [ -n "$label_path" ] || fail "label ${cfg.storage.rootLabel} not found"
    [ "$(readlink -f "$label_path")" = "$dev" ] || fail "label resolves elsewhere"

    # Lock every sd* node read-only, then verify the lock took. An empty
    # glob is a failure, not proof of safety.
    seen=0
    for node in /dev/sd[a-z] /dev/sd*[0-9]*; do
      [ -b "$node" ] || continue
      seen=1
      blockdev --setro "$node"
    done
    [ "$seen" = 1 ] || fail "no sd* nodes to lock"
    for node in /dev/sd[a-z] /dev/sd*[0-9]*; do
      [ -b "$node" ] || continue
      [ "$(blockdev --getro "$node")" = 1 ] || fail "read-only lock did not hold on $node"
    done

    # Probe-mount the root read-only and require the root marker to be a
    # regular file owned 644 root:root whose sha256 matches exactly the
    # content this system writes (see systemd.tmpfiles below).
    probe=$(mktemp -d)
    mount -t ext4 -o ro,noload "$dev" "$probe" || fail "read-only probe mount failed"
    marker=$probe/etc/liuqin-nixos-root
    marker_ok=0
    if [ -f "$marker" ] && [ ! -L "$marker" ]; then
      meta=$(stat -c '%a %u %g %s' "$marker" 2>/dev/null || true)
      sum=$(sha256sum "$marker" | cut -d' ' -f1)
      if [ "$meta" = "644 0 0 21" ] && [ "$sum" = "${markerSha256}" ]; then
        marker_ok=1
      else
        echo "liuqin-storage-guard: marker meta '$meta' sha256 '$sum' rejected" >&2
      fi
    fi
    umount "$probe"
    rmdir "$probe"
    [ "$marker_ok" = 1 ] || fail "root marker missing or invalid (not a liuqin NixOS root?)"

    # Unlock the parent disk first: a partition cannot be opened rw while
    # its parent disk is read-only (downstream init:674-682 opens
    # parent, then target, in that order).
    blockdev --setrw "$parent"
    [ "$(blockdev --getro "$parent")" = 0 ] || fail "could not re-enable rw on sda"
    blockdev --setrw "$dev"
    [ "$(blockdev --getro "$dev")" = 0 ] || fail "could not re-enable rw on sda35"

    # Reassert read-only on every sibling partition after the unlock: the
    # parent disk rw must not widen any other partition's window.
    for node in /dev/sda[0-9]*; do
      [ -b "$node" ] || continue
      [ "$node" = "$dev" ] && continue
      blockdev --setro "$node"
      [ "$(blockdev --getro "$node")" = 1 ] || fail "read-only reassert failed on $node"
    done

    echo "liuqin-storage-guard: sda35 identity verified; only sda35 is writable"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # The marker the guard requires. environment.etc would place a symlink
    # into /etc; the guard demands a regular file on the rootfs, so
    # systemd-tmpfiles writes it (f+ also repairs a drifted copy on boot).
    # 0444 would be equally acceptable, but 0644 matches the downstream
    # marker metadata contract byte for byte.
    systemd.tmpfiles.rules = [
      "f+ /etc/liuqin-nixos-root 0644 root root - ${markerContent}"
    ];

    # Never hand out a root shell in the initrd: a guard failure drops to
    # emergency.target, and that must not be a sidestep around the checks.
    boot.initrd.systemd.emergencyAccess = lib.mkDefault false;

    boot.initrd.systemd = {
      enable = true;
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
        after = [ "systemd-udev-settle.service" ];
        wants = [ "systemd-udev-settle.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = guardScript;
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
