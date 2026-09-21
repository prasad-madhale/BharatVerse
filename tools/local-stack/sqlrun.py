"""Runs a SQL file over pg8000 (the bundled Postgres has no psql): `python sqlrun.py PORT FILE`.

Splits on ';' outside quotes, comments and dollar-quoted bodies, then tells a running PostgREST to reload its schema.
"""
import re
import sys

import pg8000.native


def statements(script: str):
    buf, i, n, dollar = [], 0, len(script), None
    while i < n:
        ch = script[i]
        if dollar:
            if script.startswith(dollar, i):
                buf.append(dollar); i += len(dollar); dollar = None
                continue
            buf.append(ch); i += 1
            continue
        if script.startswith("--", i):
            j = script.find("\n", i)
            i = n if j < 0 else j
            continue
        m = re.match(r"\$[A-Za-z_]*\$", script[i:])
        if m:
            dollar = m.group(0); buf.append(dollar); i += len(dollar)
            continue
        if ch == "'":
            j = i + 1
            while j < n and not (script[j] == "'" and script[j + 1:j + 2] != "'"):
                j += 2 if script[j] == "'" else 1
            buf.append(script[i:j + 1]); i = j + 1
            continue
        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                yield stmt
            buf = []; i += 1
            continue
        buf.append(ch); i += 1
    tail = "".join(buf).strip()
    if tail:
        yield tail


def run_script(script: str, port: int, database: str = "postgres") -> int:
    conn = pg8000.native.Connection("postgres", host="127.0.0.1", port=port, database=database)
    count = 0
    for stmt in statements(script):
        try:
            conn.run(stmt)
        except Exception as e:
            print(f"FAILED statement #{count + 1}: {stmt[:120]!r}\n  {e}", file=sys.stderr)
            raise
        count += 1
    conn.run("NOTIFY pgrst, 'reload schema'")
    conn.close()
    return count


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python sqlrun.py PORT FILE")
    print(run_script(open(sys.argv[2]).read(), int(sys.argv[1])), "statements applied")
