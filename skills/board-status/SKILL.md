---
name: board-status
description: Read-only survey of boards (uname, STACK_MANIFEST, librfnm, module + firmware md5s) and local source checkouts. Run at session start and after deploys.
---

# Board status survey

```bash
tools/board_status.sh                  # all boards in boards.toml + sources/ table
tools/board_status.sh --board blue0    # one board
```

Read-only: writes nothing on the host or the boards.

## When

- At the start of a work session — know what is actually deployed before changing it.
- After a deploy — confirm the board runs what you think it runs.
- When two boards behave differently — diff their module/firmware md5 columns first;
  a version split explains more "mystery" behavior differences than RF does.

## What it reports

Per board (over ssh): kernel version, uptime, `/rfnm/STACK_MANIFEST` (what the last
deploy claims), installed `librfnm.so*`, md5 of each `/rfnm/kernel/*.ko`, md5 of each
firmware image (`la9310.bin`, `rfnm_m7_v0.elf`, VSPA `.eld`s).

Locally: a branch / HEAD / dirty-count table for every git checkout under `sources/` at
the SDK root.

## Reading it

- `STACK_MANIFEST: (none)` — the last deploy didn't write a manifest. Fix that habit
  (deploy-stack skill); undocumented deploys are how fleets drift.
- Module md5s that differ from your latest build = the board is NOT running your code.
- An UNREACHABLE board with a configured power backend: `tools/reboot_board.sh --board
  <name> --check` to probe PSU + ssh without cycling anything.
