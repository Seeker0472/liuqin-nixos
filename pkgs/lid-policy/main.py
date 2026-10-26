#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Apply the liuqin GNOME lid policy without suspending the system."""
import argparse
from pathlib import Path
import signal
import sys
import time

import gi
gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix


class LidPolicy:
    def __init__(self, state_dir):
        self.loop = GLib.MainLoop()
        self.marker = Path(state_dir) / "display-blanked"
        self.applied = None
        self.next_update = 0
        self.last_error = None

        self.upower = self.proxy(
            Gio.BusType.SYSTEM,
            "org.freedesktop.UPower",
            "/org/freedesktop/UPower",
            "org.freedesktop.UPower")
        self.session = self.proxy(
            Gio.BusType.SESSION,
            "org.gnome.SessionManager",
            "/org/gnome/SessionManager",
            "org.gnome.SessionManager")
        self.screensaver = self.proxy(
            Gio.BusType.SESSION,
            "org.gnome.ScreenSaver",
            "/org/gnome/ScreenSaver",
            "org.gnome.ScreenSaver")
        self.mutter = self.proxy(
            Gio.BusType.SESSION,
            "org.gnome.Mutter.DisplayConfig",
            "/org/gnome/Mutter/DisplayConfig",
            "org.gnome.Mutter.DisplayConfig")
        self.display_properties = self.proxy(
            Gio.BusType.SESSION,
            "org.gnome.Mutter.DisplayConfig",
            "/org/gnome/Mutter/DisplayConfig",
            "org.freedesktop.DBus.Properties")

        for proxy in (self.upower, self.session, self.screensaver,
                      self.mutter, self.display_properties):
            proxy.connect("g-properties-changed", self.changed)
            proxy.connect("notify::g-name-owner", self.owner_changed)

    @staticmethod
    def proxy(bus, name, path, interface):
        return Gio.DBusProxy.new_for_bus_sync(
            bus, Gio.DBusProxyFlags.DO_NOT_AUTO_START, None,
            name, path, interface, None)

    @staticmethod
    def prop(proxy, name, default=None):
        value = proxy.get_cached_property(name)
        return value.unpack() if value is not None else default

    @staticmethod
    def call(proxy, method, parameters=None):
        return proxy.call_sync(
            method, parameters, Gio.DBusCallFlags.NONE, 2000, None)

    def changed(self, *_):
        self.next_update = 0

    def owner_changed(self, *_):
        self.applied = None
        self.next_update = 0

    def report(self, error):
        message = str(error)
        if message != self.last_error:
            print(f"liuqin-lid-policy: {message}", file=sys.stderr, flush=True)
            self.last_error = message

    def set_display_power(self, mode):
        self.call(
            self.display_properties,
            "Set",
            GLib.Variant(
                "(ssv)",
                ("org.gnome.Mutter.DisplayConfig", "PowerSaveMode",
                 GLib.Variant("i", mode))))

    def update(self):
        if time.monotonic() < self.next_update:
            return GLib.SOURCE_CONTINUE
        self.next_update = time.monotonic() + 1

        try:
            required = (self.upower, self.session, self.screensaver,
                        self.mutter, self.display_properties)
            if not all(proxy.get_name_owner() for proxy in required):
                return GLib.SOURCE_CONTINUE
            if not self.prop(self.upower, "LidIsPresent", False):
                return GLib.SOURCE_CONTINUE
            if not self.prop(self.session, "SessionIsActive", False):
                return GLib.SOURCE_CONTINUE

            closed = self.prop(self.upower, "LidIsClosed", False)
            power_mode = self.prop(self.mutter, "PowerSaveMode", -1)

            if closed:
                self.marker.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                self.marker.touch(mode=0o600, exist_ok=True)
                if self.applied is True and power_mode == 3:
                    return GLib.SOURCE_CONTINUE

                # Lock before blanking.  Opening the cover only changes DPMS,
                # so this session remains on the lock screen.
                self.call(self.screensaver, "Lock")
                self.set_display_power(3)
                self.applied = True
            else:
                # Starting an ordinary open-lid session must not wake a panel
                # the user blanked with the power key.  The marker records that
                # this service, rather than another policy, blanked it.
                if not self.marker.exists():
                    self.applied = False
                    return GLib.SOURCE_CONTINUE
                if self.applied is False and power_mode == 0:
                    return GLib.SOURCE_CONTINUE

                self.set_display_power(0)
                self.marker.unlink(missing_ok=True)
                self.applied = False

            self.last_error = None
        except (GLib.Error, OSError, ValueError) as error:
            self.report(error)
        return GLib.SOURCE_CONTINUE

    def stop(self):
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def run(self):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.stop)
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self.stop)
        GLib.timeout_add(250, self.update)
        self.loop.run()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", required=True)
    arguments = parser.parse_args()
    LidPolicy(arguments.state_dir).run()
