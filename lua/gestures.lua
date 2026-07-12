local V = require("variables")

-- Touchpad gesture tuning (still configured under the global table)
hl.config({
  gestures = {
    workspace_swipe_distance               = 700,
    workspace_swipe_cancel_ratio           = 0.15,
    workspace_swipe_min_speed_to_force     = 5,
    workspace_swipe_direction_lock         = true,
    workspace_swipe_direction_lock_threshold = 10,
    workspace_swipe_create_new             = true,
  },
})

-- Bound gestures (new gestures system, replaces the old `gesture =` lines)
hl.gesture({ fingers = V.workspaceSwipeFingers, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = V.gestureFingers,        direction = "up",         action = "special",   workspace_name = "special" })
hl.gesture({ fingers = V.gestureFingers,        direction = "down",       action = function() hl.exec_cmd("caelestia toggle specialws") end })
hl.gesture({ fingers = V.gestureFingersMore,    direction = "down",       action = function() hl.exec_cmd("systemctl suspend-then-hibernate") end })
