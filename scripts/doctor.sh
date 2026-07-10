#!/bin/bash
# Environment preflight check for BharatVerse local development.
#
# Diagnoses gaps only -- it never installs or configures anything itself.
# Anything that's actually scriptable (deps, formatting, etc.) already
# lives in build.sh; this is specifically for the stuff that needs a
# human (Xcode/App Store auth, Supabase project setup, etc.) so you find
# out what's missing up front instead of mid-task.
#
# Usage: ./scripts/doctor.sh

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0

ok() {
  echo "  ✓ $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "  ✗ $1"
  if [ -n "$2" ]; then
    echo "      → $2"
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "==============================="
echo "BharatVerse environment doctor"
echo "==============================="

echo ""
echo "🐍 Python"
if command -v python3 >/dev/null 2>&1; then
  PY_VERSION="$(python3 --version 2>&1)"
  ok "$PY_VERSION found (CI targets 3.12)"
else
  fail "python3 not found" "Install Python 3.12+: https://www.python.org/downloads/"
fi

echo ""
echo "📱 Flutter"
if command -v flutter >/dev/null 2>&1; then
  ok "$(flutter --version 2>&1 | head -1)"
else
  fail "flutter not found" "Install: https://docs.flutter.dev/get-started/install"
fi

echo ""
echo "🍎 iOS toolchain (needed for \`flutter run -d ios\` / iOS Simulator)"
if [ -d "/Applications/Xcode.app" ]; then
  ok "Xcode.app is installed"
  XCODE_SELECT_PATH="$(xcode-select -p 2>/dev/null || echo "")"
  if [[ "$XCODE_SELECT_PATH" == *"Xcode.app"* ]]; then
    ok "xcode-select points at Xcode.app ($XCODE_SELECT_PATH)"
  else
    fail "xcode-select points at Command Line Tools only ($XCODE_SELECT_PATH)" \
      "sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch"
  fi
else
  fail "Xcode.app not installed (Command Line Tools alone isn't enough for iOS builds)" \
    "Install Xcode from the App Store, then: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch"
fi
if command -v pod >/dev/null 2>&1; then
  ok "CocoaPods installed ($(pod --version 2>/dev/null))"
else
  fail "CocoaPods not found (needed for iOS native plugin integration)" "brew install cocoapods"
fi

echo ""
echo "🤖 Android toolchain (needed for \`flutter run -d android\` / emulator)"
if [ -n "$ANDROID_HOME" ] || [ -n "$ANDROID_SDK_ROOT" ]; then
  ok "Android SDK env var set (ANDROID_HOME=${ANDROID_HOME:-unset}, ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-unset})"
else
  fail "No Android SDK detected" "Install Android Studio: https://developer.android.com/studio (first-run wizard installs the SDK)"
fi

echo ""
echo "🔧 Project-specific setup"
if [ -f ".env" ]; then
  ok ".env exists at repo root"
else
  fail ".env missing at repo root" "Copy from a teammate's redacted template or create one -- see README.md for required keys"
fi

HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || echo "")"
if [ "$HOOKS_PATH" == "scripts/git-hooks" ]; then
  ok "Pre-push hook enabled (core.hooksPath=scripts/git-hooks)"
else
  fail "Pre-push hook not enabled -- ./build.sh --check won't run automatically before push" \
    "git config core.hooksPath scripts/git-hooks"
fi

echo ""
echo "☁️  CLI tools used by this project"
if command -v supabase >/dev/null 2>&1; then
  ok "Supabase CLI installed ($(supabase --version 2>/dev/null))"
else
  fail "Supabase CLI not found (used for schema/project management)" "brew install supabase/tap/supabase"
fi

if command -v gh >/dev/null 2>&1; then
  ok "GitHub CLI installed"
else
  fail "GitHub CLI (gh) not found (used for inspecting Actions runs)" "brew install gh"
fi

if command -v act >/dev/null 2>&1; then
  ok "act installed (run GitHub Actions locally -- see .actrc)"
else
  fail "act not found (optional: lets you run CI locally before pushing)" "brew install act"
fi

echo ""
echo "==============================="
echo "$PASS_COUNT check(s) passed, $FAIL_COUNT check(s) need attention"
echo "==============================="

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
