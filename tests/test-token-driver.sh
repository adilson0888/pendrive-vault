#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Tests for the pty driver. No hardware and no root needed: the driver is
# copied and its cryptsetup invocation is replaced by a fake that behaves like
# cryptsetup (prints a prompt, echoes, waits, exits with a known status).
#
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$SRC/src/pendrive-vault-token"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# Build a driver whose child command is replaced by $1 (a shell snippet).
make_probe() {
  python3 - "$DRIVER" "$TMP/probe.py" "$1" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
cmd = sys.argv[3]
old = '["cryptsetup", "open", "--token-only", device, name]'
assert old in src, "driver command line not found - update this test"
new = f'["/bin/sh", "-c", {cmd!r}]'
pathlib.Path(sys.argv[2]).write_text(src.replace(old, new))
PY
}

echo "pty driver"

# 1. The PIN is delivered only after the prompt, and the child receives it.
#    (The value itself is masked by the driver, so report its length.)
make_probe "printf 'Enter token PIN: '; read -r x; echo; echo LEN=\${#x}"
out="$(printf 'PIN-1234\n' | python3 "$TMP/probe.py" /dev/null x 2>&1)"
if grep -q 'LEN=8' <<<"$out"; then
  ok "PIN delivered after the prompt"
else
  bad "PIN was not delivered to the child"
fi

# 2. A child that prints the PIN back must not leak it (masking).
make_probe "printf 'Enter token PIN: '; read -r x; echo; echo LEAK=\$x"
out="$(printf 'TOPSECRET\n' | python3 "$TMP/probe.py" /dev/null x 2>&1)"
if grep -q 'TOPSECRET' <<<"$out"; then
  bad "PIN appeared in the captured output"
else
  ok "PIN masked in captured output"
fi

# 3. Terminal echo is disabled by the driver, so typed input is not echoed.
make_probe "printf 'Enter token PIN: '; read -r x; echo; echo done"
out="$(printf 'ECHO-ME-42\n' | python3 "$TMP/probe.py" /dev/null x 2>&1)"
if grep -q 'ECHO-ME-42' <<<"$out"; then
  bad "input was echoed by the terminal"
else
  ok "terminal echo disabled"
fi

# 4. The driver keeps the terminal open while the child waits (touch wait).
make_probe "printf 'Enter token PIN: '; read -r x; echo; echo touch-now; sleep 3; echo finished"
start=$(date +%s)
out="$(printf 'x\n' | python3 "$TMP/probe.py" /dev/null x 2>&1)"
elapsed=$(( $(date +%s) - start ))
if grep -q 'finished' <<<"$out" && [ "$elapsed" -ge 3 ]; then
  ok "waited for the child after the PIN (${elapsed}s)"
else
  bad "driver did not wait for the child (${elapsed}s)"
fi

# 5. Exit status is propagated.
make_probe "printf 'Enter token PIN: '; read -r x; exit 42"
printf 'x\n' | python3 "$TMP/probe.py" /dev/null x >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 42 ]; then
  ok "child exit status propagated"
else
  bad "child exit status not propagated"
fi

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all driver tests passed"
