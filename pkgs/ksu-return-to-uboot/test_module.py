#!/usr/bin/env python3
"""Exercise the boot script with fake Android commands and a fake boot image."""

import gzip
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = (Path(__file__).parent / "boot-completed.sh").read_text()


class BootCompletedTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.calls = root / "calls"
        self.active = root / "active"
        self.active.write_text("0\n")
        self.image = root / "boot_b"
        self.image.write_bytes(
            b"ANDROID!" + bytes(4096 - 8) + gzip.compress(b"LIUQIN-UBOOT:")
        )
        self.getprop = root / "getprop"
        self.getprop.write_text(
            "#!/bin/sh\n"
            'case "$1" in\n'
            '  ro.product.device) echo "${MOCK_DEVICE:-liuqin}" ;;\n'
            '  sys.boot_completed) echo "${MOCK_COMPLETE:-1}" ;;\n'
            '  ro.boot.slot_suffix) echo "${MOCK_SLOT:-_a}" ;;\n'
            "esac\n"
        )
        self.bootctl = root / "bootctl"
        self.bootctl.write_text(
            "#!/bin/sh\n"
            'echo "$*" >> "$MOCK_CALLS"\n'
            'case "$1" in\n'
            '  hal-info) echo "HAL Version: android.hardware.boot@1.2::IBootControl" ;;\n'
            '  get-number-slots) echo 2 ;;\n'
            '  get-current-slot) echo 0 ;;\n'
            '  get-suffix) echo _b ;;\n'
            '  get-active-boot-slot) cat "$MOCK_ACTIVE" ;;\n'
            '  set-active-boot-slot)\n'
            '    [ "${MOCK_SET_FAIL:-0}" = 0 ] || exit 1\n'
            '    [ "${MOCK_READBACK_FAIL:-0}" = 1 ] || echo 1 > "$MOCK_ACTIVE" ;;\n'
            '  is-slot-bootable) [ "${MOCK_UNBOOTABLE:-0}" = 0 ] ;;\n'
            '  *) exit 1 ;;\n'
            "esac\n"
        )
        self.log = root / "log"
        self.log.write_text("#!/bin/sh\nexit 0\n")
        for command in (self.getprop, self.bootctl, self.log):
            command.chmod(0o755)
        script = SOURCE.replace("/system/bin/getprop", str(self.getprop))
        script = script.replace("/data/adb/ksu/bin/bootctl", str(self.bootctl))
        script = script.replace("/system/bin/log", str(self.log))
        script = script.replace("/dev/block/by-name/boot_b", str(self.image))
        script = script.replace("/dev/block/bootdevice/by-name/boot_b", str(self.image))
        script = script.replace('[ -b "$boot_b" ]', '[ -f "$boot_b" ]')
        self.script = root / "boot-completed.sh"
        self.script.write_text(script)

    def run_script(self, **overrides):
        env = os.environ.copy()
        env.update({"MOCK_CALLS": str(self.calls), "MOCK_ACTIVE": str(self.active)})
        env.update(overrides)
        return subprocess.run(
            ["sh", str(self.script)], env=env, capture_output=True, text=True
        )

    def calls_after(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_selects_b_and_checks_readback(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.active.read_text(), "1\n")
        self.assertIn("set-active-boot-slot 1", self.calls_after())
        self.assertIn("is-slot-bootable 1", self.calls_after())

    def test_device_and_boot_guards_do_not_write(self):
        for override in (
            {"MOCK_DEVICE": "other"},
            {"MOCK_COMPLETE": "0"},
            {"MOCK_SLOT": "_b"},
        ):
            with self.subTest(override=override):
                self.calls.unlink(missing_ok=True)
                self.assertNotEqual(self.run_script(**override).returncode, 0)
                self.assertNotIn("set-active-boot-slot 1", self.calls_after())
        self.image.write_bytes(b"NOTBOOT!")
        self.calls.unlink(missing_ok=True)
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertNotIn("set-active-boot-slot 1", self.calls_after())
        self.image.write_bytes(b"ANDROID!" + bytes(4096))
        self.calls.unlink(missing_ok=True)
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertNotIn("set-active-boot-slot 1", self.calls_after())

    def test_hal_failure_and_bad_readback_are_reported(self):
        for override in (
            {"MOCK_SET_FAIL": "1"},
            {"MOCK_READBACK_FAIL": "1"},
            {"MOCK_UNBOOTABLE": "1"},
        ):
            with self.subTest(override=override):
                self.active.write_text("0\n")
                result = self.run_script(**override)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("set-active-boot-slot 1", self.calls_after())


if __name__ == "__main__":
    unittest.main()
