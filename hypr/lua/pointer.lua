-- Placing floating windows at the pointer: the floating terminal, browser
-- popups, a floating file manager.
local M = {}

-- Where a w×h window goes to be centred on the pointer, kept on its monitor
-- (clear of the bar and other reserved space). nil if there's no pointer.
function M.spot(w, h)
  local m, c = hl.get_monitor_at_cursor(), hl.get_cursor_pos()
  if not m or not c then return nil end
  local gap, r = 10, m.reserved
  local right, bottom = m.x + m.width / m.scale, m.y + m.height / m.scale
  local x = math.max(m.x + r.left + gap, math.min(right - r.right - w - gap, c.x - w / 2))
  local y = math.max(m.y + r.top + gap, math.min(bottom - r.bottom - h - gap, c.y - h / 2))
  return math.floor(x), math.floor(y)
end

-- Apps with one process for all their windows (Nautilus) open a new window
-- from the process that's already running, which exec rules can't follow.
-- So: the next window of `class`, within 5 s, floats at the pointer at w×h.
local pending

function M.float_next(class, w, h)
  pending = { class = class, w = w, h = h, deadline = os.time() + 5 }
end

if _G.__floatNextSub then pcall(function() _G.__floatNextSub:remove() end) end
_G.__floatNextSub = hl.on("window.open", function(win)
  if not pending or not win or win.class ~= pending.class then return end
  local p = pending
  pending = nil
  if os.time() > p.deadline then return end
  local addr = "address:" .. win.address
  if not win.floating then
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = addr }))
  end
  hl.dispatch(hl.dsp.window.resize({ x = p.w, y = p.h, window = addr }))
  local x, y = M.spot(p.w, p.h)
  if x then
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = addr }))
  end
end)

return M
