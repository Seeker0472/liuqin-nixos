# SPDX-License-Identifier: MIT
#
# liuqin storage guard: the fail-closed identity check that runs in the initrd
# before the persistent root is ever mounted. It verifies that the configured
# root partition is what it claims (by-partlabel path -> sysfs PARTNAME ->
# findfs LABEL), that every sd* node is locked read-only, that the root marker
# is a regular file 644 root:root of exactly the expected size and sha256, and
# only then re-opens that one partition (and its parent disk) read-write.
#
# It is a package rather than embedded shell so the argument handling and the
# first identity check can be exercised at build time against fixtures, with no
# root, no block device and no /dev/sd* involved (see checkPhase).
# modules/liuqin/initrd-guard.nix owns the unit, the ordering and the values:
# it passes the root device, the label and the marker size/sha256 as arguments.
{ lib
, stdenv
, writeShellApplication
, buildPackages
, coreutils
, util-linux
, gnugrep
}:

let
  # writeShellApplication's default checkPhase runs shellcheck, guarded by
  # shellcheck's compiler bootstrap availability (that is also why the minimal
  # build is enough: only the executable is needed). It takes that shellcheck
  # from pkgsBuildHost (pkgs/top-level/stage.nix), i.e. one that runs on this
  # machine even when this package is cross-built; supplying checkPhase
  # replaces the default, so the same choice is repeated here.
  shellcheckStep = lib.optionalString buildPackages.shellcheck-minimal.compiler.bootstrapAvailable ''
    ${lib.getExe buildPackages.shellcheck-minimal} "$target"
  '';

  # Fixture runs: the argument handling and the first identity check,
  # exercised without root, a block device or /dev/sd* - the cases that must
  # fail closed before anything is mounted or written.
  fixtures = ''
    # run_expect STATUS TEXT [ARG ...]: run the guard, require exactly STATUS
    # and TEXT somewhere in its stderr.
    run_expect() {
      expected_status=$1
      expected_text=$2
      shift 2
      status=0
      stderr=$("$target" "$@" 2>&1 >/dev/null) || status=$?
      if [ "$status" -ne "$expected_status" ]; then
        echo "FAIL: '$target $*' exited $status, expected $expected_status" >&2
        echo "--- stderr ---" >&2
        echo "$stderr" >&2
        exit 1
      fi
      case $stderr in
        *"$expected_text"*) ;;
        *)
          echo "FAIL: '$target $*' stderr does not mention '$expected_text'" >&2
          echo "--- stderr ---" >&2
          echo "$stderr" >&2
          exit 1
          ;;
      esac
      echo "ok: '$target $*' -> $status, stderr mentions '$expected_text'"
    }

    # No arguments at all, a missing value and an unknown option are all usage
    # errors: a guard that silently ran with an empty root would check nothing.
    run_expect 2 "usage:"
    run_expect 2 "usage:" --root
    run_expect 2 "usage:" --root /dev/null --bogus

    # A nonexistent path, a directory and a character device must not get past
    # the first identity check, and must say so.
    run_expect 1 "block device" --root /nonexistent/liuqin --label X --marker-size 1 --marker-sha256 0
    run_expect 1 "block device" --root . --label X --marker-size 1 --marker-sha256 0
    run_expect 1 "block device" --root /dev/null --label X --marker-size 1 --marker-sha256 0
  '';

  # The runs execute the built script, which only works where this machine can
  # run target-platform binaries: every configuration in this repository builds
  # this package natively (pkgs/device-packages.nix). The skip keeps the
  # x86_64 -> aarch64 fallback (mkLiuqinSystem { crossBuild = true; }), where
  # the script and its runtimeInputs are aarch64 binaries, buildable.
  fixtureRuns =
    if stdenv.buildPlatform.canExecute stdenv.hostPlatform
    then fixtures
    else ''
      echo "skipping the fixture runs: ${stdenv.buildPlatform.system} cannot execute ${stdenv.hostPlatform.system} binaries"
    '';
in
writeShellApplication {
  name = "liuqin-storage-guard";

  runtimeInputs = [ coreutils util-linux gnugrep ];

  # The initrd PATH is the runtime inputs and nothing else: an unlisted tool
  # must not be reachable, so the guard cannot depend on whatever the image
  # happens to inherit.
  inheritPath = false;

  text = ''
    # Everything about the root device arrives as an argument: the module
    # owns the device/label (hardware.liuqin.storage) and the marker contract
    # (lib/liuqin-root-marker.nix). A missing value is a usage error, never a
    # default that silently checks the wrong thing.
    root=
    label=
    marker_size=
    marker_sha256=

    usage() {
      cat >&2 <<'EOF'
    usage: liuqin-storage-guard --root PATH --label LABEL --marker-size N --marker-sha256 HEX

      --root          root partition device (/dev/disk/by-partlabel/<name>)
      --label         filesystem label the root partition must carry
      --marker-size   exact size in bytes of the root identity marker
      --marker-sha256 exact sha256 (hex) of the root identity marker
    EOF
      exit 2
    }

    while [ "$#" -gt 0 ]; do
      case $1 in
        --root | --label | --marker-size | --marker-sha256)
          if [ "$#" -lt 2 ]; then
            usage
          fi
          case $1 in
            --root) root=$2 ;;
            --label) label=$2 ;;
            --marker-size) marker_size=$2 ;;
            --marker-sha256) marker_sha256=$2 ;;
          esac
          shift 2
          ;;
        *)
          usage
          ;;
      esac
    done

    [ -n "$root" ] || usage
    [ -n "$label" ] || usage
    [ -n "$marker_size" ] || usage
    [ -n "$marker_sha256" ] || usage

    # The configured root device; the partition node, its partlabel name and
    # its parent disk are all derived from it below.
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

    [ -b "$dev" ] || fail "root device $root is absent or not a block device"
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
    label_path=$(findfs LABEL="$label" 2>/dev/null || true)
    [ -n "$label_path" ] || fail "label $label not found"
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
    # (see systemd.tmpfiles in modules/liuqin/initrd-guard.nix).
    marker=$probe/etc/liuqin-nixos-root
    marker_ok=0
    if [ -f "$marker" ] && [ ! -L "$marker" ]; then
      meta=$(stat -c '%a %u %g %s' "$marker" 2>/dev/null || true)
      sum=$(sha256sum "$marker" | cut -d' ' -f1)
      if [ "$meta" = "644 0 0 $marker_size" ] && [ "$sum" = "$marker_sha256" ]; then
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
    for node in "/dev/$(basename "$parent")"[0-9]*; do
      [ -b "$node" ] || continue
      [ "$node" = "$dev" ] && continue
      blockdev --setro "$node"
      [ "$(blockdev --getro "$node")" = 1 ] || fail "read-only reassert failed on $node"
    done

    echo "liuqin-storage-guard: $dev ($part) identity verified; only $dev is writable"
  '';

  # The fixture runs are the point of packaging this: they exercise the real
  # argument parsing and the first identity check with no root, no block
  # device and no /dev/sd* - the cases that must fail closed before anything
  # is mounted or written (the text is in `fixtures` above; `fixtureRuns` skips
  # it only where the target binaries cannot run). Supplying checkPhase
  # replaces writeShellApplication's default one, so its two steps are repeated
  # explicitly: `bash -n` (what shellDryRun runs) and shellcheck, which every
  # other writeShellApplication package in this tree also gets.
  checkPhase = ''
    runHook preCheck

    bash -n "$target"

    ${shellcheckStep}

    ${fixtureRuns}

    runHook postCheck
  '';

  meta = {
    mainProgram = "liuqin-storage-guard";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
