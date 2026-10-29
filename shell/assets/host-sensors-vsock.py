#!/usr/bin/env python3
# The VM side of the host temperatures over vsock: connects to the host
# (CID 2) on the given port and copies its readings to stdout, as the ssh
# source does. See host-sensors-vsock-setup.sh for the host side.
import socket
import sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 7770
try:
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect((socket.VMADDR_CID_HOST, port))
except OSError as e:
    print(f"vsock: {e.strerror or e}", file=sys.stderr)
    sys.exit(1)

# Readings come every few seconds: this long without one, the host is gone
s.settimeout(30)
try:
    for line in s.makefile("rb"):
        sys.stdout.write(line.decode(errors="replace"))
        sys.stdout.flush()
except OSError as e:
    print(f"vsock: {e.strerror or e}", file=sys.stderr)
    sys.exit(1)
