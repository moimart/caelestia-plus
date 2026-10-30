-- Color palette loader.
--
-- The Caelestia shell writes the active palette for Hyprland: as
-- scheme/current.lua (a table of name = "hexrgb") when the config is Lua, as
-- caelestia-cli does since it learned about Lua configs, or as the older
-- scheme/current.conf (`$name = hexrgb` lines). The Lua one wins when both
-- are there; scheme_watcher.lua reloads when either changes.
--
-- If you no longer use Caelestia, replace `read_scheme()` with a static table.

local M = {}

local P = require("paths")
local hypr = P.user

-- Make sure scheme/current.conf exists (the shell writes it), falling back to
-- the default.conf that comes with the config.
local function ensure_current()
  local f = io.open(hypr .. "/scheme/current.conf", "r")
  if f then f:close(); return end
  os.execute(string.format(
    "mkdir -p '%s/scheme' && cp -L --no-preserve=mode '%s/scheme/default.conf' '%s/scheme/current.conf' 2>/dev/null",
    hypr, P.root, hypr))
end

local function read_scheme(path)
  local t = {}
  local f = io.open(path, "r")
  if not f then return t end
  for line in f:lines() do
    local k, v = line:match("^%s*%$([%w_]+)%s*=%s*(.-)%s*$")
    if k and v then t[k] = v end
  end
  f:close()
  return t
end

-- scheme/current.lua: `return { primary = "71fb7d", ... }`
local function read_lua_scheme(path)
  local f = io.open(path, "r")
  if not f then return nil end
  f:close()
  local ok, t = pcall(dofile, path)
  if ok and type(t) == "table" then return t end
  return nil
end

ensure_current()
M.palette = read_lua_scheme(hypr .. "/scheme/current.lua") or read_scheme(hypr .. "/scheme/current.conf")

-- Build a "rgba(<hex><alpha>)" string from a palette entry.
function M.rgba(name, alpha)
  local hex = M.palette[name] or "000000"
  return string.format("rgba(%s%s)", hex, alpha or "ff")
end

-- Build a "rgb(<hex>)" string from a palette entry.
function M.rgb(name)
  local hex = M.palette[name] or "000000"
  return string.format("rgb(%s)", hex)
end

return M
