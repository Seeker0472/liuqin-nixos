#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""Run one bounded display helper operation, then fetch its cached report.

Requires U-Boot fastboot (the menu's Enable Fastboot Mode), not ABL fastboot.
quiesce blanks the panel until reboot. This tool never reboots or retries it.
"""
import argparse
import json
import re
import subprocess
import sys


def getvar(command, name):
    result = subprocess.run(command + ["getvar", name], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=15, check=True)
    values = re.findall(r"^(?:\(bootloader\)\s*)?" + re.escape(name) + r":\s*(.*?)\s*$",
                        result.stdout, re.M)
    if len(values) != 1:
        raise ValueError(f"missing or ambiguous {name}: {result.stdout.strip()}")
    return values[0]


def run(command, action):
    # A FAIL still has a useful report. Never repeat a destructive operation
    # because of a transport error or a failed preflight/commit.
    result = subprocess.run(command + ["oem", "board:display-" + action], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=15)
    count = getvar(command, "display-count")
    if not count.isdecimal() or not 1 <= int(count) <= 32:
        raise ValueError(f"invalid display-count: {count!r}")
    rows = [getvar(command, f"display{i}") for i in range(int(count))]
    return result.returncode, {
        "action": action,
        "command_ok": result.returncode == 0,
        "response": result.stdout.strip(),
        "report": rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fastboot", default="fastboot", help="fastboot executable")
    parser.add_argument("--serial", help="select exactly this fastboot device")
    parser.add_argument("action", choices=["status", "prepare", "quiesce"],
                        help="status is cached; prepare checks hardware; quiesce is one-way")
    args = parser.parse_args()
    command = [args.fastboot] + (["-s", args.serial] if args.serial else [])
    try:
        code, report = run(command, args.action)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"display helper: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return code


if __name__ == "__main__":
    sys.exit(main())
