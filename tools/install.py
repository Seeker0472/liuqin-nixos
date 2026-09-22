#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Install a NixOS rootfs (and, for the ABL path, a boot.img) from fastboot.

Two targets, matching hardware.liuqin.boot.loader:

  --target linux     Flashes the ext4 rootfs image to the `linux` partition.
                     With boot.loader = "uboot" that image also carries
                     /boot/{Image,initrd.img,liuqin.dtb}, so it is the only
                     artifact the device needs. Boot slots, userdata and
                     persist are never touched and no slot is activated.

  --target userdata  The ABL path: flashes --boot to boot_a and the rootfs to
                     the whole userdata partition. Destructive to Android's
                     /data and requires hardware.liuqin.storage.layout =
                     "whole-userdata".

Host-side installer running over fastboot (device: Xiaomi Pad 6 Pro, liuqin). The device-identity checks kept
from the downstream installer are exactly:

  * fastboot product must be "liuqin"
  * the bootloader must be unlocked
  * --target userdata additionally requires slot A to be active and never
    switches slots; --target linux ignores the A/B state (the `linux`
    partition is independent of it, and U-Boot on boot_b is what loads it)
  * the required --serial must be given and is bound to every fastboot call
  * the target partition size is measured on the unit with fastboot
    (`getvar partition-size:<target>`); it is capacity-specific (128/256/512
    GB variants exist) and is never assumed. A missing `linux` partition is
    a hard stop: carving it is an explicit, measured `sgdisk` operation in the
    live bring-up image, not the installer
  * --target userdata: boot.img must carry the ANDROID! magic and fit the
    reported boot_a partition
  * the rootfs image must fit the target partition, be an ext4 image, and
    carry the LIUQIN_ROOT volume label (superblock offset 0x478)
  * the sha256 of --boot and --rootfs is verified before anything is sent

