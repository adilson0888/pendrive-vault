# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Added

- The drop-down now lists **every** LUKS2 USB volume, labelled or not, so a
  fresh stick can be picked and added from the UI with one click ("Add this
  volume"). The choice is remembered in `/etc/pendrive-vault.volumes`; the
  volume itself is not modified.
- `adopt` action in the helper, with the same USB/LUKS2/root-disk validation as
  unlocking.

### Fixed

- A `cryptsetup` that never returns (seen with a PIN shorter than the token's
  minimum length) used to hang forever: it held the FIDO2 device and left the
  window spinning, and because the app is single-instance, later clicks only
  re-activated the stuck window. The pty driver now kills the child after
  75 s, and the GUI kills the helper after 120 s, so an operation can never
  wedge the app.
- `tests/make_probe.py` keeps the driver tests honest by failing loudly if the
  cryptsetup invocation changes, and a new test covers the hang above.

## [0.1.0] — 2026-11-15

First public release.

### Added

- GTK4 app that unlocks one or more LUKS2 volumes with a FIDO2 security key
  (PIN + touch) or with a passphrase, then opens the mounted folder in the
  desktop file manager.
- Volume discovery by LUKS2 label (`MARKER`, default `PENDRIVE_VAULT`), with
  support for several volumes attached at the same time.
- "Plug in your security key" step before the PIN is requested, and a
  `TOUCH YOUR SECURITY KEY NOW` banner when the token asks for presence.
- Live cryptsetup output in a collapsible **Details** panel, plus a log at
  `/run/pendrive-vault/last.log`.
- Narrow polkit helper: validated target, four actions, secrets on stdin only.
- `install.sh` (with `DESTDIR` support for packaging), `uninstall.sh`,
  Makefile targets, and an AUR recipe.
- Test suite for the pty driver and the helper's input validation, wired into
  GitHub Actions.

### Security

- The pty used for the FIDO2 PIN is created with echo disabled, and the PIN is
  masked in any captured output, so it cannot reach the log or the GUI.
- The operation log moved to `/run/pendrive-vault` (a root-owned directory) so
  it cannot be pre-created as a symlink.
- Mount folder names derived from filesystem labels are sanitised, and the
  helper refuses to mount over a symlink.
- The helper does not read its configuration from the environment, and refuses
  devices that are not USB, not LUKS2, not labelled `MARKER`, or that hold the
  running root filesystem.

[Unreleased]: https://github.com/adilson0888/pendrive-vault/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/adilson0888/pendrive-vault/releases/tag/v0.1.0
