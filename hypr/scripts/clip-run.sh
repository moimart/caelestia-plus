#!/usr/bin/env bash
# Runs the text on the clipboard as a shell command, in this terminal, and
# exits with it (so the terminal closes when it's done). SUPER + both Shifts
# + Return opens a terminal running this.
#
# It shows the command before running it: what you copied from a web page
# isn't always what the page showed you.

cmd=$(wl-paste --no-newline --type text 2> /dev/null)
if [ -z "${cmd//[[:space:]]/}" ]; then
    notify-send -a "Clipboard command" -i utilities-terminal "Nothing to run" "The clipboard has no text."
    exit 1
fi

printf '\e[2m$\e[0m %s\n' "$cmd"
exec bash -c "$cmd"
