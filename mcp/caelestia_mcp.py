#!/usr/bin/env python3
"""MCP server for controlling the Caelestia shell from agents (stdio).

Wraps the shell's IPC (`qs -c caelestia ipc call ...`), the caelestia CLI,
shell.json and a few desktop helpers (grim screenshots, hyprctl queries) as
MCP tools. Standard library only; speaks newline-delimited JSON-RPC 2.0 on
stdin/stdout. Register with:

    claude mcp add --scope user caelestia -- python3 /path/to/caelestia_mcp.py

The Wayland/Hyprland environment is resolved on every call, so it works from
sessions that didn't inherit the desktop session's variables (tmux, services)
and survives Hyprland restarts.
"""

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SERVER = {"name": "caelestia", "version": "0.1.0"}
PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05"]
TIMEOUT = 20

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "caelestia"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "caelestia"


class ToolError(Exception):
    """An error reported to the agent as a failed tool result."""


# --- environment and commands ------------------------------------------------

def desktop_env() -> dict:
    env = dict(os.environ)
    runtime = Path(env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    env["XDG_RUNTIME_DIR"] = str(runtime)
    if not (runtime / env.get("WAYLAND_DISPLAY", "")).is_socket():
        sockets = sorted(p.name for p in runtime.glob("wayland-*") if p.is_socket())
        if sockets:
            env["WAYLAND_DISPLAY"] = sockets[0]
    hypr = runtime / "hypr"
    if hypr.is_dir():
        current = env.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        if not current or not (hypr / current).is_dir():
            dirs = sorted(hypr.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
            if dirs:
                env["HYPRLAND_INSTANCE_SIGNATURE"] = dirs[0].name
    return env


def run(cmd: list[str], *, binary: bool = False, check: bool = True):
    try:
        out = subprocess.run(cmd, capture_output=True, env=desktop_env(), timeout=TIMEOUT)
    except FileNotFoundError:
        raise ToolError(f"{cmd[0]} is not installed")
    except subprocess.TimeoutExpired:
        raise ToolError(f"{' '.join(cmd[:4])} timed out")
    if check and out.returncode != 0:
        err = (out.stderr or out.stdout).decode(errors="replace").strip()
        raise ToolError(f"{' '.join(cmd[:5])} failed: {err[:500]}")
    return out.stdout if binary else out.stdout.decode(errors="replace").strip()


def ipc(target: str, function: str, *args) -> str:
    out = run(["qs", "-c", "caelestia", "ipc", "call", target, function, *map(str, args)], check=False)
    if out.startswith("No running instances"):
        raise ToolError("the Caelestia shell isn't running")
    if out in ("Target not found.", "Function not found.") or out.startswith(("Invalid", "Failed to parse")):
        raise ToolError(out)
    return out


def hyprctl_json(what: str):
    return json.loads(run(["hyprctl", what, "-j"]) or "null")


# --- shell.json ---------------------------------------------------------------

def config_path(monitor: str | None) -> Path:
    return CONFIG / "monitors" / monitor / "shell.json" if monitor else CONFIG / "shell.json"


def read_config(monitor: str | None) -> dict:
    path = config_path(monitor)
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as e:
        raise ToolError(f"{path} is not valid JSON: {e}")


def write_config(monitor: str | None, data: dict) -> None:
    path = config_path(monitor)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, indent=4, ensure_ascii=False)
    # The shell writes empty lists as "[\n    ]"; match it to keep diffs small.
    text = re.sub(r"^( *)(\"[^\"]+\": )\[\](,?)$", lambda m: f"{m[1]}{m[2]}[\n{m[1]}]{m[3]}", text, flags=re.M)
    # Write through the directory (it may be a symlink into a dotfiles repo).
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".shell.json.")
    with os.fdopen(fd, "w") as f:
        f.write(text + "\n")
    os.replace(tmp, path)


def walk(data, key: str):
    node = data
    for part in key.split(".") if key else []:
        if isinstance(node, dict) and part in node:
            node = node[part]
        elif isinstance(node, list) and part.isdigit() and int(part) < len(node):
            node = node[int(part)]
        else:
            raise ToolError(f"no setting {key!r} (missing {part!r}); unset keys use the shell's default")
    return node


