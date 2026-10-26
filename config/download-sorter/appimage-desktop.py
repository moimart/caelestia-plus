#!/usr/bin/env python3
"""Keep launcher entries in sync with the AppImages in a folder.

For every *.AppImage in the watched folder (default ~/Applications) this
writes a .desktop file to ~/.local/share/applications and installs its icon
into ~/.local/share/icons/hicolor, and removes both when the AppImage goes
away. Name, categories and icon come from the AppImage's own embedded
.desktop file, read with 7z, so nothing inside the AppImage is run. Without
one, the entry is named after the file.

Every file it writes is recorded in a state file, and only those are ever
removed. An existing .desktop file with the same id is taken over only when
its Exec runs an AppImage (an app's own stale self-integration); otherwise
the generated entry gets an `appimage-` prefixed id instead.
Standard library only, plus the 7z binary.
"""

import argparse
import configparser
import json
import logging
import os
import re
import select
import shlex
import stat
import struct
import subprocess
import sys
import time
from pathlib import Path

from inotify import (IN_ATTRIB, IN_CLOSE_WRITE, IN_CREATE, IN_DELETE, IN_IGNORED, IN_MOVED_FROM, IN_MOVED_TO,
                     IN_Q_OVERFLOW, Inotify)

HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "appimage-desktop" / "state.json"
APPS = DATA / "applications"
ICONS = DATA / "icons" / "hicolor"
MARKER = "X-AppImage-Desktop-Managed"
SETTLE = 2.0
ICON_SIZES = [16, 22, 24, 32, 48, 64, 96, 128, 192, 256, 512]

log = logging.getLogger("appimage-desktop")


# --- reading the AppImage -------------------------------------------------

