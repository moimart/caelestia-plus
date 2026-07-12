-- hyprexpo plugin (colonelpanic8/hyprexpo, installed via hyprpm).
-- The .so is loaded synchronously in lua/plugins.lua so the config keys
-- below are already registered by the time hl.config runs.
--
-- Bail out silently if hyprexpo is disabled in hyprpm — `sudo hyprpm
-- disable hyprexpo` then a reload skips the plugin load, the config
-- block, and the keybinds. (Known to crash 0.55.2 during mirror
-- surface teardown — keep it off when using the receiver mirror.)
if not require("plugins").enabled("hyprexpo", "hyprexpo") then return end

hl.config({
  plugin = {
    hyprexpo = {
      columns                   = 3,
      gap_size                  = 5,
      gap_size_outer            = 0,
      bg_col                    = "rgb(111111)",
      workspace_method          = "center current",
      skip_empty                = false,
      max_workspace             = 0,
      show_workspace_numbers    = false,
      workspace_number_color    = "rgb(ffffff)",
      -- window_icon_{enable,position,size} are upstream-only — not in the
      -- colonelpanic8/hyprexpo fork we have installed.
      label_enable              = false,
      label_text_mode           = "id",
      label_token_map           = "",
      selection_label_enable    = false,
      selection_label_token_map = "a,s,d,f,g,q,w,e,r,t,z,x,c,v,b",
      gesture_distance          = 300,
      cancel_key                = "escape",
    },
  },
})

-- Open/close the overview via the plugin's Lua API directly (avoids the
-- broken layoutmsg argv path in 0.55).
hl.bind("CTRL + up",   function() hl.plugin.hyprexpo.expo("on")  end)
hl.bind("CTRL + down", function() hl.plugin.hyprexpo.expo("off") end)
