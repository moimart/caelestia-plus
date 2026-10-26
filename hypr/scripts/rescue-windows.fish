#!/usr/bin/env fish

set -l current_monitor (hyprctl activeworkspace -j | jq -r '.monitor')
set -l current_ws (hyprctl activeworkspace -j | jq -r '.id')

hyprctl -j clients | jq -r --arg m "$current_monitor" '.[] | select(.monitor != $m) | .address' | while read -l addr
    hyprctl dispatch movetoworkspacesilent $current_ws,address:$addr
end

hyprctl dispatch movetoworkspace $current_ws
