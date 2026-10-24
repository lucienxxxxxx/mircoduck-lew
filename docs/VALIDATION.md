# Validation record

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
