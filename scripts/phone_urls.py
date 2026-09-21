#!/usr/bin/env python3
"""Tells scripts/run-device.sh's user where a phone can reach this machine: addresses, a QR code, the firewall rule."""

import argparse
import ipaddress
import re
import shutil
import socket
import subprocess
import sys

# Interfaces only containers and VMs can see, so a phone can never use their addresses.
VIRTUAL_PREFIXES = ("docker", "br-", "veth", "virbr", "lxc", "cni", "flannel")
# An iPhone sharing its connection over USB (Personal Hotspot) gives the computer an address in this range.
IPHONE_USB = ipaddress.ip_network("172.20.10.0/28")


def host_interfaces(ip_output: str) -> list[ipaddress.IPv4Interface]:
    """The machine's real addresses, from `ip -4 -o addr show scope global`, the iPhone's USB one first."""
    found = []
    for line in ip_output.splitlines():
        match = re.match(r"\d+:\s+(\S+)\s+inet\s+(\S+)", line)
        if match and not match.group(1).startswith(VIRTUAL_PREFIXES):
            found.append(ipaddress.ip_interface(match.group(2)))
    return sorted(found, key=lambda interface: interface.ip not in IPHONE_USB)


def interfaces() -> list[ipaddress.IPv4Interface]:
    """The machine's addresses; without `ip` (macOS), the one it reaches the network from."""
    if shutil.which("ip"):
        listing = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True)
        return host_interfaces(listing.stdout)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("10.255.255.255", 1))  # sends nothing; it only makes the OS pick a route
        except OSError:
            return []
        return [ipaddress.ip_interface(f"{probe.getsockname()[0]}/24")]


def label(interface: ipaddress.IPv4Interface) -> str:
    return "iPhone Personal Hotspot over USB" if interface.ip in IPHONE_USB else "Wi-Fi or Ethernet"


def firewall_rule(interface: ipaddress.IPv4Interface, port: int) -> str:
    return f"sudo ufw allow from {interface.network} to any port {port} proto tcp"


def ufw_active() -> bool:
    return bool(shutil.which("systemctl")) and subprocess.run(["systemctl", "is-active", "--quiet", "ufw"]).returncode == 0


def show_qr(url: str) -> bool:
    """Prints a QR code for `url` with segno or qrencode, whichever is installed; False if neither is."""
    try:
        import segno
    except ImportError:
        if not shutil.which("qrencode"):
            return False
        subprocess.run(["qrencode", "-t", "ANSIUTF8", "-m", "2", url])
        return True
    segno.make(url, error="m").terminal(compact=True)
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True, help="Port the web app is served on.")
    port = parser.parse_args(argv).port

    found = interfaces()
    if not found:
        print("No network address found. Join the phone's Wi-Fi, or share the phone's connection over USB.")
        return 1

    print("Open one of these on the phone (same Wi-Fi, or the iPhone's Personal Hotspot over USB):\n")
    for interface in found:
        print(f"  http://{interface.ip}:{port}    {label(interface)}")
    print()
    if not show_qr(f"http://{found[0].ip}:{port}"):
        print("(pip install -r scripts/requirements.txt adds a QR code here.)")
    print("\nIn Safari, Share > Add to Home Screen installs it like an app.")
    if ufw_active():
        print("\nThe firewall (ufw) is on. If the page will not load, allow the phone in once:")
        for interface in found:
            print(f"  {firewall_rule(interface, port)}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
