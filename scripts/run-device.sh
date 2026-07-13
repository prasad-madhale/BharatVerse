#!/bin/bash
# Runs the Flutter app on the first connected physical iOS/Android device
# (wired or wirelessly paired) -- skips simulators/emulators/web/desktop.
#
# Usage: ./scripts/run-device.sh [--release]
#   (no flag)  Debug build -- hot reload, requires an attached debugger to
#              keep running (iOS won't launch a Debug/JIT build standalone).
#   --release  Release build -- no hot reload, but keeps working standalone
#              from the home screen after you disconnect/close Xcode.
#
# One-time setup per device is still required (Xcode signing for iOS,
# wireless ADB pairing for Android) -- this only automates picking the
# right `-d` target once a device is already paired.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT/bharatverse_app"

DEVICE_ID="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys

devices = json.load(sys.stdin)
physical = [d for d in devices if not d["emulator"] and d["targetPlatform"] in ("ios", "android")]
if not physical:
    sys.exit(1)
print(physical[0]["id"])
')"

if [ -z "$DEVICE_ID" ]; then
  echo "No physical device found. Is it connected/paired? Run 'flutter devices' to check."
  exit 1
fi

flutter run -d "$DEVICE_ID" "$@"
