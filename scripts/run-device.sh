#!/bin/bash
# Runs the Flutter app on a physical phone.
#
# Usage: ./scripts/run-device.sh [--release] [--web] [--port N] [other `flutter run` flags]
#
# Native: on the first connected physical iOS/Android device that `flutter devices` lists (wired or wirelessly
# paired), skipping simulators, emulators, web and desktop. iPhones only appear on a Mac with Xcode.
#   (no flag)  Debug build -- hot reload, requires an attached debugger to keep running (iOS won't launch a
#              Debug/JIT build standalone).
#   --release  Release build -- no hot reload, but keeps working standalone from the home screen after you
#              disconnect/close Xcode.
#
# Web: when no device is listed (an iPhone from Linux, say) or with --web, serves a release build of the web app on
# the network (default port 8767) and prints its address and a QR code to open in the phone's browser. In Safari,
# Share > Add to Home Screen installs it like an app. See scripts/README.md.
#
# One-time setup per device is still required (Xcode signing for iOS, wireless ADB pairing for Android) -- this only
# automates picking the right `-d` target once a device is already paired.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT/bharatverse_app"

WEB=false
PORT=8767
FLUTTER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --web) WEB=true ;;
    --port) PORT="${2:?--port needs a number}"; shift ;;
    *) FLUTTER_ARGS+=("$1") ;;
  esac
  shift
done

DEVICE_ID=""
if [ "$WEB" = false ]; then
  DEVICE_ID="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys

devices = json.load(sys.stdin)
# Android reports an arch-qualified platform (android-arm64, android-x64, ...), never the bare
# "android" -- a literal match here never found a real Android phone.
physical = [d for d in devices if not d["emulator"] and (d["targetPlatform"] == "ios" or d["targetPlatform"].startswith("android"))]
if not physical:
    sys.exit(1)
print(physical[0]["id"])
' || true)"
  if [ -n "$DEVICE_ID" ]; then
    exec flutter run -d "$DEVICE_ID" "${FLUTTER_ARGS[@]}"
  fi
  echo "No physical device found (run 'flutter devices' to check), so serving the web app for the phone's browser."
  echo "An iPhone can only be built for from a Mac with Xcode."
  echo ""
fi

if command -v lsof >/dev/null && [ -n "$(lsof -ti:"$PORT" 2>/dev/null)" ]; then
  echo "Port $PORT is already in use. Stop it first, or pick another with --port."
  exit 1
fi

python3 "$REPO_ROOT/scripts/phone_urls.py" --port "$PORT"

case " ${FLUTTER_ARGS[*]} " in
  *" --debug "* | *" --profile "* | *" --release "*) ;;
  *) FLUTTER_ARGS+=(--release) ;;
esac
exec flutter run -d web-server --web-hostname any --web-port "$PORT" "${FLUTTER_ARGS[@]}"
