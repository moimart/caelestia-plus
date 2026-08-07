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
-- Position: auto-center-up keeps HDMI-A-1's bottom edge glued to DP-1's
-- top edge no matter the negotiated mode. Reason: the AVR falls back to
-- a 1920x1080 EDID whenever the TV/AVR handshake is in a "not fully 4K
-- Enhanced" state, and a fixed y that assumed 2160-tall left a 1080 px
-- dead band the mouse couldn't cross into (see conversation with moises).
-- auto-center-up loses the physical +460 horizontal offset in favour of
-- always-reachable — worth it.
--
-- If the AVR is set to "4K Enhanced" (or equivalent) on this input and
-- reliably negotiates 3840x2160, swap for the fixed-offset version:
--   position = "844x-2160",   -- centre at (2764,-1080), +460 from DP centre
hl.monitor({
  output   = "HDMI-A-1",
  mode     = "preferred",  -- let EDID decide (3840x2160@60 on this AVR)
  position = "auto-center-up",
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
