#!/bin/bash
# Enforce a minimum line-coverage percentage against an lcov.info file.
#
# Usage: check_lcov_coverage.sh <lcov-file> <min-percent> [exclude-pattern]
#
# exclude-pattern (optional) is an awk regex matched against each SF: path;
# matching files are dropped from both the hit and found line counts.

set -e

LCOV_FILE="$1"
MIN_PERCENT="$2"
EXCLUDE_PATTERN="${3:-}"

if [ -z "$LCOV_FILE" ] || [ -z "$MIN_PERCENT" ]; then
  echo "Usage: $0 <lcov-file> <min-percent> [exclude-pattern]" >&2
  exit 2
fi

if [ ! -f "$LCOV_FILE" ]; then
  echo "lcov file not found: $LCOV_FILE" >&2
  exit 2
fi

awk -v exclude="$EXCLUDE_PATTERN" -v min="$MIN_PERCENT" '
  /^SF:/ {
    file = $0
    sub(/^SF:/, "", file)
    skip = (exclude != "" && file ~ exclude)
  }
  /^LF:/ { if (!skip) { split($0, a, ":"); lf += a[2] } }
  /^LH:/ { if (!skip) { split($0, a, ":"); lh += a[2] } }
  END {
    if (lf == 0) {
      print "No coverable lines found in " ARGV[1]
      exit 1
    }
    pct = (lh / lf) * 100
    printf "Line coverage: %d/%d = %.2f%% (minimum: %s%%)\n", lh, lf, pct, min
    if (pct + 0.0001 < min) {
      print "Coverage below threshold"
      exit 1
    }
  }
' "$LCOV_FILE"
