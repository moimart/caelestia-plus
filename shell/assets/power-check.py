#!/usr/bin/env python3
"""What besides the shell can put this computer to sleep, for Settings → Power.

Prints JSON. Only reads: the system's own idle and lid settings (from logind,
so whatever config they came from), the steps in hypridle's config, and which
other power managers are running.
"""

import json
import os
import re
import subprocess
from pathlib import Path

LOGIND = ("org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager")
# As ps shows them: at most 15 characters
OTHERS = {
    "org_kde_powerde": "KDE Power Management",
    "gsd-power": "GNOME Power",
    "xfce4-power-man": "Xfce Power Manager",
    "mate-power-mana": "MATE Power Manager",
    "lxqt-powermanag": "LXQt Power Management",
    "cosmic-settings": "COSMIC Settings",
    "swayidle": "swayidle",
    "xidlehook": "xidlehook",
    "xautolock": "xautolock",
}


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def last_word(text):
    return text.split(" ", 1)[1].strip('"') if " " in text else ""


def prop(name):
    return last_word(run("busctl", "get-property", *LOGIND, name))


def can(name):
    return last_word(run("busctl", "call", *LOGIND, name))


def hypridle_sleeps():
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hypr" / "hypridle.conf"
    try:
        text = config.read_text()
    except OSError:
        return []
    text = re.sub(r"^\s*#.*$", "", text, flags=re.M)
    sleeps = []
    for block in re.findall(r"listener\s*\{(.*?)\}", text, flags=re.S):
        command = re.search(r"on-timeout\s*=\s*(.+)", block)
        timeout = re.search(r"timeout\s*=\s*(\d+)", block)
        if command and timeout and re.search(r"suspend|hibernate|hybrid-sleep", command[1]):
            sleeps.append({"timeout": int(timeout[1]), "command": command[1].strip()})
    return sleeps


def main():
    comms = set(run("ps", "-eo", "comm=").splitlines())
    idle_usec = prop("IdleActionUSec")
    print(json.dumps({
        "idleAction": prop("IdleAction"),
        "idleSeconds": int(idle_usec) // 1000000 if idle_usec.isdigit() else 0,
        "lid": prop("HandleLidSwitch"),
        "canSuspend": can("CanSuspend"),
        "canHibernate": can("CanHibernate"),
        "hypridleRunning": "hypridle" in comms,
        "hypridleSleeps": hypridle_sleeps(),
        "others": [name for comm, name in OTHERS.items() if comm in comms],
    }))


if __name__ == "__main__":
    main()
