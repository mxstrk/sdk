# Radio bring-up laws

Rules for the window between "the board booted" and "you can trust what the radio tells
you" — plus the TX-safety principle. They exist because radio bring-up failures rarely
look like failures: they look like plausible data.

## Law 0 — The ready gate

After ANY reboot (warm `reboot` or hard power-cycle), start no radio consumer until the
board's `ready_marker` line has appeared in dmesg. `tools/reboot_board.sh` polls it for
you; verify manually with:

```bash
ssh -o ConnectTimeout=5 root@192.168.1.50 "dmesg | grep -i '<ready_marker>'"
```

The marker means the driver finished daughterboard bring-up. Starting a client before it
races initialization and can wedge the board into a state only a hard power-cycle
clears. Do not substitute sleeps for the marker — a sleep that worked yesterday is a
race that wins tomorrow.

## Law 1 — The first RX session after boot is a throwaway

Session 1 on a fresh boot may exhibit per-packet chain breaks, a stale or invalid timing
anchor, and odd first-buffer timestamps. These are bring-up artifacts. Protocol:

1. Run one short RX session (a few seconds; `samples/lrx_probe` is fine).
2. Discard everything it reported.
3. Measure from session 2 onward.

If session 2+ still shows every-packet chain breaks, do NOT keep tuning RF parameters —
the likely causes are: a client crashed and what you think is session 2 is a fresh
process's session 1; or the board silently rebooted underneath you. Check `uptime` and
dmesg first.

## Law 2 — RX before the first TX

On a virgin boot, run at least one RX session start/stop before the first TX session.
The TX datapath depends on state that RX bring-up settles; a TX-first session can hit
not-yet-armed endpoints and time out in ways indistinguishable from broken hardware. One
RX start/stop — even a trivial one — is cheap insurance.

## Law 3 — No timing or level verdicts from a cold board

Do not record latency, timing-advance, scheduled-window hit-rates, or absolute level
measurements from the first session after boot. Clocks, calibration state and gain
chains are still converging. For precision verdicts:

- Fresh boot, marker gate, throwaway session (Laws 0–1).
- Then exactly ONE measurement session per verdict. Long-lived sessions accumulate
  state; if you need a second verdict, prefer a fresh session (or a fresh boot for the
  strictest timing measurements) over reusing a warm one.

## Law 4 — Don't judge amplitude in the ISM soup

The 2.4 GHz ISM band (and its friends) is a soup of Wi-Fi bursts, Bluetooth hops and
microwave ovens. Any amplitude, flatness or spur judgment made there measures your
neighborhood. For level work:

- Pick a frequency you have VERIFIED quiet — scan it first, don't assume.
- Or cable the DUT with known attenuation.
- Use peak-hold when hunting bursty/swept content — dB-averaging hides exactly the
  signals that matter.

## The TX-safety principle

RF paths are directional and mistakes are irreversible on hardware timescales.

- **Know which SMA may transmit** in your setup, and keep the list current. "Any port,
  probably fine" is how LNAs die.
- **A receive-only port feeding an LNA must never see TX.** An LNA's input stage is
  rated for microwatts; even a brief transmit burst into it is destruction, not stress.
  If a port is wired into an RX chain (LNA, filter bank, active antenna), treat TX on
  that port as forbidden at the tooling level — build interlocks into your scripts, not
  just into your memory.
- **Verify the physical path before drawing RF conclusions.** Wrong port, forgotten
  attenuator, unconnected cable — each produces clean-looking, wrong data. Before
  interpreting levels: which SMA, which cable, which pads, terminated into what?
- **Switches and relays power up in undefined states.** If your setup includes RF
  switching, explicitly SET the switch position after every power cycle before trusting
  any path-dependent measurement; never assume it held its last position.
- When transmitting into the air, know your local regulations, use appropriate
  attenuation/shielding, and prefer dummy loads for anything that doesn't need to
  radiate.
