#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER:-aarch64-linux-gnu-gcc}"
export CC_aarch64_unknown_linux_gnu="${CC_aarch64_unknown_linux_gnu:-aarch64-linux-gnu-gcc}"
export CARGO_INCREMENTAL=0
cd "$root/firmware"
cargo build --locked --release -p robotd --target aarch64-unknown-linux-gnu
target=${CARGO_TARGET_DIR:-$root/firmware/target}
mkdir -p "$root/dist"
cp "$target/aarch64-unknown-linux-gnu/release/robotd" "$root/dist/robotd"
echo "Built: $root/dist/robotd"
if command -v aarch64-linux-gnu-readelf >/dev/null; then
    aarch64-linux-gnu-readelf -W --version-info "$root/dist/robotd" > "$root/dist/robotd-glibc.txt"
    echo 'Check dist/robotd-glibc.txt against the target board glibc before installation.'
fi
