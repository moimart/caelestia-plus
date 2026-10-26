local V = require("variables")

local P      = require("paths")
local home   = P.home
local wsaction = P.root .. "/scripts/wsaction.fish"
local rescue   = P.root .. "/scripts/rescue-windows.fish"

-- =====================================================================
-- Workspace switching
-- =====================================================================
hl.bind("CTRL + left",  hl.dsp.focus({ workspace = "-1" }))
hl.bind("CTRL + right", hl.dsp.focus({ workspace = "+1" }))

-- SUPER + `  → rotary cycle through populated workspaces on this monitor.
-- SUPER + ~  → same cycle in reverse (SHIFT+backtick = tilde).
-- Skips special workspaces, empty workspaces, and workspaces on other
-- monitors. Wraps around at the ends.
local function cycle_populated(reverse)
  local cur = hl.get_active_workspace()
  if not cur or not cur.monitor then return end
  local candidates = {}
  for _, ws in ipairs(hl.get_workspaces() or {}) do
    if ws.id > 0 and not ws.special
       and ws.windows > 0 and ws.monitor
       and ws.monitor.id == cur.monitor.id then
      candidates[#candidates + 1] = ws
    end
  end
  table.sort(candidates, function(a, b) return a.id < b.id end)
  if #candidates < 2 then return end
  local step = reverse and -1 or 1
  local target = candidates[1]
  for i, ws in ipairs(candidates) do
    if ws.id == cur.id then
      target = candidates[((i - 1 + step) % #candidates) + 1]
      break
    end
  end
  hl.dispatch(hl.dsp.focus({ workspace = tostring(target.id) }))
end
hl.bind("SUPER + grave",         function() cycle_populated(false) end)
hl.bind("SUPER + SHIFT + grave", function() cycle_populated(true)  end)

-- =====================================================================
-- Caelestia shell global IPC binds
-- =====================================================================
-- Launcher.
-- The `caelestia:launcher` global shortcut path (Hyprland → portal →
-- caelestia's QML GlobalShortcut listener) is broken on 0.55: Hyprland sends
-- the event ok (`hl.dispatch(hl.dsp.global("caelestia:launcher"))` returns
-- ok) but the launcher never surfaces, even after restarting the shell.
-- Workaround: call caelestia's QML IPC directly via quickshell. Tracking
-- caelestia-dots/caelestia#405 for the upstream 0.55 migration.
hl.bind("SUPER + Space",
        hl.dsp.exec_cmd("qs -c caelestia ipc call drawers toggle launcher"))

-- Dashboard toggle. dashboard.showOnHover was set to false in
-- ~/.config/caelestia/shell.json, so the top-edge hover no longer
-- summons it — this bind is the way to bring it up.
hl.bind("SUPER + E",
        hl.dsp.exec_cmd("qs -c caelestia ipc call drawers toggle dashboard"))
-- The original `bindin = Super, catchall, ...` line was dropped: `catchall`
-- is a submap-only keysym in the new API. The mouse/wheel interrupts below
-- cover the common cases the user wired up.
for _, k in ipairs({ "mouse:272", "mouse:273", "mouse:274",
                     "mouse:275", "mouse:276", "mouse:277",
                     "mouse_up", "mouse_down" }) do
  hl.bind("SUPER + " .. k, hl.dsp.global("caelestia:launcherInterrupt"),
          { ignore_mods = true, non_consuming = true })
end

-- Misc shell actions
hl.bind("CTRL + ALT + Delete",   hl.dsp.global("caelestia:session"))
hl.bind("CTRL + ALT + C",        hl.dsp.global("caelestia:clearNotifs"), { locked = true })
hl.bind("SUPER + K",             hl.dsp.global("caelestia:showall"))
hl.bind("SUPER + L",             hl.dsp.global("caelestia:lock"))
hl.bind("SUPER + slash",         hl.dsp.global("caelestia:keybinds"))  -- keyboard shortcuts panel
hl.bind("CTRL + SUPER + Space",  hl.dsp.global("caelestia:emoji"))     -- emoji picker, like macOS

-- Restore lockscreen if it crashed
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd("caelestia shell -d"),  { locked = true })
hl.bind("SUPER + ALT + L", hl.dsp.global("caelestia:lock"),         { locked = true })

-- Re-broadcast caelestia colour sequences to every open terminal
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd(home .. "/.local/share/bin/refresh-term-colors"))

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.global("caelestia:brightnessUp"),   { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"), { locked = true })

-- Media (also wired to the Fn-row keys for laptops)
hl.bind("XF86AudioPlay",         hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPause",        hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("CTRL + SUPER + Equal",  hl.dsp.global("caelestia:mediaNext"),   { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.global("caelestia:mediaNext"),   { locked = true })
hl.bind("CTRL + SUPER + Minus",  hl.dsp.global("caelestia:mediaPrev"),   { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.global("caelestia:mediaPrev"),   { locked = true })
hl.bind("XF86AudioStop",         hl.dsp.global("caelestia:mediaStop"),   { locked = true })

-- Kill / restart shell
hl.bind("CTRL + SUPER + SHIFT + R",
        hl.dsp.exec_cmd("qs -c caelestia kill"),                          { release = true })
hl.bind("CTRL + SUPER + ALT + R",
        hl.dsp.exec_cmd("qs -c caelestia kill; caelestia shell -d"),      { release = true })

-- =====================================================================
-- Workspace navigation (numeric)
-- =====================================================================
-- Workspaces are grouped in tens (1-10, 11-20, …). The old wsaction.fish
-- script computed the target id and called `hyprctl dispatch workspace N`,
-- but argv-form dispatch is dead in 0.55 ("dispatch in lua is a shorthand
-- for hl.dispatch(...)"). Inlining the math in Lua removes the subprocess.
local function active_ws_id()
  local w = hl.get_active_workspace()
  return (w and w.id and w.id > 0) and w.id or 1
end
-- Stay in current group, switch to slot n: floor((cur-1)/10)*10 + n
local function ws_in_current_group(n)
  return math.floor((active_ws_id() - 1) / 10) * 10 + n
end
-- Switch group, keep current slot:        (n-1)*10 + (cur % 10 or 10)
local function ws_in_group(n)
  local slot = active_ws_id() % 10
  if slot == 0 then slot = 10 end
  return (n - 1) * 10 + slot
end
local function ws_focus(n) hl.dispatch(hl.dsp.focus({ workspace = tostring(n) })) end
local function ws_move(n)  hl.dispatch(hl.dsp.window.move({ workspace = tostring(n) })) end

for i = 1, 10 do
  local k = (i == 10) and "0" or tostring(i)
  -- Switch to slot i in current group
  hl.bind("SUPER + " .. k,              function() ws_focus(ws_in_current_group(i)) end)
  -- Switch to group i, keeping slot
  hl.bind("CTRL + SUPER + " .. k,       function() ws_focus(ws_in_group(i))         end)
  -- Move active window to slot i in current group
  hl.bind("SUPER + ALT + " .. k,        function() ws_move (ws_in_current_group(i)) end)
  -- Move active window to group i, keeping slot
  hl.bind("CTRL + SUPER + ALT + " .. k, function() ws_move (ws_in_group(i))         end)
end

-- Relative workspace navigation
hl.bind("CTRL + SUPER + left",  hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("CTRL + SUPER + right", hl.dsp.focus({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + Page_Up",      hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + Page_Down",    hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Across workspace groups
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "-10" }))
hl.bind("CTRL + SUPER + mouse_up",   hl.dsp.focus({ workspace = "+10" }))

-- Special workspace toggle. The old `caelestia toggle specialws` shells out
-- to `hyprctl dispatch togglespecialworkspace`, which no longer parses on
-- 0.55 (dispatch bodies are now Lua, not "name args" strings), so the
-- caelestia command silently no-ops. Use the direct Lua dispatcher instead.
hl.bind("SUPER + S", function()
  hl.dispatch(hl.dsp.workspace.toggle_special("special"))
end)

-- Move active window across workspaces
hl.bind("SUPER + ALT + Page_Up",      hl.dsp.window.move({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + ALT + Page_Down",    hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + ALT + mouse_down",   hl.dsp.window.move({ workspace = "-1" }))
hl.bind("SUPER + ALT + mouse_up",     hl.dsp.window.move({ workspace = "+1" }))
hl.bind("CTRL + SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("CTRL + SUPER + SHIFT + left",  hl.dsp.window.move({ workspace = "-1" }), { repeating = true })

-- Special workspaces (window movement)
hl.bind("CTRL + SUPER + SHIFT + up",   hl.dsp.window.move({ workspace = "special:special" }))
hl.bind("CTRL + SUPER + SHIFT + down", hl.dsp.window.move({ workspace = "e+0" }))
hl.bind("SUPER + ALT + S",             hl.dsp.window.move({ workspace = "special:special" }))

hl.bind("CTRL + SUPER + ALT + M", hl.dsp.window.move({ workspace = "special:music" }))
hl.bind("CTRL + SUPER + ALT + D", hl.dsp.window.move({ workspace = "special:communication" }))
hl.bind("CTRL + SUPER + ALT + T", hl.dsp.window.move({ workspace = "special:todo" }))
hl.bind("CTRL + SUPER + ALT + Y", hl.dsp.window.move({ workspace = "special:sysmon" }))

-- =====================================================================
-- Window groups
-- =====================================================================
hl.bind("ALT + Tab",                hl.dsp.window.cycle_next(),                       { repeating = true })
hl.bind("SHIFT + ALT + Tab",        hl.dsp.window.cycle_next({ next = "prev" }),      { repeating = true })
hl.bind("CTRL + ALT + Tab",         hl.dsp.group.next(),                              { repeating = true })
hl.bind("CTRL + SHIFT + ALT + Tab", hl.dsp.group.prev(),                              { repeating = true })
hl.bind("SUPER + Comma",            hl.dsp.group.toggle())
hl.bind("SUPER + U",                hl.dsp.window.move({ out_of_group = true }))
hl.bind("SUPER + SHIFT + Comma",    hl.dsp.group.lock_active({ action = "toggle" }))

-- hyprexpo binds live in lua/hyprexpo.lua, next to the plugin config.

-- =====================================================================
-- Window cards (caelestia: two windows paired into one that flips over)
-- =====================================================================
hl.bind("SUPER + Tab",       hl.dsp.global("caelestia:cardFlip"))    -- flip the focused card
hl.bind("SUPER + ALT + Tab", hl.dsp.global("caelestia:cardPair"))    -- pair the focused window with one you pick
hl.bind("SUPER + SHIFT + Tab", hl.dsp.global("caelestia:cardUnpair"))  -- split the card back into two windows

-- =====================================================================
-- Desktop widgets (caelestia plugins)
-- =====================================================================
hl.bind("SUPER + CTRL + W", hl.dsp.global("caelestia:widgets"))  -- place and resize desktop widgets

-- =====================================================================
-- Camera (caelestia)
-- =====================================================================
hl.bind("SUPER + ALT + C", hl.dsp.global("caelestia:camera"))          -- camera panel: mirror, controls, presets
hl.bind("SUPER + ALT + G", hl.dsp.global("caelestia:cameraGestures"))  -- hand gestures on/off

-- =====================================================================
-- Window movement / focus / resizing
-- =====================================================================
hl.bind("SUPER + N", hl.dsp.exec_cmd("caelestia shell drawers toggle sidebar"))

hl.bind("SUPER + left",  hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + up",    hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + down",  hl.dsp.focus({ direction = "d" }))

hl.bind("SUPER + SHIFT + CTRL + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + CTRL + right", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + left",         hl.dsp.window.swap({ direction = "l" }))
hl.bind("SUPER + SHIFT + right",        hl.dsp.window.swap({ direction = "r" }))
hl.bind("SUPER + SHIFT + up",           hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + down",         hl.dsp.window.move({ direction = "d" }))

hl.bind("SUPER + Minus", hl.dsp.layout("splitratio -0.1"), { repeating = true })
hl.bind("SUPER + Equal", hl.dsp.layout("splitratio 0.1"),  { repeating = true })

-- Mouse-driven move/resize (and keyboard equivalents on Z/X)
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + Z",         hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("SUPER + X",         hl.dsp.window.resize(), { mouse = true })

hl.bind("CTRL + SUPER + Backslash",       hl.dsp.window.center())
hl.bind("CTRL + SUPER + ALT + Backslash", function()
  hl.dispatch(hl.dsp.window.resize({ x = "55%", y = "70%" }))  -- exact 55% 70%
  hl.dispatch(hl.dsp.window.center())
end)
hl.bind("SUPER + ALT + Backslash", hl.dsp.exec_cmd("caelestia resizer pip"))

hl.bind("SUPER + P",          hl.dsp.window.pin())
hl.bind("SUPER + F",          hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + ALT + F",    hl.dsp.window.fullscreen({ mode = "maximized"  }))  -- with borders
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + W",          hl.dsp.window.close())
hl.bind("SUPER + J",          hl.dsp.layout("togglesplit"))
hl.bind("SUPER + SHIFT + J",  hl.dsp.layout("promote"))

-- Special workspace toggles. Direct Lua dispatcher (caelestia's wrappers
-- are broken on 0.55 — see SUPER+S note above).
hl.bind("CTRL + SHIFT + Escape", function() hl.dispatch(hl.dsp.workspace.toggle_special("sysmon"))        end)
hl.bind("SUPER + M",             function() hl.dispatch(hl.dsp.workspace.toggle_special("music"))         end)
hl.bind("SUPER + D",             function() hl.dispatch(hl.dsp.workspace.toggle_special("communication")) end)
hl.bind("SUPER + R",             function() hl.dispatch(hl.dsp.workspace.toggle_special("todo"))          end)

-- =====================================================================
-- Apps
-- =====================================================================
hl.bind("SUPER + Return",     hl.dsp.exec_cmd("app2unit -- " .. V.terminal))
-- SUPER + SHIFT + Return → floating terminal at the pointer, kept on screen
hl.bind("SHIFT + SUPER + Return", function()
  local m, c = hl.get_monitor_at_cursor(), hl.get_cursor_pos()
  if not m or not c then
    return hl.exec_cmd("app2unit -- " .. V.terminal)
  end
  local w, h, gap = 960, 600, 10
  local r = m.reserved
  local right, bottom = m.x + m.width / m.scale, m.y + m.height / m.scale
  local x = math.max(m.x + r.left + gap, math.min(right - r.right - w - gap, c.x - w / 2))
  local y = math.max(m.y + r.top + gap, math.min(bottom - r.bottom - h - gap, c.y - h / 2))
  hl.exec_cmd("app2unit -- " .. V.terminal, {
    float = true,
    size  = w .. " " .. h,
    move  = math.floor(x) .. " " .. math.floor(y),
  })
end)
hl.bind("SHIFT + SUPER + B",  hl.dsp.exec_cmd("app2unit -- " .. V.browser))
hl.bind("SUPER + C",          hl.dsp.exec_cmd("app2unit -- " .. V.editor))
hl.bind("SHIFT + SUPER + F",  hl.dsp.exec_cmd("app2unit -- " .. V.fileExplorer))
hl.bind("SUPER + ALT + E",    hl.dsp.exec_cmd("app2unit -- nemo"))
hl.bind("CTRL + ALT + Escape", hl.dsp.exec_cmd("app2unit -- qps"))
hl.bind("CTRL + ALT + V",     hl.dsp.exec_cmd("app2unit -- pavucontrol"))
-- iPhone Mirror (USB if plugged in, else Wi-Fi); focuses the window if already running.
-- The wrapper re-mounts the developer image over USB and notifies on failure.
hl.bind("SUPER + SHIFT + I",  hl.dsp.exec_cmd(home .. "/.local/bin/iphone-mirror-launch"),
        { description = "iPhone Mirror" })

-- Web apps (description shows up in `hyprctl binds`)
hl.bind("SUPER + SHIFT + H", hl.dsp.exec_cmd('launch-webapp "http://homeassistant.local:8123/"'),
        { description = "Home Assistant" })
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd('launch-webapp-or-focus Whatsapp "https://web.whatsapp.com/"'),
        { description = "Whatsapp" })
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd('launch-webapp "https://claude.ai"'),
        { description = "Claude" })
hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd('launch-webapp-or-focus Gemini "https://gemini.google.com"'),
        { description = "Gemini" })
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd('launch-webapp "https://inbox.google.com"'),
        { description = "GMail" })
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd('launch-webapp-or-focus Telegram "https://web.telegram.org"'),
        { description = "Telegram" })

hl.bind("SUPER + Q", hl.dsp.layout("fit all"))

-- Rescue windows from disconnected/headless monitors
hl.bind("SUPER + Home", hl.dsp.exec_cmd(rescue))

-- =====================================================================
-- Scrolling-layout column movement & cursor zoom
-- (was in the entry hyprland.conf)
-- =====================================================================
hl.bind("CTRL + SUPER + period", hl.dsp.layout("move +col"))
hl.bind("CTRL + SUPER + comma",  hl.dsp.layout("move -col"))

-- Cursor-zoom helpers. Under the new Lua parser `hyprctl keyword
-- cursor:zoom_factor X` is rejected ("keyword can't work with non-legacy
-- parsers. Use eval."), so we set the value directly through hl.config.
-- zoom_factor must be >= 1.0.
local function set_zoom(v)
  if v < 1.0 then v = 1.0 end
  hl.config({ cursor = { zoom_factor = v } })
end
local function bump_zoom(delta)
  local curr = hl.get_config("cursor.zoom_factor") or 1.0
  set_zoom(curr + delta)
end

-- Hold-to-zoom on Ctrl+Super+MMB
hl.bind("CTRL + SUPER + mouse:274", function() set_zoom(3.0) end)
hl.bind("CTRL + SUPER + mouse:274", function() set_zoom(1.0) end, { release = true })

-- Wheel zoom in/out (Super + scroll)
hl.bind("SUPER + mouse_up",   function() bump_zoom(-0.5) end)
hl.bind("SUPER + mouse_down", function() bump_zoom( 0.5) end)

-- Move scrolling-layout columns with Shift+Super+wheel
hl.bind("SHIFT + SUPER + mouse_up",   hl.dsp.layout("move +col"))
hl.bind("SHIFT + SUPER + mouse_down", hl.dsp.layout("move -col"))

-- =====================================================================
-- Utilities (screenshot, screen recording, color picker, reload, lock)
-- =====================================================================
hl.bind("Print",                     hl.dsp.exec_cmd("caelestia screenshot"),         { locked = true })
hl.bind("SUPER + SHIFT + S",         hl.dsp.global("caelestia:screenshotFreeze"))     -- region (freeze)
hl.bind("SUPER + SHIFT + ALT + S",   hl.dsp.global("caelestia:screenshot"))           -- region
hl.bind("SUPER + ALT + R",           hl.dsp.exec_cmd("caelestia record -s"))          -- record screen+sound
hl.bind("CTRL + ALT + R",            hl.dsp.exec_cmd("caelestia record"))             -- record screen
hl.bind("SUPER + SHIFT + ALT + R",   hl.dsp.exec_cmd("caelestia record -r"))          -- record region
hl.bind("CTRL + SUPER + SHIFT + C",  hl.dsp.exec_cmd("hyprpicker -a"))                -- color picker

hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd("/usr/bin/hyprctl reload"))
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("hyprlock"))

-- =====================================================================
-- Volume / mic
-- =====================================================================
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true })
hl.bind("SUPER + SHIFT + M",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true })
hl.bind("XF86AudioRaiseVolume",
        hl.dsp.exec_cmd(string.format(
          "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ %d%%+", V.volumeStep)),
        { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",
        hl.dsp.exec_cmd(string.format(
          "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ %d%%-", V.volumeStep)),
        { locked = true, repeating = true })

-- =====================================================================
-- Clipboard / emoji picker
-- =====================================================================
hl.bind("SUPER + SHIFT + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
hl.bind("SUPER + ALT + V",   hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d"))
hl.bind("SUPER + Period",    hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))
hl.bind("CTRL + SHIFT + ALT + V",
        hl.dsp.exec_cmd("sleep 0.5s && ydotool type -d 1 \"$(cliphist list | head -1 | cliphist decode)\""),
        { locked = true })

-- =====================================================================
-- Testing
-- =====================================================================
hl.bind("SUPER + ALT + F12",
        hl.dsp.exec_cmd([[notify-send -u low -i dialog-information-symbolic 'Test notification' "Here's a really long message to test truncation and wrapping\nYou can middle click or flick this notification to dismiss it!" -a 'Shell' -A "Test1=I got it!" -A "Test2=Another action"]]),
        { locked = true })
