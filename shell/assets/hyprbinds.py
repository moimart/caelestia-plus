#!/usr/bin/env python3
"""Lists the active Hyprland keybinds, described from the user's config.

With the Lua config (Hyprland 0.55+) every bind's action is an opaque Lua
callback, so `hyprctl binds` alone can't tell what a bind does. This reads the
config the way Hyprland loads it -- hyprland.lua and the modules it
require()s, or hyprland.conf and the files it `source`s -- evaluates each
hl.bind() / bind= line (including binds made in loops), pairs it with the live
bind from `hyprctl binds -j`, and derives a title, category and icon from the
dispatcher, the command, the config's own comments and the global shortcuts
apps have registered.

    hyprbinds.py [--config PATH] [--pretty]

Prints JSON: {"source", "config", "binds": [...], "unbound": [...]}.
Standard library only.
"""

import argparse
import configparser
import difflib
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path

HOME = str(Path.home())
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or f"{HOME}/.config")


def _first_line(path: Path) -> str:
    try:
        return path.read_text().splitlines()[0].strip()
    except (OSError, IndexError):
        return ""

MOD_BITS = {
    "SHIFT": 1, "CAPS": 2, "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD1": 8, "MOD2": 16,
    "MOD3": 32, "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "META": 64, "MOD5": 128,
}
MOD_ORDER = [(64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift"), (2, "Caps"), (16, "Mod2"), (32, "Mod3"), (128, "Mod5")]

# Symbols people write in comments, mapped to keysym names (and implied mods)
KEY_ALIASES = {
    "`": (0, "grave"), "~": (1, "grave"), "/": (0, "slash"), "?": (1, "slash"), ".": (0, "period"),
    ",": (0, "comma"), "-": (0, "minus"), "=": (0, "equal"), "\\": (0, "backslash"),
    "[": (0, "bracketleft"), "]": (0, "bracketright"), ";": (0, "semicolon"), "'": (0, "apostrophe"),
    "enter": (0, "return"), "esc": (0, "escape"), "del": (0, "delete"), "mmb": (0, "mouse:274"),
}

KEY_LABELS = {
    "grave": "`", "space": "Space", "return": "Enter", "escape": "Esc", "delete": "Del", "tab": "Tab",
    "backspace": "Backspace", "page_up": "PgUp", "page_down": "PgDn", "prior": "PgUp", "next": "PgDn",
    "home": "Home", "end": "End", "insert": "Ins", "print": "PrtSc", "left": "←", "right": "→", "up": "↑",
    "down": "↓", "comma": ",", "period": ".", "minus": "−", "equal": "=", "plus": "+", "backslash": "\\",
    "slash": "/", "semicolon": ";", "apostrophe": "'", "bracketleft": "[", "bracketright": "]",
    "caps_lock": "Caps Lock", "num_lock": "Num Lock",
}
# (label, icon) for keys better shown as a symbol
KEY_ICONS = {
    "mouse:272": ("Left click", "mouse"), "mouse:273": ("Right click", "mouse"),
    "mouse:274": ("Middle click", "mouse"), "mouse:275": ("Back button", "mouse"),
    "mouse:276": ("Forward button", "mouse"), "mouse:277": ("Button 6", "mouse"),
    "mouse_up": ("Scroll up", "swipe_up"), "mouse_down": ("Scroll down", "swipe_down"),
    "mouse_left": ("Scroll left", "swipe_left"), "mouse_right": ("Scroll right", "swipe_right"),
    "xf86audioplay": ("Play", "play_arrow"), "xf86audiopause": ("Pause", "pause"),
    "xf86audionext": ("Next", "skip_next"), "xf86audioprev": ("Previous", "skip_previous"),
    "xf86audiostop": ("Stop", "stop"), "xf86audioraisevolume": ("Volume up", "volume_up"),
    "xf86audiolowervolume": ("Volume down", "volume_down"), "xf86audiomute": ("Mute", "volume_off"),
    "xf86audiomicmute": ("Mic mute", "mic_off"), "xf86monbrightnessup": ("Brightness up", "brightness_high"),
    "xf86monbrightnessdown": ("Brightness down", "brightness_low"), "xf86calculator": ("Calculator", "calculate"),
    "xf86poweroff": ("Power", "power_settings_new"), "xf86sleep": ("Sleep", "bedtime"),
}

GLOBAL_ICONS = {
    "launcher": "apps", "dashboard": "dashboard", "session": "power_settings_new", "sidebar": "view_sidebar",
    "utilities": "construction", "showall": "dashboard_customize", "lock": "lock", "unlock": "lock_open",
    "clearNotifs": "clear_all", "brightnessUp": "brightness_high", "brightnessDown": "brightness_low",
    "mediaToggle": "play_pause", "mediaNext": "skip_next", "mediaPrev": "skip_previous", "mediaStop": "stop",
    "screenshot": "screenshot_region", "screenshotFreeze": "screenshot_region", "screenshotClip": "screenshot_region",
    "screenshotFreezeClip": "screenshot_region", "nexus": "settings", "refreshDevices": "refresh",
    "keybinds": "keyboard", "launcherInterrupt": "apps",
}

DRAWER_ICONS = {"launcher": "apps", "dashboard": "dashboard", "sidebar": "view_sidebar",
                "session": "power_settings_new", "utilities": "construction", "osd": "tune", "keybinds": "keyboard"}

# Commands recognised by pattern: (regex on the normalised command, title, icon)
COMMANDS = [
    (r"^(?:qs -c caelestia ipc call|caelestia shell) drawers toggle (\w+)", "Toggle {0}", "drawer"),
    (r"^(?:qs -c caelestia ipc call|caelestia shell) keybinds toggle", "Keyboard shortcuts", "keyboard"),
    (r"^(?:qs -c caelestia ipc call|caelestia shell) nexus open", "Shell settings", "settings"),
    (r"^qs -c caelestia kill;\s*caelestia shell -d", "Restart the shell", "restart_alt"),
    (r"^qs -c caelestia kill$", "Quit the shell", "cancel"),
    (r"^caelestia shell -d", "Start the shell", "play_circle"),
    (r"^caelestia screenshot", "Screenshot", "screenshot_monitor"),
    (r"^caelestia record -s", "Record screen with sound", "screen_record"),
    (r"^caelestia record -r", "Record a region", "screen_record"),
    (r"^caelestia record", "Record screen", "screen_record"),
    (r"^caelestia clipboard -d", "Delete from clipboard history", "delete"),
    (r"^caelestia clipboard", "Clipboard history", "content_paste"),
    (r"^caelestia emoji", "Emoji picker", "mood"),
    (r"^caelestia resizer pip", "Picture-in-picture", "picture_in_picture_alt"),
    (r"^caelestia wallpaper", "Change wallpaper", "wallpaper"),
    (r"^caelestia scheme", "Change colour scheme", "palette"),
    (r"^hyprpicker", "Colour picker", "colorize"),
    (r"hyprctl reload", "Reload Hyprland config", "refresh"),
    (r"^hyprlock", "Lock with hyprlock", "lock"),
    (r"^loginctl lock-session", "Lock the session", "lock"),
    (r"wpctl set-volume\b.*\+$", "Volume up", "volume_up"),
    (r"wpctl set-volume\b.*-$", "Volume down", "volume_down"),
    (r"wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", "Mute microphone", "mic_off"),
    (r"wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "Mute audio", "volume_off"),
    (r"(?:pamixer|pactl).*(?:-i|\+)", "Volume up", "volume_up"),
    (r"(?:pamixer|pactl).*(?:-d|-\d)", "Volume down", "volume_down"),
    (r"brightnessctl.*\+", "Brightness up", "brightness_high"),
    (r"brightnessctl.*-", "Brightness down", "brightness_low"),
    (r"playerctl play-pause", "Play / pause", "play_pause"),
    (r"playerctl next", "Next track", "skip_next"),
    (r"playerctl previous", "Previous track", "skip_previous"),
    (r"^notify-send", "Send a test notification", "notifications"),
    (r"ydotool type", "Type the last clipboard entry", "keyboard"),
    (r"^grim|^hyprshot|^grimblast", "Screenshot", "screenshot_monitor"),
    (r"^wlogout|^systemctl poweroff", "Power menu", "power_settings_new"),
]

# Icon by keyword in the final title, for anything that got no better icon
TITLE_ICONS = [
    (r"^move (the )?(active )?window", "move_item"), (r"\bslot\b|^switch to group", "workspaces"),
    (r"special workspace|scratchpad", "auto_awesome_mosaic"), (r"workspace group", "view_carousel"),
    (r"workspace", "workspaces"), (r"\bgroup\b", "tab_group"), (r"zoom", "zoom_in"), (r"\bhdr\b", "hdr_on"),
    (r"screenshot", "screenshot_region"), (r"record", "screen_record"), (r"wallpaper", "wallpaper"),
    (r"notification", "notifications"), (r"clipboard", "content_paste"), (r"emoji", "mood"),
    (r"colou?r", "palette"), (r"unlock", "lock_open"), (r"lock", "lock"), (r"mic", "mic"),
    (r"mute", "volume_off"), (r"volume", "volume_up"), (r"bright", "brightness_6"),
    (r"media|track|play", "music_note"), (r"column", "view_column"), (r"split", "vertical_split"),
    (r"float", "picture_in_picture_alt"), (r"fullscreen|maximi", "fullscreen"), (r"close|kill", "close"),
    (r"resize", "open_in_full"), (r"cent(er|re)", "center_focus_strong"), (r"pin", "push_pin"),
    (r"monitor|display|hdmi|tv\b", "tv"), (r"rescue", "emergency"), (r"overview|expo", "grid_view"),
    (r"cycle|switch", "swap_horiz"), (r"reload|refresh", "refresh"), (r"restart", "restart_alt"),
    (r"shell", "terminal"), (r"window", "web_asset"), (r"test", "science"), (r"mirror|iphone|phone", "phone_iphone"),
    (r"launch|open", "open_in_new"),
]

CATEGORY_ICONS = [
    (r"shell|caelestia|ipc", "auto_awesome"), (r"workspace", "workspaces"), (r"group", "tab_group"),
    (r"window|focus|resiz", "web_asset"), (r"\bapps?\b|launch", "apps"), (r"util|tool", "construction"),
    (r"volume|audio|sound|mic", "volume_up"), (r"media|music|player", "music_note"),
    (r"clipboard|emoji", "content_paste"), (r"wallpaper", "wallpaper"), (r"screenshot|record", "screenshot_region"),
    (r"column|scroll|zoom|layout", "view_column"), (r"\btv\b|monitor|display|sink|hdmi", "tv"),
    (r"overview|expo", "grid_view"), (r"test|debug", "science"), (r"other", "more_horiz"),
]

DIRECTIONS = {"l": "left", "r": "right", "u": "up", "d": "down", "left": "left", "right": "right", "up": "up",
              "down": "down", "t": "up", "b": "down"}
DIR_ARROWS = {"left": "arrow_back", "right": "arrow_forward", "up": "arrow_upward", "down": "arrow_downward"}


# --- environment ----------------------------------------------------------------

def desktop_env() -> dict:
    env = dict(os.environ)
    runtime = Path(env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    hypr = runtime / "hypr"
    sig = env.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if hypr.is_dir() and (not sig or not (hypr / sig).is_dir()):
        dirs = sorted(hypr.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        if dirs:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = dirs[0].name
    return env


def hyprctl(*args: str) -> str | None:
    try:
        out = subprocess.run(["hyprctl", *args], capture_output=True, text=True, env=desktop_env(), timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout if out.returncode == 0 else None


def live_binds() -> list[dict] | None:
    out = hyprctl("binds", "-j")
    try:
        return json.loads(out) if out else None
    except json.JSONDecodeError:
        return None


def global_shortcuts() -> dict[str, str]:
    shortcuts = {}
    for line in (hyprctl("globalshortcuts") or "").splitlines():
        name, sep, desc = line.partition(" -> ")
        if sep:
            shortcuts[name.strip()] = desc.strip()
    return shortcuts


# --- desktop entries --------------------------------------------------------------

class Apps:
    def __init__(self):
        self.entries = []
        dirs = [os.environ.get("XDG_DATA_HOME") or f"{HOME}/.local/share"]
        dirs += (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
        seen = set()
        for d in dirs:
            for path in sorted(glob.glob(f"{d}/applications/**/*.desktop", recursive=True)):
                did = os.path.relpath(path, f"{d}/applications").replace("/", "-")[:-8]
                if did in seen:
                    continue
                seen.add(did)
                parser = configparser.RawConfigParser(interpolation=None, strict=False)
                try:
                    parser.read(path, encoding="utf-8")
                    entry = parser["Desktop Entry"]
                except (configparser.Error, KeyError, UnicodeDecodeError):
                    continue
                self.entries.append({"id": did, "name": entry.get("Name", did), "icon": entry.get("Icon", ""),
                                     "exec": entry.get("Exec", ""), "wmclass": entry.get("StartupWMClass", ""),
                                     "nodisplay": entry.get("NoDisplay", "").lower() == "true"})

    def by_binary(self, binary: str) -> dict | None:
        candidates = [binary]
        if "-" in binary:
            candidates.append(binary.split("-")[0])
        for cand in candidates:
            # Prefer real launcher entries (with an icon) over stubs that only register mime handlers
            matches = [e for e in self.entries if e["id"].lower() == cand.lower()]
            matches += [e for e in self.entries if (argv := e["exec"].split()) and os.path.basename(argv[0]) == cand]
            if matches:
                return max(matches, key=lambda e: (bool(e["icon"]), not e["nodisplay"]))
        return None

    def by_name(self, name: str, url: str = "") -> dict | None:
        name = name.lower()
        host = re.sub(r"^https?://([^/:]+).*", r"\1", url).removeprefix("www.") if url else ""
        for e in self.entries:
            if name and (e["name"].lower() == name or e["name"].lower().startswith(name + " ")):
                return e
        for e in self.entries:
            if host and host in e["exec"]:
                return e
        return None


# --- Lua -----------------------------------------------------------------------------

LUA_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstr>\[(?P<seq>=*)\[.*?\](?P=seq)\])
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<num>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|::|[-+*/%^\#<>=(){}\[\];:,.])
""", re.S | re.X)
KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
            "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "0": "\0", "a": "\a", "b": "\b"}


class Tok:
    __slots__ = ("kind", "value", "line", "raw")

    def __init__(self, kind, value, line, raw):
        self.kind, self.value, self.line, self.raw = kind, value, line, raw

    def is_(self, kind, value=None):
        return self.kind == kind and (value is None or self.value == value)


def lua_tokens(text: str):
    toks, comments = [], []
    pos, line, last_code_line = 0, 1, 0
    while pos < len(text):
        m = LUA_TOKEN.match(text, pos)
        if not m:
            pos += 1
            continue
        kind, raw = m.lastgroup, m.group()
        if kind in ("comment", "lcomment"):
            body = raw[2:] if kind == "comment" else re.sub(r"^\[=*\[|\]=*\]$", "", raw[2:])
            comments.append({"line": line, "text": body.strip(), "trailing": last_code_line == line})
        elif kind != "ws":
            if kind == "str":
                value = re.sub(r"\\(.)", lambda e: ESCAPES.get(e.group(1), e.group(1)), raw[1:-1])
                kind = "str"
            elif kind == "lstr":
                value = re.sub(r"^\[=*\[\n?|\]=*\]$", "", raw)
                kind = "str"
            elif kind == "num":
                value = int(raw, 0) if re.fullmatch(r"0[xX][0-9a-fA-F]+|\d+", raw) else float(raw)
            elif kind == "name":
                value = raw
                if raw in KEYWORDS:
                    kind = "kw"
            else:
                value = raw
            toks.append(Tok(kind, value, line, raw))
            last_code_line = line + raw.count("\n")
        line += raw.count("\n")
        pos = m.end()
    return toks, comments


class Unknown:
    """A value the evaluator couldn't compute; `text` is a readable stand-in."""

    def __init__(self, text="…"):
        self.text = text

    def __str__(self):
        return self.text


class Text(str):
    """A string that remembers which module fields (e.g. V.terminal) built it."""

    refs: tuple = ()


class Func:
    def __init__(self, toks, start, end, file):
        self.toks, self.start, self.end, self.file = toks, start, end, file  # body tokens [start, end)

    def source(self) -> str:
        return " ".join(t.raw for t in self.toks[self.start:self.end])


class Dsp:
    """A dispatcher built with hl.dsp.*, e.g. name 'window.move' with args [{...}]."""

    def __init__(self, name, args):
        self.name, self.args = name, args

    def arg(self, key=None, index=0):
        if not self.args:
            return None
        first = self.args[index] if index < len(self.args) else None
        if key is None:
            return first
        return first.get(key) if isinstance(first, dict) else None


def as_text(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    if isinstance(v, (str, int, float)):
        return str(v)
    return str(v) if isinstance(v, Unknown) else "…"


def concat(a, b):
    if isinstance(a, Unknown) or isinstance(b, Unknown):
        return Unknown(as_text(a) + as_text(b))
    out = Text(as_text(a) + as_text(b))
    out.refs = getattr(a, "refs", ()) + getattr(b, "refs", ())
    return out


def lua_format(fmt, args):
    it = iter(args)

    def sub(m):
        if m.group() == "%%":
            return "%"
        try:
            return as_text(next(it))
        except StopIteration:
            return m.group()
    return re.sub(r"%%|%[-+ #0]*\d*(?:\.\d+)?[sdifgqxXc]", sub, fmt)


class LuaConfig:
    """Executes just enough of a Hyprland Lua config to see its binds."""

    def __init__(self, entry: Path):
        self.entry = entry
        self.root = entry.parent
        self.search = [self.root / "lua", self.root / "scheme", self.root, CONFIG_HOME / "caelestia"]
        # caelestia-plus layers (hosts/README.md in caelestia-plus): the host
        # profile's modules replace the defaults, so it's searched first
        self.personal = None
        self.host = None
        plus = CONFIG_HOME / "caelestia-plus"
        host = os.environ.get("CAELESTIA_PLUS_HOST") or _first_line(plus / "host") or _first_line(Path("/etc/hostname"))
        if host:
            for d in (plus / "hosts" / host / "hypr", Path("/usr/share/caelestia-plus/hosts") / host / "hypr"):
                if d.is_dir():
                    self.search.insert(0, d)
                    self.host = d / "host.lua" if (d / "host.lua").is_file() else None
                    break
        if (plus / "personal/hypr/personal.lua").is_file():
            self.personal = plus / "personal/hypr/personal.lua"
        self.modules = {}
        self.binds = []
        self.comments = {}  # file -> comments
        self.sections = {}  # file -> [(line, title)]
        self.files = []

    def run(self):
        self.exec_file(self.entry)
        # The packaged config loads these behind checks made at runtime
        for layer in (self.personal, self.host):
            if layer and layer not in self.files:
                self.exec_file(layer)
        return self.binds

    # dofile("<path>"): a config that loads another (the caelestia-plus
    # stub loads the packaged one); its folders join the module search
    def dofile(self, name):
        path = Path(os.path.expanduser(name))
        if not path.is_file() or path in self.files:
            return Unknown(f"dofile({name!r})")
        for d in (path.parent / "scheme", path.parent / "lua"):
            if d not in self.search:
                self.search.insert(1 if self.search and "hosts" in self.search[0].parts else 0, d)
        return self.exec_file(path)

    # --- modules
    def resolve(self, name):
        rel = name.replace(".", "/") + ".lua"
        for d in self.search:
            if (d / rel).is_file():
                return d / rel
        return None

    def require(self, name):
        if name in self.modules:
            return self.modules[name]
        self.modules[name] = Unknown(f"require({name!r})")
        path = self.resolve(name)
        if path:
            self.modules[name] = self.exec_file(path)
        return self.modules[name]

    def exec_file(self, path: Path):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return Unknown()
        toks, comments = lua_tokens(text)
        self.files.append(path)
        self.comments[path] = comments
        self.sections[path] = find_sections(comments)
        env = {"__file": path, "__toks": toks, "__return": None, "__module": True}
        self.block(toks, 0, len(toks), env)
        return env["__return"]

    # --- statements
    def block(self, toks, i, end, env):
        while i < end:
            try:
                i = self.statement(toks, i, end, env)
            except (IndexError, ValueError, TypeError, KeyError, RecursionError):
                i += 1
        return i

    def statement(self, toks, i, end, env):
        t = toks[i]
        if t.is_("kw", "local") and toks[i + 1].is_("kw", "function"):
            name = toks[i + 2].value
            body_start, body_end = self.func_body(toks, i + 2)
            env[name] = Func(toks, body_start, body_end, env["__file"])
            return body_end + 1
        if t.is_("kw", "function"):
            j = i + 1
            while not toks[j].is_("op", "("):
                j += 1
            _, body_end = self.func_body(toks, j - 1)
            return body_end + 1
        if t.is_("kw", "local"):
            names, j = [], i + 1
            while toks[j].kind == "name":
                names.append(toks[j].value)
                j += 1
                if toks[j].is_("op", ","):
                    j += 1
                    continue
                break
            if j < end and toks[j].is_("op", "="):
                values, j = self.exprlist(toks, j + 1, env)
                for n, v in zip(names, values + [None] * len(names)):
                    env[n] = v
            else:
                for n in names:
                    env[n] = None
            return j
        if t.is_("kw", "return"):
            if env.get("__module") and i + 1 < end and not toks[i + 1].is_("kw", "end"):
                env["__return"], j = self.expr(toks, i + 1, env)
                return j
            return i + 1
        if t.is_("kw", "for"):
            return self.for_loop(toks, i, end, env)
        if t.kind == "name":
            # assignment (a.b = x) or a call statement
            j = i
            target, j = self.suffixed(toks, j, env, want_target=True)
            if j < end and toks[j].is_("op", "="):
                value, k = self.expr(toks, j + 1, env)
                if isinstance(target, tuple):
                    obj, key = target
                    if isinstance(obj, dict):
                        obj[key] = value
                else:
                    env[t.value] = value
                return k
            return max(j, i + 1)
        return i + 1

    def func_body(self, toks, name_idx):
        """Given the index just before '(', returns (body_start, index of matching 'end')."""
        j = name_idx + 1
        while not toks[j].is_("op", "("):
            j += 1
        depth = 0
        while True:
            if toks[j].is_("op", "("):
                depth += 1
            elif toks[j].is_("op", ")"):
                depth -= 1
                if depth == 0:
                    break
            j += 1
        start = j + 1
        return start, self.block_end(toks, start)

    @staticmethod
    def block_end(toks, j):
        depth = 1
        while j < len(toks):
            t = toks[j]
            if t.kind == "kw" and t.value in ("function", "do", "if", "repeat"):
                depth += 1
            elif t.kind == "kw" and t.value in ("end", "until"):
                depth -= 1
                if depth == 0:
                    return j
            j += 1
        return j

    def for_loop(self, toks, i, end, env):
        j = i + 1
        names = []
        while toks[j].kind == "name":
            names.append(toks[j].value)
            j += 1
            if toks[j].is_("op", ","):
                j += 1
        iterations = []
        if toks[j].is_("op", "="):
            vals, j = self.exprlist(toks, j + 1, env)
            start, stop = vals[0], vals[1]
            step = vals[2] if len(vals) > 2 else 1
            if all(isinstance(v, (int, float)) for v in (start, stop, step)) and step:
                n = start
                while (step > 0 and n <= stop) or (step < 0 and n >= stop):
                    iterations.append({names[0]: int(n) if float(n).is_integer() else n})
                    n += step
                    if len(iterations) > 200:
                        break
        elif toks[j].is_("kw", "in"):
            it, j = self.expr(toks, j + 1, env)
            if isinstance(it, tuple) and it[0] in ("ipairs", "pairs"):
                seq = it[1]
                pairs = list(enumerate(seq, 1)) if isinstance(seq, list) else list(seq.items()) if isinstance(seq, dict) else []
                for k, v in pairs:
                    iterations.append(dict(zip(names, (k, v))))
        while not toks[j].is_("kw", "do"):
            j += 1
        body_start = j + 1
        body_end = self.block_end(toks, body_start)
        loop_id = f"{env['__file']}:{toks[i].line}"
        for n, values in enumerate(iterations):
            scope = dict(env)
            scope.update(values)
            scope["__loop"] = (loop_id, n, names[0], list(values.values())[0])
            scope["__module"] = False
            self.block(toks, body_start, body_end, scope)
        return body_end + 1

    # --- expressions
    def exprlist(self, toks, j, env):
        values = []
        while True:
            v, j = self.expr(toks, j, env)
            values.append(v)
            if j < len(toks) and toks[j].is_("op", ","):
                j += 1
                continue
            return values, j

    BINARY = {"or": 1, "and": 2, "<": 3, ">": 3, "<=": 3, ">=": 3, "~=": 3, "==": 3, "..": 5,
              "+": 6, "-": 6, "*": 7, "/": 7, "%": 7, "^": 9}

    def expr(self, toks, j, env, limit=0):
        t = toks[j]
        if t.is_("kw", "not") or t.is_("op", "-") or t.is_("op", "#"):
            v, j = self.expr(toks, j + 1, env, 8)
            v = (not truthy(v)) if t.value == "not" else (-v if isinstance(v, (int, float)) else
                                                         len(v) if t.value == "#" and isinstance(v, (str, list)) else Unknown())
        else:
            v, j = self.simple(toks, j, env)
        while j < len(toks):
            t = toks[j]
            op = t.value if t.kind in ("op", "kw") else None
            prec = self.BINARY.get(op)
            if prec is None or prec <= limit:
                break
            # .. and ^ are right associative
            rhs, j = self.expr(toks, j + 1, env, prec - 1 if op in ("..", "^") else prec)
            v = self.binop(op, v, rhs)
        return v, j

    @staticmethod
    def binop(op, a, b):
        if op == "..":
            return concat(a, b)
        if op == "and":
            return b if truthy(a) else a
        if op == "or":
            return a if truthy(a) else b
        if op == "==":
            return a == b
        if op == "~=":
            return a != b
        if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
            try:
                return {"<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b, "+": a + b, "-": a - b,
                        "*": a * b, "/": a / b if b else Unknown(), "%": a % b if b else Unknown(), "^": a ** b}[op]
            except (OverflowError, KeyError):
                return Unknown()
        return Unknown()

    def simple(self, toks, j, env):
        t = toks[j]
        if t.kind in ("str", "num"):
            return t.value, j + 1
        if t.is_("kw", "nil"):
            return None, j + 1
        if t.is_("kw", "true") or t.is_("kw", "false"):
            return t.value == "true", j + 1
        if t.is_("op", "..."):
            return Unknown("..."), j + 1
        if t.is_("op", "{"):
            return self.table(toks, j, env)
        if t.is_("kw", "function"):
            start, body_end = self.func_body(toks, j)
            return Func(toks, start, body_end, env["__file"]), body_end + 1
        return self.suffixed(toks, j, env)

    def table(self, toks, j, env):
        j += 1
        items, keyed = [], {}
        while not toks[j].is_("op", "}"):
            if toks[j].kind == "name" and toks[j + 1].is_("op", "="):
                key = toks[j].value
                keyed[key], j = self.expr(toks, j + 2, env)
            elif toks[j].is_("op", "["):
                key, j = self.expr(toks, j + 1, env)
                j += 1  # ]
                keyed[as_text(key)], j = self.expr(toks, j + 1, env)  # skip =
            else:
                v, j = self.expr(toks, j, env)
                items.append(v)
            if toks[j].is_("op", ",") or toks[j].is_("op", ";"):
                j += 1
        if keyed and not items:
            return keyed, j + 1
        if items and not keyed:
            return items, j + 1
        keyed.update({i + 1: v for i, v in enumerate(items)})
        return keyed, j + 1

    def suffixed(self, toks, j, env, want_target=False):
        """Parses name(.name|[x]|(args)|"str"|{t})* and evaluates it."""
        t = toks[j]
        path = []
        if t.is_("op", "("):
            value, j = self.expr(toks, j + 1, env)
            j += 1
        elif t.kind == "name":
            path = [t.value]
            value = env[t.value] if t.value in env else Unknown(t.value)
            j += 1
        else:
            raise ValueError(f"unexpected {t.raw}")
        last_obj, last_key = None, None
        while j < len(toks):
            t = toks[j]
            if t.is_("op", ".") or t.is_("op", ":"):
                key = toks[j + 1].value
                if path:
                    path.append(key)
                last_obj, last_key = value, key
                if isinstance(value, dict):
                    field = value.get(key)
                    if isinstance(field, str):
                        field = Text(field)
                        field.refs = (key,)
                    value = field
                else:
                    value = Unknown(".".join(path) if path else key)
                j += 2
            elif t.is_("op", "["):
                key, j = self.expr(toks, j + 1, env)
                j += 1
                last_obj, last_key = value, as_text(key)
                value = value.get(key, value.get(as_text(key))) if isinstance(value, dict) else \
                    value[key - 1] if isinstance(value, list) and isinstance(key, int) and 0 < key <= len(value) else Unknown()
                path = []
            elif t.is_("op", "(") or t.kind == "str" or t.is_("op", "{"):
                if t.is_("op", "("):
                    args, j = ([], j + 1) if toks[j + 1].is_("op", ")") else self.exprlist(toks, j + 1, env)
                    j += 1
                elif t.kind == "str":
                    args, j = [t.value], j + 1
                else:
                    tbl, j = self.table(toks, j, env)
                    args = [tbl]
                value = self.call(path, value, args, env, toks[j - 1].line)
                path, last_obj = [], None
            else:
                break
        if want_target and last_obj is not None:
            return (last_obj, last_key), j
        return value, j

    def call(self, path, fn, args, env, line):
        name = ".".join(path)
        if name == "require" and args and isinstance(args[0], str):
            return self.require(args[0])
        if name == "dofile" and args and isinstance(args[0], str):
            return self.dofile(args[0])
        if name == "os.getenv" and args:
            return Text(os.environ.get(as_text(args[0]), ""))
        if name == "tostring" and args:
            return Text(as_text(args[0]))
        if name == "tonumber" and args:
            try:
                return float(args[0]) if "." in str(args[0]) else int(args[0])
            except (TypeError, ValueError):
                return None
        if name in ("string.format", "fmt") and args and isinstance(args[0], str):
            return Text(lua_format(args[0], args[1:]))
        if name in ("ipairs", "pairs") and args:
            return (name, args[0])
        if name == "hl.bind":
            self.binds.append({"args": args, "file": env["__file"], "line": line, "loop": env.get("__loop")})
            return None
        if path[:2] == ["hl", "dsp"]:
            return Dsp(".".join(path[2:]), args)
        if isinstance(fn, Func):
            return Unknown(f"{name}()")
        return Unknown(f"{name}(…)")


def truthy(v):
    return v is not None and v is not False


def find_sections(comments):
    """Section titles from banner comments: a line between two '=====' rules."""
    out = []
    for i, c in enumerate(comments):
        if re.fullmatch(r"[=\-#*~]{5,}", c["text"]) and i + 1 < len(comments):
            nxt = comments[i + 1]
            if nxt["line"] == c["line"] + 1 and not re.fullmatch(r"[=\-#*~]{5,}", nxt["text"]) and nxt["text"]:
                # require a closing rule within the next few comment lines
                for k in range(i + 2, min(i + 5, len(comments))):
                    if re.fullmatch(r"[=\-#*~]{5,}", comments[k]["text"]):
                        out.append((nxt["line"], nxt["text"]))
                        break
    return out


# --- hyprland.conf -------------------------------------------------------------------

def conf_binds(entry: Path):
    """Parses bind lines from hyprland.conf and its sourced files."""
    binds, comments, sections, files = [], {}, {}, []
    variables = {}

    def subst(s):
        return re.sub(r"\$(\w+)", lambda m: variables.get(m.group(1), m.group()), s)

    def read(path: Path, depth=0):
        if depth > 10 or path in files:
            return
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return
        files.append(path)
        fc = comments.setdefault(path, [])
        for n, raw in enumerate(lines, 1):
            code, _, comment = raw.partition("#") if not raw.lstrip().startswith("##") else ("", "", raw.strip("# "))
            if comment and not code.strip():
                fc.append({"line": n, "text": comment.strip(), "trailing": False})
            elif comment:
                fc.append({"line": n, "text": comment.strip(), "trailing": True})
            m = re.match(r"\s*\$(\w+)\s*=\s*(.*?)\s*$", code)
            if m:
                variables[m.group(1)] = subst(m.group(2))
                continue
            m = re.match(r"\s*source\s*=\s*(.*?)\s*$", code)
            if m:
                pattern = os.path.expanduser(subst(m.group(1)))
                if not os.path.isabs(pattern):
                    pattern = str(path.parent / pattern)
                for p in sorted(glob.glob(pattern)):
                    read(Path(p), depth + 1)
                continue
            m = re.match(r"\s*bind([a-z]*)\s*=\s*(.*?)\s*$", code)
            if m:
                flags, fields = m.group(1), [f.strip() for f in subst(m.group(2)).split(",")]
                has_desc = "d" in flags
                if len(fields) < 3 + has_desc:
                    continue
                mods, key = fields[0], fields[1]
                desc = fields[2] if has_desc else ""
                rest = fields[2 + has_desc:]
                dispatcher, arg = rest[0], ",".join(rest[1:]).strip()
                binds.append({"conf": True, "mods": mods, "key": key, "description": desc,
                              "dsp": conf_dispatcher(dispatcher, arg), "flags": flags, "file": path, "line": n,
                              "loop": None})
        sections[path] = find_sections(fc)

    read(entry)
    return binds, comments, sections, files


def conf_dispatcher(name, arg):
    """Maps a hyprland.conf dispatcher to the hl.dsp.* shape used for Lua binds."""
    name = name.lower()
    simple = {"killactive": "window.close", "pin": "window.pin", "centerwindow": "window.center",
              "togglegroup": "group.toggle", "pseudo": "window.pseudo", "togglesplit": None}
    if name == "exec" or name == "execr":
        return Dsp("exec_cmd", [arg])
    if name == "global":
        return Dsp("global", [arg])
    if name == "workspace":
        return Dsp("focus", [{"workspace": arg}])
    if name in ("movetoworkspace", "movetoworkspacesilent"):
        return Dsp("window.move", [{"workspace": arg}])
    if name == "movefocus":
        return Dsp("focus", [{"direction": arg}])
    if name == "movewindow":
        return Dsp("window.drag", []) if not arg else Dsp("window.move", [{"direction": arg}])
    if name == "swapwindow":
        return Dsp("window.swap", [{"direction": arg}])
    if name == "resizewindow":
        return Dsp("window.resize", [])
    if name == "togglefloating":
        return Dsp("window.float", [{"action": "toggle"}])
    if name == "fullscreen":
        return Dsp("window.fullscreen", [{"mode": "maximized" if arg == "1" else "fullscreen"}])
    if name == "togglespecialworkspace":
        return Dsp("workspace.toggle_special", [arg or "special"])
    if name == "layoutmsg":
        return Dsp("layout", [arg])
    if name == "togglesplit":
        return Dsp("layout", ["togglesplit"])
    if name == "changegroupactive":
        return Dsp("group.prev" if arg.startswith("b") else "group.next", [])
    if name == "cyclenext":
        return Dsp("window.cycle_next", [{"next": "prev"}] if "prev" in arg else [])
    if name == "exit":
        return Dsp("exit", [])
    if name in simple and simple[name]:
        return Dsp(simple[name], [])
    return Dsp(f"conf:{name}", [arg])


# --- description -------------------------------------------------------------------------

def parse_combo(combo: str):
    """'CTRL + SUPER + H' or 'SUPER SHIFT, H' -> (modmask, key) with the key lowercased."""
    parts = [p.strip() for p in re.split(r"\s*\+\s*|\s+", combo.strip()) if p.strip()]
    if not parts:
        return 0, ""
    *mods, key = parts
    mask = 0
    for m in mods:
        bit = MOD_BITS.get(m.upper())
        if bit is None:
            return None
        mask |= bit
    alias = KEY_ALIASES.get(key.lower()) or KEY_ALIASES.get(key)
    if alias:
        mask |= alias[0]
        key = alias[1]
    return mask, key.lower()


def conf_mods(mods: str) -> int:
    mask = 0
    for m in re.split(r"[\s_+]+", mods.strip()):
        if m:
            mask |= MOD_BITS.get(m.upper(), 0)
    return mask


def key_cap(key: str) -> dict:
    k = key.lower()
    if k in KEY_ICONS:
        label, icon = KEY_ICONS[k]
        return {"label": label, "icon": icon}
    if k in KEY_LABELS:
        return {"label": KEY_LABELS[k]}
    if k.startswith("code:"):
        return {"label": f"Key {k[5:]}"}
    if k.startswith("xf86"):
        return {"label": re.sub(r"(?<=[a-z])(?=[A-Z])", " ", key[4:])}
    return {"label": key.upper() if len(key) == 1 else key[:1].upper() + key[1:]}


def mod_caps(mask: int) -> list[dict]:
    return [{"label": label, "mod": True} for bit, label in MOD_ORDER if mask & bit]


def humanise(name: str) -> str:
    words = re.sub(r"(?<=[a-z])(?=[A-Z])|_", " ", name).strip()
    return words[:1].upper() + words[1:].lower()


def sentence(text: str, var: str | None = None) -> str:
    text = text.strip().strip("-—–: ")
    text = re.sub(r"^[\w\s-]{1,24}?\b(?:key)?binds?:\s*|^[\w\s-]{1,24}?\bshortcuts?:\s*", "", text, flags=re.I)
    text = re.split(r"(?<=[a-z0-9)])\.(?:\s|$)", text)[0]
    cut = text.find(" (")
    if cut >= 15:
        text = text[:cut]
    if var and len(var) <= 2:
        text = re.sub(rf"\b{re.escape(var)}\b", "N", text)
    if len(text) > 70:
        text = text[:70].rsplit(" ", 1)[0] + "…"
    return text[:1].upper() + text[1:]


def workspace_phrase(ws) -> str:
    ws = as_text(ws)
    if m := re.fullmatch(r"([er]?)([+-])(\d+)", ws):
        n = int(m.group(3))
        direction = "next" if m.group(2) == "+" else "previous"
        if n == 0:
            return "the current workspace"
        if n == 1:
            return f"the {direction} workspace"
        if n == 10:
            return f"the {direction} workspace group"
        return f"{n} workspaces {'forward' if m.group(2) == '+' else 'back'}"
    if ws == "special:special":
        return "the special workspace"
    if ws.startswith("special:"):
        return f"the {ws[8:]} special workspace"
    if ws == "special":
        return "the special workspace"
    if ws.isdigit():
        return f"workspace {ws}"
    if ws.startswith("name:"):
        return f"workspace {ws[5:]}"
    return f"workspace {ws}"


def describe_dsp(d: Dsp, globals_: dict, apps: Apps):
    """-> (title, icon, detail, owner, confident, app) for a dispatcher."""
    n = d.name
    a = d.arg() if d.args else None
    get = (lambda k: a.get(k) if isinstance(a, dict) else None)
    if n == "global":
        name = as_text(a)
        app, _, short = name.partition(":")
        desc = globals_.get(name)
        title = desc or humanise(short or name)
        icon = GLOBAL_ICONS.get(short, "keyboard_command_key") if app == "caelestia" else "keyboard_command_key"
        return title, icon, f"global {name}", "shell" if app == "caelestia" else "app", bool(desc), None
    if n == "exec_cmd":
        return describe_command(a, apps)
    if n == "focus":
        if get("workspace") is not None:
            ws = get("workspace")
            return f"Go to {workspace_phrase(ws)}", ws_icon(ws), f"focus workspace {as_text(ws)}", "hyprland", True, None
        if get("direction") is not None:
            dr = DIRECTIONS.get(as_text(get("direction")), as_text(get("direction")))
            return f"Focus the window {'above' if dr == 'up' else 'below' if dr == 'down' else 'to the ' + dr}", \
                DIR_ARROWS.get(dr, "open_with"), f"focus {dr}", "hyprland", True, None
        if get("monitor") is not None:
            return f"Focus monitor {as_text(get('monitor'))}", "monitor", "focus monitor", "hyprland", True, None
    if n == "window.move":
        if get("workspace") is not None:
            ws = get("workspace")
            return f"Move window to {workspace_phrase(ws)}", "move_item" if "special" not in as_text(ws) else "move_to_inbox", \
                f"move window to workspace {as_text(ws)}", "hyprland", True, None
        if get("direction") is not None:
            dr = DIRECTIONS.get(as_text(get("direction")), as_text(get("direction")))
            return f"Move window {dr}", DIR_ARROWS.get(dr, "open_with"), f"move window {dr}", "hyprland", True, None
        if get("out_of_group"):
            return "Move window out of its group", "tab_close_right", "move out of group", "hyprland", True, None
    if n == "window.swap" and get("direction") is not None:
        dr = DIRECTIONS.get(as_text(get("direction")), as_text(get("direction")))
        return f"Swap window {dr}", "swap_horiz" if dr in ("left", "right") else "swap_vert", f"swap {dr}", "hyprland", True, None
    if n == "window.resize":
        if get("x") is not None:
            return f"Resize window to {as_text(get('x'))} × {as_text(get('y'))}", "aspect_ratio", "resize window", "hyprland", True, None
        return "Resize window (drag)", "open_in_full", "resize window", "hyprland", True, None
    if n == "workspace.toggle_special":
        name = as_text(a) if a is not None else "special"
        label = "the special workspace" if name == "special" else f"the {name} special workspace"
        return f"Toggle {label}", "auto_awesome_mosaic", f"toggle special {name}", "hyprland", True, None
    if n == "layout":
        return describe_layout(as_text(a))
    window_actions = {
        "window.close": ("Close window", "close"), "window.center": ("Center window", "center_focus_strong"),
        "window.pin": ("Pin window", "push_pin"), "window.drag": ("Move window (drag)", "drag_pan"),
        "window.pseudo": ("Toggle pseudotiling", "picture_in_picture"), "group.toggle": ("Toggle window group", "tab_group"),
        "group.next": ("Next window in group", "tab"), "group.prev": ("Previous window in group", "tab"),
        "exit": ("Exit Hyprland", "logout"), "window.kill": ("Kill window", "dangerous"),
    }
    if n in window_actions:
        title, icon = window_actions[n]
        return title, icon, n.replace(".", " "), "hyprland", True, None
    if n == "window.fullscreen":
        mode = as_text(get("mode")) if get("mode") is not None else "fullscreen"
        return ("Maximise window" if mode == "maximized" else "Fullscreen"), "fullscreen", f"fullscreen {mode}", "hyprland", True, None
    if n == "window.float":
        return "Toggle floating", "picture_in_picture_alt", "float toggle", "hyprland", True, None
    if n == "window.cycle_next":
        prev = as_text(get("next")) == "prev"
        return f"Cycle to the {'previous' if prev else 'next'} window", "switch_access_shortcut", "cycle windows", "hyprland", True, None
    if n == "group.lock_active":
        return "Lock window group", "lock", "group lock", "hyprland", True, None
    title = humanise(n.split(":")[-1].replace(".", " "))
    return title, "keyboard_command_key", f"{n} {as_text(a) if a is not None else ''}".strip(), "hyprland", False, None


def ws_icon(ws):
    ws = as_text(ws)
    if ws.startswith("special"):
        return "auto_awesome_mosaic"
    if m := re.fullmatch(r"[er]?([+-])(\d+)", ws):
        if m.group(2) == "10":
            return "keyboard_double_arrow_left" if m.group(1) == "-" else "keyboard_double_arrow_right"
        return "keyboard_arrow_left" if m.group(1) == "-" else "keyboard_arrow_right"
    return "workspaces"


def describe_layout(msg):
    msg = msg.strip()
    if m := re.fullmatch(r"splitratio\s+([+-]?)([\d.]+)", msg):
        return ("Shrink the split" if m.group(1) == "-" else "Grow the split"), "width", f"layout {msg}", "hyprland", True, None
    known = {"togglesplit": ("Toggle split direction", "vertical_split"), "promote": ("Promote window", "vertical_align_top"),
             "fit all": ("Fit all columns on screen", "fit_screen"), "move +col": ("Move column right", "view_column"),
             "move -col": ("Move column left", "view_column"), "swapwithmaster": ("Swap with master", "swap_horiz"),
             "orientationnext": ("Next layout orientation", "screen_rotation")}
    if msg in known:
        title, icon = known[msg]
        return title, icon, f"layout {msg}", "hyprland", True, None
    return f"Layout: {msg}", "view_quilt", f"layout {msg}", "hyprland", False, None


def describe_command(cmd, apps: Apps):
    raw = as_text(cmd)
    refs = getattr(cmd, "refs", ())
    norm = raw.replace(HOME, "~").strip()
    norm = re.sub(r"^pkill \S+ \|\|\s*", "", norm)
    norm = re.sub(r"^(?:app2unit|uwsm app|uwsm-app|runapp)\s+(?:-\S+\s+)*--\s+", "", norm)
    norm = re.sub(r"^(?:setsid|nohup)\s+", "", norm)
    norm = re.sub(r"^/usr/bin/", "", norm)
    detail = norm if len(norm) <= 80 else norm[:79] + "…"
    owner = "shell" if re.match(r"(caelestia|qs -c caelestia)\b", norm) else "hyprland"
    for pattern, title, icon in COMMANDS:
        if m := re.search(pattern, norm):
            if icon == "drawer":
                icon = DRAWER_ICONS.get(m.group(1), "dock_to_bottom")
            return title.format(*m.groups()), icon, detail, owner, True, None
    url = re.search(r"https?://[^\s\"']+", norm)
    argv = norm.split()
    binary = os.path.basename(argv[0]) if argv else ""
    app = apps.by_binary(binary) if binary and not url else None
    if refs:
        role = humanise(refs[-1])
        name = app["name"] if app else binary
        return role, "open_in_new", detail, "app", True, app | {"note": name} if app else {"note": name}
    if app:
        return app["name"], "open_in_new", detail, "app", True, app
    if url:
        host = re.sub(r"^https?://(?:www\.)?([^/:]+).*", r"\1", url.group())
        return host, "public", detail, "app", False, {"url": url.group()}
    return f"Run {binary}" if binary else "Run a command", "terminal", detail, "app", False, None


def describe_func(f: Func, globals_, apps):
    """A Lua function bind: describe its dispatch if it's a one-liner."""
    body = f.toks[f.start:f.end]
    dsp_starts = [i for i in range(len(body) - 2)
                  if body[i].is_("name", "hl") and body[i + 2].is_("name", "dsp")]
    source = re.sub(r"\s+([(),.])\s*|\s*([(.])\s+", r"\1\2", f.source()).strip()
    source = re.sub(r"([(,]\s*)-\s+(?=\d)", r"\1-", source).replace(",", ", ")
    detail = source if len(source) <= 70 else source[:69] + "…"
    simple = len(body) <= 24 * max(1, len(dsp_starts)) and not any(t.is_("kw", "if") for t in body)
    described = []
    if 1 <= len(dsp_starts) <= 3:
        lc = LuaConfig.__new__(LuaConfig)
        lc.binds, lc.modules = [], {}
        for start in dsp_starts:
            try:
                value, _ = lc.expr(f.toks, f.start + start, {"__file": f.file})
            except (IndexError, ValueError, TypeError, KeyError):
                value = None
            if isinstance(value, Dsp):
                described.append(describe_dsp(value, globals_, apps))
    if described and len(described) == len(dsp_starts):
        title = " and ".join([described[0][0]] + [d[0][:1].lower() + d[0][1:] for d in described[1:]])
        _, icon, _, owner, confident, app = described[0]
        return title, icon, detail, owner, confident and simple and all(d[4] for d in described), app
    return None, "function", detail, "hyprland", False, None


def comment_blocks(comments):
    """Groups contiguous full-line comments: [(first_line, last_line, [texts])]."""
    blocks = []
    for c in comments:
        if c["trailing"]:
            continue
        if blocks and blocks[-1][1] == c["line"] - 1:
            blocks[-1][1] = c["line"]
            blocks[-1][2].append(c["text"])
        else:
            blocks.append([c["line"], c["line"], [c["text"]]])
    return blocks


def combo_comments(comments):
    """Comment lines of the form 'CTRL+SUPER+H — does a thing' -> {(mask, key): text}."""
    out = {}
    for c in comments:
        m = re.match(r"^((?:(?:[A-Za-z0-9_]+)\s*\+\s*)+\S+)\s*(?:→|->|—|–|:|\s-\s)\s*(.+)$", c["text"])
        if not m:
            continue
        combo = parse_combo(m.group(1))
        if combo and combo[0]:
            out.setdefault(combo, m.group(2))
    return out


def command_available(cmd: str) -> bool:
    """Whether the program a command runs exists (False only when it clearly doesn't)."""
    norm = re.sub(r"^pkill \S+ \|\|\s*", "", cmd.strip())
    norm = re.sub(r"^(?:app2unit|uwsm app|uwsm-app|runapp)\s+(?:-\S+\s+)*--\s+", "", norm)
    argv = norm.split()
    if not argv or re.search(r"[;&|$`]", argv[0]):
        return True
    binary = os.path.expanduser(argv[0].strip("\"'"))
    extra = [f"{HOME}/.local/bin", f"{HOME}/.local/share/bin"]
    return bool(shutil.which(binary, path=os.pathsep.join([os.environ.get("PATH", ""), *extra])))


def similar(a: str, b: str) -> bool:
    a, b = a.lower(), b.lower()
    return a in b or b in a or difflib.SequenceMatcher(None, a, b).ratio() > 0.6


# --- assembling ---------------------------------------------------------------------------

def find_config(explicit: str | None) -> Path | None:
    if explicit:
        p = Path(os.path.expanduser(explicit))
        return p if p.is_file() else None
    for name in ("hyprland.lua", "hyprland.conf"):
        p = CONFIG_HOME / "hypr" / name
        if p.is_file():
            return p
    return None


def build(config: Path):
    apps = Apps()
    globals_ = global_shortcuts()
    live = live_binds()

    if config.suffix == ".lua":
        lc = LuaConfig(config)
        raw = lc.run()
        comments, sections, files = lc.comments, lc.sections, lc.files
        parsed = []
        for b in raw:
            args = b["args"]
            key_expr = args[0] if args else None
            action = args[1] if len(args) > 1 else None
            opts = args[2] if len(args) > 2 and isinstance(args[2], dict) else {}
            combo = parse_combo(as_text(key_expr)) if isinstance(key_expr, str) else None
            parsed.append({"combo": combo, "combo_text": as_text(key_expr), "action": action, "opts": opts,
                           "description": as_text(opts.get("description")) if opts.get("description") else "",
                           "file": b["file"], "line": b["line"], "loop": b["loop"]})
    else:
        raw, comments, sections, files = conf_binds(config)
        parsed = []
        for b in raw:
            mask = conf_mods(b["mods"])
            key = b["key"].lower()
            f = b["flags"]
            opts = {"locked": "l" in f, "repeating": "e" in f, "release": "r" in f, "mouse": "m" in f,
                    "non_consuming": "n" in f}
            parsed.append({"combo": (mask, key), "combo_text": f"{b['mods']} + {b['key']}", "action": b["dsp"],
                           "opts": opts, "description": b["description"], "file": b["file"], "line": b["line"],
                           "loop": None})

    # Pair with what Hyprland actually has bound, in definition order
    pool = defaultdict(deque)
    for idx, lb in enumerate(live or []):
        key = lb.get("key", "").lower() or (f"code:{lb['keycode']}" if lb.get("keycode") else "")
        pool[(lb.get("submap", ""), lb.get("modmask", 0), key)].append(idx)
    used = set()
    for p in parsed:
        p["live"] = None
        if live is None or not p["combo"]:
            continue
        mask, key = p["combo"]
        queue = pool.get(("", mask, key))
        if queue:
            p["live"] = live[queue.popleft()]
            used.add(id(p["live"]))
    if live is not None:
        parsed = [p for p in parsed if p["live"] is not None]

    combo_notes = {}
    for f in files:
        combo_notes.update({k: v for k, v in combo_comments(comments.get(f, [])).items() if k not in combo_notes})
    blocks = {f: comment_blocks(comments.get(f, [])) for f in files}
    trailing = {f: {c["line"]: c["text"] for c in comments.get(f, []) if c["trailing"]} for f in files}

    # Paragraph comments: the comment block above a run of binds (until a blank line or the next block)
    by_file = defaultdict(list)
    for p in parsed:
        by_file[p["file"]].append(p)
    for f, items in by_file.items():
        file_lines = Path(f).read_text(encoding="utf-8", errors="replace").splitlines()
        section_list = sections.get(f, [])
        for p in items:
            p["section"] = next((t for line, t in reversed(section_list) if line < p["line"]), None)
            p["block"], p["own_block"] = None, False
            for first, last, texts in reversed(blocks[f]):
                if last >= p["line"]:
                    continue
                between = file_lines[last:p["line"] - 1]
                if any(not s.strip() for s in between):
                    break
                if re.fullmatch(r"[=\-#*~]{5,}", texts[-1]) or any(re.fullmatch(r"[=\-#*~]{5,}", t) for t in texts):
                    break
                p["block"] = (first, texts)
                p["own_block"] = last == p["line"] - 1
                break
        runs = defaultdict(set)
        for p in items:
            if p["block"]:
                runs[p["block"][0]].add((p["combo"], p["loop"][0] if p["loop"] else p["line"]))
        for p in items:
            if p["block"]:
                members = runs[p["block"][0]]
                p["block_single"] = len({m[1] for m in members}) == 1 or len({m[0] for m in members}) == 1
            else:
                p["block_single"] = False

    rows, order = [], {}
    for p in parsed:
        lb = p["live"] or {}
        action, opts = p["action"], p["opts"]
        loop = p["loop"]
        if isinstance(action, Dsp):
            title, icon, detail, owner, confident, app = describe_dsp(action, globals_, apps)
        elif isinstance(action, Func):
            title, icon, detail, owner, confident, app = describe_func(action, globals_, apps)
        else:
            title, icon, detail, owner, confident, app = None, "function", as_text(action), "hyprland", False, None

        candidates = []
        desc = p["description"] or (lb.get("description") if lb.get("has_description") else "")
        if desc:
            candidates.append(("description", desc))
        if p["combo"] in combo_notes:
            candidates.append(("combo", sentence(combo_notes[p["combo"]])))
        var = loop[2] if loop else None
        block = sentence(p["block"][1][0], var) if p["block"] else ""
        # The user's own comment over a single bind says best what it's for, unless it's just a label
        if block and p["block_single"] and (len(block.split()) >= 3 or not confident):
            candidates.append(("block", block))
        if title and confident:
            candidates.append(("derived", title))
        trail = trailing.get(p["file"], {}).get(p["line"])
        if trail:
            candidates.append(("trailing", sentence(trail)))
        if block and p["own_block"] and isinstance(action, Func):
            candidates.append(("block", block))
        if title:
            candidates.append(("derived", title))
        if block:
            candidates.append(("block", block))
        candidates.append(("fallback", "Custom action"))
        source, final = candidates[0]
        notes = [t for s, t in candidates[1:] if s in ("trailing", "description") and not similar(t, final)]
        if app and app.get("note") and not similar(app["note"], final):
            notes.insert(0, app["note"])

        if icon in ("function", "keyboard_command_key", "open_in_new", "terminal", "public") or source in ("combo", "block"):
            for pattern, kw_icon in TITLE_ICONS:
                if re.search(pattern, final, re.I):
                    icon = kw_icon
                    break
            if icon == "function":
                icon = "code"

        # Binds with a description may name an app or web app (iPhone Mirror, WhatsApp, ...)
        url = (app or {}).get("url", "")
        if (not app or not app.get("icon")) and (desc or url):
            found = apps.by_name(desc or final, url)
            if found:
                app = found | ({"url": url} if url else {})
        missing = False
        if isinstance(action, Dsp) and action.name == "exec_cmd":
            missing = not command_available(as_text(action.arg()))

        mask = lb.get("modmask", p["combo"][0] if p["combo"] else 0)
        key = lb.get("key") or (p["combo"][1] if p["combo"] else "")
        if not key and lb.get("keycode"):
            key = f"code:{lb['keycode']}"
        flags = {
            "locked": bool(lb.get("locked", opts.get("locked"))),
            "repeat": bool(lb.get("repeat", opts.get("repeating"))),
            "release": bool(lb.get("release", opts.get("release"))),
            "mouse": bool(lb.get("mouse", opts.get("mouse"))),
        }
        internal = bool(lb.get("non_consuming", opts.get("non_consuming"))) or (
            isinstance(action, Dsp) and action.name == "global" and as_text(action.arg()) == "caelestia:launcherInterrupt")
        category = p.get("section") or re.sub(r"\b(tv|hdr|hdmi|ipc|osd|ui|vm)\b", lambda m: m.group().upper(),
                                                humanise(Path(p["file"]).stem), flags=re.I)
        category = re.sub(r"\s*\(.*\)\s*$", "", category).strip() or category
        group = loop[0] if loop else None
        merge_key = (group, mask) if group else (category, mask, key.lower())

        row = order.get(merge_key)
        if row is not None:
            # Another iteration of a loop, or the same combo bound twice (press/release, two actions)
            r = rows[row]
            if key not in r["_keys"]:
                r["_keys"].append(key)
            r["flags"] = {k: r["flags"][k] or v for k, v in flags.items()}
            r["internal"] = r["internal"] and internal
            continue
        order[merge_key] = len(rows)
        if app and app.get("note"):
            app = {k: v for k, v in app.items() if k != "note"} or None
        rows.append({
            "title": final, "source": source, "note": notes[0] if notes else "", "detail": detail or "",
            "icon": icon, "owner": owner, "category": category, "modmask": mask, "_keys": [key],
            "flags": flags, "internal": internal, "missing": missing,
            "app": {"name": app.get("name", ""), "icon": app.get("icon", ""), "id": app.get("id", ""),
                    "url": app.get("url", "")} if app else None,
            "file": str(p["file"]).replace(HOME, "~"), "line": p["line"],
        })

    # Live binds that didn't come from a file we could read
    if live is not None:
        for lb in live:
            if id(lb) in used:
                continue
            key = lb.get("key") or (f"code:{lb['keycode']}" if lb.get("keycode") else "")
            internal = bool(lb.get("non_consuming"))
            desc = lb.get("description") if lb.get("has_description") else ""
            dsp = conf_dispatcher(lb["dispatcher"], lb.get("arg", "")) if lb.get("dispatcher") != "__lua" else None
            if dsp:
                title, icon, detail, owner, _, app = describe_dsp(dsp, globals_, apps)
            else:
                title, icon, detail, owner, app = None, "help", "set outside the config files", "hyprland", None
            rows.append({
                "title": desc or title or "Unknown action", "source": "live", "note": "", "detail": detail,
                "icon": icon, "owner": owner, "category": "Other", "modmask": lb.get("modmask", 0), "_keys": [key],
                "flags": {"locked": lb.get("locked", False), "repeat": lb.get("repeat", False),
                          "release": lb.get("release", False), "mouse": lb.get("mouse", False)},
                "internal": internal, "missing": False, "app": None, "file": "", "line": 0,
            })

    for r in rows:
        keys = r.pop("_keys")
        r["keys"] = keys
        r["caps"] = mod_caps(r["modmask"]) + [key_range(keys)]
        r["combo"] = " + ".join(c["label"] for c in r["caps"])
        r["alts"] = []

    # Several keys for the same action (Play, Pause and Ctrl+Super+Space) make one row
    merged, seen = [], {}
    for r in rows:
        same = (r["category"], r["title"], r["detail"], r["internal"])
        first = seen.get(same)
        if first is not None and len(first["alts"]) < 3:
            first["alts"].append(r["caps"])
            first["combo"] += " / " + r["combo"]
            first["keys"] += r["keys"]
            first["flags"] = {k: first["flags"][k] or v for k, v in r["flags"].items()}
            continue
        seen[same] = r
        merged.append(r)
    rows = merged
    for r in rows:
        r["search"] = " ".join(filter(None, [r["title"], r["note"], r["detail"], r["category"], r["combo"],
                                              " ".join(r["keys"])])).lower()

    bound_globals = set()
    for p in parsed:
        a = p["action"]
        if isinstance(a, Dsp) and a.name == "global":
            bound_globals.add(as_text(a.arg()))
        if isinstance(a, Dsp) and a.name == "exec_cmd":
            cmd = as_text(a.arg())
            if m := re.search(r"(?:qs -c caelestia ipc call|caelestia shell) drawers toggle (\w+)", cmd):
                bound_globals.add(f"caelestia:{m.group(1)}")
            if re.search(r"(?:qs -c caelestia ipc call|caelestia shell) nexus open", cmd):
                bound_globals.add("caelestia:nexus")
            if re.search(r"(?:qs -c caelestia ipc call|caelestia shell) keybinds toggle", cmd):
                bound_globals.add("caelestia:keybinds")
    if live is not None:
        for lb in live:
            if lb.get("dispatcher") == "global":
                bound_globals.add(lb.get("arg", ""))
    unbound = []
    for name, desc in globals_.items():
        app, _, short = name.partition(":")
        if name in bound_globals or short in ("launcherInterrupt", "refreshDevices"):
            continue
        unbound.append({"name": name, "title": desc or humanise(short), "app": app,
                        "icon": GLOBAL_ICONS.get(short, "keyboard_command_key") if app == "caelestia" else "keyboard_command_key"})

    categories = []
    for r in rows:
        if not any(c["name"] == r["category"] for c in categories):
            icon = next((i for pattern, i in CATEGORY_ICONS if re.search(pattern, r["category"], re.I)), "keyboard")
            categories.append({"name": r["category"], "icon": icon})

    return {
        "source": "lua" if config.suffix == ".lua" else "conf",
        "config": str(config).replace(HOME, "~"),
        "files": [str(f).replace(HOME, "~") for f in files],
        "live": live is not None,
        "categories": categories,
        "binds": rows,
        "unbound": unbound,
    }


def key_range(keys: list[str]) -> dict:
    if len(keys) == 1:
        return key_cap(keys[0])
    labels = [key_cap(k)["label"] for k in keys]
    if all(len(k) == 1 and k.isdigit() for k in keys):
        return {"label": f"{labels[0]}–{labels[-1]}", "range": True}
    if all(k.startswith("mouse") for k in keys):
        return {"label": "Mouse", "icon": "mouse", "range": True}
    if len(labels) <= 3:
        return {"label": " / ".join(labels), "range": True}
    return {"label": f"{labels[0]} … {labels[-1]}", "range": True}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", help="Hyprland config to read (default: ~/.config/hypr/hyprland.lua or .conf)")
    ap.add_argument("--pretty", action="store_true")
    args = ap.parse_args()
    config = find_config(args.config)
    if not config:
        json.dump({"error": "No Hyprland config found", "binds": [], "unbound": []}, sys.stdout)
        return
    sys.setrecursionlimit(5000)
    json.dump(build(config), sys.stdout, indent=2 if args.pretty else None, ensure_ascii=False)


if __name__ == "__main__":
    main()
