# Validation record

## AP auto-connect 0.4.1 (2026-10-29)

- Detects the current Android Wi-Fi IPv4 gateway, verifies a stateless DuckPilot UDP discovery response, and connects telemetry/video without typed IP or motor intent.
- Android process routing selects Wi-Fi even when cellular remains the default network; no SSID/location permission.
- 34 Linux Python tests and 18 Flutter tests pass, analyze is clean, ARM64 APK builds. Tests include UDP discovery, custom subnets, incorrect responses, busy sessions, explicit disconnect, stale discovery after network changes and background cancellation.
- No native Android handset/AP acceptance test. The board is charging/unavailable; new discovery handler has not been deployed to the physical board. Prior 0.4.0 hardware tests remain historical evidence only.

## DuckPilot / duckctl 0.4.0 (2026-10-29)

- Keyless UDP v2 replaces signed v1; matching App and gateway required.
- 32 Linux Python tests and 10 Flutter tests pass; analyze reports no issues.
- ARM64 release APK, package version 0.4.0+4 and signature verified.
- Real Flutter client connects without a key, reads fresh IMU/all 15 joints and reconnects. No motor action is requested.
- Installed on the user-confirmed reflashed board. Existing robotd build `1fa8438-feetech-ft6-control.43-md12.2` remains unchanged; its active IMU protocol is microduck-v1.2. Original torque ON and policy OFF are retained.
- duckctl help/version, profiles, real IMU gyro/quaternion/gravity and service status verified on board. UDP and mediad are active.
- NetworkManager accepts generated STA/AP profiles with autoconnect disabled; test profiles are then deleted. Active Wi-Fi UUID remains unchanged.
- No actual STA/AP radio switch, Android handset install or physical movement/audio acceptance was performed. Independent systemd switch/rollback workers and confirmation logic have unit coverage; a real network-switch acceptance remains outstanding.
- Original private flash image has not been rebuilt for 0.4; install the current UDP/CLI update after restoring it.

## DuckPilot / camera 0.3.0 (2026-10-24)

- Fullscreen camera background, floating controls, a single forward/turn joystick,
  three speed gears, visible short/held calls, and a compact horizontal action panel.
- Twenty-four Python checks and nine Flutter tests passed. New coverage includes
  no sideways velocity from the left stick, held-call release, early native video
  ready events, rotation without reconnecting, 640×320 layout, and startup transition.
- `flutter analyze` reports no issues; Android ARM64 release builds successfully.
- The exact bundled video client/HTML was exercised against the actual board in
  a browser: 1280×720, 30 FPS, approximately 3.4 Mb/s and zero packet loss in the
  observed window. DOM/video checks confirmed 90° display rotation. The scene
  itself was very dark. This does not establish camera exposure or focus quality.
- The real Flutter client exercised power preparation: actual motion mode, fresh
  IMU and all 15 joints, torque OFF, no HOME and no enabled policy. It did not
  request standing, sound, skill playback or nonzero movement on the hardware.
- No Android handset was attached to ADB. Native WebView behavior on the user's
  actual phone and physical movement/audio still require acceptance there.
- The user selected the controller wordmark image for the named DuckPilot startup
  page and approved the separate duck-head/controller launcher artwork.
- The installed robotd binary remains unchanged; updated UDP operations use the
  existing IPC. `sit_toggle` is the actual daemon skill name, correcting the
  previous generic sitstand spelling while retaining a compatibility alias.

## Phone / UDP 0.2.0 (2026-10-24)

- Flutter 3.47.7, Dart 3.13.5, JDK17, Android build tools 36.0.0; ARM64 APK,
  minimum Android API24 / Android 7.0, target API36. Personal test signing,
  APK v2 signature verified; not a Play Store release.
- `flutter analyze`: no issues. Six automated App tests pass, covering phone
  layout, two pointers, protocol vectors and real local UDP sockets. The
  optional live-board test is skipped unless explicit host/key-file variables
  are provided; it was separately run and passed against the installed board.
