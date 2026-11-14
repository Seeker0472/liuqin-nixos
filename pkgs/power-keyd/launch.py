#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Enter the desktop's configuration environment before loading GSettings.

The broker knows credentials and the bus address, not the desktop's XDG
directories. In particular, GDM keeps per-seat dconf outside the account's
home. Query the user manager as the session UID, then exec a fresh controller:
GLib caches directory lookups, so changing os.environ in that controller is
too late. No input is grabbed until the controller reports readiness.
"""
import os
from pathlib import Path
import select
import socket
import struct
import sys

from gi.repository import Gio, GLib

CONFIGURATION_ENVIRONMENT = frozenset((
    'HOME', 'XDG_CONFIG_HOME', 'XDG_CONFIG_DIRS', 'XDG_DATA_HOME',
    'XDG_DATA_DIRS', 'XDG_CACHE_HOME', 'DCONF_PROFILE',
))


class DesktopNotReady(RuntimeError):
    pass


def configuration_environment(original, entries):
    environment = original.copy()
    for entry in entries:
        name, separator, value = entry.partition('=')
        if separator and name in CONFIGURATION_ENVIRONMENT:
            environment[name] = value
    return environment


def read_environment(connection, original):
    # GNOME imports its configuration environment before starting Mutter.
    # The user manager alone can exist earlier with only login defaults.
    owner = connection.call_sync(
        'org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
        'NameHasOwner', GLib.Variant('(s)', ('org.gnome.Mutter.DisplayConfig',)),
        GLib.VariantType.new('(b)'), Gio.DBusCallFlags.NONE, 2000, None)
    if not owner.unpack()[0]:
        raise DesktopNotReady('Waiting for the desktop configuration environment')
    reply = connection.call_sync(
        'org.freedesktop.systemd1', '/org/freedesktop/systemd1',
        'org.freedesktop.DBus.Properties', 'Get',
        GLib.Variant('(ss)', ('org.freedesktop.systemd1.Manager', 'Environment')),
        GLib.VariantType.new('(v)'), Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
    return configuration_environment(original, reply.unpack()[0])


def launch(channel, arguments):
    _pid, uid, _gid = struct.unpack('3i', channel.getsockopt(
        socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid != 0:
        raise PermissionError('Controller must be launched by the root broker')
    disconnected = select.poll()
    # Leave the broker's initial snapshot queued for the actual controller.
    disconnected.register(channel, select.POLLHUP | select.POLLERR)
    retry_ms = 250
    while not disconnected.poll(0):
        connection = None
        try:
            connection = Gio.DBusConnection.new_for_address_sync(
                os.environ['DBUS_SESSION_BUS_ADDRESS'],
                Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
                Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
            environment = read_environment(connection, os.environ)
        except (GLib.Error, DesktopNotReady):
            # logind can publish a session before its user bus/manager exists.
            if disconnected.poll(retry_ms):
                return
            retry_ms = min(30000, retry_ms*2)
            continue
        finally:
            if connection is not None:
                try:
                    connection.close_sync(None)
                except GLib.Error:
                    pass  # A disappearing startup bus is retried above.
        os.set_inheritable(channel.fileno(), True)
        os.execve(sys.executable,
                  [sys.executable, str(Path(__file__).with_name('session.py')), *arguments],
                  environment)


if __name__ == '__main__':
    # The broker supplies this fixed argument list; the controller validates it.
    fd = int(sys.argv[sys.argv.index('--fd')+1])
    launch(socket.socket(fileno=fd), sys.argv[1:])