# --- tools ----------------------------------------------------------------------

TOOLS: dict[str, dict] = {}


def tool(name: str, description: str, properties: dict | None = None, required: list[str] | None = None):
    def register(fn):
        TOOLS[name] = {
            "fn": fn,
            "spec": {
                "name": name,
                "description": description,
                "inputSchema": {"type": "object", "properties": properties or {}, "required": required or []},
            },
        }
        return fn
    return register


S = {"type": "string"}
MONITOR = {"type": "string", "description": "Monitor name, e.g. DP-1 (see list_monitors)."}


@tool("list_monitors", "Monitors with their names, resolution, scale, focused state and active workspace.")
def list_monitors(_):
    return [{k: m[k] for k in ("name", "description", "width", "height", "scale", "focused", "dpmsStatus")}
            | {"activeWorkspace": m["activeWorkspace"]["name"]} for m in hyprctl_json("monitors")]


@tool("list_windows", "Open windows (class, title, workspace, monitor, position, size, floating, fullscreen). Read-only.",
      {"workspace": {"type": "string", "description": "Only this workspace (name or id)."}})
def list_windows(args):
    mons = {m["id"]: m["name"] for m in hyprctl_json("monitors")}
    wins = [{"class": c["class"], "title": c["title"], "workspace": c["workspace"]["name"], "monitor": mons.get(c["monitor"]),
             "at": c["at"], "size": c["size"], "floating": c["floating"], "fullscreen": c["fullscreen"],
             "focused": c.get("focusHistoryID") == 0} for c in hyprctl_json("clients")]
    if ws := args.get("workspace"):
        wins = [w for w in wins if w["workspace"] == str(ws)]
    return wins


@tool("screenshot", "Capture a monitor (or all) as an image so you can see the desktop. While the screen is locked this shows the lock screen.",
      {"monitor": MONITOR,
       "max_width": {"type": "integer", "description": "Downscale to at most this width in pixels (default 1920)."}})
def screenshot(args):
    if not shutil.which("grim"):
        raise ToolError("grim is not installed")
    monitor = args.get("monitor")
    max_width = int(args.get("max_width") or 1920)
    mons = hyprctl_json("monitors")
    if monitor:
        m = next((m for m in mons if m["name"] == monitor), None)
        if not m:
            raise ToolError(f"no monitor {monitor!r}; have {[m['name'] for m in mons]}")
        width = m["width"] / m["scale"]  # grim -s scales the logical size
    else:
        width = max(m["x"] / m["scale"] + m["width"] / m["scale"] for m in mons) if mons else max_width
    scale = min(1.0, max_width / width)
    cmd = ["grim", "-t", "jpeg", "-q", "85", "-s", f"{scale:.4f}"]
    if monitor:
        cmd += ["-o", monitor]
    data = run(cmd + ["-"], binary=True)
    return {"image": base64.b64encode(data).decode(), "mimeType": "image/jpeg"}


@tool("lock_status", "Whether the screen is locked.")
def lock_status(_):
    return {"locked": ipc("lock", "isLocked") == "true"}


@tool("lock", "Lock the screen.")
def lock(_):
    ipc("lock", "lock")
    return {"locked": True}


@tool("unlock", "Unlock the screen without a password. Anyone at the computer can then use it; lock again when done.")
def unlock(_):
    ipc("lock", "unlock")
    return {"locked": ipc("lock", "isLocked") == "true"}


@tool("wallpaper_get", "The current wallpaper (image or video path), globally or for one monitor.", {"monitor": MONITOR})
def wallpaper_get(args):
    if m := args.get("monitor"):
        return {"monitor": m, "wallpaper": ipc("wallpaper", "getFor", m)}
    return {"wallpaper": ipc("wallpaper", "get")}


@tool("wallpaper_list", "Available wallpapers (images and videos). Use `query` to filter by a case-insensitive substring.",
      {"query": S, "kind": {"type": "string", "enum": ["any", "image", "video"]},
       "limit": {"type": "integer", "description": "Default 200."}})
