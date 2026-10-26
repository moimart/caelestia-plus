"""Minimal inotify via ctypes (standard library only)."""

import ctypes
import ctypes.util
import os
import struct

IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
IN_ISDIR = 0x40000000
IN_NONBLOCK = 0o4000
IN_CLOEXEC = 0o2000000

_EVENT = struct.Struct("iIII")


class Inotify:
    def __init__(self):
        self._libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        self.fd = self._libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1 failed")

    def add_watch(self, path, mask: int) -> int:
        wd = self._libc.inotify_add_watch(self.fd, os.fsencode(path), mask)
        if wd < 0:
            raise OSError(ctypes.get_errno(), f"cannot watch {path}")
        return wd

    def rm_watch(self, wd: int) -> None:
        self._libc.inotify_rm_watch(self.fd, wd)

    def read(self):
        """Yield (wd, mask, name) for pending events; name is '' for the dir itself."""
        try:
            data = os.read(self.fd, 64 * 1024)
        except BlockingIOError:
            return
        offset = 0
        while offset < len(data):
            wd, mask, _cookie, length = _EVENT.unpack_from(data, offset)
            name = data[offset + _EVENT.size: offset + _EVENT.size + length].rstrip(b"\0")
            offset += _EVENT.size + length
            yield wd, mask, os.fsdecode(name)
