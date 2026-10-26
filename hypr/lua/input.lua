local V = require("variables")

hl.config({
  input = {
    kb_layout         = "us",
    numlock_by_default = false,
    repeat_delay      = 250,
    repeat_rate       = 35,
    kb_options        = "compose:ralt",
    focus_on_close    = 1,

    touchpad = {
      natural_scroll       = true,
      disable_while_typing = V.touchpadDisableTyping,
      scroll_factor        = V.touchpadScrollFactor,
    },
  },

  binds = {
    scroll_event_delay = 0,
  },

  cursor = {
    hotspot_padding = 1,
  },
})

-- Plugin: virtcode/dynamic-cursors.
--
-- Cannot run under Hyprland 0.55 yet — the .so refuses to load with
-- "this plugin does not yet support lua configuration". Once upstream ships
-- the lua migration, uncomment the load line in lua/plugins.lua AND the
-- block below.
--
-- hl.config({
--   plugin = {
--     ["dynamic-cursors"] = {
--       enabled   = true,
--       mode      = "tilt",  -- tilt | rotate | stretch | none
--       threshold = 2,
--       rotate = {
--         length = 20,
--         offset = 0.0,
--       },
--     },
--   },
-- })
