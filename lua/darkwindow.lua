-- Hypr-DarkWindow: per-window shaders.
-- The .so is loaded in lua/plugins.lua; bail out if it didn't load
-- (missing build, or a stale build after a Hyprland upgrade).
if hl.plugin.darkwindow == nil then return end

local hypr = os.getenv("HOME") .. "/.config/hypr"

-- CRT scanlines + glitching refresh band (shaders/kitty-crt.glsl)
hl.plugin.darkwindow.load_shader("crt", {
  path = hypr .. "/shaders/kitty-crt.glsl",
  -- The curved corners are cut out, so Hyprland must not treat the window as opaque
  introduces_transparency = true,
  -- x_Time wraps at this interval; a multiple of the band (6s) and burst (5s) cycles
  animation_interval = 3600,
})

hl.window_rule({
  name  = "kitty-crt",
  match = { class = "kitty" },
  ["darkwindow:shade"] = "crt",
})
