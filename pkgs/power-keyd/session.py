#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Unprivileged GNOME power controller; all desktop calls are asynchronous."""
import argparse
import os
import signal
import socket
import struct
import time

import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLibUnix', '2.0')
from gi.repository import Gio, GLib, GLibUnix

from policy import PowerPolicy
from transport import receive_packet, send_packet

DISPLAY_NAME = 'org.gnome.Mutter.DisplayConfig'
DISPLAY_PATH = '/org/gnome/Mutter/DisplayConfig'
SESSION_INTERFACE = 'org.freedesktop.login1.Session'


def now_ms():
    return time.monotonic_ns() // 1_000_000


def prop(proxy, name):
    if proxy is None or not proxy.get_name_owner():
        return None
    value = proxy.get_cached_property(name)
    return value.unpack() if value is not None else None


class DesktopBackend:
    """Translate effects into API calls; facts remain owned by the providers.

    logind Session.Lock acknowledges a request. LockedHint confirms locking.
    ScreenSaver.GetActive and ScreenSaver.Lock are deliberately unused: GNOME
    distinguishes an active shield from a lock, and a repeated Lock request
    can wait forever for a lock-screen-shown event that will not occur again.
    """
    def __init__(self, session_path, *, greeter, on_facts, on_ready, on_lid,
                 session_connection=None, system_connection=None):
        self.greeter = greeter
        self.session_path = session_path
        self.on_facts, self.on_ready, self.on_lid = on_facts, on_ready, on_lid
        self.proxies = {}
        self.calls = set()
        self.closed = False
        self.session_connection = session_connection
        self.system_connection = system_connection
        self.retry = None
        self.retry_seconds = 1
        self.generation = 0
        self.proxy_handlers = []
        self.connection_handlers = []
        self.connect_providers()

    def connect_providers(self):
        self.retry = None
        if self.closed:
            return GLib.SOURCE_REMOVE
        try:
            if self.session_connection is None:
                self.session_connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
                self.session_connection.set_exit_on_close(False)
                self.connection_handlers.append((self.session_connection,
                    self.session_connection.connect('closed', self.connection_closed)))
            if self.system_connection is None:
                self.system_connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
                self.system_connection.set_exit_on_close(False)
                self.connection_handlers.append((self.system_connection,
                    self.system_connection.connect('closed', self.connection_closed)))
        except GLib.Error:
            # logind publishes the GDM session before /run/user/UID/bus may
            # exist. Keep input ungrabbed and retry without crashing the
            # service or exhausting systemd's restart budget.
            self.on_ready(False)
            self.retry = GLib.timeout_add_seconds(self.retry_seconds, self.connect_providers)
            self.retry_seconds = min(30, self.retry_seconds*2)
            return GLib.SOURCE_REMOVE
        self.retry_seconds = 1
        definitions = [
            ('display', self.session_connection, DISPLAY_NAME, DISPLAY_PATH, DISPLAY_NAME),
            ('login', self.system_connection, 'org.freedesktop.login1', self.session_path, SESSION_INTERFACE),
            ('upower', self.system_connection, 'org.freedesktop.UPower',
             '/org/freedesktop/UPower', 'org.freedesktop.UPower'),
        ]
        for key, connection, name, path, interface in definitions:
            Gio.DBusProxy.new(connection, Gio.DBusProxyFlags.DO_NOT_AUTO_START, None,
                              name, path, interface, None, self.proxy_ready, (key, self.generation))
        return GLib.SOURCE_REMOVE

    def connection_closed(self, connection, *_):
        if self.closed:
            return
        for watched, handler in tuple(self.connection_handlers):
            if watched is connection:
                watched.disconnect(handler)
                self.connection_handlers.remove((watched, handler))
        if connection is self.session_connection:
            self.session_connection = None
        if connection is self.system_connection:
            self.system_connection = None
        self.generation += 1
        for proxy, handler in self.proxy_handlers:
            proxy.disconnect(handler)
        self.proxy_handlers.clear()
        self.proxies.clear()
        for call in tuple(self.calls):
            call.cancel()
        self.on_ready(False)
        if self.retry is None:
            self.retry = GLib.timeout_add_seconds(1, self.connect_providers)

    def proxy_ready(self, _source, result, context):
        key, generation = context
        if self.closed or generation != self.generation:
            return
        try:
            proxy = Gio.DBusProxy.new_finish(result)
        except GLib.Error as error:
            self.on_ready(False)
            print(f'liuqin-power-session: {key} unavailable: {error}', flush=True)
            return
        self.proxies[key] = proxy
        self.proxy_handlers.extend((proxy, proxy.connect(signal, self.sync))
                                   for signal in ('g-properties-changed', 'notify::g-name-owner'))
        self.sync()

    def sync(self, *_):
        if self.closed:
            return
        display = prop(self.proxies.get('display'), 'PowerSaveMode')
        active = prop(self.proxies.get('login'), 'Active')
        locked = True if self.greeter else prop(self.proxies.get('login'), 'LockedHint')
        self.on_facts(display, locked)
        self.on_ready(active is True and type(display) is int and display in (0, 1, 2, 3)
                      and type(locked) is bool)
        closed = prop(self.proxies.get('upower'), 'LidIsClosed')
        if type(closed) is bool:
            self.on_lid(closed)

    def perform(self, effect, done):
        cancellable = Gio.Cancellable()
        self.calls.add(cancellable)

        def finished(connection, result, *_):
            self.calls.discard(cancellable)
            if self.closed:
                return
            error = None
            try:
                connection.call_finish(result)
            except GLib.Error as failure:
                error = str(failure)
            done(effect.kind, effect.token, now=now_ms(), value=effect.value, error=error)

        if effect.kind == 'lock':
            proxy = self.proxies['login']
            proxy.get_connection().call(
                proxy.get_name(), proxy.get_object_path(), SESSION_INTERFACE, 'Lock', None,
                None, Gio.DBusCallFlags.NONE, 2000, cancellable, finished)
        elif effect.kind == 'power':
            self.session_connection.call(
                DISPLAY_NAME, DISPLAY_PATH, 'org.freedesktop.DBus.Properties', 'Set',
                GLib.Variant('(ssv)', (DISPLAY_NAME, 'PowerSaveMode',
                                      GLib.Variant('i', effect.value))),
                None, Gio.DBusCallFlags.NONE, 2000, cancellable, finished)
        else:
            raise ValueError(effect.kind)

    def close(self):
        self.closed = True
        for connection, handler in self.connection_handlers:
            connection.disconnect(handler)
        self.connection_handlers.clear()
        if self.retry is not None:
            GLib.source_remove(self.retry)
            self.retry = None
        for proxy, handler in self.proxy_handlers:
            proxy.disconnect(handler)
        self.proxy_handlers.clear()
        for cancellable in tuple(self.calls):
            cancellable.cancel()
        self.calls.clear()