def wallpaper_list(args):
    videos = (".mp4", ".mkv", ".webm", ".mov", ".m4v", ".avi")
    walls = [w for w in ipc("wallpaper", "list").splitlines() if w]
    if q := (args.get("query") or "").lower():
        walls = [w for w in walls if q in w.lower()]
    kind = args.get("kind") or "any"
    if kind != "any":
        walls = [w for w in walls if w.lower().endswith(videos) == (kind == "video")]
    limit = int(args.get("limit") or 200)
    return {"count": len(walls), "wallpapers": walls[:limit]}


@tool("wallpaper_set", "Set the wallpaper (image or video). Without `monitor` it applies everywhere, clears per-monitor choices and regenerates the colour scheme; with `monitor` it only changes that monitor.",
      {"path": {"type": "string", "description": "Absolute path, e.g. from wallpaper_list."}, "monitor": MONITOR}, ["path"])
def wallpaper_set(args):
    path = os.path.expanduser(args["path"])
    if not os.path.isfile(path):
        raise ToolError(f"no such file: {path}")
    if m := args.get("monitor"):
        ipc("wallpaper", "setFor", m, path)
    else:
        ipc("wallpaper", "set", path)
    return {"set": path, "monitor": args.get("monitor") or "all"}


@tool("wallpaper_clear_monitor", "Remove a monitor's own wallpaper so it shows the global one again.", {"monitor": MONITOR}, ["monitor"])
def wallpaper_clear_monitor(args):
    ipc("wallpaper", "clearFor", args["monitor"])
    return {"cleared": args["monitor"]}


@tool("scheme_get", "The current colour scheme: name, flavour, mode (dark/light) and variant.")
def scheme_get(_):
    path = STATE / "scheme.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {"raw": run(["caelestia", "scheme", "get"])}
    return {k: data.get(k) for k in ("name", "flavour", "mode", "variant")}


@tool("scheme_list", "Available scheme names, flavours, modes or variants.",
      {"what": {"type": "string", "enum": ["names", "flavours", "modes", "variants"]}})
def scheme_list(args):
    what = args.get("what") or "names"
    return {what: run(["caelestia", "scheme", "list", f"--{what}"]).split()}


@tool("scheme_set", "Change the colour scheme. 'dynamic' follows the wallpaper. Note: a wallpaper hook may force the vibrant variant after wallpaper changes.",
      {"name": S, "flavour": S, "mode": {"type": "string", "enum": ["dark", "light"]}, "variant": S})
def scheme_set(args):
    cmd = ["caelestia", "scheme", "set"]
    for key, flag in (("name", "-n"), ("flavour", "-f"), ("mode", "-m"), ("variant", "-v")):
        if args.get(key):
            cmd += [flag, args[key]]
    if len(cmd) == 3:
        raise ToolError("give at least one of name, flavour, mode, variant")
    run(cmd)
    return scheme_get({})


@tool("config_get", "Read a shell.json setting by dotted key (e.g. 'border.rounding', 'background.desktopClock'). Empty key returns the whole file. Unset keys use the shell's built-in default.",
      {"key": S, "monitor": {"type": "string", "description": "Read the per-monitor override file instead (monitors/<name>/shell.json)."}})
def config_get(args):
    return walk(read_config(args.get("monitor")), args.get("key") or "")


@tool("config_set", "Set a shell.json setting by dotted key; the shell reloads it live. `value` is any JSON value. Creates missing parent objects.",
      {"key": S, "value": {"description": "New value (string, number, bool, object or array)."},
       "monitor": {"type": "string", "description": "Write the per-monitor override file instead."}}, ["key", "value"])
def config_set(args):
    key, value, monitor = args["key"], args["value"], args.get("monitor")
    if not key:
        raise ToolError("key is required")
    data = read_config(monitor)
    parts = key.split(".")
    node = data
    for part in parts[:-1]:
        if not isinstance(node.get(part), dict):
            if part in node:
                raise ToolError(f"{part!r} in {key!r} is not an object")
            node[part] = {}
        node = node[part]
    old = node.get(parts[-1])
    node[parts[-1]] = value
    write_config(monitor, data)
    return {"key": key, "old": old, "new": value, "file": str(config_path(monitor))}


