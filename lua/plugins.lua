-- Load hyprpm-managed plugins synchronously so their config keys are
-- registered before hl.config tries to use them.
--
-- hyprpm builds plugins under /var/cache/hyprpm/<user>/<repo>/<plugin>.so
-- and tracks per-plugin enable state in <repo>/state.toml.
-- We read that file as our source of truth so `sudo hyprpm enable|disable
-- <plugin>` is the single switch that controls everything: the .so load,
-- the hl.config({ plugin = ... }) block, AND the keybinds. Other modules
-- query via the returned `M.enabled(repo, plugin)` helper.

local M = {}

local function load(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  local ok, err = pcall(hl.plugin.load, path)
  if not ok then
    io.stderr:write(("hyprland: failed to load plugin %s: %s\n"):format(path, tostring(err)))
    return false
  end
  return true
end

local user = os.getenv("USER") or "moimart"
local hyprpm_cache = "/var/cache/hyprpm/" .. user

-- Parse <repo>/state.toml and return `enabled` for the named plugin section.
-- Returns false on missing file or section.
function M.enabled(repo, plugin)
  local f = io.open(hyprpm_cache .. "/" .. repo .. "/state.toml", "r")
  if not f then return false end
  local in_section = false
  local result = false
  for line in f:lines() do
    local section = line:match("^%s*%[([%w_%-%.]+)%]%s*$")
    if section then in_section = (section == plugin) end
    if in_section then
      local val = line:match("^%s*enabled%s*=%s*(%a+)")
      if val == "true"  then result = true;  break end
      if val == "false" then result = false; break end
    end
  end
  f:close()
  return result
end

-- Upstream lua migration status (checked 2026-05-14):
--
--   hyprwm/hyprland-plugins (hyprbars, borders-plus-plus, csgo-vulkan-fix,
--     hyprfocus, hyprexpo, hyprwinwrap, hyprscrolling):
--     ✅ FIXED in commits b6e0805 (PR #649 "lua update compatibility",
--     merged 2026-05-04) and eaf18d5 ("all: update for 0.55", 2026-05-12).
--     Run `hyprpm update` to fetch the current builds. Plugins now load
--     cleanly under 0.55. Verified locally with `hyprctl plugin load`.
--     Open follow-ups: #656 (lua dispatchers in plugins), #664 (docs).
--
--   VirtCode/hypr-dynamic-cursors:
--     ❌ NOT READY. PR #139 "support lua configuration" (branch `lua`,
--     commit 2f112a5) is WIP; the commit message says verbatim
--     "this would add lua support if it didn't abort on startup".
--     Upstream Hyprland prereq (PR #14379 — config variables with dashes)
--     is merged. Track issue #138 and PR #139:
--       https://github.com/VirtCode/hypr-dynamic-cursors/pull/139
--     Until that PR lands and a release is cut, dynamic-cursors cannot be
--     used with Hyprland 0.55.

-- Plugins handled here. Each entry is gated on hyprpm's own enabled flag
-- (via M.enabled), so toggling via `sudo hyprpm enable|disable <name>` is
-- the only thing needed to switch a plugin on/off — no config edits.
local PLUGINS = {
  { repo = "hyprexpo",          plugin = "hyprexpo",         so = "hyprexpo.so" },
  { repo = "dynamic-cursors",   plugin = "dynamic-cursors",  so = "dynamic-cursors.so" },
  { repo = "hyprland-plugins",  plugin = "hyprbars",         so = "hyprbars.so" },
  { repo = "hyprland-plugins",  plugin = "borders-plus-plus", so = "borders-plus-plus.so" },
  { repo = "hyprland-plugins",  plugin = "csgo-vulkan-fix",  so = "csgo-vulkan-fix.so" },
  { repo = "hyprland-plugins",  plugin = "hyprfocus",        so = "hyprfocus.so" },
}

for _, p in ipairs(PLUGINS) do
  if M.enabled(p.repo, p.plugin) then
    load(("%s/%s/%s"):format(hyprpm_cache, p.repo, p.so))
  end
end

-- Hypr-DarkWindow (per-window shaders; used by lua/darkwindow.lua).
-- Not managed by hyprpm: built by hand from ~/.local/src/Hypr-DarkWindow,
-- checked out at the tag matching the installed Hyprland. After a Hyprland
-- upgrade, rebuild with:
--   cd ~/.local/src/Hypr-DarkWindow && git fetch --tags \
--     && git checkout $(hyprctl version -j | jq -r .tag) && make
-- A stale build is refused by Hyprland's API hash check (load fails, no crash).
load(os.getenv("HOME") .. "/.local/src/Hypr-DarkWindow/out/hypr-darkwindow.so")

return M
