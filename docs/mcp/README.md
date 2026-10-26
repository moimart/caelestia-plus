# The caelestia MCP server

An [MCP](https://modelcontextprotocol.io) server that lets AI agents (Claude
Code, Claude Desktop, any MCP client) see and drive the desktop: take
screenshots, change wallpapers and colours, read and change settings, run the
shell's features. It talks to the running shell over its IPC, the `caelestia`
CLI, `shell.json`, `grim` and `hyprctl`.

It's one file of standard-library Python ([`shell/mcp/caelestia_mcp.py`](../../shell/mcp/caelestia_mcp.py)),
speaking MCP over stdio. It finds the Wayland and Hyprland sockets by itself,
so it works from tmux, SSH-started or service-started sessions too.

- [TOOLS.md](TOOLS.md): every tool and its parameters (generated from the code).
- [EXAMPLES.md](EXAMPLES.md): things to ask an agent, and the tools behind them.

## Set it up

The `caelestia-shell-moimart` package installs it as `caelestia-mcp`.

```sh
# Claude Code, for your user
claude mcp add --scope user caelestia -- caelestia-mcp
```

For other clients, the server command is `caelestia-mcp` with no arguments
(stdio). From a checkout: `python3 shell/mcp/caelestia_mcp.py`.

## What an agent can do

| Area | What | Tools |
| --- | --- | --- |
| See | Screenshots of any monitor (JPEG, downscaled), the monitors, the open windows | `screenshot`, `list_monitors`, `list_windows` |
| Lock | Check, lock, unlock | `lock_status`, `lock`, `unlock` |
| Wallpaper | List images and videos, set one everywhere or per monitor | `wallpaper_list`, `wallpaper_get`, `wallpaper_set`, `wallpaper_clear_monitor` |
| Colours | The scheme: dynamic from the wallpaper, or a named one; light or dark | `scheme_get`, `scheme_list`, `scheme_set` |
| Settings | Any `shell.json` setting by dotted key, reloaded live, globally or per monitor | `config_get`, `config_set` |
| Desktop | Media players, brightness, toasts, do-not-disturb, game mode and keep awake, opening panels and settings | `media_status`, `media_control`, `brightness`, `toast`, `notifications`, `toggle`, `panel` |
| Shortcuts | Every shortcut from your Hyprland config, searchable; the shortcuts panel | `keybinds` |
| Emoji | Search emoji, type one into the focused window, the picker | `emoji` |
| Window cards | List cards, pair two windows, flip, split | `cards` |
| Desktop widgets | Plugins and placed widgets: add, place, resize, configure, remove, the editor | `widgets` |
| Camera | Who's using it, its controls and presets, gestures on or off, the camera panel | `camera` |
| Anything else | Every IPC function the shell has | `ipc_list`, `ipc_call` |

## What it deliberately doesn't do

- **No photos from the camera.** The camera tool reads status, controls and
  presets, and toggles gestures, but can't take a picture: an agent seeing
  through your webcam is a line it shouldn't cross by accident.
- **No window management.** Moving and focusing windows is Hyprland's job;
  `list_windows` is read-only. (Window cards pair windows the shell's way.)

## Be careful with

- **`unlock`** unlocks without a password: anyone at the computer can use it
  afterwards. Lock again when done.
- **`screenshot`** sees whatever is on screen: open chats, mail, notifications.
- **`emoji` with `type`** types into whichever window has focus.
- **`config_set`** writes `~/.config/caelestia/shell.json`; the shell keeps
  only what differs from the defaults and your layers.

Agents run tools with your user's rights, so the usual advice applies: give
them the access you'd give a person sitting at your keyboard.
