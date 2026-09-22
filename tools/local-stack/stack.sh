#!/usr/bin/env bash
# A local stand-in for Supabase, so the app, API and content pipeline can be tried without a hosted project: real
# Postgres and PostgREST, a small auth and storage gateway, the backend API and the built web app, all on 127.0.0.1.
#
#   stack.sh setup      one time: download the binaries, create the database, apply schema.sql, then start, seed and build
#   stack.sh start      start every service       stack.sh stop     stop them       stack.sh status   what is up
#   stack.sh build      compile the web app against the stand-in
#   stack.sh seed       add the three sample articles (safe to repeat)
#   stack.sh reset      throw the data away and set up again
#   stack.sh sql FILE   run a SQL file against the database (and reload PostgREST's schema)
#   stack.sh env        print the SUPABASE_* variables that point the backend at the stand-in (also in STACK_DIR/env)
#
# BV_STACK_OFFSET (default 0) shifts every port so a second stack can run beside the first; each offset keeps its own
# data. See README.md for the ports, the other BV_* settings and how to recreate this on another machine.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OFFSET="${BV_STACK_OFFSET:-0}"
BIN_DIR="${BV_BIN_DIR:-$REPO/.local-stack/bin}"
STACK_DIR="${BV_STACK_DIR:-$REPO/.local-stack/$OFFSET}"
PY="${BV_PYTHON:-python3}"
PG_BIN="${BV_PG_BIN:-$BIN_DIR/pg/bin}"
POSTGREST="${BV_POSTGREST:-$BIN_DIR/postgrest}"
JWT_SECRET="${BV_JWT_SECRET:-super-secret-jwt-token-with-at-least-32-characters-long}"

GATEWAY_PORT=$((54321 + OFFSET))
PG_PORT=$((54322 + OFFSET))
REST_PORT=$((54323 + OFFSET))
BACKEND_PORT=$((8000 + OFFSET))
WEB_PORT=$((8765 + OFFSET))
GATEWAY_URL="http://127.0.0.1:$GATEWAY_PORT"

listening() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
key() { "$PY" -c "import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$STACK_DIR/keys.json" "$1"; }

# The backend, the seeder and the tests read these; explicit values keep them from ever reaching a hosted project.
supabase_env() {
  echo "SUPABASE_URL=$GATEWAY_URL SUPABASE_ANON_KEY=$(key anon) SUPABASE_SERVICE_ROLE_KEY=$(key service_role)"
}

launch() {  # name port command...
  local name=$1 port=$2
  shift 2
  if listening "$port"; then echo "  $name already up on :$port"; return; fi
  nohup "$@" >"$STACK_DIR/logs/$name.log" 2>&1 &
  echo $! >"$STACK_DIR/run/$name.pid"
  for _ in $(seq 60); do
    if listening "$port"; then echo "  $name up on :$port"; return; fi
    sleep 0.5
  done
  echo "  $name did not start; see $STACK_DIR/logs/$name.log" >&2
  return 1
}

start_postgres() {
  if ! listening "$PG_PORT"; then
    "$PG_BIN/pg_ctl" -D "$STACK_DIR/data" -l "$STACK_DIR/logs/postgres.log" -w start \
      -o "-p $PG_PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" >/dev/null
  fi
  echo "  postgres up on :$PG_PORT"
}

need_setup() {
  [ -f "$STACK_DIR/.ready" ] || { echo "Nothing set up in $STACK_DIR yet: run '$0 setup' first." >&2; exit 1; }
}