@tool("media_status", "Media players and the active player's track (title, artist, album, status).")
def media_status(_):
    out = {"players": [p for p in ipc("mpris", "list").splitlines() if p]}
    if ipc("mpris", "getActive", "identity") == "No active player":
        return out | {"active": None}
    for prop in ("identity", "trackTitle", "trackArtist", "trackAlbum", "isPlaying"):
        out[prop] = ipc("mpris", "getActive", prop)
    return out


@tool("media_control", "Control the active media player.",
      {"action": {"type": "string", "enum": ["play", "pause", "playPause", "next", "previous", "stop"]}}, ["action"])
def media_control(args):
    ipc("mpris", args["action"])
    return media_status({})


@tool("brightness", "Get or set screen brightness (0-1). `value`: '0.5' or '50%' absolute, '+10%' / '+0.1' up, '10%-' / '0.1-' down; omit to read. `monitor` targets one display, else the active one.",
      {"value": S, "monitor": MONITOR})
def brightness(args):
    m, value = args.get("monitor"), args.get("value")
    message = None
    if value:
        message = ipc("brightness", "setFor", m, value) if m else ipc("brightness", "set", value)
    level = float(ipc("brightness", "getFor", m) if m else ipc("brightness", "get"))
    if level < 0:
        raise ToolError(f"no brightness control for {m or 'the active monitor'}")
    return {"brightness": level, **({"message": message} if message else {})}


@tool("toast", "Show a toast message in the shell.",
      {"title": S, "message": S, "kind": {"type": "string", "enum": ["info", "success", "warn", "error"]},
       "icon": {"type": "string", "description": "Material Symbols icon name (default per kind)."}}, ["title"])
def toast(args):
    kind = args.get("kind") or "info"
    icon = args.get("icon") or {"info": "info", "success": "check_circle", "warn": "warning", "error": "error"}[kind]
    ipc("toaster", kind, args["title"], args.get("message") or "", icon)
    return {"shown": True}


@tool("notifications", "Do-not-disturb control and clearing notifications.",
      {"action": {"type": "string", "enum": ["status", "enableDnd", "disableDnd", "toggleDnd", "clear"]}}, ["action"])
def notifications(args):
    if args["action"] != "status":
        ipc("notifs", args["action"])
    return {"dnd": ipc("notifs", "isDndEnabled") == "true"}


@tool("toggle", "Turn game mode or the idle inhibitor (keep awake) on/off, or read their state.",
      {"feature": {"type": "string", "enum": ["gameMode", "idleInhibitor"]},
       "action": {"type": "string", "enum": ["status", "enable", "disable", "toggle"]}}, ["feature", "action"])
def toggle(args):
    if args["action"] != "status":
        ipc(args["feature"], args["action"])
    return {args["feature"]: ipc(args["feature"], "isEnabled") == "true"}


@tool("panel", "Open/close a shell panel (drawer) such as launcher, dashboard, session, sidebar; or 'settings' to open the settings window. Use action 'list' to see drawer names.",
      {"name": S, "action": {"type": "string", "enum": ["toggle", "status", "list"]}}, ["action"])
def panel(args):
    action, name = args["action"], args.get("name")
    if action == "list":
        return {"drawers": ipc("drawers", "list").split()}
    if not name:
        raise ToolError("name is required")
    if name == "settings":
        ipc("nexus", "open")
        return {"opened": "settings"}
    if action == "toggle":
        ipc("drawers", "toggle", name)
    return {name: ipc("drawers", "isOpen", name)}


HYPRBINDS = Path(__file__).resolve().parent.parent / "assets" / "hyprbinds.py"


@tool("keybinds", "The Hyprland and shell keyboard shortcuts, read from the Hyprland config (what each does, its keys, category). "
      "Action 'list' (default) returns them, optionally filtered; 'show'/'hide'/'toggle' the on-screen shortcuts panel; "
      "'settings' opens its settings page.",
      {"action": {"type": "string", "enum": ["list", "show", "hide", "toggle", "settings"]},
       "query": {"type": "string", "description": "Only shortcuts whose title, keys, command or category contain all these words."},
       "owner": {"type": "string", "enum": ["shell", "hyprland", "app"], "description": "Only shortcuts handled by the shell, Hyprland or launching apps."},
       "include_internal": {"type": "boolean", "description": "Include pass-through binds the shell uses itself."}})
