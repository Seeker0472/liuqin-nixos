# SPDX-License-Identifier: MIT
"""Exercise real Gio proxies/methods/properties against a private D-Bus.

The fake logind deliberately separates Lock's reply from LockedHint, including
an indefinitely pending request like the GNOME regression. No CLI mocking.
"""
import gc
from concurrent.futures import ThreadPoolExecutor
import time
import unittest
from unittest.mock import patch
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
from policy import PowerPolicy
from session import DesktopBackend, DISPLAY_NAME, DISPLAY_PATH, SESSION_INTERFACE
from launch import read_environment, DesktopNotReady

LOGIN_NAME = 'org.freedesktop.login1'
LOGIN_PATH = '/org/freedesktop/login1/session/test'
XML = '''<node>
<interface name="org.gnome.Mutter.DisplayConfig">
  <property name="PowerSaveMode" type="i" access="readwrite"/>
</interface>
<interface name="org.freedesktop.login1.Session">
  <method name="Lock"/>
  <property name="Active" type="b" access="read"/>
  <property name="LockedHint" type="b" access="read"/>
</interface>
<interface name="org.freedesktop.UPower">
  <property name="LidIsClosed" type="b" access="read"/>
</interface>
<interface name="org.freedesktop.systemd1.Manager">
  <property name="Environment" type="as" access="read"/>
</interface>
</node>'''


def spin_until(predicate, seconds=3):
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if predicate():
            return
        time.sleep(.001)
    raise AssertionError('D-Bus condition not reached')


