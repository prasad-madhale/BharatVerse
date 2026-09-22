"""Local stand-in for the parts of Supabase the app and backend talk to, in front of a real PostgREST.

  /rest/v1/*     proxied to PostgREST, unchanged
  /auth/v1/*     minimal GoTrue-compatible email/password auth over a real auth.users table
  /storage/v1/*  files from a local directory

For local testing only (see README.md). It signs tokens with the same secret PostgREST verifies, and is configured by
environment variables set by stack.sh. `python gateway.py keys` prints the anon and service_role keys as JSON.
"""
import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode

import httpx
import pg8000.native
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, RedirectResponse

JWT_SECRET = os.environ.get("JWT_SECRET", "super-secret-jwt-token-with-at-least-32-characters-long")
REST_URL = os.environ.get("REST_URL", "http://127.0.0.1:54323")
STORAGE_DIR = Path(os.environ.get("STORAGE_DIR", Path(__file__).parent / "storage"))
DB = {"user": "postgres", "host": "127.0.0.1", "port": int(os.environ.get("DB_PORT", "54322")), "database": "postgres"}
TOKEN_TTL = 3600
PUBLIC_URL = os.environ.get("PUBLIC_URL", "http://127.0.0.1:54321")
APP_URL = os.environ.get("APP_URL", "http://127.0.0.1:8765")
RECOVER_INTERVAL = int(os.environ.get("RECOVER_INTERVAL", "5"))  # GoTrue's real limit is 60 s per user
HOP_BY_HOP = {"host", "connection", "content-length", "transfer-encoding", "content-encoding", "keep-alive"}

app = FastAPI(title="local supabase stand-in")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
                   expose_headers=["Content-Range"])
