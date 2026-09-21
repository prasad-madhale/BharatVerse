#!/usr/bin/env bash
# Downloads the Postgres and PostgREST binaries the stand-in runs on into $BV_BIN_DIR, checking each against a pinned
# checksum. Called by stack.sh setup; Linux x86-64 only. On another platform install Postgres 17 and PostgREST
# yourself and set BV_PG_BIN (the directory holding initdb, pg_ctl and postgres) and BV_POSTGREST (the binary).
set -euo pipefail

BIN_DIR="${BV_BIN_DIR:?run this through stack.sh}"

PG_VERSION=17.11.0
PG_JAR="embedded-postgres-binaries-linux-amd64-$PG_VERSION.jar"
PG_URL="https://repo1.maven.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-linux-amd64/$PG_VERSION/$PG_JAR"
PG_SHA256=0dd7b72b6f335b8ecfb355fa24c5781e8a93edd09880bb77eb52ebbf29b3e96d

POSTGREST_VERSION=v16.3
POSTGREST_URL="https://github.com/PostgREST/postgrest/releases/download/$POSTGREST_VERSION/postgrest-$POSTGREST_VERSION-linux-static-x86-64.tar.xz"
POSTGREST_SHA256=4eb414eb948c8800863cc8c9896a17b611b2dccf9ff581f4d57f42ec9ccee40d

if [ -z "${BV_PG_BIN:-}${BV_POSTGREST:-}" ] && { [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; }; then
  echo "No download for $(uname -s) $(uname -m). Install Postgres 17 and PostgREST, then set BV_PG_BIN and BV_POSTGREST." >&2
  exit 1
fi

download() {  # url sha256 file
  curl -fsSL -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "Checksum mismatch for $1" >&2; rm -f "$3"; exit 1; }
}

mkdir -p "$BIN_DIR"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [ -z "${BV_PG_BIN:-}" ] && [ ! -x "$BIN_DIR/pg/bin/postgres" ]; then
  echo "  downloading Postgres $PG_VERSION"
  download "$PG_URL" "$PG_SHA256" "$work/pg.jar"
  python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract('postgres-linux-x86_64.txz', sys.argv[2])" "$work/pg.jar" "$work"
  mkdir -p "$BIN_DIR/pg"
  tar -xJf "$work/postgres-linux-x86_64.txz" -C "$BIN_DIR/pg"
fi

if [ -z "${BV_POSTGREST:-}" ] && [ ! -x "$BIN_DIR/postgrest" ]; then
  echo "  downloading PostgREST $POSTGREST_VERSION"
  download "$POSTGREST_URL" "$POSTGREST_SHA256" "$work/postgrest.tar.xz"
  tar -xJf "$work/postgrest.tar.xz" -C "$BIN_DIR" postgrest
fi
