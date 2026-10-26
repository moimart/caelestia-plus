-- Top-level animations toggle is set via hl.config; per-leaf animations and
-- bezier curves are declared with hl.curve / hl.animation.

hl.config({
  animations = {
    enabled = true,
  },
})

-- Curves (bezier control points {{X0,Y0},{X1,Y1}})
hl.curve("specialWorkSwitch", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1,  1   } } })
hl.curve("emphasizedAccel",   { type = "bezier", points = { { 0.3,  0.0 }, { 0.8,  0.15 } } })
hl.curve("emphasizedDecel",   { type = "bezier", points = { { 0.05, 0.7 }, { 0.1,  1   } } })
hl.curve("standard",          { type = "bezier", points = { { 0.2,  0.0 }, { 0.0,  1   } } })
hl.curve("easeOut",           { type = "bezier", points = { { 0.16, 1.0 }, { 0.3,  1   } } })

-- Layers
hl.animation({ leaf = "layersIn",   enabled = true, speed = 5, bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "layersOut",  enabled = true, speed = 4, bezier = "emphasizedAccel", style = "slide" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 5, bezier = "standard" })

-- Windows
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5, bezier = "emphasizedDecel" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 3, bezier = "emphasizedAccel" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "standard" })

-- Workspaces
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5, bezier = "standard", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 4, bezier = "specialWorkSwitch", style = "slidefadevert 15%" })

-- Misc
hl.animation({ leaf = "fade",    enabled = true, speed = 6, bezier = "standard" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 6, bezier = "standard" })
hl.animation({ leaf = "border",  enabled = true, speed = 6, bezier = "standard" })

-- The original `animation = zoomFactor, 1, 6, easeOut` (cursor zoom)
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 6, bezier = "easeOut" })
