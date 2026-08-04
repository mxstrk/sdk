# Troubleshooting

Field-reported issues and their fixes, newest first.

## `rsync: command not found` on the board (sysroot / deploy)

Older factory images ship without rsync. The SDK no longer needs it: `./rfnm-sdk sysroot`
and `./rfnm-sdk deploy` detect a missing board-side rsync and automatically fall back to
tar-over-ssh (same result; rsync is only an incremental-speed nicety on re-pulls). If you
want to force the fallback explicitly: `RFNM_SYSROOT_TRANSPORT=tar ./rfnm-sdk sysroot <board>`.

You do NOT need to install anything on the board for the SDK to work.

## `apt` on the board times out against a private address (e.g. `10.0.0.x`)

Some early factory images carry a leftover apt proxy from the image build environment —
it points at an address that only existed on the factory network, so every `apt` operation
times out. On the board:

```
grep -ri proxy /etc/apt/apt.conf.d/ /etc/apt/apt.conf 2>/dev/null
```

Delete the file (or line) that sets `Acquire::http::Proxy` / `Acquire::https::Proxy`,
then `apt update` works against the normal distro mirrors. Alternatively, updating the
board firmware to a current release replaces the whole root filesystem with a clean one
(which also ships rsync).

## The sysroot: what it is and how the board's filesystem is used

The board always runs its stock OS image — the SDK never rebuilds or replaces the root
filesystem. Cross-compiling on your PC, however, needs the board's headers and libraries
(librfnm, libc, libusb, ...) to compile and link against. `./rfnm-sdk sysroot <board>`
copies just those directories (`/usr/include`, `/usr/lib`, `/usr/local/{include,lib}`,
`/lib`) from your board to `sysroot/<board>/` on the host — a few hundred MB, one-time
(re-run it after a firmware update). Everything the SDK builds then compiles with
`--sysroot` pointing there, and `./rfnm-sdk deploy` copies the built artifacts back onto
the running board over ssh.

Developers hacking on the kernel/drivers themselves can skip the copy entirely with the
NFS-boot workflow (docs/nfs-boot.md): the board's rootfs lives as a directory on your
host, which then doubles as the sysroot (`rootfs = "..."` in boards.toml).

## Cross builds silently produce x86 binaries

`cross/env.sh` must be sourced in the same shell that runs `make` (`. cross/env.sh`).
If `file` says a produced binary is x86-64, the environment wasn't active — the samples
Makefile now refuses to build when `CXX` isn't the cross compiler. Verify any board
binary with `file <bin>` (expect `ARM aarch64`) before deploying; the deploy rules doc
covers the full provenance discipline.
