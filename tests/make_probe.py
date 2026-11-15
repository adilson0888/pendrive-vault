#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build a test copy of the pty driver whose child command is replaced.

Usage: make_probe.py <driver> <output> <shell-snippet> [timeout-seconds]

The driver must keep calling a single cryptsetup command line; this script
fails loudly if that line changes, so the tests cannot silently stop testing
the real thing.
"""
from __future__ import annotations

import pathlib
import sys

ORIGINAL = '["cryptsetup", "open", "--token-only", device, name]'


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    source, output, snippet = argv[1], argv[2], argv[3]
    timeout = argv[4] if len(argv) > 4 else ""

    src = pathlib.Path(source).read_text()
    if ORIGINAL not in src:
        print("error: cryptsetup command line not found in the driver", file=sys.stderr)
        return 1

    src = src.replace(ORIGINAL, f'["/bin/sh", "-c", {snippet!r}]')

    if timeout:
        if "CHILD_TIMEOUT = 75" not in src:
            print("error: CHILD_TIMEOUT constant not found", file=sys.stderr)
            return 1
        src = src.replace("CHILD_TIMEOUT = 75", f"CHILD_TIMEOUT = {timeout}")

    pathlib.Path(output).write_text(src)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
