-- Workspace rules. Replaces the old `workspace = ...` lines.

local V = require("variables")

-- xwaylandscale: the old `workspace = 5, xwaylandscale:3` field is gone in
-- Hyprland 0.55. v0.55.1's WorkspaceRuleSpec only accepts
-- {animation, border_size, decorate, default, default_name, enabled,
--  float_gaps, gaps_in, gaps_out, layout, layout_opts, monitor, no_border,
--  no_rounding, no_shadow, on_created_empty, persistent, workspace}.
-- The xwayland source path that read it (XWaylandManager.cpp) only knows
-- xwayland:force_zero_scaling now (which is enabled globally in misc.lua).
--
-- Closest replicas, depending on intent:
--   * if you wanted Resolve (the original use-case) on this workspace, the
--     window rule below sends it to ws 5 silently — uncomment when needed:
-- hl.window_rule({ match = { class = "^(resolve)$" }, workspace = "5 silent" })
--   * if you wanted a higher-DPI workspace, pin it to a different monitor:
-- hl.workspace_rule({ workspace = "5", monitor = "DP-2" })
--   * per-app XWayland upscale must now be done via env on the launcher,
--     e.g. `GDK_SCALE=3 QT_SCALE_FACTOR=3 <app>`.

-- (Workspace 2's `layout = "scrolling"` override was dropped — scrolling
--  is now the global default in lua/general.lua. If you flip general.layout
--  back to "dwindle", re-add this rule to keep ws 2 on scrolling.)

-- Workspace 3 uses scrolling in the vertical direction — rows top-to-bottom
-- instead of columns left-to-right. Everything else (column_width becomes
-- row-height, fullscreen_on_one_column, etc.) still applies.
hl.workspace_rule({ workspace = "3", layout_opts = { direction = "down" } })

-- Single-window workspaces (tiled or floating, no special) use a smaller gap
hl.workspace_rule({ workspace = "w[tv1]s[false]", gaps_out = V.singleWindowGapsOut })
hl.workspace_rule({ workspace = "f[1]s[false]",   gaps_out = V.singleWindowGapsOut })

-- Persistent named special workspace for remote streaming. Uncomment if used.
-- hl.workspace_rule({ workspace = "name:remote", monitor = "sunshine", persistent = true })
