#!/bin/bash
# Starts local dev servers: FastAPI backend + Flutter web app.
#
# Usage: ./scripts/dev.sh
# Stop with Ctrl+C -- both processes are cleaned up automatically.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BACKEND_PORT=8000
WEB_PORT=8765

check_port_free() {
  local port="$1" label="$2"
  local pid
  pid="$(lsof -ti:"$port" 2>/dev/null || true)"
  if [ -n "$pid" ]; then
    echo "Port $port ($label) is already in use (pid $pid)."
    echo "Stop it first, e.g.: lsof -ti:$port | xargs kill"
    exit 1
  fi
}

check_port_free "$BACKEND_PORT" "backend"
check_port_free "$WEB_PORT" "flutter web"

cleanup() {
  echo ""
  echo "Stopping dev servers..."
  kill "$BACKEND_PID" "$FLUTTER_PID" 2>/dev/null || true
  wait "$BACKEND_PID" "$FLUTTER_PID" 2>/dev/null || true
  # `flutter run`'s actual process gets reparented away from the subshell
  # that launched it, so killing $FLUTTER_PID alone can leave it running --
  # kill whatever's still bound to either port as a reliable fallback.
  lsof -ti:"$BACKEND_PORT","$WEB_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
  echo "Stopped."
}
trap cleanup EXIT INT TERM

echo "Starting backend on http://127.0.0.1:$BACKEND_PORT ..."
uvicorn backend.main:app --host 127.0.0.1 --port "$BACKEND_PORT" &
BACKEND_PID=$!

echo "Starting Flutter web app on http://localhost:$WEB_PORT ..."
(cd bharatverse_app && flutter run -d web-server --web-port="$WEB_PORT") &
FLUTTER_PID=$!

echo ""
echo "==============================="
echo "Backend:  http://127.0.0.1:$BACKEND_PORT"
echo "Frontend: http://localhost:$WEB_PORT  (open this in your browser once it finishes compiling)"
echo "Press Ctrl+C to stop both."
echo "==============================="
echo ""

wait
