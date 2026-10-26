# SPDX-License-Identifier: MIT
"""Exercise lid transitions without a running GNOME or system bus."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from gi.repository import GLib
from main import LidPolicy


class Proxy:
    def __init__(self, properties=None, on_call=None):
        self.owner = ":1.10"
        self.properties = properties or {}
        self.calls = []
        self.on_call = on_call

    def get_name_owner(self):
        return self.owner

    def get_cached_property(self, name):
        return self.properties.get(name)

    def call_sync(self, method, parameters, *args):
        self.calls.append((method, parameters))
        if self.on_call:
            self.on_call(method, parameters)
        return GLib.Variant("()", ())


class LidPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        client = object.__new__(LidPolicy)
        self.client = client
        client.marker = Path(self.temporary.name) / "display-blanked"
        client.applied = None
        client.next_update = 0
        client.last_error = None
        client.upower = Proxy({
            "LidIsPresent": GLib.Variant("b", True),
            "LidIsClosed": GLib.Variant("b", False),
        })
        client.session = Proxy({"SessionIsActive": GLib.Variant("b", True)})
        client.screensaver = Proxy()
        client.mutter = Proxy({"PowerSaveMode": GLib.Variant("i", 0)})

        def set_property(method, parameters):
            if method != "Set":
                return
            interface, name, value = parameters.unpack()
            self.assertEqual(interface, "org.gnome.Mutter.DisplayConfig")
            self.assertEqual(name, "PowerSaveMode")
            client.mutter.properties[name] = GLib.Variant("i", value)

        client.display_properties = Proxy(on_call=set_property)

    def update(self):
        self.client.next_update = 0
        self.client.update()

    def power_modes(self):
        return [parameters.unpack()[2]
                for method, parameters in self.client.display_properties.calls
                if method == "Set"]

    def set_closed(self, closed):
        self.client.upower.properties["LidIsClosed"] = GLib.Variant("b", closed)

    def test_initial_open_lid_does_not_wake_manually_blanked_display(self):
        self.client.mutter.properties["PowerSaveMode"] = GLib.Variant("i", 3)
        self.update()
        self.assertEqual(self.power_modes(), [])
        self.assertFalse(self.client.marker.exists())

    def test_close_locks_then_blanks_and_open_only_unblanks(self):
        self.set_closed(True)
        self.update()
        self.assertEqual([method for method, _ in self.client.screensaver.calls], ["Lock"])
        self.assertEqual(self.power_modes(), [3])
        self.assertTrue(self.client.marker.exists())

        self.update()
        self.assertEqual(self.power_modes(), [3])

        self.set_closed(False)
        self.update()
        self.assertEqual(self.power_modes(), [3, 0])
        self.assertEqual([method for method, _ in self.client.screensaver.calls], ["Lock"])
        self.assertFalse(self.client.marker.exists())

    def test_closed_lid_reblanks_display_turned_on_elsewhere(self):
        self.set_closed(True)
        self.update()
        self.client.mutter.properties["PowerSaveMode"] = GLib.Variant("i", 0)
        self.update()
        self.assertEqual(self.power_modes(), [3, 3])
        self.assertEqual([method for method, _ in self.client.screensaver.calls],
                         ["Lock", "Lock"])

    def test_inactive_session_waits_then_applies_current_lid_state(self):
        self.client.session.properties["SessionIsActive"] = GLib.Variant("b", False)
        self.set_closed(True)
        self.update()
        self.assertEqual(self.power_modes(), [])

        self.client.session.properties["SessionIsActive"] = GLib.Variant("b", True)
        self.update()
        self.assertEqual(self.power_modes(), [3])

    def test_restart_with_marker_and_open_lid_restores_display(self):
        self.client.marker.touch()
        self.client.mutter.properties["PowerSaveMode"] = GLib.Variant("i", 3)
        self.update()
        self.assertEqual(self.power_modes(), [0])
        self.assertFalse(self.client.marker.exists())


if __name__ == "__main__":
    unittest.main()
