# SPDX-License-Identifier: MIT
"""Broker trust boundary and event ordering without root or input hardware."""
import socket
from types import SimpleNamespace
import unittest
from unittest.mock import Mock
import evdev
from gi.repository import GLib
from broker import Broker
from transport import send_packet


class BrokerTests(unittest.TestCase):
    def setUp(self):
        self.b = Broker.__new__(Broker)
        self.packets = []
        self.b.send = self.packets.append
        self.b.log = Mock()
        self.b.key_down = Mock(return_value=False)
        self.b.channel = object()
        self.b.child_ready = True
        self.b.preparing = self.b.suspend_pending = False
        self.b.suspend_serial = 0
        self.b.manager = Mock()
        self.b.activity_device = Mock()

    def test_wake_projects_only_the_standard_wakeup_key(self):
        self.b.request_wake(7)
        calls = self.b.activity_device.write.call_args_list
        self.assertEqual([c.args for c in calls], [(evdev.ecodes.EV_KEY, evdev.ecodes.KEY_WAKEUP, 1),
                                                  (evdev.ecodes.EV_KEY, evdev.ecodes.KEY_WAKEUP, 0)])
        self.assertEqual(self.packets, [{'type': 'done', 'kind': 'activity', 'token': 7, 'error': None}])

    def test_pending_suspend_cannot_project_a_premature_wake(self):
        self.b.suspend_pending = True
        self.b.request_wake(7)
        self.b.activity_device.write.assert_not_called()
        self.assertIsNotNone(self.packets[-1]['error'])

    def reply(self):
        callback = self.b.manager.call.call_args.args[-1]
        callback(self.b.manager, object())

    def test_suspend_completion_cannot_target_replacement_session(self):
        self.b.request_suspend(4)
        self.b.channel = object()  # Seat switched to another worker/UID.
        self.reply()
        self.assertEqual(self.packets, [])

    def test_repeated_suspend_request_is_coalesced(self):
        self.b.request_suspend(4)
        self.b.request_suspend(5)
        self.assertEqual(self.b.manager.call.call_count, 1)
        self.assertEqual(self.packets[-1]['type'], 'done')
        self.assertEqual(self.packets[-1]['token'], 5)
        self.assertIsNotNone(self.packets[-1]['error'])
        self.assertFalse(any(p['type'] == 'sleep' for p in self.packets))
        self.assertTrue(self.b.suspend_pending)

    def test_old_error_after_resume_cannot_clear_a_new_suspend(self):
        self.b.request_suspend(4)
        old_callback = self.b.manager.call.call_args.args[-1]
        self.b.read_input = Mock()
        self.b.manager_signal(None, None, 'PrepareForSleep', GLib.Variant('(b)', (False,)))
        self.b.request_suspend(8)
        self.packets.clear()
        self.b.manager.call_finish.side_effect = GLib.Error('late error')
        old_callback(self.b.manager, object())
        self.assertTrue(self.b.suspend_pending)
        self.assertEqual(self.packets, [])

    def test_resume_drains_queued_input_before_notifying_worker(self):
        order = []
        self.b.preparing = self.b.suspend_pending = True
        self.b.read_input = lambda: order.append(('key', self.b.preparing))
        self.b.send = lambda packet: order.append((packet['type'], packet['preparing']))
        self.b.manager_signal(None, None, 'PrepareForSleep', GLib.Variant('(b)', (False,)))
        self.assertEqual(order, [('key', True), ('sleep', False)])
        self.assertFalse(self.b.suspend_pending)

    def channel(self):
        parent, worker = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        parent.setblocking(False)
        self.addCleanup(parent.close)
        self.addCleanup(worker.close)
        self.b.channel = parent
        self.b.active_worker = Mock(return_value=True)
        self.b.set_grab = Mock()
        self.b.stop = Mock()
        self.b.reconcile = Mock()
        return worker

    def test_inactive_worker_cannot_suspend(self):
        worker = self.channel()
        self.b.active_worker.return_value = False
        send_packet(worker, {'action': 'suspend', 'token': 7})
        self.b.worker_input(None, GLib.IO_IN)
        self.b.manager.call.assert_not_called()
        self.b.reconcile.assert_called_once()

    def test_readiness_controls_input_grab_and_handoff_snapshot(self):
        worker = self.channel()
        send_packet(worker, {'action': 'ready', 'value': False})
        self.b.worker_input(None, GLib.IO_IN)
        self.b.set_grab.assert_called_with(False)
        self.assertEqual(self.packets, [])
        send_packet(worker, {'action': 'ready', 'value': True})
        self.b.worker_input(None, GLib.IO_IN)
        self.b.set_grab.assert_called_with(True)
        self.assertEqual(self.packets, [{'type': 'reset', 'down': False}])

    def test_worker_cannot_request_arbitrary_privileged_command(self):
        worker = self.channel()
        send_packet(worker, {'action': 'poweroff', 'command': '/bin/sh'})
        self.b.worker_input(None, GLib.IO_IN)
        self.b.manager.call.assert_not_called()
        self.b.stop.assert_called_once_with(1)

    def test_syn_dropped_discards_events_until_resynchronisation(self):
        def event(kind, code, value=0):
            return SimpleNamespace(type=kind, code=code, value=value, sec=1, usec=500)
        codes = evdev.ecodes
        self.b.device = Mock()
        self.b.device.read.return_value = [
            event(codes.EV_SYN, codes.SYN_DROPPED),
            event(codes.EV_KEY, codes.KEY_POWER, 1),
            event(codes.EV_KEY, codes.KEY_POWER, 0),
            event(codes.EV_SYN, codes.SYN_REPORT),
            event(codes.EV_KEY, codes.KEY_POWER, 1),
        ]
        self.b.sync_lost = False
        self.b.grabbed = True
        self.b.read_input()
        self.assertEqual(self.packets, [{'type': 'reset', 'down': False},
                                       {'type': 'key', 'value': 1, 'at': 1000}])
