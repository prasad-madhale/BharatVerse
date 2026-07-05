#!/bin/bash
# Build script: install deps, format, lint, test, and enforce coverage
# across the whole monorepo (scrapper, backend, common, bharatverse_app).
#
# Usage:
#   ./build.sh          Auto-fix formatting, then lint + run the full test
#                        suite (including integration tests, which need live
#                        credentials/network -- meant for local dev with a
#                        real .env).
#   ./build.sh --check  Non-mutating: fail instead of auto-fixing formatting,
#                        and only run the fast suite (-m "not integration"),
#                        matching CI. Used by the pre-push hook and CI so
#                        neither depends on live external services.
#
# Every `pytest` invocation below enforces >=85% source coverage on its own
# (see */pytest.ini's addopts + */.coveragerc) -- no extra flags needed here.

set -e  # Exit on error

CHECK_MODE=false
if [ "$1" == "--check" ]; then
  CHECK_MODE=true
fi

echo "==============================="
echo "Building BharatVerse Project"
echo "==============================="
echo ""

echo "📦 Installing dependencies..."
python -m pip install --upgrade pip

# Install scrapper dependencies
if [ -f scrapper/requirements.txt ]; then
  echo "  → Installing scrapper dependencies..."
  pip install -r scrapper/requirements.txt
fi

# Install backend dependencies
if [ -f backend/requirements.txt ]; then
  echo "  → Installing backend dependencies..."
  pip install -r backend/requirements.txt
fi

echo "  → Installing Flutter dependencies..."
(cd bharatverse_app && flutter pub get)

echo ""
echo "🌐 Installing Playwright browsers..."
playwright install --with-deps chromium
echo "  ✓ Chromium installed"

echo ""
if [ "$CHECK_MODE" = true ]; then
  echo "🎨 Checking code formatting (autopep8, dart format)..."
  autopep8 --recursive --aggressive --aggressive --max-line-length=127 --exit-code --diff backend/ scrapper/ common/
  (cd bharatverse_app && dart format --output=none --set-exit-if-changed .)
  echo "  ✓ Already formatted"
else
  echo "🎨 Auto-formatting code (autopep8, dart format)..."
  autopep8 --in-place --recursive --aggressive --aggressive --max-line-length=127 backend/ scrapper/ common/
  (cd bharatverse_app && dart format .)
  echo "  ✓ Code formatted"
fi

echo ""
echo "🔍 Running flake8 linting..."
# stop the build if there are Python syntax errors or undefined names
flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics \
  --exclude=.venv,.git,__pycache__,.pytest_cache,.hypothesis,bharatverse_app,scripts
echo "  ✓ No critical errors found"

echo ""
echo "🔍 Running flutter analyze..."
(cd bharatverse_app && flutter analyze)
echo "  ✓ No analyzer issues found"

if [ "$CHECK_MODE" = true ]; then
  PYTEST_MARKER_ARGS=(-m "not integration")
else
  PYTEST_MARKER_ARGS=()
fi

echo ""
echo "🧪 Testing common (coverage gate: 85%)..."
(cd common && pytest "${PYTEST_MARKER_ARGS[@]}")

echo ""
echo "🧪 Testing scrapper (coverage gate: 85%)..."
(cd scrapper && pytest "${PYTEST_MARKER_ARGS[@]}")

echo ""
echo "🧪 Testing backend (coverage gate: 85%)..."
(cd backend && pytest "${PYTEST_MARKER_ARGS[@]}" --reruns 2 --reruns-delay 5)

echo ""
echo "🧪 Testing bharatverse_app (coverage gate: 85%)..."
(cd bharatverse_app && flutter test --coverage)
./scripts/check_lcov_coverage.sh bharatverse_app/coverage/lcov.info 85 "lib/main.dart"

echo ""
echo "✅ Build successful! All checks passed!"