def keybinds(args):
    action = args.get("action") or "list"
    if action != "list":
        ipc("keybinds", {"show": "open", "hide": "close", "toggle": "toggle", "settings": "settings"}[action])
        return {"ok": True}
    data = json.loads(run(["python3", "-I", str(HYPRBINDS)]))
    if data.get("error"):
        raise ToolError(data["error"])
    words = (args.get("query") or "").lower().split()
    binds = [b for b in data["binds"]
             if (args.get("include_internal") or not b["internal"])
             and (not args.get("owner") or b["owner"] == args["owner"])
             and all(w in b["search"] for w in words)]
    return {
        "config": data["config"],
        "binds": [{k: b[k] for k in ("combo", "title", "category", "owner", "note", "detail")}
                  | ({"missing": True} if b["missing"] else {})
                  | ({"flags": [f for f, on in b["flags"].items() if on]} if any(b["flags"].values()) else {})
                  for b in binds],
        "unbound_shell_actions": [{"name": u["name"], "title": u["title"]} for u in data["unbound"]] if not words else [],
    }


@tool("cards", "Window cards: two windows paired into one Hyprland group that flips over in 3D to show the other. "
      "'list' shows the cards; 'pair' pairs two windows by address (see list_windows / hyprctl clients), front first; "
      "'pick' starts interactive pairing for the focused window; 'flip' and 'unpair' act on the focused card.",
      {"action": {"type": "string", "enum": ["list", "pair", "pick", "flip", "unpair"]},
       "front": {"type": "string", "description": "Address (0x...) of the window shown first, for 'pair'."},
       "back": {"type": "string", "description": "Address (0x...) of the window on the back, for 'pair'."}}, ["action"])
def cards(args):
    action = args["action"]
    if action == "list":
        return json.loads(ipc("cards", "list") or "[]")
    if action == "pair":
        if not args.get("front") or not args.get("back"):
            raise ToolError("'pair' needs front and back window addresses")
        ipc("cards", "pairWindows", args["front"], args["back"])
    else:
        ipc("cards", {"pick": "pair", "flip": "flip", "unpair": "unpair"}[action])
    return {"ok": True}


@tool("widgets", "Desktop widgets (widget plugins). 'list' shows installed plugins and placed widgets; 'add' places one "
      "(type = plugin id, monitor = e.g. DP-1); 'place' moves/resizes one (screen logical px); 'configure' sets its "
      "settings (JSON object, e.g. {\"style\": \"almond\"} for eyes); 'remove'; 'edit'/'done' open/close the "
      "on-screen editor; 'rescan' re-reads the plugin folders.",
      {"action": {"type": "string", "enum": ["list", "add", "place", "configure", "remove", "edit", "done", "rescan"]},
       "type": {"type": "string", "description": "Plugin id, for 'add'."},
       "monitor": MONITOR,
       "uid": {"type": "string", "description": "Placed widget id (from 'list')."},
       "x": {"type": "integer"}, "y": {"type": "integer"},
       "width": {"type": "integer"}, "height": {"type": "integer"},
       "settings": {"type": "object", "description": "For 'configure': replaces the widget's settings."}}, ["action"])
def widgets(args):
    action = args["action"]
    if action == "list":
        return json.loads(ipc("widgets", "list") or "{}")
    if action == "add":
        if not args.get("type") or not args.get("monitor"):
            raise ToolError("'add' needs type and monitor")
        ipc("widgets", "add", args["type"], args["monitor"])
    elif action == "place":
        missing = [k for k in ("uid", "x", "y", "width", "height") if args.get(k) is None]
        if missing:
            raise ToolError(f"'place' needs {', '.join(missing)}")
        ipc("widgets", "place", args["uid"], args["x"], args["y"], args["width"], args["height"])
    elif action == "configure":
        if not args.get("uid"):
            raise ToolError("'configure' needs uid")
        ipc("widgets", "configure", args["uid"], json.dumps(args.get("settings") or {}))
    elif action == "remove":
        if not args.get("uid"):
            raise ToolError("'remove' needs uid")
        ipc("widgets", "remove", args["uid"])
    else:
        ipc("widgets", action)
    return {"ok": True}


