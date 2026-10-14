-- Shared user variables. Equivalent to the old variables.conf.
-- Other modules pick these up via require("variables").

local C = require("colors")
local M = {}

-- Apps
M.terminal      = "kitty-crt"  -- bin/kitty-crt in the caelestia dotfiles: kitty + wall-clock-synced CRT shader
M.browser       = "google-chrome-stable"
M.editor        = "vim"
M.fileExplorer  = "nautilus"

-- Touchpad
M.touchpadDisableTyping = true
M.touchpadScrollFactor  = 0.3
M.workspaceSwipeFingers = 4
M.gestureFingers        = 3
M.gestureFingersMore    = 4

-- Blur
M.blurEnabled      = true
M.blurSpecialWs    = false
M.blurPopups       = true
M.blurInputMethods = true
M.blurSize         = 10
M.blurPasses       = 2
M.blurXray         = false

-- Shadow
M.shadowEnabled     = true
M.shadowRange       = 20
M.shadowRenderPower = 3
M.shadowColour      = C.rgba("surface", "d4")

-- Gaps
M.workspaceGaps      = 20
M.windowGapsIn       = 10
M.windowGapsOut      = 40
M.singleWindowGapsOut = 20

-- Window styling
M.windowOpacity                = 0.975
M.windowRounding               = 10
M.windowBorderSize             = 3
M.activeWindowBorderColour     = C.rgba("primary",          "e6")
M.inactiveWindowBorderColour   = C.rgba("onSurfaceVariant", "11")

-- Misc
M.volumeStep   = 10  -- percent
M.cursorTheme  = "capitaine-cursors"
M.cursorSize   = 44

return M
