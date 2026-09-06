local C = require("colors")

hl.config({
  misc = {
    vrr = 1,

    animate_manual_resizes        = false,
    animate_mouse_windowdragging  = false,

    disable_hyprland_logo    = true,
    disable_splash_rendering = true,   -- hide the version text on outputs
                                       -- where nothing else draws a
                                       -- wallpaper (HDMI-A-1 sink mode)
    force_default_wallpaper  = 0,

    -- new_window_takes_over_fullscreen = 2,
    allow_session_lock_restore = true,
    middle_click_paste         = false,
    focus_on_activate          = true,
    session_lock_xray          = true,

    mouse_move_enables_dpms = true,
    key_press_enables_dpms  = true,

    -- Pure black — DP-1 is fully covered by caelestia's wallpaper layer,
    -- so this is what shows on HDMI-A-1 (which has caelestia disabled).
    background_color = "rgb(000000)",
  },

  debug = {
    vfr            = true,  -- moved from misc.vfr in new schema
    error_position = 1,
  },

  xwayland = {
    force_zero_scaling = true,
  },
})
