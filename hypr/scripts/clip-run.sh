#!/usr/bin/env bash
# Runs the text on the clipboard as a shell command, in this terminal, and
# exits with it (so the terminal closes when it's done). SUPER + both Shifts
# + Return opens a terminal running this.
#
# It shows the command and waits for Enter before running it: what you copied
# from a web page isn't always what the page showed you.

cmd=$(wl-paste --no-newline --type text 2> /dev/null)
if [ -z "${cmd//[[:space:]]/}" ]; then
    notify-send -a "Clipboard command" -i utilities-terminal "Nothing to run" "The clipboard has no text."
    exit 1
fi

printf '\e[2m$\e[0m %s\n\n' "$cmd"

# Nothing runs until you say so: Enter runs it, any other key cancels
printf '\e[2mEnter to run it, any other key to cancel\e[0m'
IFS= read -rsn1 key
printf '\r\e[K'
[ -z "$key" ] || exit 0

exec bash -c "$cmd"
