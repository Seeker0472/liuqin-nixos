#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Private, fail-closed custody of an accepted OEM enrolment until fprintd saves it.

The uncertainty marker is durable before END_ENROL can leave a template in
the TA. A failure before the first accepted final sample therefore leaves no
marker and can be retried normally; once the enrolment has reached its final
authorization gate, an interrupted export is never guessed or auto-retried.
A completed export is reusable only after the native client has returned
successfully, its file is synced, and the exact user/finger acceptance marker
is synced. Only fprintd's post-save acknowledgement may remove an accepted
export.
"""
import fcntl
import hashlib
import json
import os
import resource
from pathlib import Path
import re
import stat
import struct
import sys

from native_credentials import private_directory

ROOT = Path("/var/lib/liuqin-fingerprint/pending")
FINGERS = ("left-thumb", "left-index-finger", "left-middle-finger", "left-ring-finger",
           "left-little-finger", "right-thumb", "right-index-finger", "right-middle-finger",
           "right-ring-finger", "right-little-finger")


class ExportUncertain(Exception):
    """Existing state cannot prove both TA acceptance and complete export."""


def validate_scope(user, finger):
    if (not user or user in (".", "..") or "/" in user or "\x00" in user or
            finger not in FINGERS):
        raise ValueError("invalid enrolment account or finger")


def sync_directory(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def private_file(path):
    fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
        os.close(fd)
        raise ExportUncertain("invalid pending private file")
    return fd


def write_exclusive(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb", closefd=False) as output:
            output.write(data)
            output.flush()
        os.fsync(fd)
    finally:
        os.close(fd)
    sync_directory(path.parent)


def database_digest(fd):
    if not 0 < os.fstat(fd).st_size:
        raise ExportUncertain("empty pending export")
    digest = hashlib.sha256()
    while block := os.read(fd, 1024 * 1024):
        digest.update(block)
    return digest.hexdigest()

def identity_digest(fd):
    """Validate the exact native ID envelope without exposing its contents."""
    if os.fstat(fd).st_size != 28:
        raise ExportUncertain("invalid private gallery identity size")
    data = os.read(fd, 29)
    if len(data) != 28:
        raise ExportUncertain("incomplete private gallery identities")
    count, added, *ids = struct.unpack("<7I", data)
    if (not 1 <= count <= 5 or added == 0 or added not in ids[:count] or
            len(set(ids[:count])) != count or any(value == 0 for value in ids[:count]) or
            any(ids[count:])):
        raise ExportUncertain("invalid private gallery identities")
    return hashlib.sha256(data).hexdigest(), count


def read_marker(path):
    fd = private_file(path)
    try:
        if os.fstat(fd).st_size > 4096:
            raise ExportUncertain("invalid private marker size")
        with os.fdopen(fd, "r", closefd=False) as source:
            return json.load(source)
    except (ValueError, UnicodeError) as error:
        raise ExportUncertain("invalid private marker") from error
    finally:
        os.close(fd)


class PendingTransaction:
    def __init__(self, user, finger, root=ROOT, create=True, gallery=False, base_digest=None):
        validate_scope(user, finger)
        self.user = user
        self.finger = finger
        self.directory = Path(root) / user / finger
        if create:
            for path in (Path(root), Path(root) / user, self.directory):
                private_directory(path)
                # A synced marker inside a newly created directory is not
                # durable unless that directory's parent entry is synced too.
                sync_directory(path.parent)
        else:
            for path in (Path(root), Path(root) / user, self.directory):
                info = path.lstat()
                if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
                    raise ExportUncertain("invalid pending private directory")
        if not create and not gallery:
            for candidate in ("export-ready.json", "ack-received.json", "export-uncertain.json"):
                marker_path = self.directory / candidate
                if os.path.lexists(marker_path):
                    marker = read_marker(marker_path)
                    gallery = isinstance(marker, dict) and marker.get("schema") == 2
                    if gallery and base_digest is None:
                        base_digest = marker.get("base_sha256")
                    break
            else:
                gallery = any(os.path.lexists(self.directory / name) for name in
                              ("gallery.db", "gallery-ids.bin"))
        self.gallery = gallery
        if base_digest is not None and (not isinstance(base_digest, str) or
                                        not re.fullmatch(r"[0-9a-f]{64}", base_digest)):
            raise ExportUncertain("invalid original gallery digest")
        self.base_digest = base_digest
        self.database = self.directory / ("gallery.db" if gallery else "single-finger.db")
        self.ids = self.directory / "gallery-ids.bin" if gallery else None
        self.ready = self.directory / "export-ready.json"
        self.uncertain = self.directory / "export-uncertain.json"
        self.acknowledged = self.directory / "ack-received.json"
        flags = os.O_RDONLY if not create else os.O_RDWR | os.O_CREAT
        self.lock = os.open(self.directory / "transaction.lock",
                            flags | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
        try:
            info = os.fstat(self.lock)
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
                    stat.S_IMODE(info.st_mode) != 0o600):
                raise ExportUncertain("invalid pending lock")
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BaseException:
            os.close(self.lock)
            raise

    def close(self):
        os.close(self.lock)

    def _marker(self):
        if not self.gallery:
            return {"schema": 1, "user": self.user, "finger": self.finger,
                    "end_enrol_accepted": True, "template_count": 1}
        database = private_file(self.database)
        try:
            identities = private_file(self.ids)
            try:
                digest = database_digest(database)
                ids_digest, count = identity_digest(identities)
            finally:
                os.close(identities)
        finally:
            os.close(database)
        return {"schema": 2, "user": self.user, "finger": self.finger,
                "end_enrol_accepted": True, "template_count": count,
                "base_sha256": self.base_digest, "sha256": digest,
                "ids_sha256": ids_digest}


    def check_other_exports(self):
        user_dir = self.directory.parent
        if self.gallery and os.path.lexists(self.directory / "single-finger.db"):
            raise ExportUncertain("legacy export for same finger remains")
        # An older CLI wrote directly in the account directory. It cannot be
        # silently treated as a fresh enrolment under the new per-finger layout.
        if any(os.path.lexists(user_dir / name) for name in
               ("single-finger.db", "gallery.db", "gallery-ids.bin",
                "export-ready.json", "export-uncertain.json", "ack-received.json")):
            raise ExportUncertain("unmigrated account-level export")
        if any(os.path.lexists(user_dir / finger / name)
               for finger in FINGERS if finger != self.finger
               for name in ("single-finger.db", "gallery.db", "gallery-ids.bin",
                            "export-ready.json", "export-uncertain.json", "ack-received.json")):
            raise ExportUncertain("another finger has pending enrolment")


    def complete_ack(self, expected_digest=None):
        if not os.path.lexists(self.acknowledged):
            return None
        fd = private_file(self.acknowledged)
        try:
            if os.fstat(fd).st_size > 4096:
                raise ExportUncertain("invalid acknowledgement marker size")
            with os.fdopen(fd, "r", closefd=False) as source:
                marker = json.load(source)
        except (ValueError, UnicodeError) as error:
            raise ExportUncertain("invalid acknowledgement marker") from error
        finally:
            os.close(fd)
        if (not isinstance(marker, dict) or marker.get("schema") != (2 if self.gallery else 1) or
                marker.get("user") != self.user or marker.get("finger") != self.finger or
                not isinstance(marker.get("sha256"), str) or
                not re.fullmatch(r"[0-9a-f]{64}", marker["sha256"]) or
                (self.gallery and (not isinstance(marker.get("ids_sha256"), str) or
                                   not re.fullmatch(r"[0-9a-f]{64}", marker["ids_sha256"]) or
                                   marker.get("base_sha256") != self.base_digest))):
            raise ExportUncertain("acknowledgement does not bind this export")
        if expected_digest is not None and marker["sha256"] != expected_digest:
            raise ExportUncertain("acknowledgement database digest mismatch")
        # After this marker was durably written, fprintd had saved this exact
        # export. Complete cleanup even if a previous ack crashed mid-unlink.
        for path in (self.database, *((self.ids,) if self.gallery else ()), self.ready, self.uncertain):
            if os.path.lexists(path):
                fd = private_file(path)
                os.close(fd)
                os.unlink(path)
        sync_directory(self.directory)
        os.unlink(self.acknowledged)
        sync_directory(self.directory)
        return marker["sha256"]

    def accepted(self):
        self.complete_ack()
        present = tuple(os.path.lexists(path) for path in
                        (self.database, self.ready, self.uncertain,
                         *((self.ids,) if self.gallery else ())))
        if not any(present):
            return False
        if not all(present[:2]) or (self.gallery and not present[3]):
            raise ExportUncertain("an enrolment or export is incomplete")
        try:
            marker = read_marker(self.ready)
            if marker != self._marker():
                raise ExportUncertain("acceptance marker does not bind this user and finger")
            return True
        except (ValueError, UnicodeError) as error:
            raise ExportUncertain("invalid acceptance marker") from error

    def begin(self):
        """Validate that a fresh enrolment may start.

        No custody marker is written yet: the native client has not touched
        the TA. A failed or cancelled capture phase must remain retryable.
        """
        self.check_other_exports()
        if self.accepted():
            raise ExportUncertain("accepted export already exists")

    def arm(self):
        """Persist the single-use custody marker before acknowledging END_ENROL.

        The native client remains blocked on the binary gate until both the
        marker file and its directory have been synced by write_exclusive.
        """
        marker = {"schema": 2 if self.gallery else 1,
                  "user": self.user, "finger": self.finger}
        if self.gallery:
            marker["base_sha256"] = self.base_digest
        if os.path.lexists(self.ready):
            raise ExportUncertain("accepted export already exists")
        if os.path.lexists(self.uncertain):
            raise ExportUncertain("an earlier enrolment may already have reached the TA")
        write_exclusive(self.uncertain, (json.dumps(marker, sort_keys=True) + "\n").encode("ascii"))

    def abort(self):
        """Drop a transaction that never reached the TA-mutating phase.

        Once the uncertainty or acceptance marker exists, the export is
        potentially authoritative and must be preserved for explicit recovery.
        """
        if any(os.path.lexists(path) for path in
               (self.uncertain, self.ready, self.acknowledged)):
            return
        if any(os.path.lexists(path) for path in
               (self.database, *((self.ids,) if self.gallery else ()))):
            return
        try:
            os.unlink(self.directory / "transaction.lock")
        except FileNotFoundError:
            return
        for path in (self.directory, self.directory.parent):
            try:
                path.rmdir()
            except OSError:
                pass

    def commit(self):
        if not os.path.lexists(self.uncertain) or os.path.lexists(self.ready):
            raise ExportUncertain("enrolment transaction state is ambiguous")
        fd = private_file(self.database)
        try:
            database_digest(fd)
            os.fsync(fd)
        finally:
            os.close(fd)
        if self.gallery:
            identities = private_file(self.ids)
            try:
                identity_digest(identities)
                os.fsync(identities)
            finally:
                os.close(identities)
        sync_directory(self.directory)
        write_exclusive(self.ready, (json.dumps(self._marker(), sort_keys=True) + "\n").encode("ascii"))
        # The uncertainty marker may coexist with a fully accepted export after
        # a crash. The acceptance marker, not absence of uncertainty, proves it.
        os.unlink(self.uncertain)
        sync_directory(self.directory)

    def validate_output(self, output):
        output = Path(output)
        if (not output.is_absolute() or output == self.database or
                output == self.ids or os.path.lexists(output)):
            raise ValueError("exclusive absolute output required")
        parent = output.parent
        info = parent.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or
                stat.S_IMODE(info.st_mode) != 0o700):
            raise ValueError("root-owned private output directory required")
        return output

    def publish(self, output, identities_output=None):
        if not self.accepted():
            raise ExportUncertain("accepted export unavailable")
        output = self.validate_output(output)
        if self.gallery:
            if identities_output is None:
                raise ValueError("gallery identity output is required")
            identities_output = self.validate_output(identities_output)
            if identities_output == output:
                raise ValueError("distinct gallery outputs are required")
        elif identities_output is not None:
            raise ValueError("legacy export has no identity output")
        for source_path, destination_path in ((self.database, output), *(
                ((self.ids, identities_output),) if self.gallery else ())):
            source = private_file(source_path)
            try:
                destination = os.open(destination_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                                      os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
                try:
                    while block := os.read(source, 1024 * 1024):
                        view = memoryview(block)
                        while view:
                            view = view[os.write(destination, view):]
                    os.fsync(destination)
                finally:
                    os.close(destination)
                sync_directory(destination_path.parent)
            finally:
                os.close(source)

    def ack(self, expected_digest):
        if not re.fullmatch(r"[0-9a-f]{64}", expected_digest):
            raise ExportUncertain("invalid acknowledgement digest")
        if os.path.lexists(self.acknowledged):
            self.complete_ack(expected_digest)
            return
        if not self.accepted():
            raise ExportUncertain("acknowledgement does not match an accepted export")
        fd = private_file(self.database)
        try:
            if database_digest(fd) != expected_digest:
                raise ExportUncertain("acknowledgement database digest mismatch")
        finally:
            os.close(fd)
        # Proof of fprintd's post-save acknowledgement is persisted before
        # deleting the export; cleanup is replayable after any interruption.
        marker = {"schema": 2 if self.gallery else 1,
                  "user": self.user, "finger": self.finger,
                  "sha256": expected_digest}
        if self.gallery:
            marker["ids_sha256"] = self._marker()["ids_sha256"]
            marker["base_sha256"] = self.base_digest
        write_exclusive(self.acknowledged, (json.dumps(marker, sort_keys=True) + "\n").encode("ascii"))
        self.complete_ack()


def main():
    if len(sys.argv) != 5 or sys.argv[1] != "--ack" or os.geteuid() != 0:
        print("usage (root): enrol_transaction.py --ack USER FINGER SHA256_HEX", file=sys.stderr)
        return 2
    transaction = None
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        transaction = PendingTransaction(sys.argv[2], sys.argv[3], create=False)
        transaction.ack(sys.argv[4])
        return 0
    except (BlockingIOError, ExportUncertain, ValueError, OSError, UnicodeError):
        print("fpc_error=storage_failure", file=sys.stderr, flush=True)
        return 1
    finally:
        if transaction is not None:
            transaction.close()


if __name__ == "__main__":
    sys.exit(main())
