local V = require("variables")

hl.config({
  general = {
    -- Trial: scrolling everywhere (was "dwindle"). Combined with
    -- scrolling.column_width = 0.33 and fullscreen_on_one_column = false,
    -- this gives 1/3-column layout for 1-3 windows on every workspace.
    -- 4th+ column scrolls off-screen — swipe/hjkl to reach it. Flip back
    -- to "dwindle" here to revert.
    layout         = "scrolling",
    allow_tearing  = false,  -- gates the per-window `immediate` rule

    gaps_workspaces = V.workspaceGaps,
    gaps_in         = V.windowGapsIn,
    gaps_out        = V.windowGapsOut,
    border_size     = V.windowBorderSize,

    ["col.active_border"]   = V.activeWindowBorderColour,
    ["col.inactive_border"] = V.inactiveWindowBorderColour,
  },

  dwindle = {
    preserve_split = true,
    smart_split    = false,
    smart_resizing = true,
  },

  layout = {
    -- A 16:9 screen with a single 2:1 window centered with side padding
    single_window_aspect_ratio = { 2, 1 },
  },

  scrolling = {
    column_width = 0.33,
    -- Don't let a single-column workspace blow the window up to fill the
    -- screen — defer to column_width / layout.single_window_aspect_ratio.
    fullscreen_on_one_column = false,
  },
})
