#!/usr/bin/env bash
# Runs the app's end-to-end tests (bharatverse_app/integration_test/) on an Android emulator against the local Supabase
# stand-in (tools/local-stack, offset BV_STACK_OFFSET, default 1000) -- never the hosted project, since several tests
# sign up, save and delete. Usage: scripts/e2e.sh [integration_test/<name>_test.dart ...]   (default: all of them)
#
# The emulator and each test build run in their own memory-capped systemd scope (E2E_EMULATOR_MEMORY, default 5G;
# E2E_BUILD_MEMORY, default 4G): uncapped, an emulator beside a Gradle build once ran a 14 GB machine out of memory.
# Starts the emulator (AVD E2E_AVD, default bv_api35) when none is running, and stops it again when done.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OFFSET=${BV_STACK_OFFSET:-1000}
DEVICE=emulator-5554
EMULATOR=${ANDROID_HOME:-$HOME/Android/Sdk}/emulator/emulator

BV_STACK_OFFSET=$OFFSET "$ROOT/tools/local-stack/stack.sh" start >/dev/null
eval "$(BV_STACK_OFFSET=$OFFSET "$ROOT/tools/local-stack/stack.sh" env)"
DEFINES=(--dart-define="SUPABASE_URL=http://10.0.2.2:${SUPABASE_URL##*:}" --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY")

started=false
# Boots the emulator if it is not running -- also mid-run, since its memory cap can stop it after a few installs.
ensure_emulator() {
  if ! adb -s "$DEVICE" get-state >/dev/null 2>&1; then
    systemd-run --user --scope -q -p MemoryMax="${E2E_EMULATOR_MEMORY:-5G}" -p MemorySwapMax=512M \
      "$EMULATOR" -avd "${E2E_AVD:-bv_api35}" -no-window -no-audio -no-boot-anim -no-snapshot-save \
      -gpu swiftshader_indirect >/dev/null 2>&1 &
    started=true
  fi
  adb -s "$DEVICE" wait-for-device
  until [ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
  # 3-button navigation, the tallest navigation bar, where #30's safe-area bug showed.
  adb -s "$DEVICE" shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton
}
trap '$started && adb -s "$DEVICE" emu kill >/dev/null 2>&1 || true' EXIT

cd "$ROOT/bharatverse_app"
tests=("$@")
[ ${#tests[@]} -gt 0 ] || tests=(integration_test/*_test.dart)
passed=() failed=()
run() {
  systemd-run --user --scope -q -p MemoryMax="${E2E_BUILD_MEMORY:-4G}" -p MemorySwapMax=1G \
    flutter test "$1" -d "$DEVICE" "${DEFINES[@]}"
}
for test in "${tests[@]}"; do
  echo "== $test"
  ensure_emulator
  if run "$test"; then
    passed+=("$test")
  elif ! adb -s "$DEVICE" get-state >/dev/null 2>&1; then
    echo "   the emulator stopped during $test (its memory cap?): booting a fresh one and trying again"
    ensure_emulator
    if run "$test"; then passed+=("$test"); else failed+=("$test"); fi
  else
    failed+=("$test")
  fi
done
echo
echo "passed: ${#passed[@]}  failed: ${#failed[@]}"
for test in "${failed[@]}"; do echo "  FAILED $test"; done
[ ${#failed[@]} -eq 0 ]