--rootfs is a pre-built ext4 image (flake output .#rootfsImage, or
.#demo-rootfsImage for the U-Boot layout), or its Android sparse form
(.#rootfsImageSparse / .#demo-rootfsImageSparse). It is flashed verbatim with
`fastboot flash <target>`; sparse images are materialized temporarily only for
validation. Unlike the downstream RAM-installer
flow there is no tarball and no on-device untar: the image already carries
the /etc/liuqin-nixos-root marker the initrd storage guard requires before
it will mount the root read-write.

Backups (--target userdata only) of boot_a/boot_b/persist use `fastboot
fetch` when the device's bootloader supports it; otherwise the installer
stops with a clear error instead of writing anything. --target linux writes
the `linux` partition and nothing else, so it takes no backup.

Usage:
  # dual-boot layout: the rootfs image carries /boot for U-Boot
  liuqin-install --serial SERIAL --target linux --rootfs demo-rootfs.img \
      --sha256-rootfs SUM [--write-rootfs]

  # ABL layout: boot.img plus a rootfs over the whole userdata partition
  liuqin-install --serial SERIAL --boot boot.img --rootfs rootfs.img \
      --sha256-boot SUM --sha256-rootfs SUM --backup DIR [--write-rootfs]
"""
import argparse
import hashlib
import re
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BOOT_A_LIMIT = 192 * 1024 * 1024  # 0x0c000000
ANDROID_MAGIC_OFFSET = 0
ANDROID_MAGIC = b"ANDROID!"
EXT4_MAGIC_OFFSET = 0x438
EXT4_MAGIC = b"\x53\xef"
# ext4 superblock: s_volume_name, 16 bytes, NUL-terminated.
EXT4_LABEL_OFFSET = 0x478
EXT4_LABEL_LEN = 16
ROOTFS_LABEL = b"LIUQIN_ROOT"
SPARSE_MAGIC = b"\x3a\xff\x26\xed"
# This ABL occasionally drops back-to-back getvar replies.  The board logs
# require single probes separated by at least one second; keep the installer
# on that conservative cadence during all identity and geometry checks.
GETVAR_INTERVAL = 1.1


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def is_android_boot_image(path: Path) -> bool:
    with path.open("rb") as stream:
        return stream.read(len(ANDROID_MAGIC)) == ANDROID_MAGIC


def is_ext4_image(path: Path) -> bool:
    with path.open("rb") as stream:
        stream.seek(EXT4_MAGIC_OFFSET)
        return stream.read(2) == EXT4_MAGIC


def is_sparse_image(path: Path) -> bool:
    with path.open("rb") as stream:
        return stream.read(4) == SPARSE_MAGIC


def sparse_image_size(path: Path) -> int:
    """Return the logical byte size encoded by an Android sparse image."""
    with path.open("rb") as stream:
        header = stream.read(28)
    if len(header) != 28:
        raise ValueError("truncated Android sparse header")
    (magic, major, _minor, file_hdr, chunk_hdr, block_size, blocks,
     _chunks, _crc) = struct.unpack("<I4H4I", header)
    valid_header = all((
        magic == 0xED26FF3A, major == 1, file_hdr >= 28,
        chunk_hdr >= 12, block_size != 0,
    ))
    if not valid_header:
        raise ValueError("invalid Android sparse header")
    return blocks * block_size


def ext4_label(path: Path) -> bytes:
    with path.open("rb") as stream:
        stream.seek(EXT4_LABEL_OFFSET)
        return stream.read(EXT4_LABEL_LEN).split(b"\0", 1)[0]


def fastboot(serial, *arguments, timeout=180):
    cmd = ["fastboot"]
    if serial:
        cmd += ["-s", serial]
    cmd += list(arguments)
    result = subprocess.run(
        cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=timeout)
    return result.stdout


def getvar(serial, name):
    time.sleep(GETVAR_INTERVAL)
    return fastboot(serial, "getvar", name)


def require_var(serial, name, pattern):
    if not re.search(r"\b" + name + r":\s*" + pattern + r"\b",
                     getvar(serial, name)):
        raise RuntimeError(f"fastboot device check failed: {name}")


def require_abl_fastboot(serial):
    """Reject the board-side U-Boot fastboot endpoint for image writes."""
    output = getvar(serial, "build")
    # Current U-Boot deliberately exposes build=<diagnostic tag>; stock ABL
    # reports this variable as unknown. A future ABL may grow the variable,
    # so an affirmative value is treated conservatively as the wrong endpoint.
    if re.search(r"\bbuild:\s*(?!FAILED|Variable not found|not found)[^\s]", output,
                 re.IGNORECASE):
        raise RuntimeError(
            "installer is connected to U-Boot fastboot; return to stock ABL "
            "fastboot before flashing a rootfs")


def partition_size(serial, name):
    pattern = (rf"partition-size:{re.escape(name)}:"
               r"\s*(0x[0-9a-fA-F]+|[0-9]+)")
    match = re.search(pattern, getvar(serial, "partition-size:" + name))
    if not match:
        raise RuntimeError(f"cannot determine partition size: {name}")
    value = match.group(1)
    return int(value, 16 if value.lower().startswith("0x") else 10)


def max_download_size(serial):
    """Return the raw fastboot DATA payload limit reported by the target."""
    output = getvar(serial, "max-download-size")
    match = re.search(r"max-download-size:\s*(0x[0-9a-fA-F]+|[0-9]+)", output)
    if not match:
        raise RuntimeError("cannot determine fastboot max-download-size")
    value = match.group(1)
    return int(value, 16 if value.lower().startswith("0x") else 10)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target", choices=("linux", "userdata"), default="linux",
        help="partition to install the rootfs on: 'userdata' is the "
             "whole-userdata ABL layout, 'linux' is the dual-boot layout")
    parser.add_argument("--boot", type=Path,
                        help="boot.img to flash to boot_a (--target userdata only)")
    parser.add_argument("--rootfs", type=Path, required=True,
                        help="pre-built ext4 rootfs image (flake output "
                             ".#rootfsImage or .#demo-rootfsImage), flashed "
                             "verbatim to the target partition")
    parser.add_argument("--serial", required=True,
                        help="fastboot serial of the target device")
    parser.add_argument("--backup", type=Path,
                        help="new directory receiving boot_a/boot_b/persist "
                             "dumps (--target userdata only)")
    parser.add_argument("--write-rootfs", action="store_true",
                        help="actually write the rootfs (destructive to the "
                             "target partition)")
    parser.add_argument("--sha256-boot",
                        help="expected sha256 of --boot; verified before flashing")
    parser.add_argument("--sha256-rootfs", required=True,
                        help="expected sha256 of --rootfs; verified before flashing")
    args = parser.parse_args()

    if not args.rootfs.is_file():
        parser.error(f"missing input: {args.rootfs}")
    if args.target == "linux":
        if args.boot is not None or args.sha256_boot is not None:
            parser.error("--target linux installs the rootfs only; --boot and "
                         "--sha256-boot belong to --target userdata (the "
                         "U-Boot path reads /boot from the rootfs itself)")
        if args.backup is not None:
            parser.error("--target linux overwrites nothing but the `linux` "
                         "partition; there is no boot/persist state to dump")
    else:
        if args.boot is None or args.sha256_boot is None:
            parser.error("--target userdata needs --boot and --sha256-boot")
        if args.backup is None:
            parser.error("--target userdata needs --backup")
        if not args.boot.is_file():
            parser.error(f"missing input: {args.boot}")
        if args.backup.exists():
            parser.error("--backup must be a new directory")
        if args.boot.stat().st_size > BOOT_A_LIMIT:
            parser.error("boot.img exceeds the 192 MiB boot partition")
        if not is_android_boot_image(args.boot):
            parser.error("--boot lacks the ANDROID! magic; not a boot.img "
                         "(build it with `nix build .#bootimg-nixos`)")
        if sha256(args.boot) != args.sha256_boot:
            parser.error("boot.img checksum mismatch")
    if sha256(args.rootfs) != args.sha256_rootfs:
        parser.error("rootfs checksum mismatch")
    # Fastboot can resparse a sparse ext4 image into DATA-sized chunks. Keep
    # the supplied file for flashing, but materialize a temporary raw view for
    # the filesystem and label checks below. Raw images remain supported too.
    rootfs_check = args.rootfs
    sparse_tmp = None
    rootfs_sparse = is_sparse_image(args.rootfs)
    rootfs_bytes = args.rootfs.stat().st_size
    if rootfs_sparse:
        try:
            rootfs_bytes = sparse_image_size(args.rootfs)
        except ValueError as error:
            parser.error(f"invalid sparse rootfs: {error}")
        sparse_tmp = tempfile.TemporaryDirectory(prefix="liuqin-simg-")
        rootfs_check = Path(sparse_tmp.name) / "rootfs.ext4"
        try:
            subprocess.run(
                ["simg2img", str(args.rootfs), str(rootfs_check)],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True)
        except (OSError, subprocess.SubprocessError) as error:
            parser.error("sparse rootfs requires simg2img from android-tools: "
                         f"{error}")
    if not is_ext4_image(rootfs_check):
        parser.error("--rootfs is not an ext4 image; build it with "
                     "`nix build .#rootfsImage` (no tarballs: there is no "
                     "on-device untar step in the fastboot-only flow)")
    if ext4_label(rootfs_check) != ROOTFS_LABEL:
        parser.error("--rootfs ext4 label is not LIUQIN_ROOT; the initrd "
                     "storage guard would refuse it. Build with "
                     "`nix build .#rootfsImage`")

    print("Checking fastboot device identity...", flush=True)
    require_abl_fastboot(args.serial)
    require_var(args.serial, "product", "liuqin")
    require_var(args.serial, "unlocked", "yes")
    if args.target == "userdata":
        # Slot A only; never switch slots implicitly.
        require_var(args.serial, "current-slot", "a")
    else:
        # The `linux` partition is independent of the A/B state, so the slot
        # is neither checked nor touched here: U-Boot (boot_b) is what loads
        # this rootfs, and switching slots is the user's explicit decision.
        print("Target `linux`: boot slots are not checked and not touched.",
              flush=True)
    # userdata's size is capacity-specific (this tablet ships as 128/256/512
    # GB), so it is measured on the unit, never assumed. partition_size() has
    # no default: a device that reports nothing makes it raise, and the
    # install stops instead of guessing which layout the device has. The
    # measured number is then the only gate left: a rootfs that does not fit
    # the partition the device actually reports is refused.
    if args.target == "linux":
        # Partition numbers and sizes are per-unit, so the `linux` partition
        # is measured, never assumed - and its absence is a hard stop, not a
        # reason to create it here: carving it is the live image operator's
        # explicit `sgdisk` job after geometry measurement and backup.
        linux_bytes = partition_size(args.serial, "linux")
        if linux_bytes <= 0:
            parser.error("fastboot reported no usable `linux` partition; "
                         "carve it first in the live image with sgdisk "
                         "(liuqin-dualboot/docs/TESTING.md phase 5)")
        if rootfs_bytes > linux_bytes:
            parser.error("rootfs image does not fit the measured `linux` "
                         f"partition ({linux_bytes} bytes); rebuild "
                         ".#demo-rootfsImage with a smaller closure")
    else:
        userdata_bytes = partition_size(args.serial, "userdata")
        if userdata_bytes <= 0:
            parser.error("fastboot reported no usable userdata size; refusing "
                         "to install onto a layout that cannot be measured")
        if rootfs_bytes > userdata_bytes:
            parser.error("rootfs image does not fit the measured userdata "
                         f"partition ({userdata_bytes} bytes); rebuild "
                         ".#rootfsImage with a smaller closure")
        if args.boot.stat().st_size > partition_size(args.serial, "boot_a"):
            parser.error("boot image exceeds the reported boot partition size")

    # Raw ext4 artifacts are ordinary (non-sparse) images. The fastboot client
    # sends one DATA payload for such an image, so a partition being large
    # enough is not sufficient: the bootloader's advertised transfer ceiling
    # must also contain the file. Sparse artifacts are split by fastboot and
    # were checked above for their expanded capacity. Refuse before any
    # backup or flash rather than relying on a late protocol failure.
    download_limit = max_download_size(args.serial)
    if not rootfs_sparse and args.rootfs.stat().st_size > download_limit:
        parser.error("rootfs image exceeds the target fastboot "
                     f"max-download-size ({download_limit} bytes); use a "
                     "smaller closure/image or a tested sparse/chunked flow")
    if args.target == "userdata" and args.boot.stat().st_size > download_limit:
        parser.error("boot image exceeds the target fastboot "
                     f"max-download-size ({download_limit} bytes)")

    if args.target == "userdata":
        args.backup.mkdir(mode=0o700, parents=True)
        sums = {}
        for name in ("boot_a", "boot_b", "persist"):
            print(f"Backing up {name}...", flush=True)
            target = args.backup / f"{name}.img"
            try:
                fastboot(args.serial, "fetch", name, str(target), timeout=900)
            except (subprocess.SubprocessError, RuntimeError) as error:
                sys.exit(
                    "fastboot fetch is not supported by this bootloader; "
                    f"backup of {name} failed and nothing will be flashed. "
                    f"({error})")
            target.chmod(0o600)
            # A silently truncated fetch must fail here, not after flashing.
            expected = partition_size(args.serial, name)
            actual = target.stat().st_size
            if actual != expected:
                sys.exit(f"backup of {name} is truncated: {actual} bytes, "
                         f"partition reports {expected}")
            sums[target.name] = sha256(target)
        (args.backup / "SHA256SUMS").write_text(
            "".join(f"{h}  {n}\n" for n, h in sums.items()))

    if not args.write_rootfs:
        print("Checks complete. Re-run with --write-rootfs to write the "
              f"rootfs image to `{args.target}`.", flush=True)
        return

    if args.target == "linux":
        # Nothing else is written: the rootfs image carries /boot, so this one
        # flash covers both the system and what U-Boot reads. The partition
        # already exists (the live GPT maintenance step made it) and is
        # measured above.
        print("Flashing the ext4 rootfs image to the `linux` partition "
              "(boot slots, userdata and persist untouched)...", flush=True)
        fastboot(args.serial, "flash", "linux", str(args.rootfs), timeout=1800)
    else:
        # Flash boot_a before userdata: boot_a is small and quick, so if a
        # userdata failure follows, the unbootable window is a failed boot.img
        # while the old rootfs still survives; both orders are recoverable only
        # via fastboot (the new initrd guard would refuse the old rootfs), but
        # this order keeps the destructive userdata erase as the last step.
        print("Writing the boot image to boot_a...", flush=True)
        fastboot(args.serial, "flash", "boot_a", str(args.boot))

        print("Flashing the ext4 rootfs image to userdata "
              "(overwrites the whole partition)...", flush=True)
        fastboot(args.serial, "flash", "userdata", str(args.rootfs), timeout=1800)

    fastboot(args.serial, "reboot")
    print("Installation commands completed. The rootfs was deployed as a "
          "pre-built ext4 image carrying the guard marker; the initrd "
          "storage guard should accept it on first boot. First-boot "
          "verification is still required.", flush=True)
    if args.target == "linux":
        print("The active slot was not changed: booting the new rootfs means "
              "starting U-Boot (boot_b) and picking \"Boot Linux\" from its "
              "menu.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError,
            subprocess.SubprocessError) as error:
        sys.exit("Installation stopped: " + str(error))
