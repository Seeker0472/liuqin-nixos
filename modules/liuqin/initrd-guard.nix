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

  # The root marker: a real regular file (not an environment.etc symlink).
  # The guard verifies content, ownership, mode and size, mirroring the
  # downstream init's marker contract (regular file, 644 root:root, exact
  # sha256). The content is exposed read-only below so packages.rootfsImage
  # can bake the identical file into the ext4 image at build time — the
  # guard runs BEFORE /sysroot is mounted, so a marker written only by
  # stage-2 tmpfiles can never satisfy a fresh install.
  markerContent = "LIUQIN_NIXOS_ROOT_V1\n";
  markerSha256 = builtins.hashString "sha256" markerContent;
  markerSize = builtins.stringLength markerContent;
  # tmpfiles arguments are single-line: the trailing newline must be the
  # literal two-character escape \n (tmpfiles expands it when writing).
  # Interpolating markerContent verbatim would embed a raw newline and
  # silently truncate the written file to 20 bytes instead of 21.
  markerArgument = lib.replaceStrings [ "\n" ] [ "\\n" ] markerContent;

  # Build-time consistency check: run the exact tmpfiles rule below through
  # systemd-tmpfiles and require a byte-identical result to markerContent,
  # so a rule/marker drift fails the build instead of the initrd guard.
  # A function of a package set so the flake can build a host-arch copy
  # (packages.x86_64-linux.root-marker-check) without cross-compiling.
  mkMarkerCheck = hp: hp.runCommand "liuqin-root-marker-check" { } ''
    mkdir -p root/etc
    rule=$(printf '%s\n' ${lib.escapeShellArg "f+ /etc/liuqin-nixos-root 0644 root root - ${markerArgument}"})
    printf '%s\n' "$rule" > rule.conf
    # Guard against the exact drift this check exists for: the rule argument
    # must carry the literal \n escape, not a raw newline.
    [ "$(wc -l < rule.conf)" = 1 ]
    # The sandbox build user is not root, so the rule's chown to root fails
    # (Operation not permitted — EPERM, exit 73) after the file is already written; only the exit
    # status is tolerated, the content/mode checks below must still pass.
    ${hp.systemd}/bin/systemd-tmpfiles --create --root=$PWD/root \
      $PWD/rule.conf || true
    [ -f root/etc/liuqin-nixos-root ] && [ ! -L root/etc/liuqin-nixos-root ]
    [ "$(stat -c %a root/etc/liuqin-nixos-root)" = 644 ]
    printf '%s' ${lib.escapeShellArg markerContent} > expected
    cmp expected root/etc/liuqin-nixos-root
    touch $out
  '';
  markerCheck = mkMarkerCheck pkgs;

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

    # Controlled escape for the freshly-formatted case: label and geometry
    # check out but the ext4 filesystem is empty (no /nix). That is the
    # state a plain `fastboot format:ext4` leaves behind; it is unrecoverable
    # in the initrd (emergencyAccess is false, no shell), so say exactly how
    # to recover instead of dropping silently into emergency.target.
    probe=$(mktemp -d)
    mount -t ext4 -o ro,noload "$dev" "$probe" || fail "read-only probe mount failed"
    if [ ! -d "$probe/nix" ]; then
      umount "$probe"; rmdir "$probe"
      echo "liuqin-storage-guard: userdata is correctly labelled but EMPTY" >&2
      echo "(freshly formatted, no NixOS rootfs)." >&2
      echo "Recovery: boot the device into fastboot and re-run the installer:" >&2
      echo "  liuqin-install --serial SERIAL --boot boot.img \\" >&2
      echo "    --rootfs rootfs.img --sha256-boot SUM --sha256-rootfs SUM \\" >&2
      echo "    --backup DIR --write-rootfs" >&2
      echo "Re-flashing the rootfs image over fastboot is the ONLY recovery" >&2
      echo "channel; the initrd deliberately provides no shell." >&2
      fail "empty rootfs: re-flash .#rootfsImage (see docs/PORTING-NOTES.md)"
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
    # content baked into the rootfs image at build time (packages.rootfsImage)
    # and repaired by systemd-tmpfiles at boot (see systemd.tmpfiles below).
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
    [ "$marker_ok" = 1 ] || fail "root marker missing or invalid (not a liuqin NixOS root?; re-flash .#rootfsImage to recover)"

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
  options.hardware.liuqin.rootMarkerContent = lib.mkOption {
    type = lib.types.str;
    default = markerContent;
    readOnly = true;
    description = ''
      Exact content (with trailing newline) of /etc/liuqin-nixos-root, the
      identity marker the initrd storage guard requires on the rootfs.
      Read-only: packages.rootfsImage consumes this so the image carries the
      byte-identical marker the guard verifies.
    '';
  };

  options.hardware.liuqin.rootMarkerCheck = lib.mkOption {
    type = lib.types.functionTo lib.types.package;
    default = mkMarkerCheck;
    readOnly = true;
    description = ''
      Function from a package set to a derivation that runs the systemd
      tmpfiles marker rule through systemd-tmpfiles --create --root and
      requires byte-identical output to rootMarkerContent. The flake builds
      it on the host architecture as packages.x86_64-linux.root-marker-check.
    '';
  };

  config = lib.mkIf cfg.enable {
    # The guard hard-codes /dev/sda35 (immutable GPT geometry checks); a
    # different rootDevice would silently bypass it. Fail evaluation instead.
    assertions = [
      {
        assertion = cfg.storage.rootDevice == "/dev/disk/by-partlabel/userdata";
        message = ''
          hardware.liuqin.storage.rootDevice is "${cfg.storage.rootDevice}",
          but the initrd storage guard verifies the immutable identity of
          /dev/sda35 (by-partlabel/userdata) only. Changing the root device
          is unsupported; keep the default.'';
      }
    ];

    # The marker the guard requires. environment.etc would place a symlink
    # into /etc; the guard demands a regular file on the rootfs, so
    # systemd-tmpfiles writes it (f+ also repairs a drifted copy on boot).
    # Fresh installs get the file from the rootfs image itself; tmpfiles is
    # the drift repair, not the initial provisioning.
    systemd.tmpfiles.rules = [
      "f+ /etc/liuqin-nixos-root 0644 root root - ${markerArgument}"
    ];

    # Force the byte-consistency check into the system closure so it is
    # built and verified with every system build (system-path activation
    # script dependency, not a package symlink).
    system.activationScripts.liuqinRootMarkerCheck =
      lib.stringAfter [ ] "true # depends on ${markerCheck}";

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