refresh_tokens: dict = {}
mailbox: list = []          # the "emails" sent, for UAT: GET /_mailbox
recovery_tokens: dict = {}  # emailed token -> user row, PKCE challenge, redirect target, expiry
auth_codes: dict = {}       # PKCE auth code -> user row, challenge
last_recover: dict = {}     # email -> time of the last reset request


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def sign(claims: dict) -> str:
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64(json.dumps(claims).encode())
    sig = b64(hmac.new(JWT_SECRET.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def verify(token: str):
    try:
        head, body, sig = token.split(".")
        want = b64(hmac.new(JWT_SECRET.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
        claims = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    except Exception:
        return None
    return claims if hmac.compare_digest(sig, want) and claims.get("exp", 0) > time.time() else None


def hash_password(password: str, salt: str = None) -> str:
    salt = salt or secrets.token_hex(8)
    return f"{salt}${hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 60_000).hex()}"


def password_matches(password: str, stored: str) -> bool:
    return hmac.compare_digest(hash_password(password, stored.split("$")[0]), stored)


def db_run(sql: str, **params):
    conn = pg8000.native.Connection(**DB)
    try:
        return conn.run(sql, **params)
    finally:
        conn.close()


def iso(moment) -> str:
    return moment.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"code": status, "error_code": code, "msg": message}, status_code=status)


def user_json(row) -> dict:
    user_id, email, created, last = row
    return {
        "id": str(user_id), "aud": "authenticated", "role": "authenticated", "email": email,
        "email_confirmed_at": iso(created), "phone": "", "confirmed_at": iso(created),
        "last_sign_in_at": iso(last or created),
        "app_metadata": {"provider": "email", "providers": ["email"]}, "user_metadata": {},
        "identities": [], "created_at": iso(created), "updated_at": iso(created),
    }


def session_json(row) -> dict:
    now = int(time.time())
    claims = {"aud": "authenticated", "exp": now + TOKEN_TTL, "iat": now, "sub": str(row[0]), "email": row[1],
              "role": "authenticated", "aal": "aal1", "session_id": str(uuid.uuid4())}
    refresh = secrets.token_urlsafe(16)
    refresh_tokens[refresh] = str(row[0])
    return {"access_token": sign(claims), "token_type": "bearer", "expires_in": TOKEN_TTL, "expires_at": now + TOKEN_TTL,
            "refresh_token": refresh, "user": user_json(row)}


def find_user(where: str, **params):
    rows = db_run(f"SELECT id, email, created_at, last_sign_in_at FROM auth.users WHERE {where}", **params)
    return rows[0] if rows else None


@app.get("/auth/v1/settings")
async def settings():
    return {"external": {"email": True}, "disable_signup": False, "mailer_autoconfirm": True}


@app.post("/auth/v1/signup")
async def signup(request: Request):
    body = await request.json()
    email, password = (body.get("email") or "").strip().lower(), body.get("password") or ""
    if "@" not in email:
        return error(422, "validation_failed", "Unable to validate email address: invalid format")
    if len(password) < 6:
        return error(422, "weak_password", "Password should be at least 6 characters.")
    if find_user("email = :e", e=email):
        return error(422, "user_already_exists", "User already registered")
    db_run("INSERT INTO auth.users (email, encrypted_password) VALUES (:e, :p)", e=email, p=hash_password(password))
    return session_json(find_user("email = :e", e=email))


@app.post("/auth/v1/token")
async def token(request: Request, grant_type: str = "password"):
    body = await request.json()
    if grant_type == "refresh_token":
        user_id = refresh_tokens.pop(body.get("refresh_token", ""), None)
        row = find_user("id = :i", i=uuid.UUID(user_id)) if user_id else None
        return session_json(row) if row else error(400, "invalid_grant", "Invalid Refresh Token")
    if grant_type == "pkce":
        record = auth_codes.pop(body.get("auth_code", ""), None)
        if not record:
            return error(404, "flow_state_not_found", "invalid flow state, no valid flow state found")
        if b64(hashlib.sha256((body.get("code_verifier") or "").encode()).digest()) != record["challenge"]:
            return error(400, "bad_code_verifier", "code challenge does not match previously saved code verifier")
        return session_json(record["user"])
    email, password = (body.get("email") or "").strip().lower(), body.get("password") or ""
    stored = db_run("SELECT encrypted_password FROM auth.users WHERE email = :e", e=email)
    if not stored or not password_matches(password, stored[0][0]):
        return error(400, "invalid_credentials", "Invalid login credentials")
    db_run("UPDATE auth.users SET last_sign_in_at = now() WHERE email = :e", e=email)
    return session_json(find_user("email = :e", e=email))


@app.get("/auth/v1/user")
async def current_user(request: Request):
    claims = verify(request.headers.get("authorization", "").removeprefix("Bearer "))
    row = find_user("id = :i", i=uuid.UUID(claims["sub"])) if claims and claims.get("sub") else None
    return user_json(row) if row else error(401, "bad_jwt", "invalid JWT")


@app.post("/auth/v1/logout")
async def logout():
    return Response(status_code=204)


def user_for(request: Request):
    claims = verify(request.headers.get("authorization", "").removeprefix("Bearer "))
    return find_user("id = :i", i=uuid.UUID(claims["sub"])) if claims and claims.get("sub") else None


@app.put("/auth/v1/user")
async def update_user(request: Request):
    row = user_for(request)
    if not row:
        return error(401, "bad_jwt", "invalid JWT")
    password = (await request.json()).get("password")
    if password is not None:
        if len(password) < 6:
            return error(422, "weak_password", "Password should be at least 6 characters.")
        if password_matches(password, db_run("SELECT encrypted_password FROM auth.users WHERE id = :i", i=row[0])[0][0]):
            return error(422, "same_password", "New password should be different from the old password.")
        db_run("UPDATE auth.users SET encrypted_password = :p WHERE id = :i", p=hash_password(password), i=row[0])
    return user_json(find_user("id = :i", i=row[0]))


def with_query(url: str, params: dict) -> str:
    return url + ("&" if "?" in url else "?") + urlencode(params)


@app.post("/auth/v1/recover")
async def recover(request: Request, redirect_to: str = ""):
    """Like GoTrue: answers 200 whether or not the address has an account, and "emails" a one-time link."""
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    row = find_user("email = :e", e=email)
    if row:
        wait = RECOVER_INTERVAL - (time.time() - last_recover.get(email, 0))
        if wait > 0:
            return error(429, "over_email_send_rate_limit",
                         f"For security purposes, you can only request this after {int(wait) + 1} seconds.")
        last_recover[email] = time.time()
        token = secrets.token_urlsafe(16)
        recovery_tokens[token] = {"user": row, "challenge": body.get("code_challenge"),
                                  "redirect": redirect_to or APP_URL, "expires": time.time() + TOKEN_TTL}
        link = with_query(f"{PUBLIC_URL}/auth/v1/verify", {"token": token, "type": "recovery", "redirect_to": redirect_to})
        mailbox.append({"to": email, "subject": "Reset Your Password", "link": link})
    return {}


@app.get("/auth/v1/verify")
async def verify_link(token: str = "", type: str = "recovery", redirect_to: str = ""):
    """The emailed link: a PKCE flow comes back with ?code=, the older implicit flow with tokens in the fragment."""
    record = recovery_tokens.pop(token, None)
    target = redirect_to or APP_URL
    if not record or record["expires"] < time.time():
        problem = {"error": "access_denied", "error_code": "otp_expired",
                   "error_description": "Email link is invalid or has expired"}
        return RedirectResponse(with_query(target, problem) + "#" + urlencode(problem), status_code=303)
    if record["challenge"]:
        code = str(uuid.uuid4())
        auth_codes[code] = record
        return RedirectResponse(with_query(record["redirect"], {"code": code}), status_code=303)
    session = session_json(record["user"])
    fragment = urlencode({"access_token": session["access_token"], "expires_in": TOKEN_TTL,
                          "refresh_token": session["refresh_token"], "token_type": "bearer", "type": type})
    return RedirectResponse(f"{record['redirect']}#{fragment}", status_code=303)


@app.get("/_mailbox")
async def read_mailbox():
    return mailbox


def object_path(bucket: str, path: str) -> Path:
    target = (STORAGE_DIR / bucket / path).resolve()
    if STORAGE_DIR.resolve() not in target.parents:
        raise ValueError("path escapes the storage directory")
    return target


@app.api_route("/storage/v1/object/{rest:path}", methods=["GET", "POST", "PUT"])
async def storage(request: Request, rest: str):
    parts = rest.removeprefix("public/").split("/", 1)
    if len(parts) != 2:
        return JSONResponse({"error": "bad request"}, status_code=400)
    target = object_path(*parts)
    if request.method == "GET":
        if not target.is_file():
            return JSONResponse({"statusCode": "404", "error": "not_found", "message": "Object not found"}, status_code=404)
        return Response(target.read_bytes(), media_type="application/json")
    form = await request.form()
    upload = next(iter(form.values()))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(await upload.read())
    return {"Key": rest}


@app.api_route("/rest/v1/{path:path}", methods=["GET", "POST", "PATCH", "PUT", "DELETE", "HEAD"])
async def rest(request: Request, path: str):
    headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP_BY_HOP}
    async with httpx.AsyncClient(timeout=30) as client:
        upstream = await client.request(request.method, f"{REST_URL}/{path}", params=request.query_params,
                                        headers=headers, content=await request.body())
    out = {k: v for k, v in upstream.headers.items() if k.lower() not in HOP_BY_HOP}
    return Response(upstream.content, status_code=upstream.status_code, headers=out)


if __name__ == "__main__":
    if sys.argv[1:] != ["keys"]:
        sys.exit("usage: python gateway.py keys")
    issued = int(time.time())
    print(json.dumps({role: sign({"iss": "local-supabase", "role": role, "iat": issued, "exp": issued + 10 * 365 * 86400})
                      for role in ("anon", "service_role")}))
