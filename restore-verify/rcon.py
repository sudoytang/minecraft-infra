#!/usr/bin/env python3
"""Minimal RCON client. Usage: rcon.py PORT PASSWORD CMD..."""
import socket, struct, sys
def pkt(i, t, b): d = struct.pack('<ii', i, t) + b.encode() + b'\0\0'; return struct.pack('<i', len(d)) + d
def recv(s):
    n = struct.unpack('<i', s.recv(4))[0]; d = b''
    while len(d) < n: d += s.recv(n - len(d))
    return struct.unpack('<ii', d[:8])[0], d[8:-2].decode('utf-8', 'replace')
port, pw = int(sys.argv[1]), sys.argv[2]
s = socket.create_connection(('127.0.0.1', port), timeout=15)
s.sendall(pkt(1, 3, pw)); i, _ = recv(s)
if i == -1: sys.exit('rcon auth failed')
for c in sys.argv[3:]:
    s.sendall(pkt(2, 2, c)); print(recv(s)[1])
