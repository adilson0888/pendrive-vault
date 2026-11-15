# How Pendrive Vault works

This is the deep dive behind the short "How it works" section of the README.
Nothing here is required to *use* the app — it is for people reviewing the code
or debugging an unusual setup.

## Components and privilege levels

```text
   your user                                    root
┌──────────────────────┐        ┌────────────────────────────────────────┐
│ pendrive-vault       │  pkexec│ pendrive-vault-helper                  │
│ GTK4 GUI             │───────▶│  list | unlock-fido2 |                  │
│                      │ stdin  │  unlock-passphrase | lock              │
└──────────────────────┘        │         │                              │
                                │         ├─▶ cryptsetup open --key-file - │
                                │         └─▶ pendrive-vault-token (pty)   │
                                │                    └─▶ cryptsetup open   │
                                │                        --token-only      │
                                │         └─▶ mount -o uid=…,umask=077     │
                                └────────────────────────────────────────┘
```

| File | Runs as | Responsibility |
|---|---|---|
| `src/pendrive-vault` | your user | UI, discovery probe, collecting secrets, launching the file manager |
| `src/pendrive-vault-helper` | root via `pkexec` | validates the target, runs cryptsetup, mounts, unmounts |
| `src/pendrive-vault-token` | root (called by the helper) | drives `cryptsetup --token-only` over a pty |

The GUI never touches a block device and never mounts anything itself.

## Discovery

1. The GUI probes `lsblk` (unprivileged) only to notice plug/unplug events.
2. The helper enumerates partitions with `FSTYPE=crypto_LUKS` and keeps the
   **candidates** that pass the device-side checks:

   * it is a block device with a UUID,
   * its parent disk has `TRAN=usb`,
   * the disk does not hold the running root filesystem,
   * `cryptsetup isLuks` succeeds and `Version:` is `2`.

3. A candidate is **managed** when any of these hold:

   * its LUKS2 `Label:` equals `MARKER` (default `PENDRIVE_VAULT`),
   * its UUID is pinned in `/etc/pendrive-vault.conf` (`UUID=`),
   * its UUID is listed in `/etc/pendrive-vault.volumes`, the file the GUI
     writes through the `adopt` action when the user clicks **Add this
     volume**.

4. Each candidate is reported as
   `<uuid>\t<device>\t<state>\t<mountpoint>\t<managed>` and the GUI renders
   the list, marking unmanaged ones with "not added" and offering the Add
   button instead of the unlock buttons.

Unlocking requires *managed* **and** candidate: `ERR:not-managed 25` is
returned for a volume the user has not added, `ERR:not-a-vault 23` for
something that is not a LUKS2 USB volume at all.

Why the helper and not the GUI? Reading a LUKS2 header needs root. Doing the
detection inside the privileged process also means the GUI cannot *choose* an
arbitrary device: it can only name a UUID, and the helper re-validates it on
every call. `adopt` therefore only accepts devices that already pass the
candidate checks, and it grants no access by itself.

Neither the label nor the list authenticates anything — both are selectors.
Access is always gated by the keyslots.

## Unlocking with a passphrase

```bash
cryptsetup open --key-file - /dev/disk/by-uuid/<uuid> pv-<uuid8>
```

The passphrase is written to the helper's **stdin** and passed through with
`printf '%s' "$PASS" | cryptsetup --key-file -`. It never appears in a command
line (so not in `ps`), in an environment variable, or in a file.

### Gotcha: bash's `read` at EOF

```bash
IFS= read -r PASS || PASS=""     # WRONG: truncates the passphrase
IFS= read -r PASS || :           # right
```

`read` returns a non-zero status when it reaches EOF without a trailing
newline, *but it has still assigned the value*. The `|| PASS=""` idiom
therefore silently throws the passphrase away and cryptsetup reports:

```
Nothing to read on input.
Command failed with code -1 (wrong or missing parameters).
```

## Unlocking with a FIDO2 key

The heavy lifting is done by the `systemd-fido2` LUKS2 token handler that ships
with cryptsetup (`libcryptsetup-token-systemd-fido2.so`). It reads the
credential id, salt and relying-party from the LUKS2 header, asks the token for
an `hmac-secret` assertion and uses the result as the volume key. Pendrive
Vault does not implement any of that; it only has to satisfy the handler's
interactive prompts.

### Gotcha: the PIN prompt flushes the terminal

`cryptsetup` opens its PIN prompt with `TCSAFLUSH`, which **discards whatever is
already queued on the terminal input**. Feeding the PIN through a pipe — the
obvious approach, e.g. with `script(1)` — therefore fails no matter how
correct the PIN is:

```
Enter token PIN: Error reading passphrase from terminal.
```

The PIN never reaches the token, so the key never blinks and there is no
"touch" prompt at all.

`src/pendrive-vault-token` solves this by:

1. allocating a pty and making it the child's controlling terminal
   (`setsid` + `TIOCSCTTY`), so cryptsetup's `/dev/tty` works;
2. disabling echo on the pty **before** the child starts (never trust the child
   to do it);
3. streaming output while waiting for the prompt, and only then writing the
   PIN;
4. keeping the terminal attached while the token waits for user presence (the
   key blinks for ~30 s);
5. masking the PIN in everything it prints, with a hold-back window so a split
   across reads is still caught.

The last two points are why the app can show *"👉 TOUCH YOUR SECURITY KEY NOW"*:
the driver streams the handler's own presence prompt to the GUI.

### Timeouts

The blink window is enforced by the token (~30 s, `USER_ACTION_TIMEOUT`). A
missed touch does not consume a PIN retry; a wrong PIN does (8 attempts on
typical keys, then the token must be reset, which destroys FIDO2 credentials).

## Mounting

```bash
mount -o uid=<caller>,gid=<caller>,umask=077 /dev/mapper/pv-<uuid8> /run/media/<user>/<name>
```

* The mapper name is derived from the volume UUID, so several sticks can be
  open at once.
* The folder name comes from the inner filesystem label (`DATA` in the
  examples), falling back to `VAULT`. It is sanitised (conservative charset,
  leading dots stripped) and the helper refuses to mount over a symlink, since
  `/run/media/<user>` is writable by the user.

## Failure modes and their messages

| Helper output | Meaning |
|---|---|
| `ERR:not-a-vault 23` | not LUKS2, not on USB, or on the root disk |
| `ERR:not-managed 25` | the volume has not been added to Pendrive Vault |
| `ERR:device-not-found 10` | the volume is not plugged in |
| `ERR:already-unlocked 11` | a mapping for this UUID exists; use Lock |
| `ERR:fido2-failed 12` | PIN rejected, key not touched, or key removed |
| `ERR:passphrase-failed 14` | wrong passphrase |
| `ERR:mount-failed 13` | opened, but the filesystem could not be mounted |

## Debugging

| Where | What |
|---|---|
| GUI **Details** panel | live cryptsetup output for the current operation |
| `/run/pendrive-vault/last.log` | same output, last unlock/lock (not `list`) |
| `/run/pendrive-vault/token-debug.log` | timestamps: start → prompt seen → PIN sent → child exit |
| `sudo cryptsetup luksDump <device>` | labels, keyslots, tokens |

If `token-debug.log` shows `child-exit` ~30 s after `pin-sent`, the token timed
out waiting for the touch. If it exits within a second, the PIN was rejected or
the token was not usable — the cryptsetup message in `last.log` says which.
