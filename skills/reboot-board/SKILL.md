---
name: reboot-board
description: Reboot or power-cycle an RFNM Blue board via tools/reboot_board.sh and wait for true radio readiness (the ready_marker dmesg gate).
---

# Reboot an RFNM Blue board

```bash
tools/reboot_board.sh --board blue0            # hard power-cycle + wait for readiness
tools/reboot_board.sh --board blue0 --warm     # ssh `reboot` instead of a power cut
tools/reboot_board.sh --board blue0 --check    # read-only: PSU status + ssh probe
```

The script: syncs the board over ssh (so an NFS/eMMC rootfs isn't torn mid-write), cycles
power via the backend configured in boards.toml (`[board.<name>.power]`), polls until ssh
answers, then polls dmesg for the board's `ready_marker`.

## Warm vs hard

- **Warm (`--warm`)**: plain `reboot` over ssh. Enough after kernel/module/firmware file
  swaps. Keeps the PSU untouched — works with `backend = "manual"` unattended.
- **Hard (default)**: full power cut for `off_seconds`. Use when the radio front-end or
  the LA9310 is wedged, after power-domain experiments, or when ssh is dead. With
  `backend = "manual"` the script prompts you to pull/restore power; with a configured
  Rigol DP832 / Siglent SPD1168X / shell backend it does it for you.

## THE LAW: the marker is the gate

`ready_marker` (boards.toml) is a dmesg line that only appears once the radio driver
stack finished bring-up. **It is the ONLY readiness signal.**

- Never add settle sleeps on top of the script. If readiness seems flaky, the marker is
  wrong — fix the marker, don't pad with sleep.
- After ANY reboot (warm or hard), start **no radio consumer** (no librfnm client, no
  streaming app) until the marker has appeared. Racing bring-up can wedge the board into
  a state only a hard power-cycle clears.
- If the script warns the marker never appeared: check `dmesg` on the board for the
  actual driver-ready line of your firmware version and update `ready_marker` to match.

Manual check:

```bash
ssh -o ConnectTimeout=5 root@192.168.1.50 "dmesg | grep -i '<ready_marker>'"
```

After the marker: follow the first-session-laws skill before trusting any RF metric.
