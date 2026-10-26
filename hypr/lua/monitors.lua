-- Monitor configuration: any monitor at its preferred mode and scale.
-- A host profile replaces this file with its own monitors.lua (see
-- hosts/behemoth/hypr/monitors.lua); hyprland.lua searches the profile first.
-- Monitor-specific rules can also go in ~/.config/hypr/hyprland.lua.

hl.monitor({
  output   = "",
  mode     = "preferred",
  position = "auto",
  scale    = "auto",
})
