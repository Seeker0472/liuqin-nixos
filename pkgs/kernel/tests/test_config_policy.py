# SPDX-License-Identifier: MIT
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "config_policy", Path(__file__).parents[1] / "check-config-policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.initial = {"DRM": "m", "USB_HOST": "y", "CAMERA": "m"}
        self.board = {"DRM": "y", "ZRAM": "m"}
        self.installer = {"USB_HOST": "n"}
        self.camera = {"CAMERA": "m"}
        self.rules = {
            "board": [{"from": "m", "to": "y", "reason": "early display", "symbols": ["DRM"]}],
            "installer": [{"from": "y", "to": "n", "reason": "gadget only", "symbols": ["USB_HOST"]}],
        }

    def audit(self):
        return policy.audit(self.initial, self.board, self.installer, self.camera, self.rules)

    def test_profiles_have_explicit_owners(self):
        installed, live = self.audit()
        self.assertEqual(installed, {"DRM": "y", "USB_HOST": "y", "CAMERA": "m", "ZRAM": "m"})
        self.assertEqual(live["USB_HOST"], "n")
        self.assertEqual(self.initial["DRM"], "m")

    def test_new_conflict_is_rejected(self):
        self.board["CAMERA"] = "y"
        with self.assertRaisesRegex(policy.PolicyError, "board: CONFIG_CAMERA"):
            self.audit()

    def test_stale_exception_is_rejected(self):
        self.initial["DRM"] = "y"
        with self.assertRaisesRegex(policy.PolicyError, "stale rule"):
            self.audit()

    def test_changed_installer_override_is_rejected(self):
        self.installer["USB_HOST"] = "m"
        with self.assertRaisesRegex(policy.PolicyError, "installer: CONFIG_USB_HOST"):
            self.audit()

    def test_installer_cannot_redeclare_common_owner(self):
        for value in ("y", "n"):
            with self.subTest(value=value):
                self.installer["DRM"] = value
                with self.assertRaisesRegex(policy.PolicyError, "repeats board-owned"):
                    self.audit()

    def test_camera_assertions_cannot_contradict_explicit_answers(self):
        self.initial["CAMERA"] = "n"
        with self.assertRaisesRegex(policy.PolicyError, "camera assertion CONFIG_CAMERA"):
            self.audit()

    def test_inherited_camera_requirement_is_reported_without_inventing_an_answer(self):
        del self.initial["CAMERA"]
        installed, live = self.audit()
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "ownership.tsv"
            policy.write_report(report, self.initial, self.board, self.installer,
                                self.camera, installed, live)
            self.assertIn("CAMERA\t-\t-\t-\t-\t-\tdefconfig/Kconfig\tdefconfig/Kconfig\tm", report.read_text())

    def test_exception_needs_a_reason(self):
        self.rules["board"][0]["reason"] = ""
        with self.assertRaisesRegex(policy.PolicyError, "reason"):
            self.audit()

    def test_duplicate_transition_rule_is_rejected(self):
        self.rules["board"].append(copy.deepcopy(self.rules["board"][0]))
        with self.assertRaisesRegex(policy.PolicyError, "duplicate transition"):
            self.audit()

    def test_evaluated_nix_overrides_are_unwrapped(self):
        self.assertEqual(policy.initial_answers({"DRM": {
            "_type": "override", "priority": 50,
            "content": {"tristate": "m", "optional": False}}}), {"DRM": "m"})

    def test_fragment_duplicate_even_with_same_value_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fragment.config"
            path.write_text("CONFIG_DRM=y\nCONFIG_DRM=y\n")
            with self.assertRaisesRegex(policy.PolicyError, "duplicate CONFIG_DRM"):
                policy.read_fragment(path)

    def test_fragment_typos_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fragment.config"
            for line in ("CONFIG_DRM=yes", "# CONFIG_DRM is not set trailing", "CONFIG_DRM = y"):
                with self.subTest(line=line):
                    path.write_text(line + "\n")
                    with self.assertRaisesRegex(policy.PolicyError, "invalid tristate"):
                        policy.read_fragment(path)

    def test_unset_and_comments_are_parsed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fragment.config"
            path.write_text("# Board policy\n# CONFIG_USB_HOST is not set\nCONFIG_ZRAM=m\n")
            self.assertEqual(policy.read_fragment(path), {"USB_HOST": "n", "ZRAM": "m"})

    def test_duplicate_json_rule_key_is_rejected(self):
        with self.assertRaisesRegex(policy.PolicyError, "duplicate JSON key"):
            json.loads('{"board": [], "board": []}', object_pairs_hook=policy.unique_object)


if __name__ == "__main__":
    unittest.main()
