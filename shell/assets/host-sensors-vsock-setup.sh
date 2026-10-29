#!/bin/sh
# Run on the HOST (Proxmox, or any Linux with QEMU/KVM and systemd >= 250), as
# root. It serves the host's temperatures to its VMs over vsock, the direct
# host <-> VM channel: no network, no keys, nothing reachable from the LAN.
#
#   host-sensors-vsock-setup.sh [vmid] [port]
#
# - a socket unit listening on vsock port 7770, whose service prints
#   /sys/class/hwmon every 3 s as an unprivileged, sandboxed user;
# - the vhost_vsock module, now and at boot;
# - with a Proxmox VM id: a vsock device on that VM (guest CID = the VM id),
#   kept alongside any QEMU args it already has. The VM then needs a stop and
#   start from Proxmox (a reboot inside it isn't enough).
#
# From the VM, in one go:  ssh root@host sh -s 102 < host-sensors-vsock-setup.sh
# Undo: systemctl disable --now caelestia-sensors.socket, remove the files
# below, and the -device vhost-vsock-pci from the VM's args.
set -eu

vmid=${1:-}
port=${2:-7770}
[ "$(id -u)" = 0 ] || { echo "run it as root, on the host" >&2; exit 1; }

# The readings, as host-sensors-loop.sh prints them
cat > /usr/local/libexec/caelestia-sensors <<'LOOP'
#!/bin/sh
while :; do for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); for t in $h/temp*_input; do [ -r $t ] && echo $n\|$(cat ${t%_input}_label 2>/dev/null)\|$(cat $t); done; done; echo . || exit 0; sleep 3; done
LOOP
chmod 755 /usr/local/libexec/caelestia-sensors

cat > /etc/systemd/system/caelestia-sensors.socket <<UNIT
[Unit]
Description=Caelestia: the host's temperatures for its VMs (vsock)

[Socket]
ListenStream=vsock::$port
Accept=yes
MaxConnections=16

[Install]
WantedBy=sockets.target
UNIT

cat > /etc/systemd/system/caelestia-sensors@.service <<'UNIT'
[Unit]
Description=Caelestia: temperatures for a VM

[Service]
ExecStart=/usr/local/libexec/caelestia-sensors
StandardInput=socket
StandardOutput=socket
StandardError=journal
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX
CapabilityBoundingSet=
SystemCallFilter=@system-service
UNIT

modprobe vhost_vsock
echo vhost_vsock > /etc/modules-load.d/caelestia-vsock.conf
systemctl daemon-reload
systemctl enable --now caelestia-sensors.socket
echo "serving temperatures on vsock port $port"

if [ -n "$vmid" ]; then
    command -v qm > /dev/null || { echo "no qm here: add '-device vhost-vsock-pci,guest-cid=<n>' to the VM yourself" >&2; exit 1; }
    args=$(qm config "$vmid" | sed -n 's/^args: //p')
    case "$args" in
        *vhost-vsock-pci*) echo "VM $vmid already has a vsock device: $args" ;;
        *)
            qm set "$vmid" --args "${args:+$args }-device vhost-vsock-pci,guest-cid=$vmid"
            echo "VM $vmid has a vsock device now (CID $vmid): stop and start it from Proxmox"
            ;;
    esac
else
    echo "now give the VM a vsock device: qm set <vmid> --args '-device vhost-vsock-pci,guest-cid=<vmid>'"
fi
