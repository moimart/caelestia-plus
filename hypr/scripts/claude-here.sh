#!/usr/bin/env bash
# Asks for a folder, then runs Claude Code there. Enter alone, or a folder
# that doesn't exist, runs it in your home. SUPER + SHIFT + J opens a floating
# terminal running this.
#
# Tab completes folders (relative ones are from your home), and Up goes back
# through the folders you picked before.

history_file=${XDG_STATE_HOME:-$HOME/.local/state}/caelestia-plus/claude-folders
mkdir -p "${history_file%/*}"

cd "$HOME" || exit 1
HISTFILE=$history_file
HISTSIZE=200
history -r
set -o emacs
bind 'set completion-ignore-case on' 2> /dev/null
bind 'set mark-directories on' 2> /dev/null

printf '\e[1mClaude Code\e[0m \e[2min which folder? (Enter for ~)\e[0m\n'
IFS= read -rep $'\e[36m›\e[0m ' dir

# ~ and ~/… as the shell would
case $dir in
    "~") dir=$HOME ;;
    "~/"*) dir=$HOME/${dir#"~/"} ;;
esac

if [ -n "$dir" ] && [ -d "$dir" ]; then
    cd "$dir" || cd "$HOME"
    # Remembered once, newest last (Up finds it first)
    history -s "$PWD"
    grep -vxF -- "$PWD" "$history_file" 2> /dev/null > "$history_file.tmp"
    printf '%s\n' "$PWD" >> "$history_file.tmp"
    tail -n "$HISTSIZE" "$history_file.tmp" > "$history_file"
    rm -f "$history_file.tmp"
elif [ -n "$dir" ]; then
    printf '\e[33m%s isn'"'"'t a folder: in ~ instead\e[0m\n' "$dir"
fi

printf '\e[2m%s\e[0m\n\n' "${PWD/#$HOME/\~}"
exec claude
