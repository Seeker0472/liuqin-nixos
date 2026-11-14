#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Privileged input transport; desktop policy runs in the active user's worker."""
import argparse
import fcntl
import os
import pwd
import signal
import socket
import struct
import subprocess
import time

import evdev
import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLibUnix', '2.0')
from gi.repository import Gio, GLib, GLibUnix

from transport import send_packet, receive_packet


def now_ms():
    return time.monotonic_ns() // 1_000_000


def prop(proxy, name, default=None):
    value = proxy.get_cached_property(name)
    return value.unpack() if value is not None else default


class Broker:
    def __init__(self, session_program):
        self.loop = GLib.MainLoop()
        self.session_program = session_program
        self.device = None
        self.input_watch = None
        self.retry = None
        self.grabbed = False
        self.sync_lost = False
        self.child = None
        self.channel = None
        self.channel_watch = None
        self.child_ready = False
        self.session_path = None
        self.session = None
        self.uid = None
        self.preparing = False
        self.suspend_pending = False
        self.suspend_serial = 0
        self.stopping = False
        self.exit_code = 0
        # The compositor gets a standard wake event for accepted user wakes,
        # never the intercepted KEY_POWER which could run a second policy.
        self.activity_device = evdev.UInput(
            {evdev.ecodes.EV_KEY: [evdev.ecodes.KEY_WAKEUP]},
            name='liuqin power-key wakeup')
        self.manager = self.proxy('/org/freedesktop/login1', 'org.freedesktop.login1.Manager')
        self.seat = self.proxy('/org/freedesktop/login1/seat/seat0', 'org.freedesktop.login1.Seat')
        self.manager.connect('g-signal', self.manager_signal)
        self.manager.connect('notify::g-name-owner', self.manager_owner)
        self.seat.connect('g-properties-changed', lambda *_: self.reconcile())
        self.seat.connect('notify::g-name-owner', lambda *_: self.reconcile())
        self.preparing = bool(prop(self.manager, 'PreparingForSleep', False))

    @staticmethod
    def proxy(path, interface):
        return Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SYSTEM, Gio.DBusProxyFlags.DO_NOT_AUTO_START,
            None, 'org.freedesktop.login1', path, interface, None)

    def log(self, message):
        print(f'liuqin-power-keyd: {message}', flush=True)

    def manager_owner(self, *_):
        if not self.manager.get_name_owner():
            self.stop_worker()
        else:
            self.preparing = bool(prop(self.manager, 'PreparingForSleep', False))
            self.reconcile()

    def manager_signal(self, _proxy, _sender, signal_name, parameters):
        if signal_name != 'PrepareForSleep':
            return
        preparing, = parameters.unpack()
        # Deliver queued evdev events before the end-of-sleep notification.
        # Both inputs then share one ordered stream in the user's controller.
        if not preparing:
            try:
                self.read_input()
            except OSError:
                self.close_input()
                self.retry = GLib.timeout_add(1000, self.open_input)
        self.preparing = preparing
        if not preparing:
            self.suspend_pending = False
            self.suspend_serial += 1
        self.send({'type': 'sleep', 'preparing': preparing, 'at': now_ms(),
                   'down': self.key_down()})
        self.log('sleep preparing' if preparing else 'sleep finished')

    def reconcile(self):
        active = prop(self.seat, 'ActiveSession', ('', '/'))
        path = active[1] if active[0] else None
        if path == self.session_path and self.child is not None and self.active_worker():
            return
        if not self.stop_worker():
            return
        if not path or not self.manager.get_name_owner():
            return
        try:
            session = self.proxy(path, 'org.freedesktop.login1.Session')
            uid = prop(session, 'User', (0, '/'))[0]
            kind = prop(session, 'Class')
            if (not prop(session, 'Active', False) or kind not in ('user', 'greeter') or
                    prop(session, 'Type') not in ('wayland', 'x11') or not uid):
                return
            account = pwd.getpwuid(uid)
            parent, worker = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
            parent.setblocking(False)
            environment = {
                'HOME': account.pw_dir, 'USER': account.pw_name, 'LOGNAME': account.pw_name,
                'XDG_RUNTIME_DIR': f'/run/user/{uid}',
                'DBUS_SESSION_BUS_ADDRESS': f'unix:path=/run/user/{uid}/bus',
                'DCONF_PROFILE': 'gdm' if kind == 'greeter' else 'user',
                'PATH': '/run/current-system/sw/bin',
            }
            for name in ('GSETTINGS_SCHEMA_DIR', 'LOCALE_ARCHIVE', 'LANG', 'LC_ALL'):
                if name in os.environ:
                    environment[name] = os.environ[name]
            try:
                child = subprocess.Popen(
                    [self.session_program, '--fd', str(worker.fileno()),
                     '--session-path', path, '--class', kind],
                    user=uid, group=account.pw_gid, extra_groups=[],
                    pass_fds=(worker.fileno(),), env=environment)
            except BaseException:
                parent.close()
                raise
            finally:
                worker.close()
            self.session, self.session_path, self.uid = session, path, uid
            session.connect('g-properties-changed', lambda *_: self.reconcile())
            self.child, self.channel = child, parent
            self.channel_watch = GLib.io_add_watch(
                parent.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.worker_input)
            self.send({'type': 'snapshot', 'preparing': self.preparing,
                       'at': now_ms(), 'down': self.key_down()})
            self.log(f'started session controller for uid={uid} class={kind}')
        except (GLib.Error, OSError, KeyError) as error:
            self.log(f'session controller unavailable: {error}')
            self.stop(1)

    def active_worker(self):
        return (self.channel is not None and self.session is not None and
                prop(self.seat, 'ActiveSession', ('', '/'))[1] == self.session_path and
                prop(self.session, 'Active', False) and
                prop(self.session, 'User', (0, '/'))[0] == self.uid)

    def worker_input(self, _fd, condition):
        try:
            while True:
                packet = receive_packet(self.channel)
                if packet is None:
                    break
                if not self.active_worker():
                    self.reconcile()
                    return GLib.SOURCE_REMOVE
                action = packet.get('action')
                if action == 'ready' and type(packet.get('value')) is bool:
                    self.child_ready = packet['value']
                    self.set_grab(self.child_ready)
                    if self.child_ready:
                        self.send({'type': 'reset', 'down': self.key_down()})
                elif (action == 'suspend' and self.child_ready and
                      type(packet.get('token')) is int and packet['token'] >= 0):
                    self.request_suspend(packet['token'])
                elif (action == 'wake' and self.child_ready and
                      type(packet.get('token')) is int and packet['token'] >= 0):
                    self.request_wake(packet['token'])
                else:
                    raise ValueError('invalid controller request')
            if condition & (GLib.IO_HUP | GLib.IO_ERR):
                raise EOFError('session controller closed')
        except (OSError, ValueError, EOFError) as error:
            self.log(str(error))
            self.stop(1)
            return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    def request_wake(self, token):
        error = None
        if self.preparing or self.suspend_pending:
            error = 'System is preparing to sleep'
        else:
            for value in (1, 0):
                self.activity_device.write(evdev.ecodes.EV_KEY, evdev.ecodes.KEY_WAKEUP, value)
                self.activity_device.syn()
        self.send({'type': 'done', 'kind': 'activity', 'token': token, 'error': error})

    def request_suspend(self, token):
        if self.preparing:
            self.send({'type': 'sleep', 'preparing': True, 'at': now_ms(),
                       'down': self.key_down()})
            return
        if self.suspend_pending:
            # A queued request is not proof of PrepareForSleep. In particular,
            # a replacement worker must not be left asleep if that call fails.
            self.send({'type': 'done', 'kind': 'suspend', 'token': token,
                       'error': 'Another suspend request is pending'})
            return
        self.suspend_pending = True
        self.suspend_serial += 1
        serial = self.suspend_serial
        requesting_channel = self.channel

        def finished(proxy, result, *_):
            error = None
            try:
                proxy.call_finish(result)
            except GLib.Error as failure:
                error = str(failure)
                if self.suspend_serial == serial:
                    self.suspend_pending = False
            if self.channel is requesting_channel and self.suspend_serial == serial:
                self.send({'type': 'done', 'kind': 'suspend', 'token': token, 'error': error})

        self.manager.call('Suspend', GLib.Variant('(b)', (False,)),
                          Gio.DBusCallFlags.NONE, 5000, None, finished)

    def send(self, packet):
        if self.channel is not None:
            try:
                send_packet(self.channel, packet)
            except (OSError, ValueError) as error:
                self.log(f'controller transport failed: {error}')
                self.stop(1)

    def open_input(self):
        self.retry = None
        if self.stopping:
            return GLib.SOURCE_REMOVE
        for path in evdev.list_devices():
            try:
                device = evdev.InputDevice(path)
            except OSError:
                continue  # Hot-unplug between enumeration and open.
            try:
                matching = (device.name == 'pmic_pwrkey' and
                            evdev.ecodes.KEY_POWER in device.capabilities().get(evdev.ecodes.EV_KEY, []))
            except OSError:
                device.close()
                continue
            if not matching:
                device.close()
                continue
            try:
                # Linux input.h: EVIOCSCLOCKID = _IOW('E', 0xa0, int).
                fcntl.ioctl(device.fd, 0x400445A0, struct.pack('i', time.CLOCK_MONOTONIC))
                self.device = device
                self.input_watch = GLib.io_add_watch(
                    device.fd, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.input_ready)
                self.set_grab(self.child_ready)
                if self.child_ready:
                    self.send({'type': 'reset', 'down': self.key_down()})
                self.log(f'attached {path} ({device.name})')
                return GLib.SOURCE_REMOVE
            except OSError as error:
                device.close()
                self.device = None
                self.log(f'input setup failed: {error}')
                self.stop(1)
                return GLib.SOURCE_REMOVE
        self.retry = GLib.timeout_add(1000, self.open_input)
        return GLib.SOURCE_REMOVE

    def key_down(self):
        try:
            return bool(self.device and evdev.ecodes.KEY_POWER in self.device.active_keys())
        except OSError:
            return False  # The input watch will handle hot-unplug/retry.

    def set_grab(self, wanted):
        if not self.device or self.grabbed == wanted:
            return
        if wanted:
            # Discard events already handled by Mutter during the handoff.
            try:
                list(self.device.read())
            except BlockingIOError:
                pass
            self.device.grab()
        else:
            try:
                self.device.ungrab()
            except OSError:
                pass  # Device removal also releases a grab.
        self.grabbed = wanted
        self.log('input owned by controller' if wanted else 'input released')

    def read_input(self):
        if not self.device:
            return
        try:
            for event in self.device.read():
                if not self.grabbed:
                    continue
                if event.type == evdev.ecodes.EV_SYN:
                    if event.code == evdev.ecodes.SYN_DROPPED:
                        self.sync_lost = True
                    elif event.code == evdev.ecodes.SYN_REPORT and self.sync_lost:
                        self.sync_lost = False
                        self.send({'type': 'reset', 'down': self.key_down()})
                    continue
                if (not self.sync_lost and event.type == evdev.ecodes.EV_KEY and
                        event.code == evdev.ecodes.KEY_POWER):
                    self.send({'type': 'key', 'value': event.value,
                               'at': event.sec * 1000 + event.usec // 1000})
        except BlockingIOError:
            pass

    def input_ready(self, _fd, condition):
        try:
            if condition & (GLib.IO_HUP | GLib.IO_ERR):
                raise OSError('input disconnected')
            self.read_input()
        except OSError as error:
            self.log(str(error))
            self.close_input()
            self.retry = GLib.timeout_add(1000, self.open_input)
            return GLib.SOURCE_REMOVE
        return GLib.SOURCE_CONTINUE

    def close_input(self):
        if self.input_watch:
            GLib.source_remove(self.input_watch)
            self.input_watch = None
        if self.device:
            self.device.close()  # Closing the fd releases EVIOCGRAB.
            self.device = None
        self.grabbed = False
        self.sync_lost = False

    def stop_worker(self):
        self.set_grab(False)
        if self.channel_watch:
            GLib.source_remove(self.channel_watch)
            self.channel_watch = None
        if self.channel:
            self.channel.close()
            self.channel = None
        if self.child:
            try:
                self.child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                # The worker normally exits on channel EOF. If it does not,
                # exit the service and let systemd clean its control group;
                # the broker does not need CAP_KILL over other user IDs.
                self.log('controller did not exit on EOF; restarting the service')
                self.exit_code, self.stopping = 1, True
                self.close_input()
                self.loop.quit()
                return False
            self.child = None
        self.child_ready = False
        self.session = self.session_path = self.uid = None
        return True

    def stop(self, status=0):
        if self.stopping:
            return GLib.SOURCE_REMOVE
        self.stopping, self.exit_code = True, status
        self.stop_worker()
        self.close_input()
        self.activity_device.close()
        if self.retry:
            GLib.source_remove(self.retry)
            self.retry = None
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def run(self):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.stop)
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self.stop)
        self.open_input()
        self.reconcile()
        if not self.stopping:
            self.loop.run()
        return self.exit_code


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session-program', required=True)
    options = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('The input broker must run as root')
    raise SystemExit(Broker(options.session_program).run())
