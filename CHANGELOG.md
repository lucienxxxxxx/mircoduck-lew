# Changes

## 0.1.0 — 2026-10-24

- Consolidate the currently deployed R17 V167 console and control.43-derived robotd source.
- Add Feetech v0.1 IMU identity, 20-byte layout and readiness handling; retain FT6.
- Keep a 20 ms combined servo/IMU transaction budget and three-repeat counter rejection.
- Support valid unit quaternion readings after explicit protocol readiness.
- Publish the live commissioning snapshot instead of retaining a stale startup placeholder.
- Recognize native Feetech service build names in console Python and JavaScript.
- Retain motion interlocks and leave commissioning/torque-off as installation defaults.
- Separate private robot calibration and credentials from redistributable source.
- Preserve upstream attribution and mixed license terms.
