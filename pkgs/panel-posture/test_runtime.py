# SPDX-License-Identifier: MIT
"""Exercise claim ownership and typed calls without the host's D-Bus."""
import unittest
from unittest.mock import patch

from gi.repository import Gio, GLib
from main import Posture


class Proxy:
    def __init__(self, properties=None, state=None):
        self.owner = ":1.10"
        self.properties = properties or {}
        self.state = state
        self.calls = []
        self.locked = False

    def get_name_owner(self):
        return self.owner

    def get_cached_property(self, name):
        return self.properties.get(name)

    def call_sync(self, method, parameters, *args):
        self.calls.append((method, parameters))
        if method == "GetActive":
            return GLib.Variant("(b)", (self.locked,))
        if method == "GetCurrentState":
            return GLib.Variant("(ua((ssss)a(siiddada{sv})a{sv})a(iiduba(ssss)a{sv})a{sv})", self.state)
        return GLib.Variant("()", ())


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.client = object.__new__(Posture)
        client = self.client
        client.claim_owner = client.previous = client.last_error = None
        client.next_update = 0
        client.default_rotation = 3
        self.mode = "1"
        client.posture = lambda: self.mode
        self.rotation_locked = False
        client.settings = type("Settings", (), {"get_boolean": lambda _, key: self.rotation_locked})()
        client.sensor = Proxy({"HasAccelerometer": GLib.Variant("b", True),
                               "AccelerometerOrientation": GLib.Variant("s", "normal")})
        client.session = Proxy({"SessionIsActive": GLib.Variant("b", True)})
        client.screensaver = Proxy()
        self.panel = ("DSI-1", "unknown", "unknown", "unknown")
        self.external = ("DP-1", "vendor", "product", "serial")
        panel_monitor = (self.panel, [("1800x2880@120", 1800, 2880, 120.0, 2.0, [2.0],
                         {"is-current": GLib.Variant("b", True)})],
                         {"color-mode": GLib.Variant("u", 1)})
        state = (42, [panel_monitor], [(0, 0, 2.0, 3, True, [self.panel], {})],
                 {"layout-mode": GLib.Variant("u", 1)})
        client.mutter = Proxy({"PowerSaveMode": GLib.Variant("i", 0)}, state)

    def update(self):
        self.client.next_update = 0
        self.client.update()

    def sensor_methods(self):
        return [method for method, _ in self.client.sensor.calls]

    def requests(self):
        return [params.unpack() for method, params in self.client.mutter.calls
                if method == "ApplyMonitorsConfig"]

    def test_rotation_lock_schema_is_packaged(self):
        settings = Gio.Settings.new("org.gnome.settings-daemon.peripherals.touchscreen")
        self.assertIsInstance(settings.get_boolean("orientation-lock"), bool)

    def test_claim_once_and_send_typed_temporary_configuration(self):
        self.update()
        self.update()
        self.assertEqual(self.sensor_methods(), ["ClaimAccelerometer"])
        self.assertEqual(self.requests()[0], (42, 1, [(0, 0, 2.0, 0, True,
            [("DSI-1", "1800x2880@120", {"color-mode": 1})])], {"layout-mode": 1}))

    def test_proxy_restart_reclaims_from_new_owner(self):
        self.update()
        self.client.sensor.owner = ":1.20"
        self.update()
        self.assertEqual(self.sensor_methods(), ["ClaimAccelerometer", "ClaimAccelerometer"])

    def test_rotation_lock_releases_claim(self):
        self.update()
        self.rotation_locked = True
        self.update()
        self.assertEqual(self.sensor_methods(), ["ClaimAccelerometer", "ReleaseAccelerometer"])

    def test_inactive_session_releases_claim(self):
        self.update()
        self.client.session.properties["SessionIsActive"] = GLib.Variant("b", False)
        self.update()
        self.assertEqual(self.sensor_methods()[-1], "ReleaseAccelerometer")

    def test_laptop_posture_releases_claim(self):
        self.update()
        self.mode = "0"
        with patch("main.laptop_rotation", return_value=3):
            self.update()
        self.assertEqual(self.sensor_methods()[-1], "ReleaseAccelerometer")

    def test_laptop_posture_preserves_external_layout(self):
        external_monitor = (self.external, [("2560x1600@60", 2560, 1600, 60.0, 2.0, [2.0],
                            {"is-current": GLib.Variant("b", True)})], {})
        state = list(self.client.mutter.state)
        state[1] = list(state[1]) + [external_monitor]
        state[2] = [
            (0, 0, 2.0, 0, True, [self.panel], {}),
            (900, 0, 2.0, 0, False, [self.external], {}),
        ]
        self.client.mutter.state = tuple(state)
        self.mode = "0"
        with patch("main.laptop_rotation", return_value=3):
            self.update()
        self.assertEqual(self.requests()[0][2][1][0], 1440)
        self.assertEqual(self.requests()[0][2][1][5][0][0], "DP-1")

    def test_tablet_posture_leaves_external_layout_untouched(self):
        state = list(self.client.mutter.state)
        state[2] = list(state[2]) + [(1440, 0, 1.0, 0, False, [self.external], {})]
        self.client.mutter.state = tuple(state)
        self.update()
        self.assertEqual(self.sensor_methods(), [])
        self.assertEqual(self.requests(), [])

    def test_locked_session_releases_claim(self):
        self.update()
        self.client.screensaver.locked = True
        self.update()
        self.assertEqual(self.sensor_methods()[-1], "ReleaseAccelerometer")


if __name__ == "__main__":
    unittest.main()
