-- behemoth: a 7680x2160 ultrawide (DP-1, scale 1.6666) and a TV/AVR on
-- HDMI-A-1. Its monitors.lua replaces the default one; this runs after the
-- defaults.

-- Display scaling for this monitor
hl.env("GDK_SCALE", "2.0")

-- require("tv_grid")   -- 3-per-row auto-flow for vertical scrolling
                       --  workspaces. Re-enable together with the ws 3
                       --  direction=down rule in workspaces.lua.

-- Optional: turn HDMI-A-1 into a "cast target" workspace instead of a
-- DP-1 mirror. Comment this line to fall back to the mirror behaviour.
require("tv_sink")
