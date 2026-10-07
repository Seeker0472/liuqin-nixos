#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Verify that every hunk in the given patch files declares the line counts it
# actually carries.
#
# GNU patch does not verify the counts in "@@ -a,b +c,d @@".  A hunk that
# declares fewer lines than it contains is applied as the declared prefix and
# the rest is silently dropped, and the build stays green.  A creation hunk
# ("@@ -0,0 +1,N @@") that drifts this way writes the file without its tail:
# that is exactly how arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dts lost
# its &usb_1/&usb_1_hsphy overrides, so the built DTB came out with the eUSB2
# PHY and DWC3 disabled and the device's only debug channel never came up.
#
# pkgs/kernel/default.nix runs this over every patch in pkgs/kernel/patches, before the
# patches are applied, so the next drift fails the build instead of the boot.
# It also works standalone:  ./check-patch-hunks.py ./patches/*.patch
#
# Exit status: 0 when every hunk is consistent, 1 otherwise.

import re
import sys

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def is_file_header_pair(lines, index, old, new, want_old, want_new):
    """Whether the next two lines start the next file section.

    File headers use the same prefixes as hunk deletion and addition lines.
    Recognize them only after the current hunk's declared counts are complete
    and when both header lines are present.  This keeps valid hunk content such
    as ``-- `` and ``+++ `` from being mistaken for metadata.
    """
    return (
        old == want_old
        and new == want_new
        and lines[index].startswith("--- ")
        and index + 1 < len(lines)
        and lines[index + 1].startswith("+++ ")
    )


def check(path):
    """Return [(line_number, start_old, start_new, declared, actual), ...]."""
    problems = []
    lines = open(path, "r", encoding="utf-8", errors="replace").read().splitlines()

    i = 0
    while i < len(lines):
        m = HUNK.match(lines[i])
        if not m:
            i += 1
            continue
        want_old = int(m.group(2)) if m.group(2) is not None else 1
        want_new = int(m.group(4)) if m.group(4) is not None else 1

        old = new = 0
        j = i + 1
        while j < len(lines):
            line = lines[j]
            if line.startswith("@@ ") or line.startswith("diff --git "):
                break
            if is_file_header_pair(lines, j, old, new, want_old, want_new):
                break
            if line.startswith("\\"):          # "\ No newline at end of file"
                pass
            elif line.startswith("-"):
                old += 1
            elif line.startswith("+"):
                new += 1
            elif line.startswith(" "):
                old += 1
                new += 1
            else:
                break                           # patch metadata or malformed data
            j += 1
        if (old, new) != (want_old, want_new):
            problems.append(
                (i + 1, m.group(1), m.group(3), (want_old, want_new), (old, new))
            )
        i = j
    return problems


def main(argv):
    failed = False
    for path in argv[1:]:
        for line_no, start_old, start_new, declared, actual in check(path):
            failed = True
            drops = actual[1] > declared[1]
            print(
                f"error: {path}: hunk at line {line_no} declares "
                f"@@ -{start_old},{declared[0]} +{start_new},{declared[1]} @@ but carries "
                f"{actual[0]},{actual[1]} lines"
                + (
                    " -- GNU patch would silently drop "
                    f"{actual[1] - declared[1]} line(s)"
                    if drops
                    else " -- GNU patch would reject it"
                ),
                file=sys.stderr,
            )
            print(
                f"       fix the count: @@ -{start_old},{actual[0]} +{start_new},{actual[1]} @@",
                file=sys.stderr,
            )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
