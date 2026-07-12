-- HDMI-A-1 as an isolated "cast target" instead of a mirror of DP-1.
--
-- Nothing lands on the `name:tv` workspace unless explicitly moved there;
-- anything that does gets fullscreened automatically. Reason for going
-- standalone instead of mirror: unblocks direct scanout on DP-1 (mirror
-- lists MIRROR in directScanoutBlockedBy) and lets each output run its own
-- VRR / refresh cycle, which is measurably nicer for fullscreen games.
--
-- ============================================================
-- TO REVERT (get the mirror back):
--   1. Comment out `require("tv_sink")` in hyprland.lua.
--   2. That's it — lua/monitors.lua still holds the mirror
--      config, which becomes the last-writer-wins result again.
-- ============================================================

-- Pin DP-1 at the origin — otherwise Hyprland's "auto" placement pushes
-- it right next to HDMI-A-1 as soon as HDMI-A-1 has an explicit position.
-- Explicit rules don't inherit from the "" wildcard in monitors.lua, so we
-- restate the full config here.
hl.monitor({
  output   = "DP-1",
  mode     = "7680x2160@120",
  position = "0x0",
  scale    = 1.6666,
  bitdepth = 10,
})

-- Monitor: override the mirror rule from lua/monitors.lua. hl.monitor()
-- merges fields into the existing rule, so setting mirror="" unlinks it.
--
-- Position matches the physical layout: TV is above DP-1 with its centre
-- offset ~460 logical px right of DP-1's centre (roughly 1/10 of DP-1's
-- width — "less than 1/5" per moises' description). Bump the offset
-- towards ±1000 if the mouse feels like it snaps to the wrong edge when
-- crossing over.
--
--   DP-1 logical:  4608x1296  at (0,0)  → centre (2304, 648)
--   HDMI-A-1 logical: 3840x2160
--   Placed at (844, -2160):
--     - bottom edge at y=0 (touches DP-1 top)
--     - centre at (844 + 1920, -2160 + 1080) = (2764, -1080)
--     - horizontal offset from DP centre: +460 (≈ 1/10 of DP width)
hl.monitor({
  output   = "HDMI-A-1",
  mode     = "preferred",  -- let EDID decide (3840x2160@60 on this AVR)
  position = "844x-2160",
  scale    = 1,
  mirror   = "",           -- <-- unlink the DP-1 mirror
  disabled = false,
  -- Flip the AVR/TV into HDR mode. sdrbrightness/sdrsaturation only
  -- take effect in HDR mode; consumer TVs usually engage a brighter,
  -- more saturated picture mode when they detect an HDR signal, which
  -- fixes the muted look Hyprland's default sRGB pipeline produces.
  cm            = "hdr",
  bitdepth      = 10,     -- HDR requires 10-bit output
  sdrbrightness = 1.25,   -- 1.0 = neutral; typical range 1.0-2.0
  sdrsaturation = 1.20,   -- 1.0 = neutral
})

-- Persistent named workspace pinned to the second display. Nothing routes
-- here automatically; the only way in is an explicit move or focus.
hl.workspace_rule({
  workspace  = "name:tv",
  monitor    = "HDMI-A-1",
  persistent = true,
})

-- Pin the numeric workspaces to DP-1 so they don't gravitate onto HDMI-A-1
-- now that it's a real independent output. Without this, Hyprland spreads
-- the existing workspaces across both monitors and SUPER+1 could send you
-- to the TV.
for i = 1, 10 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "DP-1" })
end

-- Cast keybind: move the active window to name:tv AND fullscreen it.
-- The `fullscreen = true` window rule effect is a *match-time* predicate,
-- not a "set fullscreen" action, so we fullscreen imperatively from here.
-- Games that manage their own exclusive fullscreen will override this
-- into the deeper state, which is fine.
hl.bind("CTRL + SUPER + ALT + V", function()
  local w = hl.get_active_window()
  if not w then return end
  local addr = "address:" .. w.address
  hl.dispatch(hl.dsp.window.move({ workspace = "name:tv", window = addr }))
  hl.dispatch(hl.dsp.window.fullscreen({ action = "set", mode = "fullscreen", window = addr }))
end)

-- Focus / return: hover the mouse onto the TV to grab it, then use your
-- existing SUPER+ALT+<n> binds to move whatever's there back to a numbered
-- workspace on DP-1.
