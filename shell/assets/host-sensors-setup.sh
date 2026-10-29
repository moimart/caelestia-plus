#!/bin/sh
# Lets the shell read another machine's temperatures (the host of the VM it
# runs in, say): a key of its own, installed on that machine so that all it can
# do is print the readings from /sys/class/hwmon every few seconds. No shell,
# no forwarding; nothing to install there.
#
#   host-sensors-setup.sh user@host [key]
#
# Asks for that user's password once (or set SSHPASS_FILE to a file holding
# it, with sshpass installed). Run it again any time: it adds the key once.
set -eu

target=${1:?usage: host-sensors-setup.sh user@host [key]}
key=${2:-$HOME/.ssh/caelestia-host-sensors}
here=$(dirname "$(readlink -f "$0")")
loop=$(cat "$here/host-sensors-loop.sh")

[ -f "$key" ] || ssh-keygen -q -t ed25519 -N "" -C "caelestia host sensors" -f "$key"
pub=$(cat "$key.pub")
entry="restrict,command=\"$loop\" $pub"

ssh_=ssh
[ -n "${SSHPASS_FILE:-}" ] && ssh_="sshpass -f $SSHPASS_FILE ssh"
$ssh_ -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no "$target" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && { grep -qF '$(echo "$pub" | cut -d' ' -f2)' ~/.ssh/authorized_keys || echo '$entry' >> ~/.ssh/authorized_keys; }"

echo "done: the shell can read $target's temperatures with $key"