start() {
  need_setup
  mkdir -p "$STACK_DIR/run" "$STACK_DIR/logs"
  start_postgres
  cat >"$STACK_DIR/postgrest.conf" <<EOF
db-uri = "postgres://authenticator:authenticator@127.0.0.1:$PG_PORT/postgres"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$JWT_SECRET"
server-host = "127.0.0.1"
server-port = $REST_PORT
EOF
  launch postgrest "$REST_PORT" "$POSTGREST" "$STACK_DIR/postgrest.conf"
  launch gateway "$GATEWAY_PORT" env DB_PORT="$PG_PORT" REST_URL="http://127.0.0.1:$REST_PORT" \
    STORAGE_DIR="$STACK_DIR/storage" PUBLIC_URL="$GATEWAY_URL" APP_URL="http://127.0.0.1:$WEB_PORT" \
    JWT_SECRET="$JWT_SECRET" "$PY" -m uvicorn --app-dir "$HERE" gateway:app --host 127.0.0.1 --port "$GATEWAY_PORT" \
    --log-level warning
  launch backend "$BACKEND_PORT" env $(supabase_env) "$PY" -m uvicorn --app-dir "$REPO" backend.main:app \
    --host 127.0.0.1 --port "$BACKEND_PORT" --log-level warning
  if [ -f "$STACK_DIR/web/index.html" ]; then
    launch web "$WEB_PORT" "$PY" -m http.server "$WEB_PORT" --bind 127.0.0.1 --directory "$STACK_DIR/web"
  else
    echo "  no web app yet: run '$0 build'"
  fi
  echo
  echo "  API docs  http://127.0.0.1:$BACKEND_PORT/docs"
  [ -f "$STACK_DIR/web/index.html" ] && echo "  web app   http://127.0.0.1:$WEB_PORT"
  return 0
}

stop() {
  for name in web backend gateway postgrest; do
    [ -f "$STACK_DIR/run/$name.pid" ] && kill "$(cat "$STACK_DIR/run/$name.pid")" 2>/dev/null || true
    rm -f "$STACK_DIR/run/$name.pid"
  done
  [ -d "$STACK_DIR/data" ] && "$PG_BIN/pg_ctl" -D "$STACK_DIR/data" -m fast stop >/dev/null 2>&1 || true
  echo "  stopped"
}

status() {
  for entry in postgres:$PG_PORT postgrest:$REST_PORT gateway:$GATEWAY_PORT backend:$BACKEND_PORT web:$WEB_PORT; do
    if listening "${entry#*:}"; then echo "  up    ${entry%%:*} :${entry#*:}"; else echo "  down  ${entry%%:*} :${entry#*:}"; fi
  done
}

build() {
  need_setup
  command -v flutter >/dev/null || { echo "Flutter is not on PATH; the web app needs it." >&2; exit 1; }
  (
    cd "$REPO/bharatverse_app"
    flutter pub get >/dev/null
    flutter build web --release --output "$STACK_DIR/web" \
      --dart-define=SUPABASE_URL="$GATEWAY_URL" --dart-define=SUPABASE_ANON_KEY="$(key anon)"
  )
}

seed() {
  need_setup
  env $(supabase_env) PYTHONPATH="$REPO" "$PY" "$HERE/seed.py"
}

setup() {
  if [ -f "$STACK_DIR/.ready" ]; then echo "Already set up in $STACK_DIR (use reset to start over)."; return; fi
  BV_BIN_DIR="$BIN_DIR" "$HERE/fetch.sh"
  mkdir -p "$STACK_DIR/run" "$STACK_DIR/logs" "$STACK_DIR/storage"
  [ -d "$STACK_DIR/data" ] || "$PG_BIN/initdb" -D "$STACK_DIR/data" -U postgres -E UTF8 --locale=C.UTF-8 --auth=trust >/dev/null
  start_postgres
  "$PY" "$HERE/sqlrun.py" "$PG_PORT" "$HERE/bootstrap.sql"
  "$PY" "$HERE/sqlrun.py" "$PG_PORT" "$REPO/backend/database/schema.sql"
  DB_PORT="$PG_PORT" JWT_SECRET="$JWT_SECRET" "$PY" "$HERE/gateway.py" keys >"$STACK_DIR/keys.json"
  supabase_env | tr ' ' '\n' >"$STACK_DIR/env"
  touch "$STACK_DIR/.ready"
  start
  seed
  if [ ! -f "$STACK_DIR/web/index.html" ]; then
    if command -v flutter >/dev/null; then
      build
      start
    else
      echo "  Flutter is not on PATH, so the web app was not built: run '$0 build' once it is."
    fi
  fi
}

reset() {
  stop
  rm -rf "$STACK_DIR/data" "$STACK_DIR/storage" "$STACK_DIR/.ready" "$STACK_DIR/keys.json" "$STACK_DIR/env"
  setup
}

case "${1:-status}" in
  setup) setup ;;
  start) start ;;
  stop) stop ;;
  status) status ;;
  build) build ;;
  seed) seed ;;
  reset) reset ;;
  sql) need_setup; "$PY" "$HERE/sqlrun.py" "$PG_PORT" "${2:?usage: stack.sh sql FILE}" ;;
  env) need_setup; sed 's/^/export /' "$STACK_DIR/env" ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
