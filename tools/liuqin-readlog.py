#!/usr/bin/env python3
"""Host-side readback for the liuqin U-Boot diagnostic channel.

Kept byte-compatible with liuqin-dualboot/tools/liuqin-readlog.py (the U-Boot
repository, which owns the device side of this channel); it lives here too
because the kernel side of the `dump` path is this repository's: the bootlog
console (patches/kernel/0011) writes the log into DRAM at the address that
boot.kernelParams sets, and `dump` is what reads it back.

There is no UART on this board: the only way to see what U-Boot did is to have
it record its console output and export that through fastboot getvar
(liuqin_conlog), then read those variables from the host.  This script drives
that loop:

  log     fetch and print the recorded console output (fastboot.con*).
  dump    dump a kernel log left in DRAM and print it: liuqin_rdump [addr] [len]
          [raw] unwraps a pstore/ramoops persistent_ram ring (default
          0x9f000000 +1M) into fastboot.dmp*.
  raw     fetch arbitrary getvar names.
  rescue  reset the USB device node; needed when a wedged gadget leaves the
          device enumerated but unresponsive (see BRINGUP-LOG section 4.2).

Everything goes through one fastboot process at a time on purpose: concurrent
fastboot processes mix up the protocol on this board and wedge the endpoint
state machine.
"""

import argparse
import fcntl
import glob
import os
import re
import subprocess
import sys
import time

USBDEVFS_RESET = 0x5514
USB_IDS = [("17cb", "d00d"), ("18d1", "d00d")]  # U-Boot gadget, ABL fastboot
FASTBOOT_TIMEOUT = 20


def find_fastboot():
    path = os.environ.get("FASTBOOT") or shutil_which("fastboot")
    if path:
        return [path]
    # Fall back to the nix store copy so the tool works outside the dev shell.
    for candidate in sorted(glob.glob("/nix/store/*android-tools*/bin/fastboot")):
        return [candidate]
    sys.exit("error: fastboot not found (set FASTBOOT=<path>)")


def shutil_which(name):
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(directory, name)
        if os.access(candidate, os.X_OK):
            return candidate
    return None


def device_nodes():
    """Return [(node, devnum)] for the known fastboot USB ids."""
    found = []
    for sysdev in glob.glob("/sys/bus/usb/devices/*"):
        try:
            vid = open(f"{sysdev}/idVendor").read().strip()
            pid = open(f"{sysdev}/idProduct").read().strip()
        except OSError:
            continue
        if (vid, pid) not in USB_IDS:
            continue
        try:
            bus = int(open(f"{sysdev}/busnum").read().strip())
            dev = int(open(f"{sysdev}/devnum").read().strip())
        except OSError:
            continue
        found.append((f"/dev/bus/usb/{bus:03d}/{dev:03d}", dev))
    return found


def usb_reset():
    count = 0
    for node, _dev in device_nodes():
        try:
            fd = os.open(node, os.O_WRONLY)
        except OSError as exc:
            print(f"rescue: cannot open {node}: {exc}", file=sys.stderr)
            continue
        try:
            fcntl.ioctl(fd, USBDEVFS_RESET, 0)
            count += 1
            print(f"rescue: reset {node}")
        except OSError as exc:
            print(f"rescue: reset {node} failed: {exc}", file=sys.stderr)
        finally:
            os.close(fd)
    if not count:
        print("rescue: no fastboot device on the bus", file=sys.stderr)
    return count


class Fastboot:
    def __init__(self, argv):
        self.argv = argv

    def _run(self, args, timeout=FASTBOOT_TIMEOUT):
        try:
            return subprocess.run(
                self.argv + args,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return None

    def getvar(self, name, retry=True):
        """Return the variable value, or None when the device does not have it.

        Transport failures (wedged gadget) are retried once after a USB reset.
        Note that fastboot prints its responses on stderr.
        """
        proc = self._run(["getvar", name])
        if proc is not None and proc.returncode == 0:
            text = proc.stdout + proc.stderr
            match = re.search(r"^%s: (.*)$" % re.escape(name), text, re.M)
            if match:
                return match.group(1)
            return None
        if not retry:
            return None
        print(f"getvar {name}: transport failure, resetting USB", file=sys.stderr)
        usb_reset()
        time.sleep(2)
        return self.getvar(name, retry=False)

    def oem(self, command, timeout=30):
        return self._run(["oem", f"run:{command}"], timeout=timeout)


def unfold(lines):
    """Rejoin the continuation records emitted for over-long kernel lines."""
    out = []
    for line in lines:
        if line.startswith("  ") and out:
            out[-1] += line[2:]
        else:
            out.append(line)
    return out


def fetch_lines(fb, prefix):
    """Fetch <prefix>count variables, newest first, returned oldest first."""
    count = fb.getvar(f"{prefix}count")
    try:
        count = int(count)
    except (TypeError, ValueError):
        return []
    lines = []
    for i in range(count):
        name = prefix if i == 0 else f"{prefix}{i}"
        value = fb.getvar(name)
        if value is None:
            break
        lines.append(value)
    lines.reverse()
    return unfold(lines)


def print_dump(fb, prefix):
    build = fb.getvar("build")
    ab = fb.getvar("ab")
    slot = fb.getvar("slot")
    diag = fb.getvar("diag")
    print(f"# build={build} ab={ab} slot={slot}")
    print(f"# diag={diag}")

    lines = fetch_lines(fb, prefix)
    print(f"### {prefix} log ({len(lines)} lines)")
    for line in lines:
        print(line)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="log",
                        choices=["log", "dump", "raw", "rescue"])
    parser.add_argument("args", nargs="*",
                        help="'raw': variable names; 'dump': [addr] [len] [raw]")
    opts = parser.parse_args()

    fb = Fastboot(find_fastboot())

    if opts.command == "rescue":
        usb_reset()
        return 0

    if opts.command == "raw":
        for name in opts.args:
            print(f"{name}: {fb.getvar(name)}")
        return 0

    if opts.command == "dump":
        # Ask U-Boot to stage a DRAM region into the getvar ring (the command
        # itself prints nothing: drawing to the panel costs ~1 s a line, and a
        # slow response is what wedged the gadget in the first place).
        cmd = " ".join(["liuqin_rdump"] + opts.args)
        print(f"# oem run:{cmd}")
        fb.oem(cmd)
        print_dump(fb, "dmp")
        return 0

    print_dump(fb, "con")
    return 0


if __name__ == "__main__":
    sys.exit(main())
