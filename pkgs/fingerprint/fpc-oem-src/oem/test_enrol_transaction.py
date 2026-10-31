#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Non-hardware regression coverage for private enrolment custody."""
import contextlib
import errno
import hashlib
import io
import os
import json
from pathlib import Path
import struct
import tempfile
import time
import types
import unittest
from unittest import mock

from enrol_transaction import ExportUncertain, PendingTransaction
import acceptance_input
from acceptance_input import PreparedInputExpired, PreparedInputMissing
from user_credentials import (CredentialFailure, account_status, stream_enrol_line,
                              validate_parameters)


class EnrolProtocolTests(unittest.TestCase):
    def test_subsequent_capture_attempt_does_not_restart_desktop_enrolment(self):
        output = io.StringIO()
        native_lines = (
            "READY enrol attempt=1: press same finger and hold",
            "enrol_progress_status=1 remaining=19",
            "READY lift finger and reposition for next sample",
            "READY enrol attempt=2: press same finger and hold",
            "capture_rejected=4 enrol_not_sent=1",
            "READY lift finger and reposition for next sample",
            "READY enrol attempt=3: press same finger and hold",
            "enrol_progress_status=1 remaining=18",
        )
        with contextlib.redirect_stdout(output):
            for line in native_lines:
                stream_enrol_line(line)
        self.assertEqual(output.getvalue().count("kind=ready\n"), 1)
        self.assertEqual(output.getvalue().count("kind=sample"), 2)
        self.assertIn("kind=retry code=capture_rejected\n", output.getvalue())

    def test_native_failure_phase_exposes_no_untrusted_diagnostics(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            stream_enrol_line("command=11 subcommand=20")
            stream_enrol_line("tee_ret=0 origin=0 response_status=-38 status_hex=ffffffda")
            stream_enrol_line("tee_ret=0 origin=0 response_status=-38 status_hex=00000000")
            stream_enrol_line("command=11 subcommand=20 private_data=secret")
            stream_enrol_line("keymaster_input=secret")
            stream_enrol_line("pipeline_incomplete=finger_down_wait")
        self.assertEqual(output.getvalue(),
                         "fpc_event=1 kind=phase code=set_gid\n"
                         "fpc_event=1 kind=ta_reject status=-38\n"
                         "fpc_event=1 kind=phase code=sensor_wait\n")


class AccountValidationTests(unittest.TestCase):
    def test_renamed_account_has_distinct_error_before_prepared_input(self):
        account = types.SimpleNamespace(pw_name="renamed", pw_uid=1000)
        old = {"schema": 1, "linux_username": "old-name", "linux_uid": 1000,
               "native_uid": 0x500003e8, "kdf": "PBKDF2-HMAC-SHA256",
               "iterations": 600000, "input_bytes": 32}
        with self.assertRaises(CredentialFailure) as failure:
            validate_parameters(old, account, 0x500003e8)
        self.assertEqual(failure.exception.code, "account_mismatch")

    def test_invalid_parameters_are_not_account_mismatch(self):
        account = types.SimpleNamespace(pw_name="alice", pw_uid=1000)
        with self.assertRaises(CredentialFailure) as failure:
            validate_parameters({"schema": 1}, account, 0x500003e8)
        self.assertEqual(failure.exception.code, "parameters_invalid")

    def test_removed_account_status_has_no_keyring_or_hardware_call(self):
        with mock.patch("user_credentials.pwd.getpwnam", side_effect=KeyError):
            self.assertEqual(account_status("old-name", Path("/nonexistent")), "account_mismatch")


@unittest.skipUnless(os.geteuid() == 0, "prepared metadata must be owned by root")
class PreparedInputTests(unittest.TestCase):
    def test_missing_key_and_expired_preparation_have_distinct_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            metadata = Path(directory) / "acceptance-alice.json"
            with mock.patch.object(acceptance_input, "context",
                                   return_value=(None, None, None, metadata)):
                with self.assertRaises(PreparedInputMissing):
                    acceptance_input.consume("alice", 0x500003e8)
                metadata.write_text(json.dumps({
                    "schema": 1, "username": "alice", "native_uid": 0x500003e8,
                    "boot_id": "stale-boot", "expires": 1, "key_serial": 1}))
                os.chmod(metadata, 0o600)
                with self.assertRaises(PreparedInputExpired):
                    acceptance_input.consume("alice", 0x500003e8)

                metadata.write_text(json.dumps({
                    "schema": 1, "username": "alice", "native_uid": 0x500003e8,
                    "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                    "expires": int(time.time()) + 3600, "key_serial": 1}))
                libc = types.SimpleNamespace(mlock=lambda *_: 0, munlock=lambda *_: 0)
                keys = types.SimpleNamespace(keyctl_read=lambda *_: -1)
            with mock.patch.object(acceptance_input, "context",
                                   return_value=(libc, keys, None, metadata)), \
                 mock.patch.object(acceptance_input.ctypes, "get_errno", return_value=errno.ENOKEY):
                with self.assertRaises(PreparedInputMissing):
                    acceptance_input.consume("alice", 0x500003e8)


@unittest.skipUnless(os.geteuid() == 0, "private state must be owned by root")
class TransactionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "pending"
        self.transaction = PendingTransaction("alice", "right-index-finger", root=self.root)
        self.addCleanup(self.transaction.close)
        self.output_dir = Path(self.temporary.name) / "output"
        self.output_dir.mkdir(mode=0o700)
        self.output = self.output_dir / "single-finger.db"

    def test_accepted_export_replays_without_new_uncertainty_marker(self):
        self.transaction.begin()
        self.transaction.database.write_bytes(b"opaque export")
        os.chmod(self.transaction.database, 0o600)
        self.transaction.commit()
        self.assertTrue(self.transaction.accepted())
        self.transaction.publish(self.output)
        self.assertEqual(self.output.read_bytes(), b"opaque export")
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)
        self.assertTrue(self.transaction.database.exists())
        self.assertTrue(self.transaction.ready.exists())
        self.assertFalse(self.transaction.uncertain.exists())

    def test_uncertainty_blocks_replay_without_erase(self):
        self.transaction.begin()
        with self.assertRaises(ExportUncertain):
            self.transaction.begin()
        self.assertTrue(self.transaction.uncertain.exists())

    def test_bad_ack_preserves_pending(self):
        self.transaction.begin()
        self.transaction.database.write_bytes(b"opaque export")
        os.chmod(self.transaction.database, 0o600)
        self.transaction.commit()
        with self.assertRaises(ExportUncertain):
            self.transaction.ack("0" * 64)
        self.assertTrue(self.transaction.database.exists())
        self.assertTrue(self.transaction.ready.exists())
        self.transaction.ack(hashlib.sha256(b"opaque export").hexdigest())
        self.assertFalse(self.transaction.database.exists())
        self.assertFalse(self.transaction.ready.exists())

    def test_interrupted_ack_recovers_without_replaying_or_losing_export(self):
        self.transaction.begin()
        self.transaction.database.write_bytes(b"opaque export")
        os.chmod(self.transaction.database, 0o600)
        self.transaction.commit()
        digest = hashlib.sha256(b"opaque export").hexdigest()
        unlink = os.unlink

        def interrupted(path):
            if path == self.transaction.ready:
                raise OSError("interrupted after database unlink")
            return unlink(path)

        with mock.patch("enrol_transaction.os.unlink", side_effect=interrupted):
            with self.assertRaises(OSError):
                self.transaction.ack(digest)
        self.assertTrue(self.transaction.acknowledged.exists())
        self.assertTrue(self.transaction.ready.exists())
        self.assertFalse(self.transaction.database.exists())
        with self.assertRaises(ExportUncertain):
            self.transaction.ack("0" * 64)
        self.assertTrue(self.transaction.ready.exists())
        self.assertFalse(self.transaction.accepted())
        self.assertFalse(self.transaction.acknowledged.exists())
        self.assertFalse(self.transaction.ready.exists())
        self.transaction.begin()
        self.assertTrue(self.transaction.uncertain.exists())

    def test_other_finger_cannot_restart_enrolment(self):
        self.transaction.begin()
        other = PendingTransaction("alice", "left-thumb", root=self.root)
        try:
            with self.assertRaises(ExportUncertain):
                other.begin()
            self.assertFalse(other.uncertain.exists())
        finally:
            other.close()

    def test_legacy_account_level_export_blocks_new_ta_without_deletion(self):
        legacy = self.root / "alice" / "single-finger.db"
        legacy.write_bytes(b"legacy opaque export")
        os.chmod(legacy, 0o600)
        with self.assertRaises(ExportUncertain):
            self.transaction.begin()
        self.assertEqual(legacy.read_bytes(), b"legacy opaque export")
        self.assertFalse(self.transaction.uncertain.exists())


@unittest.skipUnless(os.geteuid() == 0, "private state must be owned by root")
class GalleryTransactionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "pending"
        self.output_dir = Path(temporary.name) / "output"
        self.output_dir.mkdir(mode=0o700)
        self.original_digest = hashlib.sha256(b"prior gallery").hexdigest()
        self.transaction = PendingTransaction("alice", "left-thumb", root=self.root,
                                              gallery=True, base_digest=self.original_digest)
        self.addCleanup(lambda: self.transaction.close() if self.transaction else None)
        self.data = b"opaque two-template gallery"
        self.identities = struct.pack("<7I", 2, 82, 71, 82, 0, 0, 0)
        self.db_output = self.output_dir / "gallery.db"
        self.id_output = self.output_dir / "gallery-ids.bin"

    def accepted_export(self):
        self.transaction.begin()
        self.transaction.database.write_bytes(self.data)
        self.transaction.ids.write_bytes(self.identities)
        os.chmod(self.transaction.database, 0o600)
        os.chmod(self.transaction.ids, 0o600)
        self.transaction.commit()

    def test_multi_gallery_replay_requires_same_original_and_cleans_both_on_ack(self):
        self.accepted_export()
        # The per-finger lock prevents concurrent workers. A changed original
        # is checked when a later worker retries this accepted export.
        self.transaction.close()
        self.transaction = None
        with self.assertRaises(ExportUncertain):
            different = PendingTransaction("alice", "left-thumb", root=self.root,
                                           gallery=True, base_digest="0" * 64)
            try:
                different.accepted()
            finally:
                different.close()
        replay = PendingTransaction("alice", "left-thumb", root=self.root,
                                    gallery=True, base_digest=self.original_digest)
        try:
            self.assertTrue(replay.accepted())
            replay.publish(self.db_output, self.id_output)
            self.assertEqual(self.db_output.read_bytes(), self.data)
            self.assertEqual(self.id_output.read_bytes(), self.identities)
            replay.ack(hashlib.sha256(self.data).hexdigest())
            self.assertFalse(replay.database.exists())
            self.assertFalse(replay.ids.exists())
            self.assertFalse(replay.ready.exists())
        finally:
            replay.close()

    def test_corrupt_identity_export_cannot_be_accepted_or_acknowledged(self):
        self.accepted_export()
        self.transaction.ids.write_bytes(struct.pack("<7I", 2, 82, 71, 71, 0, 0, 0))
        with self.assertRaises(ExportUncertain):
            self.transaction.accepted()
        with self.assertRaises(ExportUncertain):
            self.transaction.ack(hashlib.sha256(self.data).hexdigest())
        self.assertTrue(self.transaction.ready.exists())
        self.assertTrue(self.transaction.database.exists())
        self.assertFalse(self.db_output.exists())

    def test_interrupted_gallery_ack_finishes_identity_cleanup_on_next_open(self):
        self.accepted_export()
        digest = hashlib.sha256(self.data).hexdigest()
        unlink = os.unlink

        def interrupt(path):
            if path == self.transaction.ready:
                raise OSError("interrupted between gallery unlink and marker cleanup")
            return unlink(path)

        with mock.patch("enrol_transaction.os.unlink", side_effect=interrupt):
            with self.assertRaises(OSError):
                self.transaction.ack(digest)
        self.assertTrue(self.transaction.acknowledged.exists())
        self.assertFalse(self.transaction.database.exists())
        self.assertFalse(self.transaction.ids.exists())
        self.transaction.close()
        self.transaction = None
        resumed = PendingTransaction("alice", "left-thumb", root=self.root, create=False)
        try:
            self.assertFalse(resumed.accepted())
            self.assertFalse(resumed.acknowledged.exists())
            self.assertFalse(resumed.ready.exists())
        finally:
            resumed.close()


if __name__ == "__main__":
    unittest.main()
