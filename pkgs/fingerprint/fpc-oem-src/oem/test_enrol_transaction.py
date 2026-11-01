#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Non-hardware regression coverage for private enrolment custody."""
import contextlib
import ctypes
import errno
import hashlib
import io
import os
import json
from pathlib import Path
import select
import struct
import stat
import tempfile
import threading
import time
import types
import unittest
from unittest import mock

from enrol_transaction import ExportUncertain, PendingTransaction
import acceptance_input
from acceptance_input import PreparedInputExpired, PreparedInputMissing
from user_credentials import (CredentialFailure, account_status, await_custody,
                              stream_enrol_line, validate_parameters)


class EnrolProtocolTests(unittest.TestCase):
    def test_readiness_is_emitted_only_after_each_arm(self):
        output = io.StringIO()
        native_lines = (
            "WAIT enrol attempt=1: arming finger capture",
            "READY enrol attempt=1: press same finger and hold",
            "READY finger_wait_armed=down place or hold finger for capture",
            "enrol_progress_status=1 remaining=19",
            "WAIT lift finger before next sample",
            "WAIT enrol attempt=2: arming finger capture",
            "READY finger_wait_armed=down place or hold finger for capture",
            "capture_rejected=4 enrol_not_sent=1",
            "WAIT lift finger before next sample",
            "WAIT enrol attempt=3: arming finger capture",
            "READY finger_wait_armed=down place or hold finger for capture",
            "enrol_progress_status=1 remaining=18",
        )
        with contextlib.redirect_stdout(output):
            for line in native_lines:
                stream_enrol_line(line)
        self.assertEqual(output.getvalue().splitlines(), [
            "fpc_event=1 kind=ready",
            "fpc_event=1 kind=sample status=1 remaining=19",
            "fpc_event=1 kind=lift",
            "fpc_event=1 kind=ready",
            "fpc_event=1 kind=retry code=capture_rejected",
            "fpc_event=1 kind=lift",
            "fpc_event=1 kind=ready",
            "fpc_event=1 kind=sample status=1 remaining=18",
        ])

    def test_ta_status_not_remaining_decides_the_final_sample(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            stream_enrol_line("enrol_progress_status=0 remaining=0")
            stream_enrol_line("enrol_progress_status=0 remaining=19")
            stream_enrol_line("enrol_progress_status=1 remaining=0")
        self.assertEqual(output.getvalue().splitlines(), [
            "fpc_event=1 kind=sample status=0 remaining=0",
            "fpc_event=1 kind=sample status=0 remaining=19",
            "fpc_event=1 kind=sample status=1 remaining=0",
        ])

    def test_end_enrol_hints_do_not_arm_the_custody_marker(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertIsNone(stream_enrol_line("command=11 subcommand=3"))
            self.assertIsNone(stream_enrol_line("enrol_authorization_phase=end_enrol"))
            self.assertIsNone(stream_enrol_line("command=11 subcommand=2"))
        self.assertEqual(output.getvalue(), "fpc_event=1 kind=phase code=end_enrol\n"
                                             "fpc_event=1 kind=finalizing\n"
                                             "fpc_event=1 kind=phase code=sample\n")

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

    def test_repeated_authenticated_preparation_keeps_matching_one_use_key(self):
        with tempfile.TemporaryDirectory() as directory:
            metadata = Path(directory) / "acceptance-alice.json"
            metadata.write_text(json.dumps({
                "schema": 1, "username": "alice", "native_uid": 0x500003e8,
                "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                "expires": int(time.time()) + 3600, "key_serial": 41}))
            os.chmod(metadata, 0o600)
            key = b"a" * 32
            def read_key(serial, buffer, size):
                self.assertEqual(serial, 41)
                ctypes.memmove(buffer, key, size)
                return size
            keys = types.SimpleNamespace(keyctl_read=read_key)
            libc = types.SimpleNamespace(mlock=lambda *_: 0, munlock=lambda *_: 0,
                                         read=lambda fd, buffer, size: self._read(fd, buffer, size),
                                         memcmp=lambda a, b, size: ctypes.string_at(a, size) != ctypes.string_at(b, size))
            descriptor = os.memfd_create("test-authenticated-input")
            try:
                os.write(descriptor, key)
                original = metadata.read_bytes()
                with mock.patch.object(acceptance_input, "context",
                                       return_value=(libc, keys, 17, metadata)):
                    acceptance_input.prepare("alice", 0x500003e8, descriptor)
                self.assertEqual(metadata.read_bytes(), original)
            finally:
                os.close(descriptor)

    def test_freshly_verified_input_replaces_expired_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            metadata = Path(directory) / "acceptance-alice.json"
            metadata.write_text(json.dumps({
                "schema": 1, "username": "alice", "native_uid": 0x500003e8,
                "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                "expires": 1, "key_serial": 41}))
            os.chmod(metadata, 0o600)
            new_key = b"b" * 32
            stored = {}
            def add_key(_type, _description, buffer, size, _ring):
                stored["input"] = ctypes.string_at(buffer, size)
                return 42
            def read_key(serial, buffer, size):
                self.assertEqual(serial, 42)
                ctypes.memmove(buffer, stored["input"], size)
                return size
            revoked = []
            keys = types.SimpleNamespace(
                keyctl_search=lambda *_: 41,
                keyctl_revoke=lambda serial: revoked.append(serial) or 0,
                keyctl_unlink=lambda *_: 0,
                add_key=add_key, keyctl_setperm=lambda *_: 0,
                keyctl_set_timeout=lambda *_: 0, keyctl_read=read_key)
            libc = types.SimpleNamespace(mlock=lambda *_: 0, munlock=lambda *_: 0,
                                         read=lambda fd, buffer, size: self._read(fd, buffer, size),
                                         memcmp=lambda a, b, size: ctypes.string_at(a, size) != ctypes.string_at(b, size))
            descriptor = os.memfd_create("test-renewed-input")
            try:
                os.write(descriptor, new_key)
                with mock.patch.object(acceptance_input, "context",
                                       return_value=(libc, keys, 17, metadata)):
                    acceptance_input.prepare("alice", 0x500003e8, descriptor)
                updated = json.loads(metadata.read_text())
                self.assertEqual(updated["key_serial"], 42)
                self.assertGreater(updated["expires"], time.time())
                self.assertEqual(stored["input"], new_key)
                self.assertEqual(revoked, [41])
            finally:
                os.close(descriptor)

    @staticmethod
    def _read(descriptor, buffer, size):
        data = os.read(descriptor, size)
        ctypes.memmove(buffer, data, len(data))
        return len(data)


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

    def _gate(self, cancelled=lambda: False):
        request_read, request_write = os.pipe()
        ack_read, ack_write = os.pipe()
        errors = []

        def serve():
            try:
                await_custody(request_read, ack_write, self.transaction.arm, cancelled)
            except BaseException as error:
                errors.append(error)
            finally:
                os.close(request_read)
                os.close(ack_write)

        thread = threading.Thread(target=serve)
        thread.start()
        self.addCleanup(lambda: thread.join(timeout=2))
        self.addCleanup(lambda: os.close(ack_read))
        self.addCleanup(lambda: os.close(request_write))
        return request_write, ack_read, thread, errors

    def test_custody_ack_is_blocked_until_marker_directory_sync_finishes(self):
        self.transaction.begin()
        request_write, ack_read, thread, errors = self._gate()
        syncing = threading.Event()
        release = threading.Event()
        original_sync = os.fsync
        synced = []

        def sync(fd):
            is_directory = stat.S_ISDIR(os.fstat(fd).st_mode)
            synced.append("directory" if is_directory else "marker")
            if is_directory:
                syncing.set()
                if not release.wait(timeout=3):
                    raise TimeoutError("directory sync gate never released")
            return original_sync(fd)

        try:
            with mock.patch("enrol_transaction.os.fsync", side_effect=sync):
                os.write(request_write, b"M")
                self.assertTrue(syncing.wait(timeout=3))
                self.assertTrue(self.transaction.uncertain.exists())
                self.assertEqual(synced, ["marker", "directory"])
                self.assertFalse(select.select([ack_read], [], [], 0.05)[0],
                                 "native client must not advance before directory fsync")
                release.set()
                self.assertEqual(os.read(ack_read, 1), b"A")
                thread.join(timeout=3)
        finally:
            release.set()
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])

    def test_cancelled_gate_has_no_marker_and_no_ack(self):
        self.transaction.begin()
        request_write, ack_read, thread, errors = self._gate(lambda: True)
        os.write(request_write, b"M")
        self.assertEqual(os.read(ack_read, 1), b"")
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertFalse(self.transaction.uncertain.exists())

    def test_failed_marker_sync_closes_gate_without_ack_or_retry(self):
        self.transaction.begin()
        request_write, ack_read, thread, errors = self._gate()
        with mock.patch("enrol_transaction.sync_directory",
                        side_effect=OSError("directory fsync failed")):
            os.write(request_write, b"M")
            self.assertEqual(os.read(ack_read, 1), b"",
                             "native client must fail closed on marker persistence failure")
            thread.join(timeout=3)
        self.assertFalse(thread.is_alive())
        self.assertIsInstance(errors[0], OSError)
        self.assertTrue(self.transaction.uncertain.exists())
        with self.assertRaises(ExportUncertain):
            self.transaction.begin()

    def test_accepted_export_replays_without_new_uncertainty_marker(self):
        self.transaction.begin()
        self.transaction.arm()
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
        self.assertFalse(self.transaction.uncertain.exists())
        self.transaction.arm()
        with self.assertRaises(ExportUncertain):
            self.transaction.begin()
        self.assertTrue(self.transaction.uncertain.exists())

    def test_early_failure_aborts_without_blocking_a_retry(self):
        self.transaction.begin()
        self.transaction.abort()
        self.assertFalse(self.transaction.uncertain.exists())
        self.assertFalse(self.transaction.directory.exists())
        retry = PendingTransaction("alice", "right-index-finger", root=self.root)
        try:
            retry.begin()
            retry.arm()
            self.assertTrue(retry.uncertain.exists())
        finally:
            retry.close()

    def test_armed_failure_preserves_the_custody_marker(self):
        self.transaction.begin()
        self.transaction.arm()
        self.transaction.abort()
        self.assertTrue(self.transaction.uncertain.exists())
        self.assertTrue(self.transaction.directory.exists())
        with self.assertRaises(ExportUncertain):
            self.transaction.begin()

    def test_bad_ack_preserves_pending(self):
        self.transaction.begin()
        self.transaction.arm()
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

    def test_completed_ack_removes_empty_lock_directory(self):
        self.transaction.begin()
        self.transaction.arm()
        self.transaction.database.write_bytes(b"opaque export")
        os.chmod(self.transaction.database, 0o600)
        self.transaction.commit()
        self.transaction.ack(hashlib.sha256(b"opaque export").hexdigest())
        self.assertFalse(self.transaction.ready.exists())
        self.assertTrue(self.transaction.cleanup_empty())
        self.assertFalse(self.transaction.directory.exists())
        self.assertFalse(self.transaction.directory.parent.exists())
        self.assertTrue(self.root.exists())

    def test_cleanup_empty_preserves_unexpected_entries(self):
        (self.transaction.directory / "unexpected").write_bytes(b"keep")
        self.assertFalse(self.transaction.cleanup_empty())
        self.assertTrue((self.transaction.directory / "transaction.lock").exists())
        self.assertTrue((self.transaction.directory / "unexpected").exists())

    def test_interrupted_ack_recovers_without_replaying_or_losing_export(self):
        self.transaction.begin()
        self.transaction.arm()
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
        self.assertFalse(self.transaction.uncertain.exists())
        self.transaction.arm()
        self.assertTrue(self.transaction.uncertain.exists())

    def test_other_finger_cannot_restart_enrolment(self):
        self.transaction.begin()
        self.transaction.arm()
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
        self.transaction.arm()
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
            self.assertTrue(replay.cleanup_empty())
            self.assertFalse(replay.directory.exists())
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
