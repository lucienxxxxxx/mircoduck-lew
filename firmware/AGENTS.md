# Working in the mircoduck-lew firmware workspace

This is a reduced derivative workspace. See `../docs/BUILD.md` for build and
selected test commands, `../docs/IMU.md` for the supported wire protocols and
`../docs/VALIDATION.md` for known upstream test limitations.

Preserve upstream copyright and license notices. Record source provenance in
`../docs/PROVENANCE.md`; do not claim the entire stack is newly authored here.

IMU ID200 is read-only. Never include it in servo torque, position, centering or
calibration writes. Preserve READY/status/counter validation for Feetech v0.1.
Do not publish measured per-robot calibration, credentials or raw hardware logs.

Changes to IPC contracts must consider all console consumers and API_VERSION.
Describe the install consequence of any breaking change. Keep setup in
commissioning mode with torque off; software checks do not validate movement.

The complete upstream repository has additional design and contribution docs;
those unrelated subsystems are not part of this reduced source distribution.
