#!/usr/bin/env bash
#
# mayhem/test.sh — run hickory-proto unit tests as the functional oracle.
#
# BEHAVIORAL ORACLE: runs `cargo test -p hickory-proto --no-default-features` which
# executes assertion-based unit tests including DNS message encode/decode round-trips.
# A neutered binary (exit 0 stub) does NOT satisfy Rust #[test] assertions — those
# tests FAIL, producing a non-zero cargo exit code, causing this script to fail.
#
# CTRF output required by the grader.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

echo "=== Running hickory-proto test suite ==="

# Run cargo test and capture output; set -e is NOT active so we can capture exit code.
RUSTFLAGS="" CARGO_BUILD_JOBS="$MAYHEM_JOBS" \
  cargo +stable test --manifest-path "$SRC/Cargo.toml" -p hickory-proto \
  --no-default-features 2>&1 | tee /tmp/trust_dns_test_out.txt
TEST_RC=${PIPESTATUS[0]}

# Parse "test result: ok. N passed; M failed; ..." lines from cargo test output.
# Cargo prints one such line per test binary.
PASSED=0
FAILED=0
SKIPPED=0
while IFS= read -r line; do
  if [[ "$line" =~ ^test\ result:.*[[:space:]]([0-9]+)\ passed ]]; then
    PASSED=$(( PASSED + ${BASH_REMATCH[1]} ))
  fi
  if [[ "$line" =~ [[:space:]]([0-9]+)\ failed ]]; then
    FAILED=$(( FAILED + ${BASH_REMATCH[1]} ))
  fi
  if [[ "$line" =~ [[:space:]]([0-9]+)\ ignored ]]; then
    SKIPPED=$(( SKIPPED + ${BASH_REMATCH[1]} ))
  fi
done < /tmp/trust_dns_test_out.txt

# If cargo itself failed (e.g. build error, linker error from a neutered binary)
# count it as a test failure.
if [ "$TEST_RC" -ne 0 ] && [ "$FAILED" -eq 0 ]; then
  FAILED=1
fi

echo "Parsed: passed=$PASSED failed=$FAILED skipped=$SKIPPED"
emit_ctrf "cargo-test/hickory-proto" "$PASSED" "$FAILED" "$SKIPPED"