class SessionController:
    def __init__(self, channel, session_path, kind):
        credentials = channel.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
        _pid, uid, _gid = struct.unpack('3i', credentials)
        if uid != 0:
            raise PermissionError('Power events must come from the root broker')
        self.channel = channel
        channel.setblocking(False)
        self.loop = GLib.MainLoop()
        self.stopping = False
        self.ready = False
        self.lid_closed = None
        self.timer = None
        self.timer_deadline = None
        self.policy = PowerPolicy(self.effect, greeter=kind == 'greeter')
        source = Gio.SettingsSchemaSource.new_from_directory(
            os.environ['GSETTINGS_SCHEMA_DIR'], Gio.SettingsSchemaSource.get_default(), False)
        schema = source.lookup('io.github.liuqin.power', False)
        if schema is None:
            raise RuntimeError('Missing liuqin power settings schema')
        self.settings = Gio.Settings.new_full(schema, None, None)
        self.settings.connect('changed::short-press-action', self.settings_changed)
        self.settings_changed()
        self.backend = DesktopBackend(
            session_path, greeter=kind == 'greeter', on_facts=self.facts_changed,
            on_ready=self.available, on_lid=self.lid_changed)
        self.watch = GLib.io_add_watch(
            channel.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.input_ready)

    def log(self, message):
        print(f'liuqin-power-session: uid={os.getuid()} {message}', flush=True)

    def settings_changed(self, *_):
        self.policy.short_action = self.settings.get_string('short-press-action')

    def facts_changed(self, power, locked):
        self.policy.facts(now=now_ms(), power=power, locked=locked)
        self.sync_timer()

    def available(self, ready):
        if ready == self.ready:
            return
        self.ready = ready
        self.policy.available(ready)
        self.send({'action': 'ready', 'value': ready})
        if ready and self.lid_closed is not None:
            self.policy.lid(self.lid_closed, now=now_ms(), initial=True)
        self.sync_timer()
        self.log('controller ready' if ready else 'desktop unavailable; input handed back')

    def lid_changed(self, closed):
        self.lid_closed = closed
        if self.ready:
            self.policy.lid(closed, now=now_ms())
            self.sync_timer()

    def send(self, packet):
        try:
            send_packet(self.channel, packet)
        except OSError as error:
            self.log(str(error))
            self.stop()

    def effect(self, effect):
        self.log(f'effect={effect.kind} token={effect.token} value={effect.value}')
        if effect.kind in ('lock', 'power'):
            self.backend.perform(effect, self.done)
        elif effect.kind == 'suspend':
            self.send({'action': 'suspend', 'token': effect.token})
        elif effect.kind == 'activity':
            self.send({'action': 'wake', 'token': effect.token})
        elif effect.kind == 'menu':
            try:
                process = Gio.Subprocess.new(
                    ['systemd-run', '--user', '--quiet', '--collect', '--unit=liuqin-power-menu',
                     os.environ['LIUQIN_POWER_MENU']], Gio.SubprocessFlags.NONE)
                process.wait_check_async(None, self.menu_done)
            except GLib.Error as error:
                self.log(f'power menu: {error}')
        elif effect.kind == 'error':
            self.log(str(effect.value))

    def menu_done(self, process, result, *_):
        try:
            process.wait_check_finish(result)
        except GLib.Error as error:
            self.log(f'power menu: {error}')

    def done(self, kind, token, **result):
        self.policy.done(kind, token, **result)
        self.sync_timer()

    def read_input(self):
        while not self.stopping:
            packet = receive_packet(self.channel)
            if packet is None:
                return
            kind = packet.get('type')
            if kind == 'key':
                self.policy.key(packet['value'], at=packet['at'], now=now_ms())
            elif kind in ('sleep', 'snapshot'):
                self.policy.sleep(packet['preparing'], at=packet['at'], now=now_ms(),
                                  initial=kind == 'snapshot', down=packet['down'])
            elif kind == 'reset':
                self.policy.reset_key(packet['down'])
            elif kind == 'done':
                self.policy.done(packet['kind'], packet['token'], now=now_ms(), error=packet['error'])
            else:
                raise ValueError('invalid power event')
        self.sync_timer()

    def input_ready(self, _fd, condition):
        try:
            self.read_input()
            if condition & (GLib.IO_HUP | GLib.IO_ERR):
                raise EOFError('input broker closed')
        except (OSError, ValueError, EOFError, KeyError) as error:
            self.log(str(error))
            self.stop()
            return GLib.SOURCE_REMOVE
        self.sync_timer()
        return GLib.SOURCE_CONTINUE

    def sync_timer(self):
        deadline = self.policy.next_deadline
        if deadline == self.timer_deadline:
            return
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None
        self.timer_deadline = deadline
        if deadline is not None and not self.stopping:
            self.timer = GLib.timeout_add(max(1, deadline-now_ms()), self.timeout)

    def timeout(self):
        self.timer = self.timer_deadline = None
        # A queued release wins over a late timer; use the physical timestamps.
        try:
            self.read_input()
        except (OSError, ValueError, EOFError, KeyError):
            self.stop()
            return GLib.SOURCE_REMOVE
        if not self.stopping:
            self.policy.tick(now_ms())
            self.sync_timer()
        return GLib.SOURCE_REMOVE

    def stop(self):
        if self.stopping:
            return GLib.SOURCE_REMOVE
        self.stopping = True
        self.backend.close()
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = self.timer_deadline = None
        if self.watch:
            GLib.source_remove(self.watch)
            self.watch = None
        self.channel.close()
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def run(self):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.stop)
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self.stop)
        self.loop.run()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fd', type=int, required=True)
    parser.add_argument('--session-path', required=True)
    parser.add_argument('--class', dest='kind', choices=('user', 'greeter'), required=True)
    options = parser.parse_args()
    SessionController(socket.socket(fileno=options.fd), options.session_path, options.kind).run()
