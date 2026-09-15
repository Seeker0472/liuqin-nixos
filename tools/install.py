#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Install the NixOS boot.img and rootfs image onto a Xiaomi Pad 6 Pro
(liuqin).

Host-side installer running over fastboot. The device-identity checks kept
from the downstream installer are exactly:

  * fastboot product must be "liuqin"
  * the bootloader must be unlocked
  * slot A must be the active slot (slots are never switched)
  * the required --serial must be given and is bound to every fastboot call
  * userdata geometry must be exactly the known 256 GB layout
    (471789528 * 512 bytes as reported by fastboot)
  * boot.img must fit the reported boot_a partition
  * the sha256 of --boot and --rootfs is verified before anything is sent

--rootfs is a pre-built ext4 image (flake output .#rootfsImage), flashed
verbatim with `fastboot flash userdata`. Unlike the downstream RAM-installer
flow there is no tarball and no on-device untar: the image already carries
the /etc/liuqin-nixos-root marker the initrd storage guard requires before
it will mount the root read-write.

Backups of boot_a/boot_b/persist use `fastboot fetch` when the device's
bootloader supports it; otherwise the installer stops with a clear error
instead of writing anything.

Usage:
  liuqin-install --serial SERIAL --boot boot.img --rootfs rootfs.img \
      --sha256-boot SUM --sha256-rootfs SUM --backup DIR [--write-rootfs]
"""
import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

USERDATA_BYTES = 471789528 * 512
BOOT_A_LIMIT = 192 * 1024 * 1024  # 0x0c000000
EXT4_MAGIC_OFFSET = 0x438
EXT4_MAGIC = b"\x53\xef"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def is_ext4_image(path: Path) -> bool:
    with path.open("rb") as stream:
        stream.seek(EXT4_MAGIC_OFFSET)
        return stream.read(2) == EXT4_MAGIC


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
    return fastboot(serial, "getvar", name)


def require_var(serial, name, pattern):
    if not re.search(r"\b" + name + r":\s*" + pattern + r"\b",
                     getvar(serial, name)):
        raise RuntimeError(f"fastboot device check failed: {name}")


def partition_size(serial, name):
    match = re.search(
        r"partition-size:" + re.escape(name) + r":\s*(0x[0-9a-fA-F]+)",
        getvar(serial, "partition-size:" + name))
    if not match:
        raise RuntimeError(f"cannot determine partition size: {name}")
    return int(match.group(1), 16)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot", type=Path, required=True,
                        help="boot.img to flash to boot_a")
    parser.add_argument("--rootfs", type=Path, required=True,
                        help="pre-built ext4 rootfs image (flake output "
                             ".#rootfsImage) flashed verbatim to userdata")
    parser.add_argument("--serial", required=True,
                        help="fastboot serial of the target device")
    parser.add_argument("--backup", type=Path, required=True,
                        help="new directory receiving boot_a/boot_b/persist dumps")
    parser.add_argument("--write-rootfs", action="store_true",
                        help="actually write the rootfs (erases userdata)")
    parser.add_argument("--sha256-boot", required=True,
                        help="expected sha256 of --boot; verified before flashing")
    parser.add_argument("--sha256-rootfs", required=True,
                        help="expected sha256 of --rootfs; verified before flashing")
    args = parser.parse_args()

    for image in (args.boot, args.rootfs):
        if not image.is_file():
            parser.error(f"missing input: {image}")
    if args.backup.exists():
        parser.error("--backup must be a new directory")
    if args.boot.stat().st_size > BOOT_A_LIMIT:
        parser.error("boot.img exceeds the 192 MiB boot partition")
    if sha256(args.boot) != args.sha256_boot:
        parser.error("boot.img checksum mismatch")
    if sha256(args.rootfs) != args.sha256_rootfs:
        parser.error("rootfs checksum mismatch")
    if not is_ext4_image(args.rootfs):
        parser.error("--rootfs is not an ext4 image; build it with "
                     "`nix build .#rootfsImage` (no tarballs: there is no "
                     "on-device untar step in the fastboot-only flow)")

    print("Checking fastboot device identity...", flush=True)
    require_var(args.serial, "product", "liuqin")
    require_var(args.serial, "unlocked", "yes")
    # Slot A only; never switch slots implicitly.
    require_var(args.serial, "current-slot", "a")
    if partition_size(args.serial, "userdata") != USERDATA_BYTES:
        parser.error("unsupported userdata size; only the known 256 GB "
                     "layout is admitted")
    if args.boot.stat().st_size > partition_size(args.serial, "boot_a"):
        parser.error("boot image exceeds the reported boot partition size")

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
        # Note: this is size equality, weaker than the downstream sha256
        # record of every fetched partition (see docs/PORTING-NOTES.md).
        expected = partition_size(args.serial, name)
        actual = target.stat().st_size
        if actual != expected:
            sys.exit(f"backup of {name} is truncated: {actual} bytes, "
                     f"partition reports {expected}")
        sums[target.name] = sha256(target)
    (args.backup / "SHA256SUMS").write_text(
        "".join(f"{h}  {n}\n" for n, h in sums.items()))

    if not args.write_rootfs:
        print("Checks and backups complete. Re-run with --write-rootfs to "
              "erase userdata and install.", flush=True)
        return

    print("Flashing the ext4 rootfs image to userdata "
          "(overwrites the whole partition)...", flush=True)
    fastboot(args.serial, "flash", "userdata", str(args.rootfs), timeout=1800)

    print("Writing the boot image to boot_a...", flush=True)
    fastboot(args.serial, "flash", "boot_a", str(args.boot))
    fastboot(args.serial, "reboot")
    print("Installation commands completed. The rootfs was deployed as a "
          "pre-built ext4 image carrying the guard marker; the initrd "
          "storage guard should accept it on first boot. First-boot "
          "verification is still required.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError,
            subprocess.SubprocessError) as error:
        sys.exit("Installation stopped: " + str(error))
