#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Show a native desktop chooser; cancellation never requests a power action.

Ported from the downstream liuqin-power-menu; runs inside the user session
via liuqin-power-key-action.
"""
import gettext
import subprocess
import sys


def main():
    translate = gettext.translation(
        # The locale directory is substituted with gnome-control-center's
        # Nix store path at build time (see pkgs/power-keyd/default.nix);
        # fallback=True still covers a missing translation.
        "gnome-control-center-2.0", "/usr/share/locale", fallback=True
    ).gettext
    choice = subprocess.run(
        [
            "zenity", "--list", "--title", translate("Power"),
            "--column", "id", "--column", translate("Action"),
            "--hide-column=1", "--print-column=1",
            "suspend", translate("Suspend"),
            "reboot", translate("Restart"),
            "poweroff", translate("Power Off"),
        ],
        stdout=subprocess.PIPE,
        text=True,
        check=False,
    )
    if choice.returncode == 1:  # Cancel, Escape or closing the window
        return 0
    if choice.returncode:
        return 1
    commands = {
        "suspend": ["systemctl", "suspend"],
        "reboot": ["gnome-session-quit", "--reboot"],
        "poweroff": ["gnome-session-quit", "--power-off"],
    }
    command = commands.get(choice.stdout.strip())
    if command is None:
        return 64
    return subprocess.call(command)


if __name__ == "__main__":
    sys.exit(main())
