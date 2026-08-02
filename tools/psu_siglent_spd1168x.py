#!/usr/bin/env python3
"""Siglent SPD1168X bench supply over raw SCPI TCP.

    psu_siglent_spd1168x.py --address <host[:port]> [--channel CH1] on|off|status|set <V> <A>

Instrument quirks (documented behavior of this model, keep them in mind when editing):
  - OUTPut? has no query form — output state is SYSTem:STATus? bit 4 (0x10 = on).
  - The instrument needs a short settle between a write and the next command;
    each SCPI exchange here opens a fresh connection and sleeps 0.4 s.
"""
from __future__ import annotations

import argparse
import socket
import sys
import time

TIMEOUT_SECONDS = 5.0
SETTLE_SECONDS = 0.4
DEFAULT_PORT = 5025


def parse_address(addr: str) -> tuple[str, int]:
    host, _, port = addr.partition(":")
    if not host:
        raise ValueError("empty --address")
    return host, int(port) if port else DEFAULT_PORT


def make_scpi(hostport):
    def scpi(cmd: str, q: bool = False) -> str | None:
        s = socket.create_connection(hostport, timeout=TIMEOUT_SECONDS)
        try:
            s.settimeout(TIMEOUT_SECONDS)
            s.sendall((cmd + "\n").encode("ascii"))
            time.sleep(SETTLE_SECONDS)
            return s.recv(500).decode("ascii", errors="replace").strip() if q else None
        finally:
            s.close()
    return scpi


def status(scpi, ch: str) -> bool:
    st = int(scpi("SYSTem:STATus?", q=True), 16)
    on = bool(st & 0x10)                      # quirk: no OUTPut? query on this instrument
    vs = scpi(f"{ch}:VOLTage?", q=True)
    cs = scpi(f"{ch}:CURRent?", q=True)
    vm = scpi(f"MEASure:VOLTage? {ch}", q=True)
    cm = scpi(f"MEASure:CURRent? {ch}", q=True)
    print(f"output {'ON' if on else 'OFF'}  set {vs} V / {cs} A  meas {vm} V / {cm} A")
    return on


def main() -> int:
    ap = argparse.ArgumentParser(description="Siglent SPD1168X output control (raw SCPI TCP).")
    ap.add_argument("--address", required=True, help="host[:port], default port %d" % DEFAULT_PORT)
    ap.add_argument("--channel", default="CH1", help="channel name (default CH1)")
    ap.add_argument("action", choices=("on", "off", "status", "set"))
    ap.add_argument("values", nargs="*", help="set: <volts> <amps>")
    args = ap.parse_args()

    try:
        scpi = make_scpi(parse_address(args.address))
        ch = args.channel
        if args.action == "on":
            scpi(f"OUTPut {ch},ON")
            time.sleep(0.5)
            return 0 if status(scpi, ch) else 1
        if args.action == "off":
            scpi(f"OUTPut {ch},OFF")
            time.sleep(0.5)
            return 0 if not status(scpi, ch) else 1
        if args.action == "set":
            if len(args.values) != 2:
                ap.error("set needs <volts> <amps>")
            scpi(f"{ch}:VOLTage {float(args.values[0]):.3f}")
            scpi(f"{ch}:CURRent {float(args.values[1]):.3f}")
            status(scpi, ch)
            return 0
        status(scpi, ch)
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"psu_siglent_spd1168x: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
