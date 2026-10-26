local V = require("variables")

hl.config({
  decoration = {
    rounding = V.windowRounding,

    blur = {
      enabled           = V.blurEnabled,
      xray              = V.blurXray,
      special           = V.blurSpecialWs,
      ignore_opacity    = true,  -- allow opacity blurring
      new_optimizations = true,
      popups            = V.blurPopups,
      input_methods     = V.blurInputMethods,
      size              = V.blurSize,
      passes            = V.blurPasses,
    },

    shadow = {
      enabled      = V.shadowEnabled,
      range        = V.shadowRange,
      render_power = V.shadowRenderPower,
      color        = V.shadowColour,
    },
  },
})

-- Plugin: hyprbars. As with dynamic-cursors, hl.config rejects the keys when
-- the plugin isn't loaded. Re-enable through `hyprctl keyword plugin:...`
-- once you've confirmed the plugin is registered.
--
-- hl.exec_cmd("hyprctl keyword plugin:hyprbars:bar_height 40")
-- hl.exec_cmd("hyprctl keyword plugin:hyprbars:hyprbars-button 'rgb(ff0000), 12, , hyprctl dispatch killactive'")
-- hl.exec_cmd("hyprctl keyword plugin:hyprbars:hyprbars-button 'rgb(ffff00), 12, , hyprctl dispatch fullscreen 1'")
-- hl.exec_cmd("hyprctl keyword plugin:hyprbars:on_double_click 'hyprctl dispatch fullscreen 1'")
