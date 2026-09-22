# Scripts

| Script | What it does |
|---|---|
| `dev.sh` | Starts the API (:8000) and the web app (:8765); Ctrl+C stops both |
| `run-device.sh` | Runs the app on a physical phone, natively or in its browser (below) |
| `phone_urls.py` | Used by `run-device.sh`: the addresses a phone can open, a QR code, the firewall rule |
| `doctor.sh` | Reports what is missing from your setup; it never installs anything |
| `check_lcov_coverage.sh` | The coverage gate CI applies to the Flutter app |
| `git-hooks/pre-push` | Runs `./build.sh --check` before every push: `git config core.hooksPath scripts/git-hooks` |

## Run on a phone

`./scripts/run-device.sh [--release] [--web] [--port N] [other flutter run flags]`

| Phone | From | What runs |
|---|---|---|
| Android | any machine | the native app, over USB debugging or paired wireless ADB |
| iPhone | a Mac with Xcode | the native app |
| iPhone | Linux or Windows | the web app, in the phone's browser |

The script runs natively on the first physical device `flutter devices` lists. Xcode only exists on a Mac, so an iPhone
never appears elsewhere; with no device listed, or with `--web`, it serves a release build of the web app on the network
(port 8767, or `--port`) and prints the address and a QR code.

**Native iPhone (Mac).** Sign the `ios/Runner` target in Xcode once, with a free Personal Team. A debug build only
launches while `flutter run` or Xcode is attached (iOS grants the JIT permission it needs to a debugged process), so use
`--release` for an app that keeps working from the home screen.

**iPhone from Linux or Windows.**

1. Put the phone on the same Wi-Fi as the computer, then run `./scripts/run-device.sh`.
2. Scan the QR code with the Camera app, or type the address into Safari. If the page does not load, the firewall is
   probably in the way: the script prints the `sudo ufw allow ...` line to run once when ufw is on.
3. To keep it, use Share > Add to Home Screen. It then opens full screen with the BharatVerse icon.

The app reads Supabase directly, so the phone needs internet access but not this computer's API. The web build is a
release build with no hot reload: run the script again to see a change.

Over a cable instead of Wi-Fi (not tested here): on the iPhone turn on Settings > Personal Hotspot > Allow Others to
Join, plug it in and tap Trust. Linux needs `usbmuxd` and the kernel's `ipheth` driver, and then shows the phone as a
network interface. The computer gets an address in 172.20.10.0/28, which the script lists first.

## Set up a new machine

- `pip install -r scripts/requirements.txt` in the virtualenv you run the script from adds the QR code (`segno`, pure
  Python). Without it the script still prints the address; `qrencode` (`apt install qrencode`, `brew install qrencode`)
  also works.
- Flutter stable on your `PATH` with web enabled, which is the default. Android needs the Android SDK and `adb`; the
  native iPhone route needs Xcode and CocoaPods. `./scripts/doctor.sh` lists what is missing.
- On Linux with ufw, allow the phone's network to the port once, as the script prints.

## Tests

```bash
pip install -r scripts/requirements.txt pytest
python -m pytest scripts
```

They run `run-device.sh` in a throwaway repo against a stub `flutter`, and `phone_urls.py` against canned `ip` output.
CI does not run them.
