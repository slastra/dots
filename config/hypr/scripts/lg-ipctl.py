#!/usr/bin/env python3
"""LG IP Control (TCP 9761): tv-screen.sh's transport since 2026-10-01, independent of the
webOS SSAP API on 3000/3001. It survives the wedge where SSAP refuses
connections while the TV still answers ping (2026-09-30).

Protocol (LG's encrypted IP Control, as implemented by WesSouza/lgtv-ip-control):
key = PBKDF2-SHA256(keycode, fixed salt, 2^14 rounds, 16 bytes). Each message is
AES-ECB(random IV) followed by AES-CBC(IV, command + "\\r", PKCS7-padded).
Replies use the same framing.

The keycode is shown in the TV's hidden IP Control Settings menu
(Settings > General > Network, highlight Wired Connection, type 82888).

usage: lg-ipctl.py "POWER off" | "CURRENT_APP" | "GET_MACADDRESS wired" ...
"""
import os
import socket
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

HOST = os.environ.get("TV_IP", "192.168.11.243")
PORT = 9761
KEYFILE = os.path.expanduser("~/.config/lgtv/ipcontrol.key")
SALT = bytes([0x63, 0x61, 0xB8, 0x0E, 0x9B, 0xDC, 0xA6, 0x63,
              0x8D, 0x07, 0x20, 0xF2, 0xCC, 0x56, 0x8F, 0xB9])


def derive_key(keycode: str) -> bytes:
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=16, salt=SALT, iterations=2**14)
    return kdf.derive(keycode.encode())


def encrypt(key: bytes, command: str) -> bytes:
    data = command.encode() + b"\r"
    if len(data) % 16 == 0:  # the reference pads a full-block message with a space first
        data += b" "
    pad = 16 - len(data) % 16
    data += bytes([pad]) * pad
    iv = os.urandom(16)
    ecb = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    cbc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    return ecb.update(iv) + ecb.finalize() + cbc.update(data) + cbc.finalize()


def decrypt(key: bytes, blob: bytes) -> str:
    ecb = Cipher(algorithms.AES(key), modes.ECB()).decryptor()
    iv = ecb.update(blob[:16]) + ecb.finalize()
    cbc = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    body = blob[16:]
    body = body[: len(body) - len(body) % 16]
    plain = cbc.update(body) + cbc.finalize()
    return plain.split(b"\n")[0].split(b"\r")[0].decode(errors="replace")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    with open(KEYFILE) as f:
        key = derive_key(f.read().strip().upper())  # keycodes are [A-Z0-9]{8}
    # Exit 1 = connected but no reply: the TV in standby keeps 9761 open and
    # stays silent. Exit 3 = could not connect at all.
    # LG_IPCTL_TIMEOUT shortens the wait for polling: a lit TV answers in
    # ~60 ms, and the 5 s default made every standby probe cost 5 s.
    timeout = float(os.environ.get("LG_IPCTL_TIMEOUT", "5"))
    try:
        with socket.create_connection((HOST, PORT), timeout=timeout) as s:
            s.sendall(encrypt(key, sys.argv[1]))
            try:
                reply = s.recv(4096)
            except socket.timeout:
                reply = b""
    except OSError as e:
        print(f"(no connection: {e})")
        return 3
    if not reply:
        print("(no reply)")
        return 1
    print(decrypt(key, reply))
    return 0


if __name__ == "__main__":
    sys.exit(main())
