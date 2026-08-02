---
name: vspa-firmware
description: How the prebuilt VSPA DSP firmware (.eld) works — self-describing images under /lib/firmware/rfnm/vspa/, inspected with tools/eld_ident.py, swapped by file replace + LA9310 hard reset.
---

# VSPA DSP firmware (.eld)

The LA9310 on each daughterboard contains a VSPA DSP core. Its firmware ships as
**prebuilt `.eld` files** under `/lib/firmware/rfnm/vspa/` on the board. DSP source is
not part of the SDK — building `.eld`s requires the NXP-licensed VSPA toolchain. You
consume, inspect, and swap the shipped images.

## Self-describing images

Every shipped `.eld` carries a `.rfnm_ident` ELF section: ABI number, capability bits,
selection rank, flavor name, git hash, build time, and a checksum over the image. Read it
with:

```bash
python3 tools/eld_ident.py show /lib/firmware/rfnm/vspa/<name>.eld
```

Exit 0 = ident present and checksum MATCH. The docstring in `tools/eld_ident.py` is the
authoritative description of the ident format (the firmware registry contract) — the
kernel-side struct matches it field for field.

## Boot-time registry + per-session selection

At boot the driver scans the VSPA firmware dir, verifies each image's checksum, and
registers it with its ABI/caps/rank. When a client session starts, the driver selects a
registered image by required capabilities (rank breaks ties). You don't pick a file per
session — you install the set, the driver picks.

Consequences:

- A corrupt or truncated `.eld` is rejected at registration, not mid-session. If a
  capability "disappeared", run `eld_ident.py show` on the file — checksum MISMATCH means
  a bad copy.
- Two images with the same caps: the higher rank wins. Don't install ambiguous sets.

## Swapping firmware

A VSPA firmware swap is a **file replace + LA9310 hard reset (~1 s)** — not a board
power cycle:

1. Keep a `.prev`: `cp <name>.eld <name>.eld.prev` on the board.
2. Copy the new `.eld` into `/lib/firmware/rfnm/vspa/`, `sync`.
3. Trigger an LA9310 hard reset (or simply reboot the board if unsure — slower but
   always correct). Every endpoint re-probe re-reads the firmware files.
4. Gate on readiness (reboot-board skill), then run the acceptance client
   (deploy-stack rule 4).

The deploy-together rule applies: an `.eld` with a new ABI number must ship together with
the matching kernel modules and librfnm (see deploy-stack).
