# Security policy

## What this project does with secrets

Pendrive Vault never sees, stores or logs your passphrase or your FIDO2 PIN
beyond the moment it hands them to `cryptsetup`:

* the passphrase is written to the helper's **stdin** and piped to
  `cryptsetup open --key-file -`;
* the FIDO2 PIN is written to the helper's **stdin**, then to the pseudo
  terminal only after cryptsetup prints its prompt;
* the pseudo terminal is created with **echo disabled** by the driver itself,
  and any occurrence of the PIN in the captured output is masked before it is
  streamed to the GUI or appended to the log;
* neither value is placed on a command line, in an environment variable, or in
  a file.

`/run/pendrive-vault/last.log` and the **Details** panel contain cryptsetup's
output. That output is not expected to contain secrets, but treat it as
sensitive on a shared machine.

## Privilege boundary

The GUI runs as your user. The privileged part is a small shell script,
`pendrive-vault-helper`, started through `pkexec` with the polkit action
`org.pendrivevault.unlock`.

The helper is intentionally not generic:

* it reads a **root-owned** configuration file (`/etc/pendrive-vault.conf`),
  so an unprivileged user cannot redirect it to an arbitrary device;
* the only input is a volume UUID, and the helper re-validates it on every
  call: block device, LUKS2, LUKS2 label equal to `MARKER`, on a USB disk, and
  not the disk holding `/`;
* only four actions exist: `list`, `unlock-fido2`, `unlock-passphrase`,
  `lock`;
* it mounts with `umask=077` and ownership of the calling user;
* the mount point is derived from the inner filesystem label with a
  conservative character set (leading dots stripped), and it refuses to mount
  over a symlink, since `/run/media/<user>` is user-writable.

Note that the LUKS2 **label is only a selector**: anybody can create a LUKS2
volume labelled `PENDRIVE_VAULT`. That does not grant access to your data —
opening it still requires your keyslot — but it means "detected as a vault"
must never be read as "trusted".

If you run a multi-user machine where any active session must not be able to
mount this volume, change the installed policy's `allow_active` from `yes` to
`auth_admin_keep`. The volume still cannot be *opened* without the token or the
passphrase; this only adds an authorization prompt for the mount operation.

## Threat model

In scope:

* someone who finds or steals the drive: LUKS2 + argon2id / FIDO2 protects the
  contents;
* a malicious local unprivileged user on the machine: cannot point the helper
  at another device or run arbitrary commands through it.

Out of scope:

* a compromised desktop session or kernel — anything running as your user can
  read unlocked files, and can run `pkexec` on this helper;
* cold-boot or DMA attacks against a mounted volume;
* losing the passphrase **and** the key (the data is then unrecoverable by
  design).

## Reporting a vulnerability

Please open a private security advisory on GitHub
(*Security → Advisories → Report a vulnerability*) rather than a public issue.
Include the distribution, cryptsetup/systemd versions, and the contents of
`Details` if relevant.
