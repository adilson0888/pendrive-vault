#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# uninstall.sh — remove Pendrive Vault.
#
#   sudo ./uninstall.sh            # keep /etc/pendrive-vault.conf
#   sudo ./uninstall.sh --purge    # also remove the configuration
#
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
CONF="/etc/pendrive-vault.conf"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

[ "$(id -u)" -eq 0 ] || { echo "error: run with sudo" >&2; exit 1; }

rm -f "$PREFIX/bin/pendrive-vault" \
      "$PREFIX/libexec/pendrive-vault-token" \
      "$PREFIX/libexec/pendrive-vault-helper" \
      "/usr/share/polkit-1/actions/org.pendrivevault.unlock.policy" \
      "/usr/share/applications/org.pendrivevault.PendriveVault.desktop" \
      "/usr/share/icons/hicolor/scalable/apps/pendrive-vault.svg"

if [ "$PURGE" -eq 1 ]; then
  rm -f "$CONF"
  echo "Removed configuration $CONF"
fi

echo "Pendrive Vault removed."
echo "Note: /tmp/pendrive-vault.log (last operation log) was left in place."
