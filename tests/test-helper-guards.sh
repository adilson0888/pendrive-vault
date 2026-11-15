#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Tests for the privileged helper's input validation. Needs root (it creates a
# temporary /etc/pendrive-vault.conf and restores whatever was there); it never
# touches a real block device.
#
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$SRC/src/pendrive-vault-helper"
CONF="/etc/pendrive-vault.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "helper guards: skipped (needs root, run with sudo)"
  exit 0
fi

fails=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

backup=""
if [ -e "$CONF" ]; then
  backup="$(mktemp)"
  cp -p "$CONF" "$backup"
fi
cleanup() {
  if [ -n "$backup" ]; then cp -p "$backup" "$CONF"; rm -f "$backup"; else rm -f "$CONF"; fi
}
trap cleanup EXIT

printf '# test configuration\nMARKER=PENDRIVE_VAULT\n' > "$CONF"
chmod 644 "$CONF"

run() { PKEXEC_UID=0 "$HELPER" "$@" </dev/null 2>&1; }
expect() {  # $1=description  $2=expected rc  $3=expected ERR token
  local out rc
  out="$(run "${@:4}")"
  rc=$?
  if [ "$rc" -eq "$2" ] && grep -q "ERR:$3" <<<"$out"; then
    ok "$1 (rc=$rc)"
  else
    bad "$1 (rc=$rc, expected $2 / ERR:$3): $out"
  fi
}

echo "helper guards"

expect "unknown action refused"             2  bad-action       definitely-not-an-action
expect "malformed uuid refused"            22  bad-uuid         unlock-passphrase not-a-uuid
expect "unknown volume refused"            10  device-not-found unlock-passphrase 11111111-2222-3333-4444-555555555555
expect "adopt: malformed uuid refused"     22  bad-uuid         adopt not-a-uuid
expect "adopt: unknown volume refused"     10  device-not-found adopt 11111111-2222-3333-4444-555555555555

# list must succeed even with no vault attached
out="$(run list)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "list succeeds"; else bad "list failed (rc=$rc): $out"; fi

# A configuration without MARKER is rejected before anything else happens
printf '# broken\n' > "$CONF"
out="$(run list)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "missing MARKER falls back to the default and lists nothing"
else
  bad "missing MARKER handling unexpected (rc=$rc): $out"
fi

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all helper guard tests passed"
