-- Poll scheme/current.conf and re-apply the palette into the live config
-- when caelestia rewrites it.
--
-- Caelestia's apply_hypr() (caelestia/utils/theme.py) just writes the file
-- and walks away — it never tells Hyprland to reload. Under hyprlang that
-- still worked because `source = …current.conf` ran on every config touch;
-- under Lua, colors.lua reads the file once per `hyprctl reload`, so the
-- borders / groupbar / etc. stay on the previous palette until we do
-- something. This timer polls the file (cheap — a few hundred bytes) and
-- triggers a reload when the content changes.
--
-- Track caelestia-dots/caelestia#405 to remove this once upstream calls
-- `hyprctl reload` itself.

local scheme_path = require("paths").user .. "/scheme/current.conf"

local function read_all(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Snapshot the scheme content at config-load time so the first tick after
-- caelestia's write actually detects a change.
local last = read_all(scheme_path)

hl.timer(function()
  local cur = read_all(scheme_path)
  if cur and cur ~= last then
    last = cur
    hl.exec_cmd("hyprctl reload")
  end
end, { timeout = 1500, type = "repeat" })
