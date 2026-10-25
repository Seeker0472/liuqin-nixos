# SPDX-License-Identifier: MIT
"""Exercise the patched runtime without a tablet or a writable global path."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RUNTIME = Path(sys.argv.pop(1)).resolve()
spec = importlib.util.spec_from_file_location("oem_runtime_under_test", RUNTIME)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class Process:
    pid = 12345
    def __init__(self, running=False, result=0):
        self.running, self.result = running, result
    def poll(self):
        return None if self.running else self.result
    def terminate(self):
        self.running = False
    kill = terminate
    def wait(self, timeout=None):
        return self.result


class FirmwareTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.firmware = self.root / "private"
        self.lookup = self.root / "run/firmware"
        for path in (self.firmware, self.lookup):
            path.mkdir(parents=True)
            (path / "fpcliu.mdt").write_bytes(b"firmware fixture")
        manifest = {"fpcliu.mdt": hashlib.sha256(b"firmware fixture").hexdigest()}
        (self.firmware / "SHA256.json").write_text(json.dumps(manifest))
        self.parameter = self.root / "sys/module/firmware_class/parameters/path"
        self.parameter.parent.mkdir(parents=True)
        self.parameter.write_bytes(bytes(self.lookup) + b"\n")
        dev = self.root / "dev/fpc1020"
        dev.parent.mkdir(parents=True)
        dev.touch()
        power = self.root / "sys/bus/platform/drivers/fpc1020/device/power_state"
        power.parent.mkdir(parents=True)
        power.write_text("off\n")
        self.client_status = 0

    def mapped_path(self, path):
        string = str(path)
        if string.startswith(("/sys/", "/run/", "/dev/")):
            return self.root / string.lstrip("/")
        return Path(path)

    def popen(self, command, **kwargs):
        if "stdout" in kwargs:
            kwargs["stdout"].write(b"event=listener_registered\nevent=listener_registered\n")
            kwargs["stdout"].flush()
            return Process(running=True)
        return Process(result=self.client_status)

    def invoke(self):
        before = self.parameter.read_bytes()
        original_write = Path.write_bytes
        def forbid_parameter_write(path, data):
            if path == self.parameter:
                raise AssertionError("runtime attempted a global firmware-path write")
            return original_write(path, data)
        output = io.StringIO()
        with patch.object(runtime, "Path", self.mapped_path), \
             patch.object(runtime.os, "geteuid", return_value=0), \
             patch.dict(runtime.os.environ, {"LIUQIN_FPC_OEM_FIRMWARE": str(self.firmware)}), \
             patch.object(runtime.sys, "argv", [str(RUNTIME), "--template-inventory"]), \
             patch.object(runtime.signal, "signal"), \
             patch.object(runtime.subprocess, "Popen", side_effect=self.popen) as popen, \
             patch.object(Path, "write_bytes", forbid_parameter_write), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = runtime.main()
        self.assertEqual(self.parameter.read_bytes(), before)
        return result, output.getvalue(), popen.call_count

    def test_success_keeps_global_path(self):
        result, output, _ = self.invoke()
        self.assertEqual(result, 0, output)

    def test_client_failure_keeps_global_path(self):
        self.client_status = 1
        result, output, _ = self.invoke()
        self.assertEqual(result, 1, output)

    def test_wrong_lookup_path_rejects_before_starting_listener(self):
        self.parameter.write_bytes(b"/another/tree\n")
        result, _, calls = self.invoke()
        self.assertEqual((result, calls), (2, 0))

    def test_shadowed_firmware_rejects_before_starting_listener(self):
        (self.lookup / "fpcliu.mdt").write_bytes(b"wrong bytes")
        result, _, calls = self.invoke()
        self.assertEqual((result, calls), (2, 0))


if __name__ == "__main__":
    unittest.main()
