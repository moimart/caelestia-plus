#!/bin/sh
# Lets the shell colour Google Chrome (and Chromium) from the colour scheme,
# live: a policy file (BrowserThemeColor) the shell rewrites on every scheme
# change, which Chrome picks up while running. Run once, with sudo:
#
#   sudo chrome-theme-setup.sh            set it up
#   sudo chrome-theme-setup.sh --undo     take it away
#
# The policy files are root's folders, so the file is made there and given to
# you. With it, Chrome's menu says "Managed by your organization" and its own
# colour picker is locked: the scheme sets the colour.
set -eu

user=${SUDO_USER:-}
[ "$(id -u)" = 0 ] && [ -n "$user" ] || { echo "run it with sudo" >&2; exit 1; }

for d in /etc/opt/chrome/policies/managed /etc/chromium/policies/managed; do
    f="$d/caelestia-theme.json"
    if [ "${1:-}" = "--undo" ]; then
        rm -f "$f"
        continue
    fi
    mkdir -p "$d"
    [ -e "$f" ] || echo '{}' > "$f"
    chown "$user" "$f"
    chmod 644 "$f"
done

if [ "${1:-}" = "--undo" ]; then
    echo "done: Chrome picks its own colour again (restart it to drop the policy)"
else
    echo "done: the shell sets Chrome's colour from now on"
fi
