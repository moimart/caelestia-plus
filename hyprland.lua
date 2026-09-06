-- Hyprland config (Lua, since 0.55)
-- Converted from the previous .conf-based caelestia config tree.
-- See: https://wiki.hypr.land/Configuring/

local hypr = os.getenv("HOME") .. "/.config/hypr"
package.path = table.concat({
  hypr .. "/lua/?.lua",
  hypr .. "/scheme/?.lua",
  package.path,
}, ";")

-- Source the user's persistent overrides if present (~/.config/caelestia/hypr-vars.lua)
local cConf = os.getenv("HOME") .. "/.config/caelestia"
os.execute("mkdir -p '" .. cConf .. "'")

-- Each require() runs in its own Lua scope so an error in one file
-- will not abort the rest of the config.
require("colors")       -- color palette (parses scheme/current.conf)
require("variables")    -- shared user variables (apps, gaps, blur...)

-- Load plugins SYNCHRONOUSLY before any hl.config that mentions plugin keys.
-- (The old `exec-once = hyprpm reload` from execs.conf ran async, so plugin
--  keys were unknown when input.lua / decoration.lua were parsed.)
require("plugins")

require("hyprexpo")
require("env")
require("monitors")
require("workspaces")
require("general")
require("input")
require("misc")
require("animations")
require("decoration")
require("group")
require("rules")
require("gestures")
require("execs")
require("keybinds")
require("scheme_watcher")
require("tv_grid")

-- Optional: turn HDMI-A-1 into a "cast target" workspace instead of a
-- DP-1 mirror. Comment this line to fall back to the mirror behaviour.
require("tv_sink")

-- Optional per-host user overrides: load ~/.config/caelestia/hypr-user.lua
-- only if it actually exists (avoids the noisy "module not found" log line
-- Hyprland emits for failing requires).
local user_lua = cConf .. "/hypr-user.lua"
local f = io.open(user_lua, "r")
if f then
  f:close()
  package.path = cConf .. "/?.lua;" .. package.path
  require("hypr-user")
end