- Twenty Python checks pass on Linux, including console compatibility,
  HMAC tamper rejection, replay/endpoint rejection, kernel ownership exclusion,
  ticket rotation/absolute expiry, neutral input expiry and native telemetry.
- Real LAN UDP validation: wrong key gets no response; correct key receives
  fresh IMU data and all 15 joints. The IMU counter advances. Neutral claim,
  300 ms input expiry despite heartbeats, and delayed-frame rejection pass.
  The observed largest datagram was under 700 bytes.
- The Flutter client itself authenticated to the real board and read fresh
  15-joint / IMU telemetry, while remaining unclaimed.
- The installed robotd binary is unchanged. The console helper was updated
  and reconnected to share the same ownership lock as the phone adapter.
- Final extended observation recorded three communication failures in roughly
  66,000 cycles; the latest timeout named servo IDs 11 and 14. Current status
  recovered to ready at approximately 50 Hz with valid IMU data. This is not
  a claim of an error-free bus; no cause or gait reliability was established.
- No actual Android phone installation, gait/standing acceptance, or physical
  restore-image flashing/boot acceptance was performed. Hardware validation
  stayed in commissioning with torque OFF. Service mode changes must be
  confirmed and checked against actual status; accepting a request does not
  prove its completion.

The personal restore image is a separate private deliverable. It preserves
the owner's calibration and credentials, and is not part of the public source.

## Existing deployment evidence (2026-10-24)

- Rust 1.99.1; ARM64 Linux release build in WSL Ubuntu.
- Resulting binary requires glibc up to 2.39; tested board userland has glibc 2.41.
- ARM64 ELF structural validation and QEMU `--help` pass.
- Feetech protocol tests: 40 passed, zero failed, including two v0.1 capture/PTY tests.
- Robotd commissioning tests after report fix: five passed, zero failed.
- Broader robotd isolated tests: eleven passed, nine failed. An unmodified
  control.43 snapshot gives identical per-case outcomes. Several old tests
  reference a removed `stand_test` profile; another stability test times out.
  No claim is made that the entire upstream suite passes.
- Hardware commissioning observation: ~50 Hz; 1,994 consecutive successful cycles
  without communication failure in that window; fifteen servos and IMU200 valid.
- Startup remains torque OFF; no gait/standing acceptance was performed.

These are bounded observations, not a guarantee of future bus reliability,
sensor-age precision, mechanical safety, or gait stability. Raw personal logs
and per-robot calibrations are intentionally not published.

## Re-run the repository checks

The reorganized source snapshot was checked separately on 2026-10-24:

- Console compatibility: six Python and six JavaScript cases passed.
- The source console started independently on localhost; its HTML and JSON
  configuration/snapshot endpoints returned successfully with version 0.1.0.
- Python source compilation and shell syntax checks passed.
- All 40 Feetech tests passed from the reduced workspace, including both v0.1
  capture/PTY tests. The alternate-gain bus test reads contract parameters
  directly so it no longer needs a trained policy binary; its gain assertions
  and child-process isolation are preserved.
- The reduced workspace built robotd for aarch64-unknown-linux-gnu with the
  pruned lockfile; QEMU `--help` and `deployment-info` passed. Its SHA256 is
  identical to the previously verified board binary:
  `d4225ede745539fbdf064743644b8d3a3dcc0f84a5b1d8edd47bc279949a08db`.
  No additional installation was performed during source organization.
- No added dependency name/version pairs were found against the original lockfile.
- Credential, local machine path and actual calibration scans found no matches
  in the selected source tree.
- Upgrade ZIP generation passed with the pinned upstream base archive, including
  ELF validation, file hashes and neutral calibration default checks. This
  generated artifact has not been installed on the board.

```bash
python -m unittest discover -s tests -p 'test_*.py'
node tests/console-compat.mjs
cd firmware
cargo test --locked -p duck-control --lib feetech -- --test-threads=1
```

Optional geometry, trained policy binaries and host ONNX Runtime are not needed
for these selected checks. Historical policy-dependent tests require their own
licensed weights and the matching ONNX Runtime 1.28.0; test robotd cases in
separate processes because deployment HOME uses a process-global OnceLock.
