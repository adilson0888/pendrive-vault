# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

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
