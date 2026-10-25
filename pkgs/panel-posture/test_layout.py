# SPDX-License-Identifier: MIT
import copy
from pathlib import Path
import tempfile
import unittest

from layout import laptop_rotation, rotation_config


class LayoutTests(unittest.TestCase):
    def setUp(self):
        self.panel = ("DSI-1", "unknown", "unknown", "unknown")
        self.external = ("DP-1", "Vendor", "Monitor", "serial")
        self.panel_monitor = (self.panel, [
            ("wrong-first-mode", 1800, 2880, 60.0, 2.0, [1.0, 2.0], {"is-current": False}),
            ("current-120Hz", 1800, 2880, 120.0, 2.0, [1.0, 2.0], {"is-current": True}),
        ], {"is-underscanning": False, "color-mode": 1})
        self.external_monitor = (self.external, [
            ("external-60Hz", 2560, 1600, 60.0, 2.0, [1.0, 2.0], {"is-current": True}),
        ], {"color-mode": 2})
        self.state = (42, [self.panel_monitor],
                      [(0, 0, 2.0, 0, True, [self.panel], {})], {"layout-mode": 1})

    def test_preserves_single_panel_mode_scale_and_properties(self):
        before = copy.deepcopy(self.state)
        serial, method, logicals, properties = rotation_config(self.state, 3)
        self.assertEqual((serial, method, properties), (42, 1, {"layout-mode": 1}))
        self.assertEqual(logicals, [(0, 0, 2.0, 3, True,
            [("DSI-1", "current-120Hz", {"underscanning": False, "color-mode": 1})])])
        self.assertEqual(self.state, before)

    def test_extended_desktop_moves_right_monitor_and_preserves_it(self):
        self.state = (42, [self.panel_monitor, self.external_monitor], [
            (0, 0, 2.0, 0, True, [self.panel], {}),
            (900, 0, 2.0, 0, False, [self.external], {}),
        ], {"layout-mode": 1})
        _, _, logicals, _ = rotation_config(self.state, 3)
        self.assertEqual(logicals[0][0:5], (0, 0, 2.0, 3, True))
        self.assertEqual(logicals[1], (1440, 0, 2.0, 0, False,
            [("DP-1", "external-60Hz", {"color-mode": 2})]))

    def test_extended_desktop_moves_monitor_below_panel(self):
        self.state = (42, [self.panel_monitor, self.external_monitor], [
            (0, 0, 2.0, 0, True, [self.panel], {}),
            (0, 1440, 2.0, 0, False, [self.external], {}),
        ], {"layout-mode": 1})
        _, _, logicals, _ = rotation_config(self.state, 3)
        self.assertEqual(logicals[1][0:2], (0, 900))

    def test_mirrored_desktop_is_untouched(self):
        self.state = (42, [self.panel_monitor, self.external_monitor],
                      [(0, 0, 2.0, 0, True, [self.panel, self.external], {})],
                      {"layout-mode": 1})
        self.assertIsNone(rotation_config(self.state, 3))

    def test_already_rotated_is_noop(self):
        state = list(self.state)
        state[2] = [(0, 0, 2.0, 3, True, [self.panel], {})]
        self.assertIsNone(rotation_config(tuple(state), 3))

    def test_absent_current_mode_is_untouched(self):
        self.panel_monitor[1][1][6]["is-current"] = False
        self.assertIsNone(rotation_config(self.state, 3))

    def test_xml_uses_panel_only_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "monitors.xml"
            path.write_text('''<monitors><configuration><logicalmonitor>
              <transform><rotation>left</rotation></transform>
              <monitor><monitorspec><connector>DP-1</connector></monitorspec></monitor>
              </logicalmonitor></configuration><configuration><logicalmonitor>
              <transform><rotation>right</rotation></transform>
              <monitor><monitorspec><connector>DSI-1</connector></monitorspec></monitor>
              </logicalmonitor></configuration></monitors>''')
            self.assertEqual(laptop_rotation(path, 0), 3)
            path.write_text("invalid XML")
            self.assertEqual(laptop_rotation(path, 1), 1)


if __name__ == "__main__":
    unittest.main()