class DBusTests(unittest.TestCase):
    def test_desktop_bus_can_appear_after_the_logind_session(self):
        states = []
        with patch.object(Gio, 'bus_get_sync', side_effect=[
                GLib.Error('bus not created yet'), self.client, self.client]):
            backend = DesktopBackend(
                LOGIN_PATH, greeter=False, on_facts=lambda *_: None,
                on_ready=states.append, on_lid=lambda *_: None)
            try:
                self.assertEqual(states, [False])
                self.assertIsNotNone(backend.retry)
                spin_until(lambda: states[-1] is True)
            finally:
                backend.close()
            self.assertIsNone(backend.retry)

    @classmethod
    def setUpClass(cls):
        cls.bus = Gio.TestDBus.new(Gio.TestDBusFlags.NONE)
        cls.bus.up()
        cls.info = Gio.DBusNodeInfo.new_for_xml(XML)

    @classmethod
    def tearDownClass(cls):
        gc.collect()
        cls.bus.down()

    def setUp(self):
        flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
        self.server = Gio.DBusConnection.new_for_address_sync(self.bus.get_bus_address(), flags, None, None)
        self.client = Gio.DBusConnection.new_for_address_sync(self.bus.get_bus_address(), flags, None, None)
        self.values = {'PowerSaveMode': 0, 'Active': True, 'LockedHint': True, 'LidIsClosed': False}
        self.values['Environment'] = []
        self.events, self.pending, self.effects, self.ready_values = [], [], [], []
        self.reject_power = False
        self.registrations = []
        for name, path, interface in [
            (DISPLAY_NAME, DISPLAY_PATH, DISPLAY_NAME),
            (LOGIN_NAME, LOGIN_PATH, SESSION_INTERFACE),
            ('org.freedesktop.UPower', '/org/freedesktop/UPower', 'org.freedesktop.UPower'),
            ('org.freedesktop.systemd1', '/org/freedesktop/systemd1', 'org.freedesktop.systemd1.Manager'),
        ]:
            self.name_call('RequestName', GLib.Variant('(su)', (name, 0)))
            self.registrations.append(self.server.register_object(
                path, self.info.lookup_interface(interface), self.method, self.get_property, self.set_property))
        self.policy = PowerPolicy(self.effect)
        self.backend = DesktopBackend(
            LOGIN_PATH, greeter=False, on_facts=self.facts, on_ready=self.ready,
            on_lid=lambda closed: None, session_connection=self.client, system_connection=self.client)
        spin_until(lambda: self.policy.ready and len(self.backend.proxies) == 3)

    def tearDown(self):
        self.backend.close()
        for invocation in self.pending:
            invocation.return_dbus_error('org.freedesktop.DBus.Error.Failed', 'test cleanup')
        self.pending.clear()
        for registration in self.registrations:
            self.server.unregister_object(registration)
        self.client.close_sync(None)
        self.server.close_sync(None)
        while GLib.MainContext.default().pending():
            GLib.MainContext.default().iteration(False)

    def name_call(self, method, parameters):
        return self.server.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                                     'org.freedesktop.DBus', method, parameters, None,
                                     Gio.DBusCallFlags.NONE, 2000, None)

    def method(self, _connection, _sender, _path, interface, method, _parameters, invocation):
        self.events.append((interface, method))
        if method == 'Lock':
            self.pending.append(invocation)  # No implicit lock or acknowledgement.
        else:
            invocation.return_dbus_error('org.freedesktop.DBus.Error.UnknownMethod', method)

    def get_property(self, _connection, _sender, _path, _interface, name):
        value = self.values[name]
        return GLib.Variant('as' if isinstance(value, list) else 'b' if type(value) is bool else 'i', value)

    def resolve_environment(self, original):
        # The synchronous bootstrap runs in a separate process in production.
        # Keep this private bus's server main context responsive while querying.
        with ThreadPoolExecutor(max_workers=1) as executor:
            result = executor.submit(read_environment, self.client, original)
            spin_until(result.done)
            return result.result()

    def test_configuration_uses_actual_desktop_directories(self):
        self.values['Environment'] = [
            'XDG_CONFIG_HOME=/var/lib/gdm/seat0/config', 'DCONF_PROFILE=gdm',
            'XDG_DATA_DIRS=/desktop/share:/system/share',
            'LD_PRELOAD=/untrusted.so', 'GSETTINGS_SCHEMA_DIR=/another/schema',
        ]
        original = {'HOME': '/run/gdm/home/greeter', 'GSETTINGS_SCHEMA_DIR': '/power/schema'}
        self.assertEqual(self.resolve_environment(original), {
            **original, 'XDG_CONFIG_HOME': '/var/lib/gdm/seat0/config',
            'DCONF_PROFILE': 'gdm', 'XDG_DATA_DIRS': '/desktop/share:/system/share',
        })
        self.assertNotIn('XDG_CONFIG_HOME', original)

    def test_missing_user_manager_cannot_start_with_guessed_configuration(self):
        self.name_call('ReleaseName', GLib.Variant('(s)', ('org.freedesktop.systemd1',)))
        with self.assertRaises(GLib.Error):
            self.resolve_environment({'HOME': '/home/user'})

    def test_bootstrap_waits_for_desktop_environment_import(self):
        self.name_call('ReleaseName', GLib.Variant('(s)', (DISPLAY_NAME,)))
        with self.assertRaises(DesktopNotReady):
            self.resolve_environment({'HOME': '/home/user'})
        self.values['Environment'] = ['XDG_CONFIG_HOME=/desktop/config']
        self.name_call('RequestName', GLib.Variant('(su)', (DISPLAY_NAME, 0)))
        self.assertEqual(self.resolve_environment({'HOME': '/home/user'}), {
            'HOME': '/home/user', 'XDG_CONFIG_HOME': '/desktop/config',
        })

    def set_property(self, _connection, _sender, _path, _interface, name, variant):
        if self.reject_power:
            return False
        self.events.append(('power', variant.unpack()))
        self.change(DISPLAY_PATH, DISPLAY_NAME, name, variant.unpack())
        return True

    def change(self, path, interface, name, value):
        self.values[name] = value
        self.server.emit_signal(None, path, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                                GLib.Variant('(sa{sv}as)', (interface, {name: GLib.Variant(
                                    'b' if type(value) is bool else 'i', value)}, [])))

    def locked(self, value):
        self.change(LOGIN_PATH, SESSION_INTERFACE, 'LockedHint', value)
        spin_until(lambda: self.policy.locked == value)

    def facts(self, power, locked):
        self.policy.facts(now=int(time.monotonic()*1000), power=power, locked=locked)

    def ready(self, value):
        previous = self.policy.ready
        self.ready_values.append(value)
        self.policy.available(value)
        if value and not previous:
            # The broker sends the physical key snapshot after EVIOCGRAB.
            self.policy.reset_key(False)

    def effect(self, effect):
        self.effects.append(effect)
        if effect.kind in ('power', 'lock'):
            self.backend.perform(effect, self.policy.done)
        elif effect.kind == 'activity':
            # The broker acknowledges projection of KEY_WAKEUP. Desktop
            # calls below still go through the real private D-Bus providers.
            self.policy.done('activity', effect.token, now=int(time.monotonic()*1000))

    def press(self, at=1000):
        self.policy.key(1, at=at, now=at)
        self.policy.key(0, at=at+100, now=at+100)

    def test_lit_lock_screen_blanks_while_lock_method_would_never_reply(self):
        self.press()
        spin_until(lambda: any(e.kind == 'suspend' for e in self.effects))
        self.assertEqual(self.events, [('power', 3)])
        self.assertEqual(self.pending, [])

    def test_lock_acknowledgement_is_not_the_lock_barrier(self):
        self.locked(False)
        self.press()
        spin_until(lambda: bool(self.pending))
        self.pending.pop().return_value(None)
        spin_until(lambda: not self.backend.calls)
        self.assertEqual(self.events, [(SESSION_INTERFACE, 'Lock')])
        self.locked(True)
        spin_until(lambda: any(e.kind == 'suspend' for e in self.effects))
        self.assertEqual(self.events[-1], ('power', 3))

    def test_hint_can_complete_before_lock_reply(self):
        self.locked(False)
        self.press()
        spin_until(lambda: bool(self.pending))
        self.locked(True)
        spin_until(lambda: any(e.kind == 'suspend' for e in self.effects))
        self.pending.pop().return_value(None)
        spin_until(lambda: not self.backend.calls)
        self.assertEqual(sum(e.kind == 'suspend' for e in self.effects), 1)

    def test_unresponsive_lock_does_not_block_wake_or_commit_late_suspend(self):
        self.locked(False)
        self.press()
        spin_until(lambda: bool(self.pending))
        self.press(at=1300)
        spin_until(lambda: ('power', 0) in self.events)
        self.locked(True)
        self.pending.pop().return_value(None)
        spin_until(lambda: not self.backend.calls)
        self.assertFalse(any(e.kind == 'suspend' for e in self.effects))
        self.assertNotIn(('power', 3), self.events)

    def test_display_api_error_cannot_commit_suspend(self):
        self.reject_power = True
        self.press()
        spin_until(lambda: any(e.kind == 'error' for e in self.effects))
        self.assertFalse(any(e.kind == 'suspend' for e in self.effects))

    def test_provider_disappearance_releases_input_policy(self):
        self.name_call('ReleaseName', GLib.Variant('(s)', (DISPLAY_NAME,)))
        spin_until(lambda: not self.policy.ready)
        before = len(self.effects)
        self.press()
        self.assertEqual(len(self.effects), before)

    def test_inactive_session_cannot_handle_input(self):
        self.change(LOGIN_PATH, SESSION_INTERFACE, 'Active', False)
        spin_until(lambda: not self.policy.ready)
        self.press()
        self.assertEqual(self.effects, [])
