local V = require("variables")
local C = require("colors")

-- Group tabs in the shell's style (Material 3, like its chips and the
-- workspace pills): pills in the shell's font, the focused tab in the accent
-- colour, the others on a soft surface. A locked group (window cards use
-- them) has its focused tab in the tertiary colour.
local tabHeight = 28

hl.config({
  group = {
    ["col.border_active"]          = V.activeWindowBorderColour,
    ["col.border_inactive"]        = V.inactiveWindowBorderColour,
    ["col.border_locked_active"]   = V.activeWindowBorderColour,
    ["col.border_locked_inactive"] = V.inactiveWindowBorderColour,

    groupbar = {
      font_family               = "Google Sans Flex",
      font_size                 = 13,
      font_weight_active        = "semibold",
      font_weight_inactive      = "normal",
      height                    = tabHeight,
      text_padding              = 12,

      -- Filled pills ("gradients" are the tab backgrounds), no underline
      gradients                 = true,
      -- Hyprland draws this radius at about half the value, so the full
      -- height makes a pill (and it must be an integer: 28 / 2 is 14.0)
      gradient_rounding         = tabHeight,
      gradient_round_only_edges = false,
      indicator_height          = 0,
      gaps_in                   = 6,
      gaps_out                  = 6,
      keep_upper_gap            = true,
      blur                      = true,

      ["col.active"]              = C.rgba("primary",                 "ff"),
      ["col.inactive"]            = C.rgba("surfaceContainerHighest", "e6"),
      ["col.locked_active"]       = C.rgba("tertiary",                "ff"),
      ["col.locked_inactive"]     = C.rgba("surfaceContainerHigh",    "e6"),
      text_color                  = C.rgb("onPrimary"),
      text_color_inactive         = C.rgb("onSurfaceVariant"),
      text_color_locked_active    = C.rgb("onTertiary"),
      text_color_locked_inactive  = C.rgb("onSurfaceVariant"),
    },
  },
})
