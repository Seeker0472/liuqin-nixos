#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Keep the built-in panel upright and own our accelerometer claim."""
import argparse
import os
from pathlib import Path
import signal
import sys
import time

import gi
gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix

from layout import ORIENTATIONS, ROTATIONS, laptop_rotation, rotation_config


class Posture:
    def __init__(self, default_rotation):
        self.loop = GLib.MainLoop()
        self.default_rotation = default_rotation
        self.claim_owner = None
        self.previous = None
        self.next_update = 0
        self.last_error = None
        self.mutter = self.proxy(Gio.BusType.SESSION, "org.gnome.Mutter.DisplayConfig",
                                 "/org/gnome/Mutter/DisplayConfig", "org.gnome.Mutter.DisplayConfig")
        self.sensor = self.proxy(Gio.BusType.SYSTEM, "net.hadess.SensorProxy",
                                 "/net/hadess/SensorProxy", "net.hadess.SensorProxy")
        self.session = self.proxy(Gio.BusType.SESSION, "org.gnome.SessionManager",
                                  "/org/gnome/SessionManager", "org.gnome.SessionManager")
        self.screensaver = self.proxy(Gio.BusType.SESSION, "org.gnome.ScreenSaver",
                                      "/org/gnome/ScreenSaver", "org.gnome.ScreenSaver")
        self.settings = Gio.Settings.new("org.gnome.settings-daemon.peripherals.touchscreen")
        self.settings.connect("changed::orientation-lock", self.changed)
        for proxy in (self.mutter, self.sensor, self.session, self.screensaver):
            proxy.connect("g-properties-changed", self.changed)
            proxy.connect("notify::g-name-owner", self.changed)
        self.screensaver.connect("g-signal", self.changed)

    def proxy(self, bus, name, path, interface):
        return Gio.DBusProxy.new_for_bus_sync(
            bus, Gio.DBusProxyFlags.DO_NOT_AUTO_START, None, name, path, interface, None)

    def changed(self, *_):
        self.next_update = 0

    @staticmethod
    def prop(proxy, name, default=None):
        prop = proxy.get_cached_property(name)
        return prop.unpack() if prop is not None else default

    @staticmethod
    def call(proxy, method, parameters=None):
        return proxy.call_sync(method, parameters, Gio.DBusCallFlags.NONE, 2000, None)

    def release(self):
        if self.claim_owner and self.claim_owner == self.sensor.get_name_owner():
            try:
                self.call(self.sensor, "ReleaseAccelerometer")
            except GLib.Error as error:
                self.report(error)
        self.claim_owner = None

    def report(self, error):
        text = str(error)
        if text != self.last_error:
            print(f"liuqin-panel-posture: {text}", file=sys.stderr, flush=True)
            self.last_error = text

    @staticmethod
    def posture():
        for path in sorted(Path("/sys/bus/i2c/devices").glob("*-004c/tablet_mode")):
            try:
                mode = path.read_text().strip()
                if mode in ("0", "1"):
                    return mode
            except OSError:
                pass
        return None

    def update(self):
        mode = self.posture()
        if mode != self.previous:
            self.previous = mode
            self.next_update = 0
        if time.monotonic() < self.next_update:
            return GLib.SOURCE_CONTINUE
        self.next_update = time.monotonic() + 3
        try:
            owner = self.sensor.get_name_owner()
            if owner != self.claim_owner:
                self.claim_owner = None
            active = self.session.get_name_owner() and self.prop(self.session, "SessionIsActive", False)
            unlocked = (self.screensaver.get_name_owner()
                        and not self.call(self.screensaver, "GetActive").unpack()[0])
            visible = self.mutter.get_name_owner() and self.prop(self.mutter, "PowerSaveMode", -1) == 0
            if not active or not unlocked or not visible or mode is None:
                self.release()
                return GLib.SOURCE_CONTINUE

            state = self.call(self.mutter, "GetCurrentState").unpack()
            logicals = state[2]
            panel_logicals = [logical for logical in logicals
                              if any(spec[0] == "DSI-1" for spec in logical[5])]
            panel_only = (len(logicals) == 1 and len(panel_logicals) == 1
                          and len(panel_logicals[0][5]) == 1)
            if mode == "0":
                self.release()
                config_dir = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
                transform = laptop_rotation(config_dir / "monitors.xml", self.default_rotation)
            elif not panel_only or self.settings.get_boolean("orientation-lock"):
                self.release()
                return GLib.SOURCE_CONTINUE
            else:
                if not owner or not self.prop(self.sensor, "HasAccelerometer", False):
                    self.release()
                    return GLib.SOURCE_CONTINUE
                if not self.claim_owner:
                    self.call(self.sensor, "ClaimAccelerometer")
                    self.claim_owner = owner
                transform = ORIENTATIONS.get(self.prop(self.sensor, "AccelerometerOrientation"))
                if transform is None:
                    return GLib.SOURCE_CONTINUE

            request = rotation_config(state, transform)
            if request:
                serial, method, requested_logicals, properties = request
                for logical in requested_logicals:
                    for monitor in logical[5]:
                        for key, val in list(monitor[2].items()):
                            monitor[2][key] = GLib.Variant("b" if key == "underscanning" else "u", val)
                properties = {key: GLib.Variant("u", val) for key, val in properties.items()}
                self.call(self.mutter, "ApplyMonitorsConfig", GLib.Variant(
                    "(uua(iiduba(ssa{sv}))a{sv})",
                    (serial, method, requested_logicals, properties)))
            self.last_error = None
        except (GLib.Error, OSError, ValueError) as error:
            self.report(error)
        return GLib.SOURCE_CONTINUE

    def stop(self):
        self.release()
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def run(self):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.stop)
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self.stop)
        GLib.timeout_add(250, self.update)
        self.loop.run()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--laptop-rotation", choices=ROTATIONS, default="right")
    arguments = parser.parse_args()
    Posture(ROTATIONS[arguments.laptop_rotation]).run()
