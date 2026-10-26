#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Audit the ownership of the board's staged Kconfig answers."""
import argparse
import json
from pathlib import Path
import re
import sys


class PolicyError(ValueError):
    pass


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PolicyError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(), object_pairs_hook=unique_object)


def read_fragment(path):
    """Policy fragments contain explicit tristates, never arbitrary shell text."""
    result = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        match = re.fullmatch(r"CONFIG_(\w+)=([ymn])|# CONFIG_(\w+) is not set", line)
        if match:
            name, value = (match[1], match[2]) if match[1] else (match[3], "n")
            if name in result:
                raise PolicyError(f"{path}:{number}: duplicate CONFIG_{name}")
            result[name] = value
        elif line and (not line.startswith("#") or line.startswith("# CONFIG_") and "is not set" in line):
            raise PolicyError(f"{path}:{number}: invalid tristate assignment: {line}")
    return result


def initial_answers(settings):
    result = {}
    for name, value in settings.items():
        while isinstance(value, dict) and value.get("_type") == "override":
            value = value["content"]
        if not isinstance(value, dict) or value.get("tristate") not in ("y", "m", "n"):
            raise PolicyError(f"CONFIG_{name}: expected a structured tristate answer")
        result[name] = value["tristate"]
    return result


def check_transitions(stage, earlier, later, groups):
    allowed = {}
    for group in groups:
        if not group.get("reason", "").strip() or not group.get("symbols"):
            raise PolicyError(f"{stage}: every transition group needs symbols and a reason")
        transition = (group["from"], group["to"])
        if any(value not in ("y", "m", "n") for value in transition) or transition[0] == transition[1]:
            raise PolicyError(f"{stage}: invalid transition {transition}")
        for name in group["symbols"]:
            if name in allowed:
                raise PolicyError(f"{stage}: duplicate transition rule for CONFIG_{name}")
            allowed[name] = transition
    actual = {name: (earlier[name], value) for name, value in later.items()
              if name in earlier and earlier[name] != value}
    for name in sorted(actual.keys() | allowed.keys()):
        if actual.get(name) != allowed.get(name):
            raise PolicyError(f"{stage}: CONFIG_{name}: actual transition {actual.get(name)}, "
                              f"declared {allowed.get(name)}; unexplained change or stale rule")


def audit(initial, board, installer, camera, policy):
    if set(policy) != {"board", "installer"}:
        raise PolicyError("policy must contain exactly the board and installer stages")
    overlap = sorted(board.keys() & installer.keys())
    if overlap:
        raise PolicyError("installer repeats board-owned symbols: " + ", ".join(overlap))
    check_transitions("board", initial, board, policy["board"])
    installed = initial | board
    check_transitions("installer", installed, installer, policy["installer"])
    live = installed | installer
    # camera-symbols.txt is an assertion list, not another config input.
    # Symbols without explicit answers can come from defconfig or Kconfig
    # selects; the kernel's existing final-config check covers those too.
    for profile, answers in (("installed", installed), ("installer", live)):
        for name, required in camera.items():
            value = answers.get(name)
            accepted = {"y", "m"} if required == "m" else {required}
            if value is not None and value not in accepted:
                raise PolicyError(f"{profile}: camera assertion CONFIG_{name}={required} "
                                  f"contradicts its owner's answer {value}")
    return installed, live


def write_report(path, initial, board, installer, camera, installed, live):
    lines = ["symbol\tinitial\tboard\tinstaller\tinstalled-request\tinstaller-request"
             "\tinstalled-owner\tinstaller-owner\tcamera-assertion"]
    for name in sorted(live.keys() | camera.keys()):
        owner = ("liuqin-firstboot.config" if name in board else
                 "config.nix" if name in initial else "defconfig/Kconfig")
        installer_owner = "installer.config" if name in installer else owner
        values = [name, initial.get(name, "-"), board.get(name, "-"), installer.get(name, "-"),
                  installed.get(name, "-"), live.get(name, "-"), owner, installer_owner, camera.get(name, "-")]
        lines.append("\t".join(values))
    path.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("initial", "board", "installer", "camera", "policy"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        initial = initial_answers(read_json(args.initial))
        board, installer, camera = map(read_fragment, (args.board, args.installer, args.camera))
        installed, live = audit(initial, board, installer, camera, read_json(args.policy))
        if args.report:
            write_report(args.report, initial, board, installer, camera, installed, live)
    except (PolicyError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"kernel config policy: {error}", file=sys.stderr)
        return 1
    print(f"kernel config policy: {len(initial)} initial answers, {len(board)} board constraints, "
          f"{len(installer)} installer additions, {len(camera)} camera assertions verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
