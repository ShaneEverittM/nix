"""Ask a running game server how many players are on it. Prints "online/max".

Used by `gameserver list` (see gameservers.nix). Both queries are the public,
unauthenticated ones a server browser sends, made from the host straight to the
guest's address, so they need no credentials and nothing inside the guest.

    gameserver-players minecraft HOST PORT   Server List Ping (TCP)
    gameserver-players steam HOST PORT       A2S_INFO (UDP)

Exits non-zero, printing nothing, if the server does not answer in time -- which is
normal while a server is still starting.
"""

import json
import socket
import struct
import sys

TIMEOUT = 3


def varint(n):
    out = b""
    while True:
        byte = n & 0x7F
        n >>= 7
        out += bytes([byte | (0x80 if n else 0)])
        if not n:
            return out


def read_varint(stream):
    n = 0
    for shift in range(0, 35, 7):
        byte = stream.read(1)
        if not byte:
            raise EOFError
        n |= (byte[0] & 0x7F) << shift
        if not byte[0] & 0x80:
            return n
    raise ValueError("varint too long")


def minecraft(host, port):
    def packet(payload):
        return varint(len(payload)) + payload

    name = host.encode()
    # Handshake (id 0): protocol version -1 = "just asking", address, port, next
    # state 1 = status. Then an empty status request (id 0).
    handshake = b"\x00" + varint(0xFFFFFFFF) + varint(len(name)) + name
    handshake += struct.pack(">H", port) + varint(1)
    with socket.create_connection((host, port), timeout=TIMEOUT) as sock:
        sock.sendall(packet(handshake) + packet(b"\x00"))
        stream = sock.makefile("rb")
        read_varint(stream)  # packet length
        read_varint(stream)  # packet id
        status = json.loads(stream.read(read_varint(stream)))
    players = status["players"]
    return players["online"], players["max"]


def steam(host, port):
    request = b"\xff\xff\xff\xffTSource Engine Query\x00"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(TIMEOUT)
        sock.sendto(request, (host, port))
        data = sock.recv(4096)
        if data[4:5] == b"A":
            # Challenge: repeat the request with the number appended.
            sock.sendto(request + data[5:9], (host, port))
            data = sock.recv(4096)
    if data[4:5] != b"I":
        raise ValueError("not an A2S_INFO reply")
    # Header (4), 'I', protocol (1); four NUL-terminated strings (name, map,
    # folder, game); app id (2); players (1); max players (1).
    rest = data[6:]
    for _ in range(4):
        rest = rest[rest.index(b"\x00") + 1:]
    return rest[2], rest[3]


def main():
    protocol, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
    try:
        online, maximum = {"minecraft": minecraft, "steam": steam}[protocol](host, port)
    except (OSError, ValueError, KeyError, EOFError):
        sys.exit(1)
    print(f"{online}/{maximum}")


if __name__ == "__main__":
    main()
