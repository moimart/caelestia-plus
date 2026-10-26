local V = require("variables")

-- =====================================================================
-- Window rules
-- =====================================================================

-- Default opacity for non-fullscreen, non-XWayland windows
hl.window_rule({
  name      = "default-opacity",
  match     = { fullscreen = false, xwayland = false },
  opacity   = string.format("%s override", V.windowOpacity),
})

-- Apps that handle their own transparency, force opaque
hl.window_rule({
  name  = "force-opaque",
  match = { class = "foot|kitty|equibop|org\\.quickshell|imv|swappy" },
  opaque = true,
})

-- Center floating Wayland windows (XWayland popups left alone)
hl.window_rule({
  name  = "center-floats",
  match = { float = true, xwayland = false },
  center = true,
})

-- ----- Float-only -----
local floats = {
  "guifetch", "yad", "zenity", "wev",
  "org\\.gnome\\.FileRoller", "file-roller",
  "blueman-manager",
  "com\\.github\\.GradienceTeam\\.Gradience",
  "feh", "imv",
  "system-config-printer",
  "org\\.quickshell",
}
for _, cls in ipairs(floats) do
  hl.window_rule({ match = { class = cls }, float = true })
end

-- ----- Float, resize and center -----
hl.window_rule({
  match = { class = "foot",  title = "nmtui" },
  float = true, center = true,
  size = { "monitor_w*0.6", "monitor_h*0.7" },
})
hl.window_rule({
  match = { class = "kitty", title = "nmtui" },
  float = true, center = true,
  size = { "monitor_w*0.6", "monitor_h*0.7" },
})
hl.window_rule({
  match = { class = "org\\.gnome\\.Settings" },
  float = true, center = true,
  size = { "monitor_w*0.7", "monitor_h*0.8" },
})
hl.window_rule({
  match = { class = "org\\.pulseaudio\\.pavucontrol|yad-icon-browser" },
  float = true, center = true,
  size = { "monitor_w*0.6", "monitor_h*0.7" },
})
hl.window_rule({
  match = { class = "nwg-look" },
  float = true, center = true,
  size = { "monitor_w*0.5", "monitor_h*0.6" },
})

-- ----- Special workspaces -----
hl.window_rule({ match = { class = "btop" },                                workspace = "special:sysmon" })
hl.window_rule({ match = { class = "feishin|Spotify|Supersonic|Cider" },    workspace = "special:music" })
hl.window_rule({ match = { initial_title = "Spotify( Free)?" },             workspace = "special:music" })  -- Spotify wayland
hl.window_rule({ match = { class = "discord|equibop|vesktop|whatsapp" },    workspace = "special:communication" })
hl.window_rule({ match = { class = "Todoist" },                             workspace = "special:todo" })

-- ----- Dialogs -----
local dialog_titles = {
  "(Select|Open)( a)? (File|Folder)(s)?",
  "File (Operation|Upload)( Progress)?",
  ".* Properties",
  "Export Image as PNG",
  "GIMP Crash Debug",
  "Save As",
  "Library",
}
for _, t in ipairs(dialog_titles) do
  hl.window_rule({ match = { title = t }, float = true })
end

-- ----- Picture-in-picture -----
-- Initial move so the PiP doesn't shoot in from the center
hl.window_rule({
  match = { title = "Picture(-| )in(-| )[Pp]icture" },
  move  = { "((monitor_w*1)-window_w-(monitor_w*0.02))", "((monitor_h*1)-window_h-(monitor_h*0.03))" },
})
hl.window_rule({
  match = { title = "Picture(-| )in(-| )[Pp]icture" },
  keep_aspect_ratio = true,
  float = true,
  pin   = true,
})

-- ----- Steam -----
hl.window_rule({ match = { title = "", class = "steam" }, rounding = 10 })
-- hl.window_rule({ match = { title = "Friends List", class = "steam" }, float = true })
hl.window_rule({ match = { class = "steam_app_[0-9]+" }, immediate     = true })  -- allow tearing
hl.window_rule({ match = { class = "steam_app_[0-9]+" }, idle_inhibit  = "always" })

-- ----- ATLauncher console -----
hl.window_rule({
  match = { class = "com-atlauncher-App", title = "ATLauncher Console" },
  float = true,
})

-- ----- Autodesk Fusion 360 -----
hl.window_rule({
  match = { title = "Fusion360|(Marking Menu)", class = "fusion360\\.exe" },
  no_blur = true,
})

-- ----- XWayland popups -----
hl.window_rule({
  match     = { xwayland = true, title = "win[0-9]+" },
  no_dim    = true,
  no_shadow = true,
  rounding  = 10,
})

-- ----- Video Wallpaper Selector -----
hl.window_rule({
  name  = "video-wallpaper",
  match = { class = "sh.martinez.VideoWallpaper" },
  float = true,
  size  = { 1400, 360 },
})

-- =====================================================================
-- Layer rules
-- =====================================================================

-- Fade animations for transient overlays
for _, ns in ipairs({ "hyprpicker", "logout_dialog", "selection", "wayfreeze" }) do
  hl.layer_rule({ match = { namespace = ns }, animation = "fade" })
end

-- Fuzzel launcher
hl.layer_rule({
  match     = { namespace = "launcher" },
  animation = "popin 80%",
  blur      = true,
})

-- Caelestia shell
hl.layer_rule({
  match  = { namespace = "caelestia-(border-exclusion|area-picker)" },
  no_anim = true,
})
hl.layer_rule({
  match     = { namespace = "caelestia-(drawers|background)" },
  animation = "fade",
})
hl.layer_rule({
  match        = { namespace = "caelestia-drawers" },
  blur         = true,
  ignore_alpha = 0.57,
})
