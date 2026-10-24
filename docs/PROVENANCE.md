# Source provenance

The project is a derivative distribution, not a claim of original authorship of
the complete Microduck stack.

| Component | Source |
| --- | --- |
| Organization baseline | https://github.com/kissqy/Microduck-kissqy/tree/f02e875e73b88bf8ec7d5bbb34d0b461ac83b010 |
| Original runtime baseline | https://github.com/pollen-robotics/microduck/tree/1fa84386f07884e27866411bc1ba166977bced95 |
| Console | R17 V167 source plus native Feetech family compatibility changes |
| Local service | control.43 plus Feetech v0.1 decoder, unit quaternion handling and commissioning snapshot fix |
| Android app | User's earlier independently developed Flutter phone console, adapted to the deployed Microduck IPC through authenticated UDP |
| UDP gateway | New Python standard-library adapter; input mapping reused from console/remote_input.py under its existing license |
| v0.1 protocol reference | https://gitee.com/duinopeak/libs/raw/master/libs/microduck/firmware/imu_to_dxl/imu_to_feetech_v0.1.zip |

The v0.1 firmware reference is used to understand the wire interface. Its STM32
source/binary is not bundled or relicensed by this repository.

The Rust workspace was reduced to robotd and the crates needed to build or test
it. Unrelated camera, Bluetooth and full updater deployment packaging were not
carried into this source layout. The updater crate is retained for robotd tests.
No dependency version upgrade is intended; Cargo.lock is pruned for this workspace.

Private robot calibration values, machine addresses, password stores, console
logs, training exports and hardware raw telemetry are not part of this snapshot.

Public validation summary is in VALIDATION.md. Original per-component licenses
and copyright headers are retained. Console-derived code remains covered by
the upstream Personal Non-Commercial terms.
