-- caelestia-plus: the Hyprland config (Lua, Hyprland 0.55+).
-- See: https://wiki.hypr.land/Configuring/
--
-- This is the default config: complete on its own. Layers can extend it:
--   * your personal layer, the same on all your machines (private things:
--     your face, your home's devices, your own binds):
--     ~/.config/caelestia-plus/personal/. Its hypr/personal.lua runs after
--     the defaults; its caelestia/ layers under your shell config.
--   * a host profile, for what belongs to one machine (monitors, scaling...):
--     hosts/<name>/hypr/. Its modules replace the default ones of the same
--     name (monitors.lua), and its host.lua runs after the defaults. The name
--     comes from $CAELESTIA_PLUS_HOST, ~/.config/caelestia-plus/host, else
--     the hostname.
--   * your own changes, after everything else: ~/.config/hypr/hyprland.lua
--     when this file is installed as a package (it loads this one first), or
--     ~/.config/caelestia/hypr-user.lua.

local home = os.getenv("HOME")

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local function read_line(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local line = f:read("l")
  f:close()
  return line and line:match("^%s*(.-)%s*$")
end

-- Where this config lives (the repo, or /usr/share/caelestia-plus/hypr), and
-- where your own files are: the colour scheme the shell writes, overrides
local source = debug.getinfo(1, "S").source
local root = source:match("^@(.+)/[^/]+$") or (home .. "/.config/hypr")
local user = home .. "/.config/hypr"

-- The host profile: a private overlay first, then the ones shipped here
local hostName = os.getenv("CAELESTIA_PLUS_HOST") or read_line(home .. "/.config/caelestia-plus/host") or read_line("/etc/hostname")
local hostDir
if hostName and hostName ~= "" then
  for _, dir in ipairs({
    home .. "/.config/caelestia-plus/hosts/" .. hostName .. "/hypr",
    (root:match("^(.+)/[^/]+$") or root) .. "/hosts/" .. hostName .. "/hypr",
  }) do
    if exists(dir) then
      hostDir = dir
      break
    end
  end
end

-- Your personal layer (a private overlay; see the comment at the top)
local personalDir = home .. "/.config/caelestia-plus/personal"
if not exists(personalDir) then
  personalDir = nil
end

package.loaded.paths = {
  home = home, root = root, user = user,
  host = hostDir, hostName = hostName, personal = personalDir,
}

-- The layers' other configs (caelestia/shell.json, caelestia/monitors/...)
-- reach apps through $XDG_CONFIG_DIRS, the host profile before your personal
-- layer: the shell layers them under your own files
local dirs = os.getenv("XDG_CONFIG_DIRS") or "/etc/xdg"
local layered = dirs
for _, dir in ipairs({ personalDir or false, hostDir and hostDir:gsub("/hypr$", "") or false }) do
  if dir and not (":" .. layered .. ":"):find(":" .. dir .. ":", 1, true) then
    layered = dir .. ":" .. layered
  end
end
if layered ~= dirs then
  hl.env("XDG_CONFIG_DIRS", layered)
end

local searchPath = { root .. "/lua/?.lua", root .. "/scheme/?.lua", package.path }
if hostDir then
  table.insert(searchPath, 1, hostDir .. "/?.lua")
end
package.path = table.concat(searchPath, ";")

local cConf = home .. "/.config/caelestia"
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

-- Your personal additions, then the host profile's
if personalDir and exists(personalDir .. "/hypr/personal.lua") then
  dofile(personalDir .. "/hypr/personal.lua")
end
if hostDir and exists(hostDir .. "/host.lua") then
  require("host")
end

-- What you changed in the shell's Settings → Displays (it writes this file):
-- after the host profile, so it wins, and before your own overrides
if exists(cConf .. "/displays.lua") then
  local ok, err = pcall(dofile, cConf .. "/displays.lua")
  if not ok then
    print("caelestia-plus: displays.lua failed: " .. tostring(err))
  end
end

-- Your own overrides: load ~/.config/caelestia/hypr-user.lua only if it
-- actually exists (avoids the noisy "module not found" log line Hyprland
-- emits for failing requires).
if exists(cConf .. "/hypr-user.lua") then
  package.path = cConf .. "/?.lua;" .. package.path
  require("hypr-user")
end
