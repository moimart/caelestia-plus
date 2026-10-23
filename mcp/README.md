# caelestia MCP server

Lets agents control the shell: a stdio MCP server, standard-library Python,
wrapping the shell's IPC, the `caelestia` CLI, `shell.json`, `grim` and
`hyprctl`. It finds the Wayland/Hyprland sockets itself, so it works from
tmux and service-started sessions.

```sh
claude mcp add --scope user caelestia -- python3 ~/code/caelestia-shell/mcp/caelestia_mcp.py
```

Tools:

| Area | Tools |
|---|---|
| See | `screenshot` (JPEG, downscaled), `list_monitors`, `list_windows` |
| Lock | `lock_status`, `lock`, `unlock` (no password: anyone at the machine can use it afterwards) |
| Wallpaper | `wallpaper_list`, `wallpaper_get`, `wallpaper_set` (image or video, optionally per monitor), `wallpaper_clear_monitor` |
| Colours | `scheme_get`, `scheme_list`, `scheme_set` |
| Settings | `config_get`, `config_set` (dotted keys in `shell.json` or a monitor's override; reloads live) |
| Desktop | `media_status`, `media_control`, `brightness`, `toast`, `notifications`, `toggle` (game mode, idle inhibitor), `panel` (launcher, dashboard, ...; `settings`) |
| Shortcuts | `keybinds` (list the Hyprland/shell shortcuts from the config, filter by words or owner; show/hide the shortcuts panel; open its settings) |
| Anything else | `ipc_list`, `ipc_call` |

Window management (moving/focusing windows) is Hyprland's, not the shell's,
and isn't exposed; `list_windows` is read-only.
