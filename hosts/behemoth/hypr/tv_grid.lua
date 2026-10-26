-- Auto-flow 3-column grid on vertical-scroll workspaces.
--
-- Semantics: on workspaces flagged in IS_GRID_WORKSPACE, every new
-- window joins the previous row unless the total tiled window count is
-- a multiple of N_PER_ROW + 1 (i.e., 1st / 4th / 7th windows start
-- their own new row; every window in between joins the previous row).
--
-- Each strip is then blown up to fill the whole viewport via
-- `fit active` so each row takes the full screen.

local N_PER_ROW = 3
local SETTLE_MS = 80

local IS_GRID_WORKSPACE = { ["3"] = true }

local function tiled_count(ws_name)
  local wins = hl.get_workspace_windows(ws_name)
  if not wins then return 0 end
  local n = 0
  for _, w in ipairs(wins) do
    if not w.floating then n = n + 1 end
  end
  return n
end

hl.on("window.open", function(w)
  if not w or w.floating then return end
  if not w.workspace or not IS_GRID_WORKSPACE[w.workspace.name] then return end
  local addr = "address:" .. tostring(w.address)

  hl.timer(function()
    local live = hl.get_window(addr)
    if not live or live.floating then return end
    if not live.workspace or not IS_GRID_WORKSPACE[live.workspace.name] then return end

    local n = tiled_count(live.workspace.name)
    hl.dispatch(hl.dsp.focus({ window = addr }))

    -- 1st / 4th / 7th ... just started a new row → leave in own strip.
    -- 2nd / 3rd of the current row → consume back into previous strip.
    if n > 1 and ((n - 1) % N_PER_ROW) ~= 0 then
      hl.dispatch(hl.dsp.layout("consume_or_expel prev"))
    end

    -- Fill the strip vertically to the whole viewport.
    hl.dispatch(hl.dsp.layout("fit active"))
  end, { timeout = SETTLE_MS, type = "oneshot" })
end)
