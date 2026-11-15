#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# install.sh — install Pendrive Vault.
#
#   sudo ./install.sh                      # install; volumes found by label
#   sudo ./install.sh --marker MY_VAULT    # use a different LUKS2 label
#   sudo ./install.sh --uuid <uuid>        # pin one specific volume
#
# Options:
#   --marker NAME    LUKS2 label that marks a volume as ours (default: PENDRIVE_VAULT)
#   --uuid UUID      only manage this volume (optional)
#   --device PATH    derive --uuid from a block device (optional)
#   --mount-name N   force the folder name under /run/media/<user>/
#   --prefix PATH    install prefix (default: /usr/local)
#
# For packaging, set DESTDIR to stage files into a package root; the
# configuration is then installed as a default file instead of being written
# with a specific volume in mind.
#
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
CONF="/etc/pendrive-vault.conf"
MARKER="PENDRIVE_VAULT"
PIN_UUID=""
MOUNT_NAME=""

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

usage() { sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --marker)     MARKER="${2:-}"; shift 2 ;;
    --uuid)       PIN_UUID="${2:-}"; shift 2 ;;
    --device)     [ -b "${2:-}" ] || die "--device must be a block device"
                  PIN_UUID="$(blkid -s UUID -o value "$2")"
                  shift 2 ;;
    --mount-name) MOUNT_NAME="${2:-}"; shift 2 ;;
    --prefix)     PREFIX="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown option: $1" ;;
  esac
done

# Staging into a package root may run as a normal user; a real install may not.
if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
  die "run this script with sudo (or set DESTDIR to stage a package)"
fi

[[ "$MARKER" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || die "invalid marker: $MARKER"
[ -z "$PIN_UUID" ] || [[ "$PIN_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "invalid uuid: $PIN_UUID"

BINDIR="$PREFIX/bin"
LIBEXECDIR="$PREFIX/libexec"
POLICYDIR="/usr/share/polkit-1/actions"
APPDIR="/usr/share/applications"
ICONDIR="/usr/share/icons/hicolor/scalable/apps"

echo "==> installing binaries into ${DESTDIR}${PREFIX}"
install -Dm755 "$SRC/src/pendrive-vault"        "$DESTDIR$BINDIR/pendrive-vault"
install -Dm755 "$SRC/src/pendrive-vault-token"  "$DESTDIR$LIBEXECDIR/pendrive-vault-token"
install -Dm755 "$SRC/src/pendrive-vault-helper" "$DESTDIR$LIBEXECDIR/pendrive-vault-helper"

echo "==> installing desktop integration"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

sed "s|@LIBEXECDIR@|$LIBEXECDIR|g" \
    "$SRC/data/org.pendrivevault.unlock.policy.in" > "$tmp"
install -Dm644 "$tmp" "$DESTDIR$POLICYDIR/org.pendrivevault.unlock.policy"

sed "s|@BINDIR@|$BINDIR|g" \
    "$SRC/data/org.pendrivevault.PendriveVault.desktop.in" > "$tmp"
install -Dm644 "$tmp" "$DESTDIR$APPDIR/org.pendrivevault.PendriveVault.desktop"

install -Dm644 "$SRC/data/icons/pendrive-vault.svg" "$DESTDIR$ICONDIR/pendrive-vault.svg"

if [ -n "$DESTDIR" ]; then
  echo "==> installing default configuration to ${DESTDIR}${CONF}"
  install -Dm644 "$SRC/config/pendrive-vault.conf.example" "$DESTDIR$CONF"
else
  echo "==> writing $CONF"
  install -Dm644 /dev/null "$CONF"
  {
    echo "# Managed by Pendrive Vault install.sh — see README.md"
    echo "MARKER=$MARKER"
    [ -n "$PIN_UUID" ] && echo "UUID=$PIN_UUID"
    [ -n "$MOUNT_NAME" ] && echo "MOUNT_NAME=$MOUNT_NAME"
  } > "$CONF"
  chmod 644 "$CONF"
fi

if [ -z "$DESTDIR" ]; then
  echo
  echo "Volumes are detected by their LUKS2 label. Mark an existing volume with:"
  echo "   sudo cryptsetup config --label $MARKER /dev/sdX2"
  echo "   (the volume must be closed; only header metadata changes)"
  [ -n "$PIN_UUID" ] && echo "Pinned to UUID: $PIN_UUID"

  echo
  echo "==> dependency check"
  missing=0
  for cmd in cryptsetup pkexec python3 blkid lsblk; do
    command -v "$cmd" >/dev/null || { echo "  missing: $cmd"; missing=1; }
  done
  python3 - <<'PY' 2>/dev/null || { echo "  missing: python-gobject + gtk4 (PyGObject)"; missing=1; }
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk
PY
  [ -e /usr/lib/cryptsetup/libcryptsetup-token-systemd-fido2.so ] \
    || echo "  note: systemd's FIDO2 token plugin was not found (passphrase unlock still works)"
  [ "$missing" -eq 0 ] || echo "  install the missing packages, then run: pendrive-vault"

  echo
  echo "Done. Launch 'Pendrive Vault' from your application menu, or run pendrive-vault."
fi
