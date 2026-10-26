#!/bin/bash
# Stops the test VM started by tools/vm/run.sh, and its file server.
work=~/.cache/caelestia-plus-vm/run
for f in qemu.pid http.pid; do
    [ -f "$work/$f" ] && kill "$(cat "$work/$f")" 2>/dev/null
    rm -f "$work/$f"
done
true
