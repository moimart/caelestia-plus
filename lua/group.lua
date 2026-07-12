local V = require("variables")
local C = require("colors")

hl.config({
  group = {
    ["col.border_active"]          = V.activeWindowBorderColour,
    ["col.border_inactive"]        = V.inactiveWindowBorderColour,
    ["col.border_locked_active"]   = V.activeWindowBorderColour,
    ["col.border_locked_inactive"] = V.inactiveWindowBorderColour,

    groupbar = {
      font_family               = "JetBrains Mono NF",
      font_size                 = 15,
      gradients                 = true,
      gradient_round_only_edges = false,
      gradient_rounding         = 5,
      height                    = 25,
      indicator_height          = 0,
      gaps_in                   = 3,
      gaps_out                  = 3,

      text_color                  = C.rgb("onPrimary"),
      ["col.active"]              = C.rgba("primary",   "d4"),
      ["col.inactive"]            = C.rgba("outline",   "d4"),
      ["col.locked_active"]       = C.rgba("primary",   "d4"),
      ["col.locked_inactive"]     = C.rgba("secondary", "d4"),
    },
  },
})
