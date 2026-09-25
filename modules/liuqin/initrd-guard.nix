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
# TODO: the guard below is roughly 150 lines of embedded shell.  Move it into
# pkgs/ and use writeShellApplication with runtimeInputs, following the
# pkgs/liuqin-power-keyd/ pattern.  Not urgent: this is the safety net
# that keeps the wrong partition from being opened writable, so it wants the
# same care as the rest of the storage path rather than a hurried rewrite.
#
# This is the declarative equivalent of the downstream 1216-line busybox
# init's storage section: same checks, same fail-closed behavior, expressed
# as systemd initrd units instead of shell control flow. The probe mount is
# read-only (ro,noload); the rw mount happens via sysroot.mount only after
# this unit succeeds (sysroot.mount Requires/After the guard below).
{ config, lib, pkgs, ... }:

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

  guardScript = pkgs.writeShellScript "liuqin-storage-guard" ''
    set -eu

    export PATH=${lib.makeBinPath (with pkgs; [
      coreutils
      util-linux
      gnugrep
    ])}

    # The configured root device; the partition node, its partlabel name and
    # its parent disk are all derived from it below.
    root=${cfg.storage.rootDevice}
    part=$(basename "$root")
    dev=$(readlink -f "$root" 2>/dev/null || true)

    fail() {
      echo "liuqin-storage-guard: $*" >&2
      # Never leave anything writable on failure.
      for node in /dev/sd[a-z] /dev/sd*[0-9]*; do
        [ -b "$node" ] && blockdev --setro "$node" 2>/dev/null || true
      done
      exit 1
    }

    [ -b "$dev" ] || fail "root device $root is absent"
    [ "$(readlink -f "$dev")" = "$dev" ] || fail "$dev is a symlink"

    # sysfs identity: /sys/class/block/<node> resolves to the kernel
    # directory <...>/block/<disk>/<node>, whose parent names the disk and
    # whose 'partition' attribute exists only for a partition. Geometry is
    # deliberately not checked: partition numbers, start and size differ per
    # capacity variant and per layout.
    sys=$(readlink -f "/sys/class/block/$(basename "$dev")" 2>/dev/null || true)
    [ -n "$sys" ] || fail "no sysfs entry for $dev"
    [ -e "$sys/partition" ] || fail "$dev is not a partition"
    parent=/dev/$(basename "$(dirname "$sys")")
    [ -b "$parent" ] || fail "parent disk of $dev ($parent) is absent"
    [ "$(readlink -f "$parent")" = "$parent" ] || fail "$parent is a symlink"

    grep -qxF "PARTNAME=$part" "$sys/uevent" || fail "$dev PARTNAME is not $part"

    # The label must resolve to exactly this partition.
    label_path=$(findfs LABEL=${cfg.storage.rootLabel} 2>/dev/null || true)
    [ -n "$label_path" ] || fail "label ${cfg.storage.rootLabel} not found"
    [ "$(readlink -f "$label_path")" = "$dev" ] || fail "label resolves elsewhere"

    # Controlled escape for the freshly-formatted case: the label checks out
    # but the ext4 filesystem is empty (no /nix). That is the state a plain
    # `fastboot format:ext4` leaves behind; it is unrecoverable
    # in the initrd (emergencyAccess is false, no shell), so say exactly how
    # to recover instead of dropping silently into emergency.target.
    probe=$(mktemp -d)
    mount -t ext4 -o ro,noload "$dev" "$probe" || fail "read-only probe mount failed"
    if [ ! -d "$probe/nix" ]; then
      umount "$probe"; rmdir "$probe"
      echo "liuqin-storage-guard: $part is correctly labelled but EMPTY" >&2
      echo "(freshly formatted, no NixOS rootfs)." >&2
      echo "Recovery: boot the RAM installer image again, mount the target at /mnt," >&2
      echo "and run nixos-install --root /mnt --no-channel-copy after checking the" >&2
      echo "filesystem (README.md, Installation model)." >&2
      fail "empty rootfs: reinstall from the liuqin RAM installer"
    fi

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
    # activation-provisioned marker and repaired by systemd-tmpfiles at boot
    # (see systemd.tmpfiles below).
    marker=$probe/etc/liuqin-nixos-root
    marker_ok=0
    if [ -f "$marker" ] && [ ! -L "$marker" ]; then
      meta=$(stat -c '%a %u %g %s' "$marker" 2>/dev/null || true)
      sum=$(sha256sum "$marker" | cut -d' ' -f1)
      if [ "$meta" = "644 0 0 ${toString markerSize}" ] && [ "$sum" = "${markerSha256}" ]; then
        marker_ok=1
      else
        echo "liuqin-storage-guard: marker meta '$meta' sha256 '$sum' rejected" >&2
      fi
    fi
    umount "$probe"
    rmdir "$probe"
    [ "$marker_ok" = 1 ] || fail "root marker missing or invalid (reinstall from the RAM installer)"

    # Unlock the parent disk first: a partition cannot be opened rw while
    # its parent disk is read-only (downstream init:674-682 opens
    # parent, then target, in that order).
    blockdev --setrw "$parent"
    [ "$(blockdev --getro "$parent")" = 0 ] || fail "could not re-enable rw on $parent"
    blockdev --setrw "$dev"
    [ "$(blockdev --getro "$dev")" = 0 ] || fail "could not re-enable rw on $dev"

    # Reassert read-only on every sibling partition after the unlock: the
    # parent disk rw must not widen any other partition's window.
    for node in /dev/$(basename "$parent")[0-9]*; do
      [ -b "$node" ] || continue
      [ "$node" = "$dev" ] && continue
      blockdev --setro "$node"
      [ "$(blockdev --getro "$node")" = 1 ] || fail "read-only reassert failed on $node"
    done

    echo "liuqin-storage-guard: $dev ($part) identity verified; only $dev is writable"
  '';
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
      # text in ExecStart. The guard and all commands in its PATH must be
      # copied into the image explicitly.
      storePaths = [
        guardScript
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
