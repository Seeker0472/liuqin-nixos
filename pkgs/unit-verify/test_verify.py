# SPDX-License-Identifier: MIT
"""Run the actual analyzer on positive and negative dependency graphs."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

VERIFIER, TRUE = sys.argv[1:3]
del sys.argv[1:3]


class VerifierTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.tree = Path(self.directory.name)
        for name in ("sysinit.target", "basic.target", "shutdown.target"):
            (self.tree / name).write_text("[Unit]\nDefaultDependencies=no\n")
        (self.tree / "default.target").write_text(
            "[Unit]\nDefaultDependencies=no\nRequires=ok.service\n")
        (self.tree / "ok.service").write_text(
            f"[Unit]\nDefaultDependencies=no\n[Service]\nExecStart={TRUE}\n")

    def verify(self):
        return subprocess.run([VERIFIER, str(self.tree)], capture_output=True, text=True)

    def test_valid_graph(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_incomplete_tree_fails(self):
        (self.tree / "sysinit.target").unlink()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete unit tree", result.stderr)

    def test_cycle_in_dropin_fails(self):
        (self.tree / "peer.service").write_text(
            f"[Unit]\nRequires=ok.service\nAfter=ok.service\n[Service]\nExecStart={TRUE}\n")
        dropin = self.tree / "ok.service.d"
        dropin.mkdir()
        (dropin / "overrides.conf").write_text("[Unit]\nRequires=peer.service\nAfter=peer.service\n")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ordering cycle", result.stderr)

    def test_missing_dependency_fails(self):
        (self.tree / "bad.target").write_text(
            "[Unit]\nDefaultDependencies=no\nRequires=missing.service\n")
        with (self.tree / "default.target").open("a") as unit:
            unit.write("Requires=bad.target\n")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_missing_executable_fails(self):
        (self.tree / "bad.service").write_text(
            "[Unit]\nDefaultDependencies=no\n"
            "[Service]\nExecStart=/not/a/real/executable\n")
        with (self.tree / "default.target").open("a") as unit:
            unit.write("Requires=bad.service\n")
        self.assertNotEqual(self.verify().returncode, 0)


if __name__ == "__main__":
    unittest.main()
