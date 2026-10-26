local V = require("variables")

-- One-shot startup commands (the old `exec-once = ...`)
hl.on("hyprland.start", function()
  -- Activate graphical-session.target so portals (e.g. xdg-desktop-portal-gnome)
  -- with Requisite=graphical-session.target can start.
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP")
  hl.exec_cmd("systemctl --user start hyprland-session.target")

  -- Keyring and auth
  hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
  hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
  -- (was `sleep 1 && hyprpm reload`. Plugins are now loaded synchronously
  --  in lua/plugins.lua, so async reload at start is no longer needed.)

  -- Clipboard history
  hl.exec_cmd("wl-paste --type text  --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  -- Auto-empty trash (older than 30 days)
  hl.exec_cmd("trash-empty 30")

  -- Cursors
  hl.exec_cmd(string.format("hyprctl setcursor %s %d", V.cursorTheme, V.cursorSize))
  hl.exec_cmd(string.format("gsettings set org.gnome.desktop.interface cursor-theme '%s'", V.cursorTheme))
  hl.exec_cmd(string.format("gsettings set org.gnome.desktop.interface cursor-size %d", V.cursorSize))

  -- Geolocation + night light
  hl.exec_cmd("/usr/lib/geoclue-2.0/demos/agent")
  hl.exec_cmd("sleep 1 && gammastep")

  -- Forward bluetooth media keys to MPRIS
  hl.exec_cmd("mpris-proxy")

  -- Caelestia helpers
  hl.exec_cmd("caelestia resizer -d")  -- PiP / match-based resize+move
  hl.exec_cmd("caelestia shell -d")    -- shell

  -- Idle daemon (was `exec-once = hypridle` from the entry conf)
  hl.exec_cmd("hypridle")
end)
