"""Tests for phone_urls.py: canned `ip` output and stubbed network, firewall and QR calls."""

import ipaddress
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import phone_urls  # noqa: E402

IP_OUTPUT = (
    "2: wlp4s0    inet 10.0.0.105/24 brd 10.0.0.255 scope global dynamic noprefixroute wlp4s0\\  valid_lft 84000sec\n"
    "3: docker0    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0\\  valid_lft forever\n"
    "5: enx1234    inet 172.20.10.2/28 brd 172.20.10.15 scope global dynamic enx1234\\  valid_lft 3000sec\n"
)
WIFI = ipaddress.ip_interface("10.0.0.105/24")
USB = ipaddress.ip_interface("172.20.10.2/28")


def run(monkeypatch, capsys, found, ufw=False, qr=True):
    """Runs main() for port 8767 with the given addresses; returns (exit code, output, URLs sent to the QR code)."""
    shown = []
    monkeypatch.setattr(phone_urls, "interfaces", lambda: found)
    monkeypatch.setattr(phone_urls, "ufw_active", lambda: ufw)
    monkeypatch.setattr(phone_urls, "show_qr", lambda url: shown.append(url) or qr)
    code = phone_urls.main(["--port", "8767"])
    return code, capsys.readouterr().out, shown


def test_container_bridges_are_dropped_and_the_iphone_usb_address_comes_first():
    assert phone_urls.host_interfaces(IP_OUTPUT) == [USB, WIFI]


def test_labels_tell_the_usb_hotspot_from_wifi():
    assert "USB" in phone_urls.label(USB)
    assert "Wi-Fi" in phone_urls.label(WIFI)


def test_firewall_rule_allows_the_interfaces_own_network():
    assert phone_urls.firewall_rule(WIFI, 8767) == "sudo ufw allow from 10.0.0.0/24 to any port 8767 proto tcp"
    assert "172.20.10.0/28" in phone_urls.firewall_rule(USB, 8767)


def test_lists_every_address_and_points_the_qr_code_at_the_first(monkeypatch, capsys):
    code, out, shown = run(monkeypatch, capsys, [USB, WIFI])
    assert code == 0
    assert "http://172.20.10.2:8767" in out and "http://10.0.0.105:8767" in out
    assert shown == ["http://172.20.10.2:8767"]
    assert "ufw" not in out


def test_prints_the_firewall_rule_only_when_ufw_is_on(monkeypatch, capsys):
    _, out, _ = run(monkeypatch, capsys, [WIFI], ufw=True)
    assert "sudo ufw allow from 10.0.0.0/24 to any port 8767 proto tcp" in out


def test_says_how_to_add_the_qr_code_when_it_cannot_be_drawn(monkeypatch, capsys):
    _, out, _ = run(monkeypatch, capsys, [WIFI], qr=False)
    assert "pip install -r scripts/requirements.txt" in out


def test_no_address_is_an_error(monkeypatch, capsys):
    code, out, shown = run(monkeypatch, capsys, [])
    assert code == 1 and "No network address" in out and shown == []


def test_qr_is_skipped_when_neither_segno_nor_qrencode_is_installed(monkeypatch):
    monkeypatch.setitem(sys.modules, "segno", None)
    monkeypatch.setattr(phone_urls.shutil, "which", lambda name: None)
    assert phone_urls.show_qr("http://10.0.0.105:8767") is False


def test_qr_is_drawn_with_segno(capsys):
    pytest.importorskip("segno")
    assert phone_urls.show_qr("http://10.0.0.105:8767") is True
    assert "█" in capsys.readouterr().out
