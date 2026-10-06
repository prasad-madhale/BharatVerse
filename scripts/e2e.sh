#!/usr/bin/env bash
# Runs the app's end-to-end tests (bharatverse_app/integration_test/) on an Android emulator against the local Supabase
# stand-in (tools/local-stack, offset BV_STACK_OFFSET, default 1000) -- never the hosted project, since several tests
# sign up, save and delete. Usage: scripts/e2e.sh [integration_test/<name>_test.dart ...]   (default: all of them)
#
# Memory: an emulator beside Gradle builds twice froze a 14 GB machine (RAM and swap full), even with each process capped
# on its own, since idle Gradle daemons from earlier builds linger for hours. So:
# - everything here (builds, emulator, test runs) shares one systemd slice with one budget (E2E_MEMORY, default 7G) and
#   no swap: going over kills a test, never the desktop, and the slice gets a low CPU weight so the desktop stays usable;
# - every test APK is built first, with the emulator off and no Gradle daemon left behind, then the emulator boots and
#   `flutter drive` runs the prebuilt APKs;
# - it refuses to start unless E2E_MEMORY plus 1 GB is available.
# Starts the emulator (AVD E2E_AVD, default bv_api35) and stops it again when done.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OFFSET=${BV_STACK_OFFSET:-1000}
DEVICE=emulator-5554
EMULATOR=${ANDROID_HOME:-$HOME/Android/Sdk}/emulator/emulator
BUDGET=${E2E_MEMORY:-7G}
SLICE=bv-e2e.slice
APKS="$ROOT/bharatverse_app/build/e2e"

if adb -s "$DEVICE" get-state >/dev/null 2>&1; then
  echo "an emulator is already running: stop it first, since this builds with the emulator off" >&2
  exit 1
fi
need_kb=$(( $(numfmt --from=iec "$BUDGET") / 1024 + 1024 * 1024 ))
avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
if (( avail_kb < need_kb )); then
  echo "only $(( avail_kb / 1024 / 1024 )) GB of memory available, and this needs $BUDGET plus 1 GB:" \
    "close some apps, or set E2E_MEMORY lower" >&2
  exit 1
fi

# Gradle daemons from earlier builds hold gigabytes for hours; these builds start none
(cd "$ROOT/bharatverse_app/android" && ./gradlew --stop >/dev/null 2>&1) || true
pkill -u "$USER" -f KotlinCompileDaemon || true
export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.jvmargs=-Xmx3g -Dkotlin.compiler.execution.strategy=in-process"

systemctl --user set-property --runtime "$SLICE" MemoryMax="$BUDGET" MemorySwapMax=0 CPUWeight=20
in_budget() { systemd-run --user --scope -q --slice="$SLICE" "$@"; }

if ! BV_STACK_OFFSET=$OFFSET "$ROOT/tools/local-stack/stack.sh" start >/dev/null; then
  echo "the local stack did not start: BV_PYTHON must be a Python with backend/requirements.txt and" \
    "tools/local-stack/requirements.txt installed (see tools/local-stack/README.md)" >&2
  exit 1
fi
eval "$(BV_STACK_OFFSET=$OFFSET "$ROOT/tools/local-stack/stack.sh" env)"
DEFINES=(--dart-define="SUPABASE_URL=http://10.0.2.2:${SUPABASE_URL##*:}" --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY")

cd "$ROOT/bharatverse_app"
tests=("$@")
[ ${#tests[@]} -gt 0 ] || tests=(integration_test/*_test.dart)
mkdir -p "$APKS"
for test in "${tests[@]}"; do
  echo "== building $test"
  in_budget flutter build apk --debug -t "$test" "${DEFINES[@]}" >/dev/null
  cp build/app/outputs/flutter-apk/app-debug.apk "$APKS/$(basename "$test" .dart).apk"
done

started=false
# Boots the emulator if it is not running -- also mid-run, should the budget have stopped it.
ensure_emulator() {
  if ! adb -s "$DEVICE" get-state >/dev/null 2>&1; then
    in_budget "$EMULATOR" -avd "${E2E_AVD:-bv_api35}" -no-window -no-audio -no-boot-anim -no-snapshot-save \
      -gpu swiftshader_indirect >/dev/null 2>&1 &
    started=true
  fi
  adb -s "$DEVICE" wait-for-device
  until [ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
  # 3-button navigation, the tallest navigation bar, where #30's safe-area bug showed.
  adb -s "$DEVICE" shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton
}
trap '$started && adb -s "$DEVICE" emu kill >/dev/null 2>&1 || true' EXIT

passed=() failed=()
run() {
  in_budget flutter drive --driver=test_driver/integration_test.dart -t "$1" \
    --use-application-binary="$APKS/$(basename "$1" .dart).apk" -d "$DEVICE"
}
for test in "${tests[@]}"; do
  echo "== $test"
  ensure_emulator
  if run "$test"; then
    passed+=("$test")
  elif ! adb -s "$DEVICE" get-state >/dev/null 2>&1; then
    echo "   the emulator stopped during $test (over the memory budget?): booting a fresh one and trying again"
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
