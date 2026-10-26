-- Example host profile: replaces the default monitors.lua on this machine.
-- Copy hosts/example to ~/.config/caelestia-plus/hosts/<your name>, edit,
-- and put the name in ~/.config/caelestia-plus/host.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- A laptop panel at 1.5x, and an external monitor to its right
-- hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.5 })
-- hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "1920x0", scale = 1 })
