"""Tests for run-device.sh: a copy in a throwaway repo, with a stub `flutter` and a stub phone_urls.py."""

import json
import shutil
import socket
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "run-device.sh"

STUB_FLUTTER = """#!/bin/bash
if [ "$1" = devices ]; then
  cat "$DEVICES_JSON" 2>/dev/null || exit 99
  exit 0
fi
echo "flutter $*" >> "$CALLS"
"""
STUB_URLS = """import sys
print("urls", *sys.argv[1:])
"""
IPHONE = {"id": "00008110-0011", "targetPlatform": "ios", "emulator": False}
SIMULATOR = {"id": "SIM-1", "targetPlatform": "ios", "emulator": True}
DESKTOP = {"id": "linux", "targetPlatform": "linux-x64", "emulator": False}
# Real hardware reports an arch-qualified platform, never the bare "android".
ANDROID_PHONE = {"id": "R5GL8163W2N", "targetPlatform": "android-arm64", "emulator": False}
ANDROID_EMULATOR = {"id": "emulator-5554", "targetPlatform": "android-x64", "emulator": True}


@pytest.fixture
def run(tmp_path):
    """run(*args, devices=None) runs the script and returns (exit code, output, the flutter commands it made)."""
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    (repo / "bharatverse_app").mkdir()
    shutil.copy(SCRIPT, repo / "scripts" / "run-device.sh")
    (repo / "scripts" / "phone_urls.py").write_text(STUB_URLS)
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "flutter").write_text(STUB_FLUTTER)
    (bin_dir / "flutter").chmod(0o755)
    calls = tmp_path / "calls.txt"

    def go(*args, devices=None):
        env = {"PATH": f"{bin_dir}:/usr/bin:/bin:/usr/sbin", "CALLS": str(calls)}
        if devices is not None:
            (tmp_path / "devices.json").write_text(json.dumps(devices))
            env["DEVICES_JSON"] = str(tmp_path / "devices.json")
        done = subprocess.run(
            ["bash", str(repo / "scripts" / "run-device.sh"), *args], cwd=repo, env=env, capture_output=True, text=True
        )
        return done.returncode, done.stdout + done.stderr, calls.read_text().splitlines() if calls.exists() else []

    return go


def test_runs_natively_on_the_first_physical_device_and_passes_flags_through(run):
    code, out, calls = run("--release", devices=[SIMULATOR, DESKTOP, IPHONE])
    assert code == 0
    assert calls == ["flutter run -d 00008110-0011 --release"]
    assert "urls" not in out


def test_runs_natively_on_a_real_android_phone(run):
    """Regression test: targetPlatform for real hardware is arch-qualified (android-arm64, ...),
    never the bare "android" a literal match was looking for, so a real Android phone was never
    detected."""
    code, out, calls = run(devices=[ANDROID_EMULATOR, DESKTOP, ANDROID_PHONE])
    assert code == 0
    assert calls == ["flutter run -d R5GL8163W2N"]
    assert "urls" not in out


def test_serves_the_web_app_when_no_physical_device_is_listed(run):
    code, out, calls = run(devices=[SIMULATOR, DESKTOP])
    assert code == 0
    assert "No physical device found" in out and "urls --port 8767" in out
    assert calls == ["flutter run -d web-server --web-hostname any --web-port 8767 --release"]


def test_web_flag_skips_the_device_search_and_takes_a_port(run):
    code, out, calls = run("--web", "--port", "9123")
    assert code == 0
    assert "No physical device found" not in out and "urls --port 9123" in out
    assert calls == ["flutter run -d web-server --web-hostname any --web-port 9123 --release"]


def test_an_explicit_build_mode_is_kept_in_web_mode(run):
    _, _, calls = run("--web", "--debug")
    assert calls == ["flutter run -d web-server --web-hostname any --web-port 8767 --debug"]


@pytest.mark.skipif(not shutil.which("lsof"), reason="the port check needs lsof")
def test_refuses_a_port_that_is_already_serving(run):
    with socket.socket() as taken:
        taken.bind(("127.0.0.1", 0))
        taken.listen()
        code, out, calls = run("--web", "--port", str(taken.getsockname()[1]))
    assert code == 1 and "already in use" in out and calls == []
