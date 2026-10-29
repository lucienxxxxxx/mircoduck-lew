#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $EUID -eq 0 ]] || { echo 'Run with sudo bash scripts/install-udp.sh'; exit 1; }
[[ -x /opt/robot/feetech-ft5-r5/robotd ]] || { echo 'Install the compatible R17 runtime first'; exit 1; }
install -d -m 755 /opt/mircoduck-lew/gateway /opt/mircoduck-lew/console
install -m 644 "$root/gateway/server.py" "$root/gateway/protocol.py" /opt/mircoduck-lew/gateway/
install -m 644 "$root/console/remote_input.py" /opt/mircoduck-lew/console/
install -d -m 755 /opt/mircoduck-lew/cli
install -m 755 "$root/cli/duckctl.py" /opt/mircoduck-lew/cli/
if [[ -e /usr/local/bin/duckctl && ! -L /usr/local/bin/duckctl ]]; then
    echo '/usr/local/bin/duckctl already exists; refusing to overwrite it'; exit 1
fi
if [[ -L /usr/local/bin/duckctl && $(readlink /usr/local/bin/duckctl) != /opt/mircoduck-lew/cli/duckctl.py ]]; then
    echo '/usr/local/bin/duckctl points to another tool; refusing to overwrite it'; exit 1
fi
ln -sfn /opt/mircoduck-lew/cli/duckctl.py /usr/local/bin/duckctl
install -d -m 755 /opt/mircoduck-lew/docs
install -m 644 "$root/docs/CLI.md" "$root/docs/DUCKPILOT.md" "$root/docs/UDP.md" /opt/mircoduck-lew/docs/
install -m 644 "$root/gateway/mircoduck-udp.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mircoduck-udp.service
systemctl restart mircoduck-udp.service
systemctl is-active mircoduck-udp.service
echo 'UDP adapter installed on port 20043. No motion/torque command was sent.'
echo 'DuckPilot 0.4: connect by address and port; no pairing key is used.'
echo 'Board CLI installed: duckctl --help; duckctl wifi --help'
