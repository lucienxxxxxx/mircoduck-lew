# Build and run

## Console

Python 3.11+ and OpenSSH are required; the main console uses Python's standard
library. Optional browser/unit-test dependencies from upstream are not needed
to run the selected tests included here.

```bash
python scripts/prepare-console.py
python console/console.py --dashboard --feetech --open
```

The optional 3D mesh is downloaded from a fixed upstream commit and checked by
SHA256. Its separate non-commercial model license still applies. The console
has no embedded login password. Credentials and the last target belong in the
user's local application data, not the source tree.

### Windows OpenSSH password helper

The original helper source is `firmware/ssh-askpass-windows.c`. With MinGW installed
in WSL, build it into the untracked console runtime path:

```bash
x86_64-w64-mingw32-gcc -Os -s -nostdlib \
  -Wl,--entry=start -Wl,--subsystem,windows \
  firmware/ssh-askpass-windows.c -lkernel32 -o console/ssh-askpass.exe
```

Alternatively copy the matching helper from a trusted existing V167 console.
The helper only supplies the current process's password to OpenSSH; do not
hard-code a password or commit its environment. SSH key login does not need it.

## Robotd / WSL

```bash
sudo apt-get update
sudo apt-get install -y build-essential gcc-aarch64-linux-gnu python3 pkg-config
rustup toolchain install 1.99.1 --profile minimal
rustup target add aarch64-unknown-linux-gnu --toolchain 1.99.1
bash scripts/build-robotd.sh
```

The source workspace is pinned to Rust 1.99.1. The lockfile retains the selected
dependency versions while dropping unrelated workspace crates. GCC cross
linking uses the host's target sysroot, so inspect `dist/robotd-glibc.txt`; do not
assume a newly built binary has the same glibc floor as the previously tested one.
The tested board is Debian 13/glibc 2.41. ONNX Runtime is dynamically loaded on
the board, not linked into robotd at build time.

Selected tests:

```bash
python -m unittest discover -s tests -p 'test_*.py'
node tests/console-compat.mjs
cd firmware
cargo test --locked -p duck-control --lib feetech -- --test-threads=1
```

The project does not bundle trained motion weights or other robots' calibrations.
Policy-dependent upstream tests need separately licensed assets and a matching
host ONNX Runtime. See VALIDATION.md for known historical failures.

`.github/ci.example.yml` contains the same selected checks for GitHub Actions.
It is an inactive example. To enable it, copy it to `.github/workflows/ci.yml`
using a GitHub credential allowed to update workflows. Publishing the source
does not require granting the CLI that extra permission.

## Generate an upgrade ZIP

```bash
python scripts/package-robotd.py --robotd dist/robotd
```

This downloads the fixed upstream control.43 runtime bundle, verifies its
SHA256, replaces robotd, removes measured factory calibration defaults and
generates a commissioning-only upgrade ZIP. For offline operation pass
`--base-archive /path/to/Microduck-Robotd-FT6-R17.tar.gz` with the exact pinned hash.

The generated upgrade inherits the upstream runtime libraries, helper binaries
and trained model packages, including their historical model metadata and
separate licenses. Those files are not part of this source repository and are
not newly authored by mircoduck-lew. Only the installable calibration defaults
are replaced with uncalibrated examples; an existing board's calibration is
preserved. The newly compiled binary still requires its own hardware validation.

The original V167 firmware-upload page accepts its own fixed release hash only;
use the SSH installation path in INSTALL.md for this project's generated ZIP.
