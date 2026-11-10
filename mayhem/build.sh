#!/usr/bin/env bash
# mayhem/build.sh — builds the sanitized fuzz harnesses (+ standalone reproducers) and the
# normal-flags oracle binaries for ds4. CPU-only path (-DDS4_NO_GPU); no GPU toolchain, no model.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT=/mayhem
FZ="$SRC/mayhem/build-fuzz"
TS="$SRC/mayhem/build-test"
rm -rf "$FZ" "$TS"
mkdir -p "$FZ" "$TS" "$OUT"

COMMON="-D_GNU_SOURCE -DDS4_NO_GPU -std=c99 -Wno-unused-function -I$SRC"
LDLIBS="-lm -pthread"

# run_jobs: wait for every background compile, fail if any failed
run_jobs() {
  local rc=0 p
  for p in "$@"; do wait "$p" || rc=1; done
  return $rc
}

# 1) Sanitized project objects (SanCov via fuzzer-no-link so the library itself is covered).
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1 $COMMON"
CORE_SRCS="ds4_image ds4_distributed ds4_tp ds4_ssd ds4_layer_pack ds4_help ds4_kvstore rax ds4_gpu_args ds4_prompt_prefix"
pids=()
for s in $CORE_SRCS; do
  $CC $FUZZ_CFLAGS -c "$SRC/$s.c" -o "$FZ/$s.o" &
  pids+=($!)
  # bound parallelism
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do sleep 0.2; done
done
$CC $FUZZ_CFLAGS -c "$SRC/mayhem/ds4_fake_engine.c" -o "$FZ/ds4.o" &
pids+=($!)
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -x c++ -o "$FZ/lsan_off.o" &
pids+=($!)
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FZ/standalone_main.o" &
pids+=($!)
run_jobs "${pids[@]}"

LIB_OBJS="$FZ/ds4.o $FZ/ds4_image.o $FZ/ds4_distributed.o $FZ/ds4_tp.o $FZ/ds4_ssd.o $FZ/ds4_layer_pack.o"
SRV_OBJS="$FZ/ds4_help.o $FZ/ds4_kvstore.o $FZ/rax.o $FZ/ds4_gpu_args.o"

# 2) Harnesses: fuzz binary + standalone reproducer each.
build_harness() {
  local name="$1"; shift
  $CC $FUZZ_CFLAGS -c "$SRC/mayhem/$name.c" -o "$FZ/$name.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FZ/$name.o" "$@" "$FZ/lsan_off.o" $LDLIBS -lstdc++ -o "$OUT/$name"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$FZ/standalone_main.o" "$FZ/$name.o" "$@" "$FZ/lsan_off.o" $LDLIBS -lstdc++ -o "$OUT/$name-standalone"
}
pids=()
build_harness fuzz_server_request $SRV_OBJS $LIB_OBJS & pids+=($!)
build_harness fuzz_generated_message $SRV_OBJS $LIB_OBJS & pids+=($!)
build_harness fuzz_image_decode $FZ/ds4_image.o & pids+=($!)
build_harness fuzz_prompt_prefix $FZ/ds4_prompt_prefix.o & pids+=($!)
run_jobs "${pids[@]}"

# 3) Oracle: upstream's model-free tests, normal flags, no sanitizers, no fast-math.
TEST_CFLAGS="-O2 -g $COMMON -fno-finite-math-only $COVERAGE_FLAGS"
pids=()
$CC $TEST_CFLAGS -c "$SRC/ds4.c" -o "$TS/ds4_cpu.o" & pids+=($!)
for s in ds4_image ds4_distributed ds4_tp ds4_ssd ds4_layer_pack ds4_help ds4_kvstore rax ds4_gpu_args ds4_prompt_prefix; do
  $CC $TEST_CFLAGS -c "$SRC/$s.c" -o "$TS/$s.o" &
  pids+=($!)
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do sleep 0.2; done
done
$CC $TEST_CFLAGS -c "$SRC/tests/ds4_test.c" -o "$TS/ds4_test.o" & pids+=($!)
$CC $TEST_CFLAGS -c "$SRC/tests/test_image_decode.c" -o "$TS/test_image_decode.o" & pids+=($!)
$CC $TEST_CFLAGS -c "$SRC/tests/test_prompt_prefix.c" -o "$TS/test_prompt_prefix.o" & pids+=($!)
$CC $TEST_CFLAGS -c "$SRC/mayhem/oracle_image.c" -o "$TS/oracle_image.o" & pids+=($!)
run_jobs "${pids[@]}"

T_LIB="$TS/ds4_cpu.o $TS/ds4_image.o $TS/ds4_distributed.o $TS/ds4_tp.o $TS/ds4_ssd.o $TS/ds4_layer_pack.o"
$CC $COVERAGE_FLAGS -o "$TS/ds4_test" "$TS/ds4_test.o" "$TS/ds4_help.o" "$TS/ds4_kvstore.o" "$TS/rax.o" "$TS/ds4_gpu_args.o" $T_LIB $LDLIBS
$CC $COVERAGE_FLAGS -o "$TS/test_image_decode" "$TS/test_image_decode.o" "$TS/ds4_image.o" $LDLIBS
$CC $COVERAGE_FLAGS -o "$TS/oracle_image" "$TS/oracle_image.o" "$TS/ds4_image.o" $LDLIBS
$CC $COVERAGE_FLAGS -o "$TS/test_prompt_prefix" "$TS/test_prompt_prefix.o" "$TS/ds4_prompt_prefix.o" $LDLIBS

ls -l "$OUT"
