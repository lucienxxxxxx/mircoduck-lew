# Upgrade an existing R17 board

This workflow upgrades an existing compatible Radxa/R17 installation. It does
not provision a blank operating system or flash the HAT or IMU. The generated
upgrade inherits the pinned upstream bundle's trained policies and runtime
components under their original licenses. Keep the mechanism supported, and
do not enable motion during setup.

1. Build an ARM64 `robotd` and generate the ZIP using BUILD.md.
2. Check the output SHA256 and upload it to your own board using SSH/SCP.
3. On the board, unpack the ZIP and run:

```bash
unzip mircoduck-lew-0.1.0-robotd.zip
sudo bash mircoduck-lew-upgrade/upgrade-lew.sh
/opt/robot/feetech-ft5-r5/robotd bus-status
```

The upgrade checks file hashes, ELF structure and whether the binary can run
before service replacement. It backs up the installed R17 directory, service
configuration, calibration and robotd systemd overrides under
`/var/backups/mircoduck-lew/`, then starts commissioning mode. It preserves valid
local settings and uses uncalibrated placeholders where no actual calibration
exists. Never enable motion from those placeholders.

Expected service identity: `1fa8438-feetech-control.43-ft01.1`. Verify mode
commissioning, phase ready, torque off, fresh IMU and all expected servo feedback.
If there are no replies, check bus power, ground, UART routing and the HAT's
direction-control requirements. Do not scan an occupied serial port.

The source console has no bundled firmware artifact. Its inherited V167 upload
gate is not used for this ZIP. Start the console and connect to the upgraded
service; service-family compatibility is handled by both Python and JavaScript.

## Restore a backup

Use the actual backup name printed by the installer:

```bash
sudo systemctl stop robotd
sudo tar -xzf /var/backups/mircoduck-lew/ACTUAL-BACKUP.tar.gz -C /
sudo systemctl daemon-reload
sudo systemctl start robotd
```

Restoring the systemd backup restores its previous mode too. Confirm the actual
mode before any motor command. A completed software update is not a mechanical,
installation-axis or motion validation.
