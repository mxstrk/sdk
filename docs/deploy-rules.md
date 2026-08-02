# Deploy rules

The RFNM Blue radio stack spans five software layers that talk to each other through
private protocols:

| layer | artifact | runs on |
|---|---|---|
| kernel modules | `/rfnm/kernel/*.ko` | Linux, Cortex-A53 |
| M4 firmware | `/lib/firmware/la9310.bin` | Cortex-M4 inside the LA9310 |
| VSPA firmware | `/lib/firmware/rfnm/vspa/*.eld` | VSPA DSP inside the LA9310 |
| M7 firmware | `/lib/firmware/rfnm_m7_v0.elf` | i.MX8MP Cortex-M7 |
| librfnm + apps | `/usr/local/lib/librfnm.so*`, app binaries | Linux userspace |

These interfaces are NOT versioned compatibility surfaces. That buys simplicity and
performance and costs discipline at deploy time. Hence the rules; every one of them
encodes a class of failure that is miserable to debug after the fact.

## Rule 1 — Deploy together

The layers evolve as one protocol. When a change touches an inter-layer interface, ship
**all affected layers from one tree moment, in one deploy**. Never roll one layer forward
alone across a protocol change and assume the others cope — the failure is rarely a clean
error; it's subtly wrong samples, timeouts, or a wedge.

Kernel modules have a second coupling: **vermagic**. Modules must be built from the exact
kernel tree moment of the running kernel. Rebuilding a kernel tree regenerates its
release string — after that, ship kernel Image + modules together from the same build,
never mix build moments.

## Rule 2 — Rebuild every librfnm consumer

librfnm's ABI is not stable across changes. After replacing it, rebuild **every** binary
that links it: apps, daemons, your test tools, your probes, everything. The failure modes
of a stale-ABI consumer, in increasing order of cost:

1. Loader symbol error (lucky: loud and immediate).
2. Crash at first API call.
3. Heap corruption after minutes of apparently correct operation.
4. A crashed teardown that leaves the board in a state only a power-cycle clears.

Static links hide in plain sight — a binary that embeds `librfnm.a` doesn't show in
`ldd` output. Keep a list of your consumers, or use the `[audit]` map + `tools/build_audit.sh`.

## Rule 3 — One reboot per board

Stage every layer (with backups, Rule 5), `sync`, then reboot ONCE:

```bash
tools/reboot_board.sh --board blue0
```

and wait for the `ready_marker` gate (the script does). Do not reboot per layer: each
intermediate boot runs a mixed stack, and any observation you make on it — including "it
works" — is meaningless and often actively misleading.

## Rule 4 — Acceptance = a librfnm client streaming real samples

The only proof that a deploy works is a plain librfnm client receiving correct data on
the deployed board. A web UI that loads, a daemon that reports healthy, a service that is
`active (running)` — none of these exercise the client datapath.

The SDK ships the gate: `samples/lrx_probe.cpp` (cross-build via `samples/Makefile`, copy
to the board, run there). Exit 0 with reads reported = accepted. Run it on **every**
deployed board, **after** the ready gate, respecting the first-session laws
(`docs/radio-bring-up-laws.md`).

## Rule 5 — Keep a .prev of everything you replace

Before overwriting any board binary:

```bash
ssh root@192.168.1.50 'cp /lib/firmware/la9310.bin /lib/firmware/la9310.bin.prev'
```

(or the host-side equivalent under the NFS rootfs). Rollback = copy back + one reboot.
On the NFS-boot workflow, additionally snapshot the whole rootfs before multi-layer
deploys: `tools/snapshot_rootfs.sh --board blue0 pre-deploy`.

## The manifest: /rfnm/STACK_MANIFEST

Every deploy ends by writing a manifest on the board:

```
date: <UTC ISO8601>
kernel-modules: <git sha> (<md5 la9310rfnm.ko> ...)
la9310.bin: <git sha> <md5>
vspa: <eld name/abi/caps from eld_ident.py show>
rfnm_m7_v0.elf: <git sha> <md5>
librfnm: <git sha> <version>
apps: <list + md5s>
why: <one line>
by: <who>
```

Free-form, but always: date, per-layer identity (sha + md5), why, who. This file is the
first thing to read when a board misbehaves and the thing `tools/board_status.sh` prints
fleet-wide. A deploy without a manifest is a future archaeology project.

## Post-deploy checklist

1. `tools/reboot_board.sh --board <name>` — one reboot, marker gate.
2. First-session laws (`docs/radio-bring-up-laws.md`) — throwaway session, RX first.
3. `lrx_probe` green on every deployed board (Rule 4).
4. `tools/build_audit.sh --board <name>` — everything PASS, no ALIEN, no x86.
5. Manifest written; `tools/board_status.sh` reflects reality.
