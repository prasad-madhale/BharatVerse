#!/bin/bash
# Build script: format, lint, and test the entire project

set -e  # Exit on error

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

echo ""
echo "🌐 Installing Playwright browsers..."
playwright install --with-deps chromium
echo "  ✓ Chromium installed"

echo ""
echo "�🎨 Auto-formatting code with autopep8..."
autopep8 --in-place --recursive --aggressive --aggressive --max-line-length=127 backend/ scrapper/
echo "  ✓ Code formatted"

echo ""
echo "🔍 Running flake8 linting..."
# stop the build if there are Python syntax errors or undefined names
flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics \
  --exclude=.venv,.git,__pycache__,.pytest_cache,.hypothesis,bharatverse_app,scripts
echo "  ✓ No critical errors found"

echo ""
echo "🧪 Testing scrapper (all tests)..."
cd scrapper
pytest --reruns 2 --reruns-delay 5
cd ..

echo ""
echo "🧪 Testing backend (all tests)..."
cd backend
pytest --reruns 2 --reruns-delay 5
cd ..

echo ""
echo "✅ Build successful! All checks passed!"
