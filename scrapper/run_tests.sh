#!/bin/bash
# Simple test runner for scrapper
# Usage:
#   ./run_tests.sh              # Run with INFO logs
#   ./run_tests.sh DEBUG        # Run with DEBUG logs
#   ./run_tests.sh WARNING      # Run with WARNING logs
#   ./run_tests.sh -m unit      # Run unit tests with INFO logs
#   ./run_tests.sh DEBUG -m integration  # Run integration tests with DEBUG logs

set -e

# Default log level
LOG_LEVEL="INFO"

# Check if first argument is a log level
if [[ "$1" =~ ^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$ ]]; then
    LOG_LEVEL="$1"
    shift  # Remove first argument so remaining args go to pytest
fi

echo "Running tests with log level: $LOG_LEVEL"
python -m pytest --log-cli-level="$LOG_LEVEL" "$@"
