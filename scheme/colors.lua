-- Color palette loader.
--
-- The Caelestia desktop framework writes the active palette into
-- scheme/current.conf as `$name = hexrgb` lines. We parse that file at config
-- load time so theme changes (which rewrite current.conf and trigger
-- `hyprctl reload`) keep working without conversion.
--
-- If you no longer use Caelestia, replace `read_scheme()` with a static table.

local M = {}

local hypr = os.getenv("HOME") .. "/.config/hypr"

-- Make sure scheme/current.conf exists, falling back to default.conf.
local function ensure_current()
  local f = io.open(hypr .. "/scheme/current.conf", "r")
  if f then f:close(); return end
  os.execute(string.format(
    "cp -L --no-preserve=mode '%s/scheme/default.conf' '%s/scheme/current.conf' 2>/dev/null",
    hypr, hypr))
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

ensure_current()
M.palette = read_scheme(hypr .. "/scheme/current.conf")

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
