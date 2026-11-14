# SPDX-License-Identifier: MIT
import socket
import unittest
from transport import MAX_PACKET, send_packet, receive_packet


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.a, self.b = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        self.b.setblocking(False)
        self.addCleanup(self.a.close)
        self.addCleanup(self.b.close)

    def test_ordered_messages_and_nonblocking_empty(self):
        self.assertIsNone(receive_packet(self.b))
        for n in range(3):
            send_packet(self.a, {'n': n})
        self.assertEqual([receive_packet(self.b) for _ in range(3)], [{'n': n} for n in range(3)])
        self.assertIsNone(receive_packet(self.b))

    def test_truncated_message_rejected(self):
        self.a.send(b' ' * (MAX_PACKET + 1))
        with self.assertRaises(ValueError):
            receive_packet(self.b)

    def test_nonobject_rejected(self):
        self.a.send(b'[]')
        with self.assertRaises(ValueError):
            receive_packet(self.b)

    def test_eof_is_distinct_from_empty(self):
        self.a.close()
        with self.assertRaises(EOFError):
            receive_packet(self.b)
