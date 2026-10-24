#!/bin/bash
# Runs from the generated bundle, not directly from the source checkout.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$root"
[[ $EUID -eq 0 ]] || { echo 'Use sudo bash upgrade-lew.sh'; exit 1; }
exec 9>/run/mircoduck-lew-upgrade.lock
flock -n 9 || { echo 'Another mircoduck-lew upgrade is running'; exit 1; }
sha256sum -c SHA256SUMS
python3 elf_integrity.py "$root"
chmod 755 robotd robotctl padd sounds mediad gamepad-r7/gamesir-xboxd
./robotd --help >/dev/null
# This is an upgrade of an existing R17 installation, not a board provisioner.
[[ -x /opt/robot/feetech-ft5-r5/robotd ]] || { echo 'Existing R17 service not found'; exit 1; }
[[ -f /etc/robot/feetech-ft5/robotd.toml ]] || { echo 'Existing service configuration not found'; exit 1; }
backup_dir=/var/backups/mircoduck-lew
mkdir -p "$backup_dir"
backup="$backup_dir/pre-upgrade-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
items=(opt/robot/feetech-ft5-r5 etc/robot/feetech-ft5)
[[ ! -d /etc/systemd/system/robotd.service.d ]] || items+=(etc/systemd/system/robotd.service.d)
tar -C / -czf "$backup" "${items[@]}"
echo "Backup: $backup"
bash "$root/service.sh" upgrade
echo 'Installed mircoduck-lew service; commissioning mode, no automatic movement.'
echo "Backup retained: $backup"
