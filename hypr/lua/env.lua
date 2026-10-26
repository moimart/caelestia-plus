local V = require("variables")

-- Display scaling (GDK_SCALE and the like) belongs to a monitor, so it's set
-- by the host profile's host.lua

-- Themes
hl.env("QT_QPA_PLATFORMTHEME",            "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR",     "1")
hl.env("XCURSOR_THEME",                   V.cursorTheme)
hl.env("XCURSOR_SIZE",                    tostring(V.cursorSize))

-- Toolkit backends
hl.env("GDK_BACKEND",                  "wayland,x11")
hl.env("QT_QPA_PLATFORM",              "wayland;xcb")
hl.env("SDL_VIDEODRIVER",              "wayland,x11,windows")
hl.env("CLUTTER_BACKEND",              "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE",    "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Java/AWT
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")

-- PATH
hl.env("PATH", os.getenv("HOME") .. "/.local/share/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin")