@tool("camera", "The webcam (caelestia-camerad): 'status' (who's using it, gestures state, last light/presence readings), "
      "'controls' (zoom, focus, white balance, ...), 'set' a control, 'presets' / 'apply' a saved preset, "
      "'gestures' on/off, 'panel' to open the camera panel. Photos are deliberately not available here.",
      {"action": {"type": "string", "enum": ["status", "controls", "set", "presets", "apply", "gestures", "panel"]},
       "key": {"type": "string", "description": "Control key for 'set', e.g. zoom_absolute (see 'controls')."},
       "value": {"description": "Value for 'set' (number or boolean)."},
       "name": {"type": "string", "description": "Preset name for 'apply'."},
       "on": {"type": "boolean", "description": "For 'gestures'."}}, ["action"])
def camera(args):
    action = args["action"]
    if action == "status":
        return json.loads(ipc("camera", "status") or "{}")
    if action == "controls":
        return json.loads(ipc("camera", "controls") or "[]")
    if action == "set":
        if not args.get("key") or args.get("value") is None:
            raise ToolError("'set' needs key and value")
        v = args["value"]
        ipc("camera", "set", args["key"], str(v).lower() if isinstance(v, bool) else str(v))
    elif action == "presets":
        return [p for p in ipc("camera", "presets").splitlines() if p]
    elif action == "apply":
        if ipc("camera", "applyPreset", args.get("name", "")) != "true":
            raise ToolError(f"no preset {args.get('name')!r}")
    elif action == "gestures":
        ipc("camera", "gestures", "true" if args.get("on") else "false")
    elif action == "panel":
        ipc("camera", "open")
    return {"ok": True}


@tool("ipc_list", "Every IPC target and function the running shell exposes (for ipc_call).")
def ipc_list(_):
    return run(["qs", "-c", "caelestia", "ipc", "show"])


@tool("ipc_call", "Call any shell IPC function directly (see ipc_list), e.g. target 'picker' function 'openClip'.",
      {"target": S, "function": S, "args": {"type": "array", "items": {"type": "string"}}}, ["target", "function"])
def ipc_call(args):
    return {"result": ipc(args["target"], args["function"], *(args.get("args") or []))}


# --- JSON-RPC over stdio -------------------------------------------------------

def result_content(value) -> dict:
    if isinstance(value, dict) and "image" in value and "mimeType" in value:
        return {"content": [{"type": "image", "data": value["image"], "mimeType": value["mimeType"]}]}
    text = value if isinstance(value, str) else json.dumps(value, indent=2, ensure_ascii=False)
    return {"content": [{"type": "text", "text": text or "(empty)"}]}


def handle(msg: dict) -> dict | None:
    method, params, mid = msg.get("method"), msg.get("params") or {}, msg.get("id")
    if mid is None:  # notification
        return None
    if method == "initialize":
        asked = params.get("protocolVersion")
        result = {"protocolVersion": asked if asked in PROTOCOLS else PROTOCOLS[0],
                  "capabilities": {"tools": {}}, "serverInfo": SERVER,
                  "instructions": "Controls the Caelestia desktop shell on this machine. Use screenshot to see the result of changes."}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [t["spec"] for t in TOOLS.values()]}
    elif method == "tools/call":
        entry = TOOLS.get(params.get("name"))
        if not entry:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": f"unknown tool {params.get('name')!r}"}}
        try:
            result = result_content(entry["fn"](params.get("arguments") or {}))
        except ToolError as e:
            result = {"content": [{"type": "text", "text": str(e)}], "isError": True}
        except Exception as e:  # keep the server alive; report the bug to the agent
            result = {"content": [{"type": "text", "text": f"internal error: {type(e).__name__}: {e}"}], "isError": True}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main() -> None:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
        else:
            reply = handle(msg)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
