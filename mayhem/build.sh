#!/usr/bin/env bash
#
# mayhem/build.sh — build trust-dns fuzz target(s) as sanitized libFuzzer binaries.
# Runs inside the commit image as `mayhem` in /mayhem.
# Rust toolchain at $CARGO_HOME=/opt/toolchains/rust/cargo (pinned by Dockerfile ENV).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): PATCH tier re-runs this OFFLINE.
# The first online build populates the cargo registry under $CARGO_HOME.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Honor SANITIZER_FLAGS knob: non-empty → ASan; empty → un-sanitized build.
RUST_SAN=""
if [ -n "${SANITIZER_FLAGS:-}" ]; then
  RUST_SAN="-Zsanitizer=address"
fi

# DWARF < 4 gate (SPEC §6.2 item 10):
#   1. Pin Rust DWARF version to 3
#   2. Pin cc-compiled libfuzzer-sys shim to dwarf-3
#   3. Strip debug info from the bundled ASan runtime archive (DWARF-5, from clang)
export RUSTFLAGS="${RUSTFLAGS:-} ${RUST_DEBUG_FLAGS:-} --cfg fuzzing ${RUST_SAN} -Zdwarf-version=3 -Cdebuginfo=1 -Cforce-frame-pointers"
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# Strip DWARF-5 from bundled ASan runtime archive (idempotent).
if [ -n "${RUST_SAN}" ]; then
  RT_LIB_DIR="$(rustc --print sysroot)/lib/rustlib/x86_64-unknown-linux-gnu/lib"
  for asan in "$RT_LIB_DIR"/librustc-*_rt.asan.a; do
    [ -f "$asan" ] || continue
    if [ -w "$asan" ]; then
      objcopy --strip-debug "$asan" "$asan.stripped" && mv "$asan.stripped" "$asan"
      echo "stripped debug info from bundled ASan runtime: $asan"
    fi
  done
fi

# Use mayhem/fuzz/ (additive, avoids upstream fuzz/ zerocopy 0.8 incompatibility).
FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover fuzz targets from mayhem/fuzz/fuzz_targets/.
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (nightly-2025-05-14, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the test suite for hickory-proto (no-run: compile only, executed by test.sh).
echo "--- building test suite for hickory-proto ---"
RUSTFLAGS="" cargo +stable test --no-run --manifest-path "$SRC/Cargo.toml" -p hickory-proto \
  --no-default-features 2>&1 | tail -5
echo "build.sh complete"
