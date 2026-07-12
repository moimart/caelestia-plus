-- Monitor configuration.
-- The original conf had `monitor = ,7680x2160@120,auto,1.6666,bitdepth,10`
-- which set the default rule (empty output) with bitdepth=10. The trailing
-- ",cm,hdr,sdrbrightness,1.5,sdrsaturation,1.2" was commented out with `#`.

-- Default fallback for any unspecified output
hl.monitor({
  output   = "",
  mode     = "7680x2160@120",
  position = "auto",
  scale    = 1.6666,
  bitdepth = 10,
  -- cm           = "hdr",        -- uncomment when ready for HDR
  -- sdrbrightness = 1.5,
  -- sdrsaturation = 1.2,
})

-- HDMI-A-1: mirror DP-1 by default (was `receiver on`). Hyprland silently
-- falls back to the AVR's preferred mode if 3840x2160@120 isn't advertised.
-- Toggle off at runtime with `~/.local/bin/receiver off`.
hl.monitor({
  output   = "HDMI-A-1",
  mode     = "3840x2160@120",
  position = "auto",
  scale    = 1,
  mirror   = "DP-1",
  disabled = false,
})

-- Headless / Sunshine remote streaming. Re-enable both lines together.
-- hl.exec_cmd("/usr/bin/hyprctl output create headless sunshine")
-- hl.monitor({ output = "sunshine", mode = "2560x1440@60", position = "7680x0", scale = 1 })
