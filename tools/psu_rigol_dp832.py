#!/usr/bin/env python3
"""Rigol DP832 bench supply over raw SCPI TCP.

    psu_rigol_dp832.py --address <host[:port]> [--channel CH1] on|off|status|set <V> <A>

Instrument quirk: the DP832 reports "Command error" if a write-only socket is
closed and then queried on a fresh one — state-verify queries therefore reuse
the same socket as the write (see set_output).
"""
from __future__ import annotations

import argparse
import socket
import sys
import time

TIMEOUT_SECONDS = 3.0
SETTLE_SECONDS = 0.25
DEFAULT_PORT = 5555


def parse_address(addr: str) -> tuple[str, int]:
    host, _, port = addr.partition(":")
    if not host:
        raise ValueError("empty --address")
    return host, int(port) if port else DEFAULT_PORT


def send_scpi(hostport, command: str, expect_response: bool) -> str | None:
    with socket.create_connection(hostport, timeout=TIMEOUT_SECONDS) as sock:
        sock.settimeout(TIMEOUT_SECONDS)
        sock.sendall(f"{command}\n".encode("ascii"))
        if not expect_response:
            time.sleep(SETTLE_SECONDS)
            return None
        response = sock.recv(4096).decode("ascii", errors="replace").strip()
        if not response:
            raise RuntimeError(f"empty response for command: {command}")
        return response


def set_output(hostport, channel: str, state: str) -> int:
    with socket.create_connection(hostport, timeout=TIMEOUT_SECONDS) as sock:
        sock.settimeout(TIMEOUT_SECONDS)
        sock.sendall(f":OUTP {channel},{state}\n".encode("ascii"))
        time.sleep(SETTLE_SECONDS)          # quirk: verify on the SAME socket
        sock.sendall(f":OUTP? {channel}\n".encode("ascii"))
        current = sock.recv(4096).decode("ascii", errors="replace").strip()
    print(current)
    return 0 if current == state else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Rigol DP832 output control (raw SCPI TCP).")
    ap.add_argument("--address", required=True, help="host[:port], default port %d" % DEFAULT_PORT)
    ap.add_argument("--channel", default="CH1", help="CH1|CH2|CH3 (default CH1)")
    ap.add_argument("action", choices=("on", "off", "status", "set"))
    ap.add_argument("values", nargs="*", help="set: <volts> <amps>")
    args = ap.parse_args()

    try:
        hostport = parse_address(args.address)
        if args.action == "status":
            state = send_scpi(hostport, f":OUTP? {args.channel}", True)
            setpoint = send_scpi(hostport, f":APPL? {args.channel}", True)
            print(f"output {state}  setpoint {setpoint}")
            return 0
        if args.action == "set":
            if len(args.values) != 2:
                ap.error("set needs <volts> <amps>")
            v, a = float(args.values[0]), float(args.values[1])
            send_scpi(hostport, f":APPL {args.channel},{v},{a}", False)
            print(send_scpi(hostport, f":APPL? {args.channel}", True))
            return 0
        return set_output(hostport, args.channel, args.action.upper())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"psu_rigol_dp832: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