def list_files(appimage: Path) -> dict[str, int]:
    """Paths inside the AppImage -> size, from `7z l -slt`."""
    out = subprocess.run(["7z", "l", "-slt", str(appimage)], capture_output=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(f"7z cannot read {appimage.name}")
    files, path = {}, None
    for line in out.stdout.decode(errors="replace").splitlines():
        if line.startswith("Path = "):
            path = line[7:]
        elif line.startswith("Size = ") and path is not None:
            files[path] = int(line[7:] or 0)
            path = None
    files.pop(str(appimage), None)
    return files


def read_member(appimage: Path, files: dict[str, int], name: str, depth: int = 0) -> bytes | None:
    """File contents, following the AppImage's internal symlinks (7z prints their target)."""
    if name not in files or depth > 4:
        return None
    data = subprocess.run(["7z", "x", "-so", str(appimage), name], capture_output=True, timeout=60).stdout
    target = data.decode(errors="ignore")
    if data and len(data) < 256 and "\n" not in target and not data.startswith((b"\x89PNG", b"<", b"[")):
        resolved = os.path.normpath(os.path.join(os.path.dirname(name), target)).lstrip("/")
        if resolved in files:
            return read_member(appimage, files, resolved, depth + 1)
    return data


def png_size(data: bytes) -> int | None:
    if data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        w, h = struct.unpack(">II", data[16:24])
        return max(w, h)
    return None


def find_icon(appimage: Path, files: dict[str, int], icon: str) -> tuple[bytes, str] | None:
    """(data, "png"|"svg") for the app's icon, preferring the largest."""
    candidates = []
    if icon:
        candidates += [f"{icon}.svg", f"{icon}.png"]
        themed = [p for p in files if re.fullmatch(rf"usr/share/icons/hicolor/[^/]+/apps/{re.escape(icon)}\.(png|svg)", p)]
        candidates += sorted(themed, key=lambda p: (p.endswith(".svg"), files.get(p, 0)), reverse=True)
    candidates.append(".DirIcon")
    for name in candidates:
        data = read_member(appimage, files, name)
        if not data:
            continue
        if png_size(data):
            return data, "png"
        if data.lstrip()[:5] in (b"<?xml", b"<svg ") or b"<svg" in data[:512]:
            return data, "svg"
    return None


def embedded_entry(appimage: Path, files: dict[str, int]) -> configparser.ConfigParser | None:
    for name in sorted(p for p in files if "/" not in p and p.endswith(".desktop")):
        data = read_member(appimage, files, name)
        if not data:
            continue
        entry = new_parser()
        try:
            entry.read_string(data.decode(errors="replace"))
        except configparser.Error:
            continue
        if entry.has_section("Desktop Entry"):
            entry.id = name[: -len(".desktop")]
            return entry
    return None


# --- writing entries ------------------------------------------------------

def new_parser() -> configparser.ConfigParser:
    p = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
    p.optionxform = str  # keys are case-sensitive
    return p


def exec_quote(arg) -> str:
    """Quote one argument for a desktop entry Exec line (double quotes only)."""
    s = str(arg).replace("%", "%%")
    if re.fullmatch(r"[\w@%+=:,./-]+", s):
        return s
    return '"' + re.sub(r'(["`$\\])', r"\\\1", s) + '"'


def rewrite_exec(line: str, appimage: Path) -> str:
    """Replace the program in an Exec line with the AppImage, keeping its arguments."""
    try:
        args = shlex.split(line)
    except ValueError:
        args = []
    if args and args[0] == "env":  # env VAR=x prog ...: AppRun sets up its own env
        args = args[1:]
        while args and re.fullmatch(r"\w+=.*", args[0]):
            args = args[1:]
    args = args[1:]
    return " ".join([exec_quote(appimage), *(a if re.fullmatch(r"%[a-zA-Z]", a) else exec_quote(a) for a in args)])


def pretty_name(appimage: Path) -> str:
    stem = re.sub(r"\.appimage$", "", appimage.name, flags=re.I)
    stem = re.sub(r"[-_.]?(x86[-_]64|amd64|aarch64|arm64|i[3-6]86|linux)\b", "", stem, flags=re.I)
    stem = re.sub(r"[-_ ]?v?\d+(\.\d+)+.*$", "", stem)
    return re.sub(r"[-_]+", " ", stem).strip() or appimage.name


def build_entry(appimage: Path, files: dict[str, int]) -> tuple[configparser.ConfigParser, str]:
    entry = embedded_entry(appimage, files)
    app_id = getattr(entry, "id", None) or re.sub(r"[^\w.-]+", "-", pretty_name(appimage).lower())
    if entry is None:
        entry = new_parser()
        entry["Desktop Entry"] = {"Type": "Application", "Name": pretty_name(appimage), "Categories": "Utility;"}
    for section in entry.sections():
        if section == "Desktop Entry" or section.startswith("Desktop Action "):
            body = entry[section]
            if "Exec" in body or section == "Desktop Entry":
                body["Exec"] = rewrite_exec(body.get("Exec", ""), appimage)
    main = entry["Desktop Entry"]
    main["TryExec"] = str(appimage)
    main.pop("DBusActivatable", None)
    main["X-AppImage-Path"] = str(appimage)
    main[MARKER] = "true"
    return entry, app_id


def write_entry(entry: configparser.ConfigParser, path: Path) -> None:
    lines = []
    for section in entry.sections():
        lines.append(f"[{section}]")
        lines += [f"{k}={v}" for k, v in entry[section].items()]
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text("\n".join(lines))
    tmp.replace(path)


def is_takeover_ok(path: Path) -> bool:
    """May we overwrite this .desktop file? Only if ours or it launches an AppImage."""
    if not path.exists():
        return True
    p = new_parser()
    try:
        p.read(path)
        main = p["Desktop Entry"]
    except (configparser.Error, KeyError, UnicodeDecodeError):
        return False
    if main.get(MARKER) == "true":
        return True
    try:
        prog = shlex.split(main.get("Exec", ""))[0]
    except (ValueError, IndexError):
        return False
    return prog.lower().endswith(".appimage")


# --- reconciling ----------------------------------------------------------

class Sync:
    def __init__(self, folder: Path):
        self.folder = folder
        try:
            self.state = json.loads(STATE.read_text())
        except (OSError, json.JSONDecodeError):
            self.state = {}

    def save(self) -> None:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(self.state, indent=1, sort_keys=True))

    def remove(self, key: str) -> None:
        record = self.state.pop(key)
        for f in record.get("files", []):
            Path(f).unlink(missing_ok=True)
        log.info("removed entry for %s", Path(key).name)

    def add(self, appimage: Path, st: os.stat_result) -> None:
        if not st.st_mode & stat.S_IXUSR:
            appimage.chmod(st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        key = str(appimage)
        if key in self.state:
            self.remove(key)
        try:
            files = list_files(appimage)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            log.warning("%s; adding a plain entry", e)
            files = {}
        entry, app_id = build_entry(appimage, files)
        taken = {Path(f).name for r in self.state.values() for f in r.get("files", [])}
        desktop = APPS / f"{app_id}.desktop"
        if desktop.name in taken or not is_takeover_ok(desktop):
            app_id = f"appimage-{app_id}"
            desktop = APPS / f"{app_id}.desktop"
            n = 2
            while desktop.name in taken or not is_takeover_ok(desktop):
                desktop = APPS / f"{app_id}-{n}.desktop"
                n += 1
        written = []
        icon = find_icon(appimage, files, entry["Desktop Entry"].get("Icon", ""))
        if icon:
            data, kind = icon
            icon_name = f"appimage-desktop.{desktop.stem}"  # one icon per entry, never shared
            if kind == "svg":
                icon_path = ICONS / "scalable" / "apps" / f"{icon_name}.svg"
            else:
                size = png_size(data)
                size = min(ICON_SIZES, key=lambda s: (abs(s - size), -s))
                icon_path = ICONS / f"{size}x{size}" / "apps" / f"{icon_name}.png"
            icon_path.parent.mkdir(parents=True, exist_ok=True)
            icon_path.write_bytes(data)
            written.append(str(icon_path))
            entry["Desktop Entry"]["Icon"] = icon_name
        else:
            entry["Desktop Entry"].pop("Icon", None)
        write_entry(entry, desktop)
        written.append(str(desktop))
        self.state[key] = {"size": st.st_size, "mtime": st.st_mtime_ns, "files": written}
        log.info("added %s -> %s%s", appimage.name, desktop.name, "" if icon else " (no icon)")

    def reconcile(self) -> bool:
        """Sync once. Returns True if some file is still changing and needs another pass."""
        present, busy = {}, False
        now = time.time()
        if self.folder.is_dir():
            for e in os.scandir(self.folder):
                if e.name.lower().endswith(".appimage") and e.is_file():
                    st = e.stat()
                    if now - st.st_mtime < SETTLE:
                        busy = True
                        continue
                    present[str(Path(e.path))] = st
        changed = False
        for key in [k for k in self.state if not Path(k).exists()]:
            self.remove(key)
            changed = True
        for key, st in sorted(present.items()):
            record = self.state.get(key)
            if record and record["size"] == st.st_size and record["mtime"] == st.st_mtime_ns \
                    and all(Path(f).exists() for f in record["files"]):
                continue
            try:
                self.add(Path(key), st)
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as e:
                log.error("skipping %s until it changes: %s", Path(key).name, e)
            changed = True
        if changed:
            self.save()
        return busy


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folder", nargs="?", type=Path, default=HOME / "Applications")
    parser.add_argument("--once", action="store_true", help="sync once and exit")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stdout)

    folder = args.folder.expanduser().resolve()
    folder.mkdir(parents=True, exist_ok=True)
    sync = Sync(folder)
    if args.once:
        sync.reconcile()
        return 0

    inotify = Inotify()
    mask = IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_DELETE | IN_CREATE | IN_ATTRIB
    inotify.add_watch(folder, mask)
    log.info("watching %s", folder)
    poller = select.poll()
    poller.register(inotify.fd, select.POLLIN)
    due = time.monotonic()  # initial sync
    while True:
        timeout = None if due is None else max(0, int((due - time.monotonic()) * 1000))
        if poller.poll(timeout):
            for _wd, ev, _name in inotify.read():
                if ev & IN_IGNORED:
                    log.error("%s went away; exiting so systemd restarts the watch", folder)
                    return 1
                if ev & (mask | IN_Q_OVERFLOW):
                    due = time.monotonic() + SETTLE
        if due is not None and time.monotonic() >= due:
            due = time.monotonic() + SETTLE if sync.reconcile() else None


if __name__ == "__main__":
    sys.exit(main())
