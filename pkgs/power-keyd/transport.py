# SPDX-License-Identifier: MIT
"""Bounded, message-preserving IPC between a broker and its own child."""
import json
import socket

MAX_PACKET = 1024


def send_packet(channel, packet):
    encoded = json.dumps(packet, separators=(',', ':')).encode()
    if len(encoded) > MAX_PACKET:
        raise ValueError('controller packet too large')
    if channel.send(encoded, socket.MSG_NOSIGNAL) != len(encoded):
        raise OSError('incomplete controller packet')


def receive_packet(channel):
    try:
        data, _ancillary, flags, _address = channel.recvmsg(MAX_PACKET)
    except BlockingIOError:
        return None
    if not data:
        raise EOFError('controller disconnected')
    if flags & socket.MSG_TRUNC:
        raise ValueError('controller packet too large')
    packet = json.loads(data)
    if not isinstance(packet, dict):
        raise ValueError('controller packet must be an object')
    return packet
