#!/bin/sh
# Types text (an emoji) into the focused window, for the emoji picker.
#   type-emoji.sh wtype <text>  # through a virtual keyboard (terminals)
#   type-emoji.sh paste <text>  # through the clipboard and Ctrl+V
# Chromium-based apps (Chrome, Discord, VS Code, ...) garble characters past
# U+FFFF from a virtual keyboard, and that's most emoji, so everything but
# terminals pastes. The clipboard is put back afterwards.

mode=$1
text=$2
command -v wtype > /dev/null || exit 127

if [ "$mode" = wtype ]; then
    exec wtype -- "$text"
fi

# Keep one of the clipboard's types, preferring plain text, then an image
types=$(wl-paste -l 2> /dev/null)
type=$(printf '%s\n' "$types" | grep -m1 -x 'text/plain;charset=utf-8' ||
    printf '%s\n' "$types" | grep -m1 -x 'text/plain' ||
    printf '%s\n' "$types" | grep -m1 '^image/' ||
    printf '%s\n' "$types" | head -n1)
saved=$(mktemp)
[ -n "$type" ] && wl-paste -t "$type" > "$saved" 2> /dev/null

printf '%s' "$text" | wl-copy
sleep 0.05
wtype -M ctrl -k v -m ctrl
rc=$?

# Give the app time to read the clipboard before it changes back
sleep 0.5
if [ -n "$type" ]; then
    wl-copy -t "$type" < "$saved"
else
    wl-copy --clear
fi
rm -f "$saved"
exit $rc
