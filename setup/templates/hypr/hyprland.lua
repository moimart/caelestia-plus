-- Your Hyprland config.
--
-- The caelestia-plus defaults load first, with your host profile if you have
-- one (see /usr/share/caelestia-plus/hosts/README.md). Add or change anything
-- below: what you set here wins. pacman never touches this file.
dofile("/usr/share/caelestia-plus/hypr/hyprland.lua")

-- Examples:
-- hl.bind("SUPER + E", hl.dsp.exec_cmd("app2unit -- thunar"))
-- hl.unbind("SUPER + A")
-- hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
-- hl.config({ general = { gaps_out = 20 } })
