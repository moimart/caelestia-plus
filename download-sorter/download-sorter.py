#!/usr/bin/env python3
"""Move finished downloads out of a watched folder by extension rules.

Watches the folder with inotify for files that were closed after writing or
renamed into place (browsers download to *.part / *.crdownload and rename
when done), waits until each file has stopped changing for `settle` seconds,
then moves it to the first rule whose patterns match. Config is TOML, by
default ~/.config/download-sorter/config.toml, re-read when it changes.
Standard library only; inotify via the sibling inotify.py.
"""

import argparse
import fnmatch
import logging
import os
import select
import shutil
import stat
import sys
import time
import tomllib
from pathlib import Path

from inotify import IN_CLOSE_WRITE, IN_IGNORED, IN_ISDIR, IN_MOVED_TO, IN_Q_OVERFLOW, Inotify

DEFAULT_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "download-sorter" / "config.toml"
DEFAULT_IGNORE = ["*.part", "*.crdownload", "*.download", "*.tmp", "*.partial", ".*"]

log = logging.getLogger("download-sorter")


def expand(path: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(path)))


class Config:
    def __init__(self, path: Path):
        self.path = path
        self.mtime = None
        self.load()

    def load(self) -> None:
        with open(self.path, "rb") as f:
            data = tomllib.load(f)
        self.mtime = self.path.stat().st_mtime
        self.watch = expand(data.get("watch", "~/Downloads"))
        self.settle = float(data.get("settle", 3))
        self.sweep = bool(data.get("sweep", True))
        self.ignore = [p.lower() for p in data.get("ignore", DEFAULT_IGNORE)]
        self.rules = []
        for i, rule in enumerate(data.get("rule", [])):
            patterns = rule.get("match")
            if isinstance(patterns, str):
                patterns = [patterns]
            if not patterns or "dest" not in rule:
                raise ValueError(f"rule {i + 1} needs `match` and `dest`")
            self.rules.append({
                "match": [p.lower() for p in patterns],
                "dest": expand(rule["dest"]),
                "executable": bool(rule.get("executable", False)),
            })

    def reload_if_changed(self) -> bool:
        try:
            if self.path.stat().st_mtime == self.mtime:
                return False
            watch = self.watch
            self.load()
            log.info("reloaded %s (%d rules)", self.path, len(self.rules))
            return self.watch != watch
        except (OSError, ValueError, tomllib.TOMLDecodeError) as e:
            log.error("keeping previous config, %s is invalid: %s", self.path, e)
            self.mtime = self.path.stat().st_mtime if self.path.exists() else None
            return False

    def rule_for(self, name: str):
        lower = name.lower()
        if any(fnmatch.fnmatchcase(lower, p) for p in self.ignore):
            return None
        for rule in self.rules:
            if any(fnmatch.fnmatchcase(lower, p) for p in rule["match"]):
                return rule
        return None


def free_name(dest_dir: Path, name: str) -> Path:
    """`name` in dest_dir, or `stem (n).ext` if that's taken."""
    target = dest_dir / name
    if not target.exists():
        return target
    suffixes = Path(name).suffixes
    ext = "".join(suffixes[-2:]) if len(suffixes) > 1 and suffixes[-2].lower() == ".tar" else Path(name).suffix
    stem = name[: len(name) - len(ext)]
    for n in range(1, 1000):
        target = dest_dir / f"{stem} ({n}){ext}"
        if not target.exists():
            return target
    raise FileExistsError(f"no free name for {name} in {dest_dir}")


def move(path: Path, rule) -> None:
    dest_dir = rule["dest"]
    dest_dir.mkdir(parents=True, exist_ok=True)
    target = free_name(dest_dir, path.name)
    shutil.move(path, target)
    if rule["executable"]:
        mode = target.stat().st_mode
        target.chmod(mode | stat.S_IXUSR | (stat.S_IXGRP if mode & stat.S_IRGRP else 0) | (stat.S_IXOTH if mode & stat.S_IROTH else 0))
    log.info("moved %s -> %s", path.name, target)


class Watcher:
    def __init__(self, config: Config):
        self.config = config
        self.inotify = Inotify()
        self.wd = None
        self.pending: dict[str, tuple[float, tuple]] = {}  # name -> (first seen, last stat)
        self.add_watch()

    def add_watch(self) -> None:
        if self.wd is not None:
            self.inotify.rm_watch(self.wd)
        self.config.watch.mkdir(parents=True, exist_ok=True)
        self.wd = self.inotify.add_watch(self.config.watch, IN_CLOSE_WRITE | IN_MOVED_TO)
        log.info("watching %s (%d rules)", self.config.watch, len(self.config.rules))
        if self.config.sweep:
            self.sweep()

    def sweep(self) -> None:
        for entry in os.scandir(self.config.watch):
            if entry.is_file(follow_symlinks=False):
                self.queue(entry.name)

    def queue(self, name: str) -> None:
        if self.config.rule_for(name):
            self.pending.setdefault(name, (time.monotonic(), ()))

    def read_events(self) -> None:
        for _wd, mask, name in self.inotify.read():
            if mask & IN_Q_OVERFLOW:
                log.warning("inotify queue overflowed, rescanning")
                self.sweep()
            elif mask & IN_IGNORED:
                log.warning("watch on %s was removed, re-adding", self.config.watch)
                self.wd = None
                self.add_watch()
            elif name and not mask & IN_ISDIR:
                self.queue(name)

    def settle(self) -> None:
        now = time.monotonic()
        for name, (seen, last) in list(self.pending.items()):
            path = self.config.watch / name
            try:
                st = path.stat(follow_symlinks=False)
            except FileNotFoundError:
                del self.pending[name]
                continue
            if not stat.S_ISREG(st.st_mode):
                del self.pending[name]
                continue
            current = (st.st_size, st.st_mtime_ns)
            if current != last:
                self.pending[name] = (now, current)  # still changing: restart the clock
                continue
            if now - seen < self.config.settle:
                continue
            del self.pending[name]
            rule = self.config.rule_for(name)  # config may have changed meanwhile
            if rule:
                try:
                    move(path, rule)
                except OSError as e:
                    log.error("could not move %s: %s", name, e)

    def run(self) -> None:
        poller = select.poll()
        poller.register(self.inotify.fd, select.POLLIN)
        while True:
            timeout = 1000 if self.pending else 5000
            if poller.poll(timeout):
                self.read_events()
            if self.config.reload_if_changed():
                self.add_watch()
            self.settle()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s", stream=sys.stdout)
    try:
        config = Config(args.config)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as e:
        log.error("cannot load %s: %s", args.config, e)
        return 1
    Watcher(config).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
