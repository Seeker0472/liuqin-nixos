#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the generated system's default boot transaction without host units."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import sys



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--systemd-analyze", required=True)
    parser.add_argument("unit_tree", type=Path)
    args = parser.parse_args()
    tree = args.unit_tree.resolve()
    # Do not append ':' here: that would bring the host's default paths back.
    if ":" in str(tree):
        parser.error("the unit tree path cannot contain ':'")
    for name in ("sysinit.target", "basic.target", "shutdown.target",
                 "default.target"):
        path = tree / name
        if not path.is_file() or path.resolve() == Path("/dev/null"):
            parser.error(f"incomplete unit tree: missing {name}")
    environment = {
        **os.environ,
        "SYSTEMD_UNIT_PATH": str(tree),
        "SYSTEMD_GENERATOR_PATH": "/dev/null",
        "SYSTEMD_ENVIRONMENT_GENERATOR_PATH": "/dev/null",
        "SYSTEMD_LOG_TARGET": "console",
        "SYSTEMD_COLORS": "0",
        "LC_ALL": "C",
    }
    command = [
        args.systemd_analyze, "--generators=no", "--man=no",
        "--recursive-errors=yes", "verify", "--",
    ]

    # A target-only verify validates its transaction but systemd checks
    # commands only for units named on the command line. Ask its pinned debug
    # interface for the jobs in default.target's start transaction, then
    # verify those exact units explicitly. This excludes installed but
    # unreachable template/initrd units without weakening executable checks.
    discovery_environment = {**environment, "SYSTEMD_LOG_LEVEL": "debug"}
    discovery = subprocess.run(
        [*command, "default.target"], env=discovery_environment, text=True,
        capture_output=True)
    if discovery.returncode:
        sys.stdout.write(discovery.stdout)
        sys.stderr.write(discovery.stderr)
        return discovery.returncode if discovery.returncode > 0 else 1

    transaction_units = set()
    job_pattern = re.compile(
        r"^([^:\s]+): Installed new job ([^/]+)/start as [0-9]+$")
    for line in (discovery.stdout + "\n" + discovery.stderr).splitlines():
        match = job_pattern.match(line)
        if match and match.group(1) == match.group(2):
            transaction_units.add(match.group(1))
    if not transaction_units:
        print("systemd-analyze did not report the default.target transaction",
              file=sys.stderr)
        return 1

    result = subprocess.run(
        [*command, *sorted(transaction_units)], env=environment, text=True,
        capture_output=True)
    # Loading failures, invalid directives and missing executables are errors
    # too. Never turn an analyzer failure into success by filtering its text.
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode:
        return result.returncode if result.returncode > 0 else 1
    print(f"verified {len(transaction_units)} units in default.target's "
          f"transaction from {tree}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
