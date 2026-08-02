---
name: first-session-laws
description: Laws for the first radio sessions after a board boot — throwaway session 1, RX before first TX, no verdicts from a cold board, quiet-frequency rule. Long form in docs/radio-bring-up-laws.md.
---

# First-session laws (after any boot)

These apply after EVERY reboot or power-cycle, warm or hard. Rationale and the TX-safety
principle: `docs/radio-bring-up-laws.md`.

## 0. The ready gate comes first

No radio consumer of any kind until the `ready_marker` dmesg line has appeared
(reboot-board skill). Racing driver bring-up can wedge the board.

## 1. The first RX session is a throwaway

On a fresh boot, session 1 may show per-packet chain breaks, odd timestamps, or a stale
timing anchor — bring-up artifacts, not bugs in your code. Run one short RX session,
discard its metrics, then start measuring from session 2. If "session 2" still shows
every-packet breaks, suspect that a client crashed and restarted the session count, or
that the board silently rebooted — check `uptime` and dmesg before blaming RF.

## 2. RX before the first TX

Run at least one RX start/stop before the first TX session of a boot. TX-first on a
virgin boot can hit not-yet-armed datapath state and time out in ways that look like
hardware faults. An RX session settles the pipeline; then TX behaves.

## 3. No timing or level verdicts from session 1

Latency, timing-advance, scheduled-window and absolute-level measurements from the first
session after boot are not evidence — clocks and gain states are still converging.
Precision verdicts want a fresh boot AND a warmed session count: reboot, gate on the
marker, run a throwaway, then take exactly ONE measurement session per verdict.

## 4. Don't judge amplitude in the ISM soup

2.4 GHz (and other busy ISM bands) is full of bursty interferers; an amplitude/flatness
judgment made there measures the neighborhood, not your device. Pick a frequency you have
verified quiet (spectrum-scan it first), or use a cabled setup with known attenuation.

## 5. Know your RF path before drawing RF conclusions

Wrong antenna port, an unexpected attenuator, or a disconnected cable produce beautiful,
misleading data. Verify the physical path (which SMA, which pad, which cable) before
interpreting any level. And never TX into a receive-only port — see the TX-safety section
of docs/radio-bring-up-laws.md.
