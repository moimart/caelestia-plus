#!/bin/bash
# Tests a fresh install of caelestia-plus in a throwaway Arch VM.
#
#   tools/vm/run.sh <dir with *.pkg.tar.zst>
#
# Boots Arch's cloud image (cached in ~/.cache/caelestia-plus-vm), serves it a
# signed pacman repo made from the packages given plus cloud-init data, then
# over SSH: trusts the key, installs caelestia-plus, runs caelestia-plus-setup
# and starts Hyprland on the VM's (virtual, software-rendered) screen. The
# VM's screen is on VNC at 127.0.0.1:5907; it doesn't appear on yours.
# Leaves the VM running; stop it with tools/vm/stop.sh.
#
# Needs: qemu-system-x86, KVM, repo-add (pacman), the signing key in
# ~/.local/share/caelestia-plus/signing.

set -euo pipefail

pkgs=$(realpath "${1:?usage: run.sh <dir with packages>}")
cache=~/.cache/caelestia-plus-vm
work=$cache/run
keys=~/.local/share/caelestia-plus/signing
port=8907
ssh_port=2207
image_url=https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2

mkdir -p "$cache"
[ -f "$cache/base.qcow2" ] || curl -sSfL -o "$cache/base.qcow2" "$image_url"

"$(dirname "$0")/stop.sh" 2>/dev/null || true
rm -rf "$work" && mkdir -p "$work/www/x86_64"
cp "$cache/base.qcow2" "$work/disk.qcow2"

# A signed repo, as CI publishes it
export GNUPGHOME=$keys/gnupg
fpr=$(cat "$keys/fingerprint")
cp "$pkgs"/*.pkg.tar.zst "$work/www/x86_64/"
(
    cd "$work/www/x86_64"
    for p in ./*.pkg.tar.zst; do gpg --batch --yes --detach-sign --local-user "$fpr" "$p"; done
    repo-add -q --sign --key "$fpr" caelestia-plus.db.tar.zst ./*.pkg.tar.zst
)
cp "$keys/caelestia-plus.asc" "$work/www/"

# cloud-init: a user with this SSH key and passwordless sudo
ssh-keygen -q -t ed25519 -N '' -f "$work/ssh_key"
cat > "$work/www/meta-data" <<EOF
instance-id: caelestia-plus-test
local-hostname: cptest
EOF
cat > "$work/www/user-data" <<EOF
#cloud-config
users:
  - name: tester
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat "$work/ssh_key.pub")
growpart:
  mode: auto
EOF

(cd "$work/www" && exec python3 -m http.server "$port" --bind 127.0.0.1 > "$work/http.log" 2>&1) &
echo $! > "$work/http.pid"

qemu-system-x86_64 -enable-kvm -cpu host -smp 8 -m 8G \
    -drive file="$work/disk.qcow2",if=virtio,id=disk0 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:$ssh_port-:22 -device virtio-net,netdev=net0 \
    -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:$port/" \
    -vga virtio -display vnc=127.0.0.1:7 \
    -qmp unix:"$work/qmp.sock",server=on,wait=off \
    -S -daemonize -pidfile "$work/qemu.pid"

# Grow the 2 GiB disk before it boots (cloud-init grows the filesystem)
python3 - "$work/qmp.sock" <<'EOF'
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw")
def cmd(c, **a):
    f.write(json.dumps({"execute": c, "arguments": a} if a else {"execute": c}) + "\n"); f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r:
            return r
f.readline(); cmd("qmp_capabilities")
print("resize:", cmd("block_resize", device="disk0", size=30 * 2**30))
print("start:", cmd("cont"))
EOF

ssh_vm() {
    ssh -q -i "$work/ssh_key" -p "$ssh_port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 tester@127.0.0.1 "$@"
}
echo "Waiting for the VM..."
for _ in $(seq 1 90); do ssh_vm true 2>/dev/null && break; sleep 2; done
ssh_vm true

ssh_vm sudo bash -euo pipefail <<EOF
echo "== Trusting the signing key"
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true
curl -sSf http://10.0.2.2:$port/caelestia-plus.asc | pacman-key --add - >/dev/null
pacman-key --lsign-key $fpr >/dev/null
echo "== Adding the repo"
cat >> /etc/pacman.conf <<'CONF'

[caelestia-plus]
SigLevel = Required
Server = http://10.0.2.2:$port/\$arch
CONF
echo "== Installing caelestia-plus"
pacman -Syu --noconfirm --needed caelestia-plus 2>&1 | tail -5
pacman -Q caelestia-plus caelestia-shell-moimart caelestia-plus-hypr caelestia-plus-config quickshell-git
EOF

echo "== caelestia-plus-setup (as tester)"
ssh_vm caelestia-plus-setup

echo "VM up. SSH: ssh -i $work/ssh_key -p $ssh_port tester@127.0.0.1 ; screen: VNC 127.0.0.1:5907"
