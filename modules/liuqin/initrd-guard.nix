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
# this unit succeeds.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin;

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

    # Probe-mount the root read-only and require the root marker the NixOS
    # activation wrote, before anything is allowed rw.
    probe=$(mktemp -d)
    mount -t ext4 -o ro,noload "$dev" "$probe" || fail "read-only probe mount failed"
    marker_ok=0
    [ -f "$probe/etc/liuqin-nixos-root" ] && [ ! -L "$probe/etc/liuqin-nixos-root" ] \
      && marker_ok=1
    umount "$probe"
    rmdir "$probe"
    [ "$marker_ok" = 1 ] || fail "root marker missing (not a liuqin NixOS root?)"

    # Unlock only the root device. Everything else stays read-only.
    blockdev --setrw "$dev"
    [ "$(blockdev --getro "$dev")" = 0 ] || fail "could not re-enable rw on sda35"

    echo "liuqin-storage-guard: sda35 identity verified; only sda35 is writable"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # The marker the guard requires. Written by activation, owned 0444 root.
    environment.etc."liuqin-nixos-root" = {
      text = "LIUQIN_NIXOS_ROOT_V1\n";
      mode = "0444";
    };

    boot.initrd.systemd = {
      enable = true;
      extraBin = {
        blockdev = "${pkgs.util-linux}/bin/blockdev";
        findfs = "${pkgs.util-linux}/bin/findfs";
      };
      services.liuqin-storage-guard = {
        description = "liuqin persistent-root identity guard";
        # sysroot.mount is generated from fileSystems."/"; requiring the
        # guard from initrd.target plus Before/Requires via unitConfig makes
        # a guard failure a hard boot failure before /sysroot is mounted.
        wantedBy = [ "initrd.target" ];
        before = [ "sysroot.mount" "initrd-fs.target" ];
        after = [ "systemd-udev-settle.service" ];
        wants = [ "systemd-udev-settle.service" ];
        unitConfig = {
          DefaultDependencies = false;
          OnFailure = "emergency.target";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = guardScript;
        };
      };
    };
  };
}
