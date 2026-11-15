#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("helper", Path(__file__).parents[1] / "display-helper.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def reply(output, code=0):
    return subprocess.CompletedProcess([], code, output)


class HelperTests(unittest.TestCase):
    def test_failed_commit_is_reported_without_retry(self):
        with patch.object(helper.subprocess, "run", side_effect=[
            reply("FAILED (remote: display check/commit failed)", 1),
            reply("display-count: 2\nFinished. Total time: 0.001s"),
            reply("(bootloader) display0: v1 state=failed\n"),
            reply("display1: stage=phy error=-5 host=1\n"),
        ]) as call:
            code, result = helper.run(["fastboot", "-s", "test"], "quiesce")
        self.assertEqual(code, 1)
        self.assertFalse(result["command_ok"])
        self.assertEqual(len(result["report"]), 2)
        self.assertEqual(call.call_count, 4)
        self.assertEqual(call.call_args_list[0].args[0],
                         ["fastboot", "-s", "test", "oem", "board:display-quiesce"])

    def test_count_is_bounded(self):
        for count in ["0", "33", "-1", "1garbage"]:
            with self.subTest(count=count), patch.object(helper.subprocess, "run", side_effect=[
                reply("OKAY"), reply("display-count: " + count),
            ]) as call:
                with self.assertRaises(ValueError):
                    helper.run(["fastboot"], "status")
                self.assertEqual(call.call_count, 2)

    def test_transport_timeout_does_not_retry(self):
        with patch.object(helper.subprocess, "run", side_effect=subprocess.TimeoutExpired("fastboot", 15)) as call:
            with self.assertRaises(subprocess.TimeoutExpired):
                helper.run(["fastboot"], "quiesce")
            self.assertEqual(call.call_count, 1)

    def test_ambiguous_response_is_rejected(self):
        with patch.object(helper.subprocess, "run", return_value=reply("display0: a\ndisplay0: b")):
            with self.assertRaises(ValueError):
                helper.getvar(["fastboot"], "display0")


if __name__ == "__main__":
    unittest.main()
