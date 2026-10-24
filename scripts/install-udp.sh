#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $EUID -eq 0 ]] || { echo 'Run with sudo bash scripts/install-udp.sh'; exit 1; }
[[ -x /opt/robot/feetech-ft5-r5/robotd ]] || { echo 'Install the compatible R17 runtime first'; exit 1; }
install -d -m 755 /opt/mircoduck-lew/gateway /opt/mircoduck-lew/console
install -m 644 "$root/gateway/server.py" "$root/gateway/protocol.py" /opt/mircoduck-lew/gateway/
install -m 644 "$root/console/remote_input.py" /opt/mircoduck-lew/console/
install -d -m 700 /etc/mircoduck-lew
if [[ ! -e /etc/mircoduck-lew/udp.key ]]; then
    (umask 077; python3 -c 'import secrets; print(secrets.token_hex(32))' > /etc/mircoduck-lew/udp.key)
fi
chmod 600 /etc/mircoduck-lew/udp.key
install -m 644 "$root/gateway/mircoduck-udp.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mircoduck-udp.service
systemctl restart mircoduck-udp.service
systemctl is-active mircoduck-udp.service
echo 'UDP adapter installed on port 20043. No motion/torque command was sent.'
echo 'Read the pairing key locally with: sudo cat /etc/mircoduck-lew/udp.key'
