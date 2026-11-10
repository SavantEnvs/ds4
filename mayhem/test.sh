#!/usr/bin/env bash
# mayhem/test.sh — runs ds4's own model-free test programs (built by build.sh) and maps their
# success markers to CTRF. A neutered binary prints no marker and is counted as failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"
TS="$SRC/mayhem/build-test"

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

passed=0; failed=0
# check <name> <expected stdout/stderr line> <cmd...>: passes iff exit 0 AND the marker line is printed.
check() {
  local name="$1" marker="$2"; shift 2
  local out
  if out=$(timeout 600 "$@" 2>&1) && printf '%s\n' "$out" | grep -qxF "$marker"; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name"; printf '%s\n' "$out" | tail -20; failed=$((failed+1))
  fi
}

for b in ds4_test test_image_decode test_prompt_prefix oracle_image; do
  [ -x "$TS/$b" ] || { echo "missing $TS/$b (build.sh bug)" >&2; emit_ctrf ds4 0 1 0; exit 1; }
done

check server_unit_tests "ds4 tests: ok" "$TS/ds4_test" --server

# known-answer: dimensions + SHA-256 fingerprint of decoded pixels (bit-exact vs libjpeg-turbo djpeg)
check_value() {
  local name="$1" expect="$2" file="$3" got
  got=$("$TS/oracle_image" "$file" 2>&1)
  if [ "$got" = "$expect" ]; then echo "PASS $name"; passed=$((passed+1))
  else echo "FAIL $name: got '$got' expected '$expect'"; failed=$((failed+1)); fi
}
check_value jpeg_prog_gray "24x16 63aae8863e829170c5abc746c90a5ff3ad60e9c4312e2ffa5eefbfeaacd26bfc" tests/vision-fixtures/jpeg/prog_ac_refine_zrl_gray.jpg
check_value jpeg_prog_420 "64x48 d3be4d7078c41b6589942c82bd622ca8a3ed40adddee11cccf1de9ca1a096ba4" tests/vision-fixtures/jpeg/prog_ac_refine_zrl_420.jpg
if timeout 120 "$TS/test_image_decode"; then echo "PASS image_decode_suite"; passed=$((passed+1))
else echo "FAIL image_decode_suite"; failed=$((failed+1)); fi
check prompt_prefix_tests "prompt prefix tests passed" "$TS/test_prompt_prefix"

emit_ctrf ds4 "$passed" "$failed" 0
