#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Authenticate a Linux user before creating or using its native credential.

The password is read by the colocated PAM helper from /dev/tty. Only its
32-byte derived result crosses anonymous FDs. Public KDF parameters and the
opaque Gatekeeper handle are private, root-owned state; no password or HAT is
persisted. No credential is silently re-created after a failed authorization.
"""
import fcntl
import json
import os
from pathlib import Path
import pwd
import resource
import signal
import stat
import time
import re
import subprocess
import sys

from native_credentials import private_directory
from enrol_transaction import ExportUncertain, PendingTransaction, FINGERS, database_digest
from acceptance_input import (PreparedInputExpired, PreparedInputMismatch,
                              PreparedInputMissing, consume)


class CredentialFailure(Exception):
    def __init__(self, code):
        self.code = code


PROGRESS = re.compile(r"enrol_progress_status=([0-9]+) remaining=([0-9]+)")
CAPTURE_REJECTED = re.compile(r"capture_rejected=([0-9]+) enrol_not_sent=1")
TEE_RESPONSE = re.compile(
    r"tee_ret=0 origin=0 response_status=(-?[0-9]+) status_hex=([0-9a-f]{8})")
NATIVE_PHASES = {
    "OEM listener could not start": "listener",
    "OEM listener readiness was not observed": "listener",
    "command=11 subcommand=0": "bio_init",
    "command=11 subcommand=20": "set_gid",
    "command=11 subcommand=7": "load_database",
    "command=11 subcommand=10": "set_group",
    "enrol_challenge_available=1": "challenge",
    "command=11 subcommand=1": "begin_enrol",
    "command=10 subcommand=4": "capture",
    "command=11 subcommand=2": "sample",
    "command=11 subcommand=3": "end_enrol",
    "pipeline_incomplete=finger_down_wait": "sensor_wait",
    "pipeline_incomplete=finger_lost_wait": "sensor_wait",
    "end_enrol_not_submitted=1 fresh_authorization_failed=1": "authorization",
    "enrol_output_rejected=single_template_database_required": "export",
    "oem_runtime_timed_out=1": "timeout",
}


def event(kind, **fields):
    print("fpc_event=1 kind=" + kind + "".join(f" {key}={value}" for key, value in fields.items()),
          flush=True)


def failure(code):
    print("fpc_error=" + code, flush=True)


def stream_enrol_line(line):
    line = line.rstrip("\r\n")
    if line in NATIVE_PHASES:
        event("phase", code=NATIVE_PHASES[line])
    elif response := TEE_RESPONSE.fullmatch(line):
        status = int(response.group(1))
        if -4096 <= status < 0 and (status & 0xFFFFFFFF) == int(response.group(2), 16):
            event("ta_reject", status=status)
    elif line.startswith("READY enrol attempt=1:"):
        event("ready")
    elif line == "READY lift finger and reposition for next sample":
        event("lift")
    elif line == "enrol_authorization_phase=end_enrol":
        event("finalizing")
    else:
        progress = PROGRESS.fullmatch(line)
        if progress:
            status, remaining = map(int, progress.groups())
            # Zero is the completed TA enrol phase; a positive status is an
            # accepted intermediate sample with a remaining-touch count.
            if (status == 0 and remaining == 0) or (status > 0 and remaining > 0):
                event("sample", remaining=remaining)
        elif CAPTURE_REJECTED.fullmatch(line):
            event("retry", code="capture_rejected")
        elif line in ("native_credential_provider=BUSY", "oem_runtime=BUSY"):
            return "busy"
    return None


def private_file(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
        os.close(descriptor)
        raise ValueError("invalid private state file")
    return descriptor


def write_exclusive(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as output:
            output.write(data)
            output.flush()
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)


def sealed_memory(data):
    descriptor = os.memfd_create("liuqin-fpc-public-parameters", os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
    try:
        os.fchmod(descriptor, 0o600)
        if os.write(descriptor, data) != len(data):
            raise OSError("incomplete parameter FD")
        os.lseek(descriptor, 0, os.SEEK_SET)
        fcntl.fcntl(descriptor, fcntl.F_ADD_SEALS,
                    fcntl.F_SEAL_WRITE | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SEAL)
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def validate_parameters(parameters, account_info, native_uid):
    if not isinstance(parameters, dict):
        raise CredentialFailure("parameters_invalid")
    identity = ("linux_username", "linux_uid", "native_uid")
    if not all(field in parameters for field in identity):
        raise CredentialFailure("parameters_invalid")
    if tuple(parameters[field] for field in identity) != (
            account_info.pw_name, account_info.pw_uid, native_uid):
        raise CredentialFailure("account_mismatch")
    if (parameters.get("schema"), parameters.get("kdf"), parameters.get("iterations"),
            parameters.get("input_bytes")) != (1, "PBKDF2-HMAC-SHA256", 600000, 32):
        raise CredentialFailure("parameters_invalid")

def native_uid_for(account_info, state):
    # A previously persisted legacy identity must never be silently replaced.
    legacy_uid = 0x40000000 | account_info.pw_uid
    if any(os.path.lexists(state / str(legacy_uid) / name) for name in
           ("gatekeeper.handle", "input-parameters.json", "create.requested")):
        return legacy_uid
    return 0x50000000 | account_info.pw_uid


def account_status(username, state):
    """Inspect private public metadata without consuming a key or starting a TA."""
    from acceptance_input import ROOT as acceptance_root
    from enrol_transaction import ROOT as pending_root
    try:
        account_info = pwd.getpwnam(username)
        if account_info.pw_name != username or not 0 < account_info.pw_uid < 0x10000000:
            return "account_mismatch"
        native_uid = native_uid_for(account_info, state)
        account = state / str(native_uid)
        handle = account / "gatekeeper.handle"
        metadata = account / "input-parameters.json"
        if not os.path.lexists(handle) and not os.path.lexists(metadata):
            return "missing_handle"
        if not os.path.lexists(metadata):
            return "parameters_invalid"
        fd = private_file(metadata)
        try:
            if os.fstat(fd).st_size > 4096:
                return "parameters_invalid"
            with os.fdopen(fd, "r", closefd=False) as source:
                parameters = json.load(source)
        finally:
            os.close(fd)
        validate_parameters(parameters, account_info, native_uid)
        if not os.path.lexists(handle):
            return "missing_handle"
        fd = private_file(handle)
        try:
            if not 0 < os.fstat(fd).st_size <= 1024:
                return "parameters_invalid"
        finally:
            os.close(fd)
        pending_user = pending_root / username
        if os.path.lexists(pending_user):
            info = pending_user.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700:
                return "export_uncertain"
            if any(os.path.lexists(pending_user / name) for name in
                   ("single-finger.db", "gallery.db", "gallery-ids.bin",
                    "export-ready.json", "export-uncertain.json", "ack-received.json")):
                return "export_uncertain"
            accepted = False
            for finger in FINGERS:
                if not os.path.lexists(pending_user / finger):
                    continue
                transaction = PendingTransaction(username, finger, create=False)
                try:
                    if transaction.accepted():
                        if accepted:
                            return "export_uncertain"
                        accepted = True
                finally:
                    transaction.close()
            if accepted:
                return "accepted_pending"
        prepared = acceptance_root / ("acceptance-" + username + ".json")
        if not os.path.lexists(prepared):
            return "prepared_input_missing"
        fd = private_file(prepared)
        try:
            if os.fstat(fd).st_size > 4096:
                return "parameters_invalid"
            with os.fdopen(fd, "r", closefd=False) as source:
                public = json.load(source)
        finally:
            os.close(fd)
        if not isinstance(public, dict) or public.get("schema") != 1:
            return "parameters_invalid"
        if public.get("username") != username or public.get("native_uid") != native_uid:
            return "account_mismatch"
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        if public.get("boot_id") != boot or public.get("expires", 0) <= time.time():
            return "prepared_input_expired"
        # Presence and expiry of public metadata do not prove key readability.
        return "prepared_input_unexpired"
    except KeyError:
        return "account_mismatch"
    except CredentialFailure as error:
        return error.code
    except ExportUncertain:
        return "export_uncertain"
    except (ValueError, TypeError, UnicodeError):
        return "parameters_invalid"
    except OSError:
        return "storage_failure"


def main():
    arguments = sys.argv[1:]
    state = Path("/var/lib/liuqin-fingerprint/native")
    if len(arguments) >= 2 and arguments[0] == "--state-dir":
        state = Path(arguments[1])
        arguments = arguments[2:]
    create = len(arguments) == 2 and arguments[0] == "--create"
    status = len(arguments) == 2 and arguments[0] == "--status"
    preflight = len(arguments) == 2 and arguments[0] in ("--auth-preflight", "--auth-preflight-renew")
    sync_password = len(arguments) == 2 and arguments[0] == "--sync-password"
    prepare_acceptance = len(arguments) == 2 and arguments[0] == "--prepare-acceptance"
    prepared_enrol = len(arguments) in (5, 6) and arguments[0] == "--enrol-prepared"
    enrol = len(arguments) in (5, 6) and arguments[0] == "--enrol"
    enrol_existing = len(arguments) == 4 and arguments[0] == "--enrol-existing"
    desktop_enrol = enrol or prepared_enrol
    if os.geteuid() != 0 or not state.is_absolute() or not (
            status or create or preflight or sync_password or desktop_enrol or
            enrol_existing or prepare_acceptance):
        print("usage (root, interactive terminal): user_credentials.py [--state-dir ABSOLUTE_PRIVATE_DIRECTORY] "
              "--status LINUX_USERNAME | --create LINUX_USERNAME | --auth-preflight[-renew] LINUX_USERNAME | "
              "--sync-password LINUX_USERNAME | --prepare-acceptance LINUX_USERNAME | "
              "--enrol-prepared LINUX_USERNAME FINGER OUTPUT_DATABASE [INPUT_DATABASE] OUTPUT_IDENTITIES | "
              "--enrol LINUX_USERNAME FINGER OUTPUT_DATABASE [INPUT_DATABASE] OUTPUT_IDENTITIES | "
              "--enrol-existing LINUX_USERNAME INPUT_DATABASE OUTPUT_DATABASE", file=sys.stderr)
        return 2
    if status:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        code = account_status(arguments[1], state)
        print("fpc_status=" + code, flush=True)
        return 0 if code in ("prepared_input_unexpired", "accepted_pending") else 2
    descriptors = []
    child = None
    cancelled = False
    transaction = None

    def cancel_operation(signum, frame):
        nonlocal cancelled
        cancelled = True
        if child is not None and child.poll() is None:
            child.send_signal(signal.SIGTERM)

    def run(command, inherited):
        nonlocal child
        if cancelled:
            return 1
        # Keep the controlling terminal for PAM. Lower layers own TA cleanup.
        child = subprocess.Popen(command, pass_fds=inherited)
        while True:
            try:
                result = child.wait(timeout=0.1)
                child = None
                return 1 if cancelled else result
            except subprocess.TimeoutExpired:
                if cancelled:
                    child.send_signal(signal.SIGTERM)

    def run_enrol(command, inherited):
        nonlocal child
        if cancelled:
            return 1, None
        # The native C client already uses unbuffered stdout. All Python
        # intermediates are unbuffered too; only allowlisted status lines reach
        # the desktop. In particular, no diagnostic child output is forwarded.
        child = subprocess.Popen(command, pass_fds=inherited, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, bufsize=1,
                                 errors="replace")
        busy = None
        with child.stdout:
            for line in child.stdout:
                busy = stream_enrol_line(line) or busy
                if cancelled and child.poll() is None:
                    child.send_signal(signal.SIGTERM)
        result = child.wait()
        child = None
        return (1 if cancelled else result), busy

    signal.signal(signal.SIGINT, cancel_operation)
    signal.signal(signal.SIGTERM, cancel_operation)
    signal.signal(signal.SIGHUP, cancel_operation)
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        try:
            account_info = pwd.getpwnam(arguments[1])
        except KeyError as error:
            raise CredentialFailure("account_mismatch") from error
        if account_info.pw_name != arguments[1] or not 0 < account_info.pw_uid < 0x10000000:
            raise CredentialFailure("account_mismatch")
        uid = native_uid_for(account_info, state)
        here = Path(__file__).resolve().parent
        helper = here / "pam-input"
        for path in (here, helper, here / "native_credentials.py",
                     *((here / "enrol_transaction.py",) if desktop_enrol else ())):
            info = path.lstat()
            if info.st_uid != 0 or info.st_mode & 0o022 or stat.S_ISLNK(info.st_mode):
                raise ValueError("runtime bundle must be root-owned and not writable by other users")
        if not helper.is_file():
            raise ValueError("the colocated PAM helper is missing")
        os.umask(0o077)
        private_directory(state)
        account = state / str(uid)
        private_directory(account)
        lock = os.open(account / "user-operation.lock", os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
        descriptors.append(lock)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        handle = account / "gatekeeper.handle"
        metadata = account / "input-parameters.json"
        requested = account / "create.requested"
        if create and (os.path.lexists(handle) or os.path.lexists(requested)):
            print("linux_user_credential=REFUSED existing_identity_preserved=1 "
                  "new_credential_not_requested=1", file=sys.stderr)
            return 2
        if not create and not os.path.lexists(handle) and not os.path.lexists(metadata):
            if desktop_enrol:
                raise CredentialFailure("missing_handle")
            print("linux_user_credential=FAILED phase=missing_persistent_handle "
                  "new_credential_not_requested=1", file=sys.stderr)
            return 2
        if create and not os.path.lexists(metadata):
            parameters = {"schema": 1, "linux_username": account_info.pw_name,
                          "linux_uid": account_info.pw_uid, "native_uid": uid,
                          "kdf": "PBKDF2-HMAC-SHA256", "iterations": 600000,
                          "salt_hex": os.urandom(32).hex(), "input_bytes": 32}
            write_exclusive(metadata, (json.dumps(parameters, sort_keys=True) + "\n").encode("ascii"))
        parameter_fd = private_file(metadata)
        descriptors.append(parameter_fd)
        if os.fstat(parameter_fd).st_size > 4096:
            raise ValueError("invalid public parameter size")
        with os.fdopen(parameter_fd, "r", closefd=False) as source:
            parameters = json.load(source)
        validate_parameters(parameters, account_info, uid)
        if not create and not os.path.lexists(handle):
            if desktop_enrol:
                raise CredentialFailure("missing_handle")
            print("linux_user_credential=FAILED phase=missing_persistent_handle "
                  "new_credential_not_requested=1", file=sys.stderr)
            return 2
        if desktop_enrol:
            handle_fd = private_file(handle)
            try:
                if not 0 < os.fstat(handle_fd).st_size <= 1024:
                    raise CredentialFailure("storage_failure")
            finally:
                os.close(handle_fd)
        salt = bytes.fromhex(parameters["salt_hex"])
        if len(salt) != 32:
            raise ValueError("invalid public salt size")
        if desktop_enrol:
            if arguments[2] not in FINGERS:
                raise CredentialFailure("parameters_invalid")
            previous = Path(arguments[4]) if len(arguments) == 6 else None
            original_digest = None
            if previous is not None:
                info = previous.parent.lstat()
                if (not previous.is_absolute() or not stat.S_ISDIR(info.st_mode) or
                        info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700):
                    raise CredentialFailure("storage_failure")
                previous_fd = private_file(previous)
                try:
                    original_digest = database_digest(previous_fd)
                finally:
                    os.close(previous_fd)
            transaction = PendingTransaction(account_info.pw_name, arguments[2],
                                             gallery=True, base_digest=original_digest)
            transaction.check_other_exports()
            transaction.validate_output(arguments[3])
            transaction.validate_output(arguments[-1])
            if transaction.accepted():
                # Neither the one-use key nor the TA is touched on replay.
                transaction.publish(arguments[3], arguments[-1])
                event("recovered")
                event("committed")
                return 0
        salt_fd = sealed_memory(salt)
        descriptors.append(salt_fd)
        input_fd = os.memfd_create("liuqin-fpc-derived-input", os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
        os.fchmod(input_fd, 0o600)
        descriptors.append(input_fd)
        current_fd = -1
        if sync_password:
            current_fd = os.memfd_create("liuqin-fpc-previous-input", os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
            os.fchmod(current_fd, 0o600)
            descriptors.append(current_fd)
            helper_arguments = ["--sync-inputs", account_info.pw_name, str(salt_fd),
                                str(current_fd), str(input_fd)]
            inherited = (salt_fd, current_fd, input_fd)
        else:
            helper_arguments = ["--authenticate", account_info.pw_name, str(salt_fd), str(input_fd)]
            inherited = (salt_fd, input_fd)
        if prepared_enrol:
            try:
                prepared_fd = consume(account_info.pw_name, uid)
            except (KeyError, TypeError, ValueError, UnicodeError) as error:
                raise CredentialFailure("parameters_invalid") from error
            os.close(input_fd)
            descriptors.remove(input_fd)
            input_fd = prepared_fd
            descriptors.append(input_fd)
            result = 0
        else:
            result = run([str(helper), *helper_arguments], inherited)
        if result:
            if desktop_enrol:
                raise CredentialFailure("runtime_failure")
            print("linux_user_credential=FAILED phase=linux_identity "
                  "gatekeeper_not_requested=1", file=sys.stderr)
            return result
        input_fds = (current_fd, input_fd) if sync_password else (input_fd,)
        for descriptor in input_fds:
            if os.fstat(descriptor).st_size != 32:
                raise ValueError("incomplete authenticated derived input")
            os.lseek(descriptor, 0, os.SEEK_SET)
            if not prepared_enrol:
                fcntl.fcntl(descriptor, fcntl.F_ADD_SEALS,
                            fcntl.F_SEAL_WRITE | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SEAL)
        if create:
            # Persist an uncertainty marker before the TA can change identity.
            # A failed call must not silently retry a new SID for the same UID.
            write_exclusive(requested, b"")
            operation = ["--create", str(uid), str(input_fd)]
        elif sync_password:
            operation = ["--change-input", str(uid), str(current_fd), str(input_fd)]
        elif enrol_existing:
            operation = ["--enrol-existing", *arguments[2:4], str(uid), str(input_fd)]
        elif desktop_enrol:
            transaction.begin()
            if previous is None:
                operation = ["--enrol", str(transaction.database),
                             str(transaction.ids), str(uid), str(input_fd)]
            else:
                operation = ["--enrol-existing", str(previous), str(transaction.database),
                             str(transaction.ids), str(uid), str(input_fd)]
        elif prepare_acceptance:
            operation = ["--auth-preflight-renew", str(uid), str(input_fd)]
        else:
            operation = [arguments[0], str(uid), str(input_fd)]
        if desktop_enrol:
            result, busy = run_enrol([sys.executable, "-u", str(here / "native_credentials.py"),
                                      "--state-dir", str(state), *operation], input_fds)
            if result:
                raise CredentialFailure(busy or "runtime_failure")
            transaction.commit()
            transaction.publish(arguments[3], arguments[-1])
            event("committed")
            return 0
        result = run([sys.executable, str(here / "native_credentials.py"),
                      "--state-dir", str(state), *operation], input_fds)
        if prepare_acceptance and result == 0 and not cancelled:
            from acceptance_input import prepare
            prepare(account_info.pw_name, uid, input_fd)
            print("acceptance_input=PREPARED kernel_memory_only=1 one_use=1 expires_hours=18 touch_not_collected=1")
        if sync_password and result == 0:
            from acceptance_input import discard
            discard(account_info.pw_name)
        print(f"linux_user_credential={'OK' if result == 0 else 'FAILED'} "
              "linux_identity_checked=1 anonymous_input_fd=1 password_or_derived_input_persisted=0 "
              "desktop_authentication=disabled")
        return result
    except CredentialFailure as error:
        if desktop_enrol:
            failure(error.code)
        else:
            print("linux_user_credential=FAILED phase=account_parameters_or_private_storage", file=sys.stderr)
        return 2
    except PreparedInputMismatch:
        failure("account_mismatch")
        return 2
    except PreparedInputMissing:
        failure("prepared_input_missing")
        return 2
    except PreparedInputExpired:
        failure("prepared_input_expired")
        return 2
    except BlockingIOError:
        if desktop_enrol:
            failure("busy")
        else:
            print("linux_user_credential=BUSY", file=sys.stderr)
        return 1
    except ExportUncertain:
        failure("export_uncertain")
        return 2
    except (KeyError, ValueError, OSError, TypeError, UnicodeError):
        if desktop_enrol:
            failure("storage_failure" if transaction is not None else "parameters_invalid")
        else:
            print("linux_user_credential=FAILED phase=account_parameters_or_private_storage", file=sys.stderr)
        return 2
    finally:
        if transaction is not None:
            transaction.close()
        for descriptor in reversed(descriptors):
            os.close(descriptor)


if __name__ == "__main__":
    sys.exit(main())
