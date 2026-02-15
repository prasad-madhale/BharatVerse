#!/usr/bin/env python3
"""
Verify BharatVerse development environment setup.

This script checks:
- Python version (3.12+)
- Virtual environment
- Required dependencies
- Environment variables
"""

import sys
import os
import subprocess
from pathlib import Path


def check_python_version():
    """Check if Python version is 3.12 or higher."""
    print("Checking Python version...")
    version = sys.version_info
    
    if version.major == 3 and version.minor >= 12:
        print(f"✅ Python {version.major}.{version.minor}.{version.micro} (OK)")
        return True
    else:
        print(f"❌ Python {version.major}.{version.minor}.{version.micro} (Need 3.12+)")
        print("\nTo install Python 3.12:")
        print("  macOS: brew install python@3.12")
        print("  Ubuntu: sudo apt install python3.12")
        print("  Or use pyenv: pyenv install 3.12.0")
        return False


def check_virtual_env():
    """Check if running in a virtual environment."""
    print("\nChecking virtual environment...")
    
    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        print("✅ Virtual environment active")
        return True
    else:
        print("❌ Not in a virtual environment")
        print("\nTo create and activate:")
        print("  python3.12 -m venv .venv")
        print("  source .venv/bin/activate")
        return False


def check_dependencies():
    """Check if required packages are installed."""
    print("\nChecking dependencies...")
    
    # Map package names to their import names
    required_packages = {
        'fastapi': 'fastapi',
        'pydantic': 'pydantic',
        'google-generativeai': 'google.generativeai',
        'playwright': 'playwright',
        'python-dotenv': 'dotenv'
    }
    
    missing = []
    for package, import_name in required_packages.items():
        try:
            __import__(import_name)
            print(f"✅ {package}")
        except ImportError:
            print(f"❌ {package}")
            missing.append(package)
    
    if missing:
        print("\nTo install missing packages:")
        print("  pip install -r backend/requirements.txt")
        print("  pip install -r scrapper/requirements.txt")
        return False
    
    return True


def check_env_file():
    """Check if .env file exists and has required variables."""
    print("\nChecking environment variables...")
    
    env_path = Path('.env')
    if not env_path.exists():
        print("❌ .env file not found")
        print("\nTo create:")
        print("  cp .env.example .env")
        print("  # Edit .env and add your API keys")
        return False
    
    print("✅ .env file exists")
    
    # Check for required variables
    required_vars = ['GEMINI_API_KEY', 'JWT_SECRET_KEY']
    missing_vars = []
    
    with open(env_path) as f:
        content = f.read()
        for var in required_vars:
            if f"{var}=" not in content or f"{var}=your_" in content:
                missing_vars.append(var)
    
    if missing_vars:
        print(f"⚠️  Missing or placeholder values: {', '.join(missing_vars)}")
        print("\nUpdate .env with actual values:")
        print("  GEMINI_API_KEY - Get from: https://makersuite.google.com/app/apikey")
        print("  JWT_SECRET_KEY - Generate with: openssl rand -hex 32")
        return False
    
    print("✅ Required environment variables configured")
    return True


def check_playwright():
    """Check if Playwright browsers are installed."""
    print("\nChecking Playwright browsers...")
    
    try:
        result = subprocess.run(
            ['playwright', 'install', '--dry-run'],
            capture_output=True,
            text=True
        )
        
        if 'already installed' in result.stdout.lower() or result.returncode == 0:
            print("✅ Playwright browsers installed")
            return True
        else:
            print("❌ Playwright browsers not installed")
            print("\nTo install:")
            print("  playwright install")
            return False
    except FileNotFoundError:
        print("⚠️  Playwright not found (will be installed with dependencies)")
        return True


def main():
    """Run all checks."""
    print("=" * 60)
    print("BharatVerse Development Environment Verification")
    print("=" * 60)
    
    checks = [
        check_python_version(),
        check_virtual_env(),
        check_dependencies(),
        check_env_file(),
        check_playwright()
    ]
    
    print("\n" + "=" * 60)
    if all(checks):
        print("✅ All checks passed! Environment is ready.")
        print("\nNext steps:")
        print("  1. Run scrapper: python scrapper/scrapper_main.py")
        print("  2. Run backend: uvicorn backend.main:app --reload")
        print("  3. Run mobile app: cd bharatverse_app && flutter run")
    else:
        print("❌ Some checks failed. Please fix the issues above.")
        sys.exit(1)
    print("=" * 60)


if __name__ == "__main__":
    main()
