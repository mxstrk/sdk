---
name: deploy-stack
description: The iron rules for deploying RFNM board software — kernel modules, M4/M7/VSPA firmware, librfnm, apps — as one unit, with backups, one reboot, and a real acceptance gate. Long form in docs/deploy-rules.md.
---

# Deploy the RFNM stack — the iron rules

Every rule below encodes a real, expensive failure mode. Details and rationale:
`docs/deploy-rules.md`. Snapshot first (snapshot-rootfs skill).

## 1. Deploy together — the stack is ONE unit

Kernel modules, M4 firmware (`la9310.bin`), VSPA firmware (`.eld`), M7 firmware
(`rfnm_m7_v0.elf`) and librfnm evolve as one protocol. Ship the layers that changed
**from one build moment of one tree** — never roll a single layer forward alone across a
protocol change. Kernel modules additionally carry vermagic: modules must come from the
exact kernel tree moment of the running kernel, or they won't load (or worse, will).

## 2. Rebuild EVERY librfnm consumer

After any librfnm change, rebuild every binary that links it — apps, daemons, test tools,
probes. Stale-ABI binaries die with symbol errors at best; at worst they corrupt the heap
or wedge the board mid-teardown. "It still starts" proves nothing about ABI match.

## 3. One reboot per board, after all layers are staged

Stage everything, `sync`, then reboot ONCE (`tools/reboot_board.sh --board <name>`), then
wait for the ready_marker gate (reboot-board skill). Don't reboot per-layer: intermediate
boots run mixed stacks and produce garbage observations you will waste time explaining.

## 4. Acceptance = a librfnm client streaming real samples

A web page loading, a daemon reporting "running", a green service — none of that proves
the client path. The gate is a plain librfnm client receiving buffers:

```bash
# built via samples/Makefile, copied to the board:
ssh root@192.168.1.50 /path/to/lrx_probe     # exit 0 + "N/16 reads ok" = stack accepted
```

Run it after every deploy, on every deployed board.

## 5. Keep a .prev of every binary you replace

Before overwriting any module, firmware, library or app on the board: copy it to
`<name>.prev` (or a dated backup). The rollback moment is never the moment you want to
start hunting for the old binary.

## The manifest

Every deploy writes `/rfnm/STACK_MANIFEST` on the board: date, git shas per layer,
artifact md5s, who/why. Check it first when a board misbehaves:

```bash
ssh root@192.168.1.50 cat /rfnm/STACK_MANIFEST
```

`tools/board_status.sh` shows it fleet-wide, plus actual md5s to catch manifest lies.
