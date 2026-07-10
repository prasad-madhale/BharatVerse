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

  # Delegate iOS/Android detection to `flutter doctor` itself rather than
  # re-implementing it -- it already knows the real default SDK/Xcode
  # locations, license status, etc. (a hand-rolled env-var-only check here
  # previously gave a false negative for an Android SDK Flutter could
  # actually see fine).
  FLUTTER_DOCTOR_OUTPUT="$(flutter doctor -v 2>&1)"

  extract_flutter_doctor_section() {
    awk -v cat="$1" '
      BEGIN { found = 0 }
      /^\[.\]/ {
        if (found) exit
        if (index($0, cat) > 0) found = 1
      }
      found { print }
      /^$/ { if (found) exit }
    ' <<< "$FLUTTER_DOCTOR_OUTPUT"
  }

  report_flutter_doctor_section() {
    local label="$1" category="$2"
    local section head
    section="$(extract_flutter_doctor_section "$category")"
    head="$(echo "$section" | head -1)"
    echo ""
    echo "$label"
    if echo "$head" | grep -q '\[✓\]'; then
      ok "$head"
    else
      fail "$head"
      echo "$section" | tail -n +2 | sed 's/^/      /'
    fi
  }

  report_flutter_doctor_section "🍎 iOS toolchain (needed for \`flutter run -d ios\` / iOS Simulator)" "Xcode"
  report_flutter_doctor_section "🤖 Android toolchain (needed for \`flutter run -d android\` / emulator)" "Android toolchain"
else
  fail "flutter not found" "Install: https://docs.flutter.dev/get-started/install"
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
