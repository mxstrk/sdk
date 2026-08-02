#!/usr/bin/env python3
"""Scripted U-Boot serial interaction (expect-style) for RFNM Blue boards.

Usage:
  uboot_serial.py --port /dev/serial/by-id/... --log /tmp/blue0-serial.log catch   # wait for autoboot, interrupt, land at prompt
  uboot_serial.py --port ... --log ... cmd "printenv" "ver"                        # run commands at an already-live prompt
  uboot_serial.py --port ... --log ... watch 120                                   # just log output for N seconds

Everything read is appended to --log. cmd output also goes to stdout.
The board console is 115200 8N1 by default (--baud to override).
"""
import argparse
import os
import re
import sys
import termios
import time

BAUD_MAP = {
	9600: termios.B9600,
	19200: termios.B19200,
	38400: termios.B38400,
	57600: termios.B57600,
	115200: termios.B115200,
	230400: termios.B230400,
	460800: termios.B460800,
	921600: termios.B921600,
}


def _open_serial(port, baud=115200):
	if baud not in BAUD_MAP:
		raise SystemExit("unsupported --baud %d (supported: %s)" % (baud, ", ".join(str(b) for b in sorted(BAUD_MAP))))
	fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
	attrs = termios.tcgetattr(fd)
	attrs[0] = 0
	attrs[1] = 0
	attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
	attrs[3] = 0
	attrs[6][termios.VMIN] = 0
	attrs[6][termios.VTIME] = 0
	b = BAUD_MAP[baud]
	attrs[4] = b
	attrs[5] = b
	termios.tcsetattr(fd, termios.TCSANOW, attrs)
	return fd


class Console:
	def __init__(self, port, logpath, baud=115200):
		self.fd = _open_serial(port, baud)
		self.log = open(logpath, "ab")
		self.buf = b""

	def pump(self):
		try:
			data = os.read(self.fd, 4096)
		except BlockingIOError:
			data = b""
		if data:
			self.buf += data
			self.log.write(data)
			self.log.flush()
		return data

	def send(self, s):
		os.write(self.fd, s.encode())

	def wait_for(self, pattern, timeout, poke=None, poke_interval=0.5):
		"""Wait until regex pattern appears in the stream. Optionally send `poke` periodically."""
		rx = re.compile(pattern.encode())
		deadline = time.time() + timeout
		last_poke = 0.0
		while time.time() < deadline:
			self.pump()
			if rx.search(self.buf):
				return True
			if poke is not None and time.time() - last_poke > poke_interval:
				self.send(poke)
				last_poke = time.time()
			time.sleep(0.05)
		return False

	def run_cmd(self, cmd, timeout=30):
		"""Send a command at the U-Boot prompt, return output up to the next prompt."""
		self.buf = b""
		self.send(cmd + "\n")
		ok = self.wait_for(r"\n(u-boot)?=> ?$", timeout)
		out = self.buf.decode(errors="replace")
		if not ok:
			out += "\n[uboot_serial: TIMEOUT waiting for prompt]"
		return out


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--port", required=True)
	ap.add_argument("--log", required=True)
	ap.add_argument("--baud", type=int, default=115200)
	ap.add_argument("mode", choices=["catch", "cmd", "watch"])
	ap.add_argument("rest", nargs="*")
	args = ap.parse_args()

	c = Console(args.port, args.log, args.baud)

	if args.mode == "catch":
		# wait for the U-Boot banner, then interrupt autoboot by poking until a prompt shows
		if not c.wait_for(r"U-Boot ", 120):
			print("FAIL: no U-Boot banner within 120s")
			sys.exit(1)
		if not c.wait_for(r"(u-boot)?=> ?", 30, poke="\x03", poke_interval=0.2):
			print("FAIL: saw banner but no prompt (autoboot not interrupted)")
			sys.exit(1)
		time.sleep(0.3)
		c.pump()
		print("OK: at U-Boot prompt")
	elif args.mode == "cmd":
		# sanity poke: empty line should re-echo the prompt
		c.send("\n")
		if not c.wait_for(r"(u-boot)?=> ?", 10):
			print("FAIL: no U-Boot prompt on poke")
			sys.exit(1)
		for cmd in args.rest:
			out = c.run_cmd(cmd, timeout=60)
			print(out)
	elif args.mode == "watch":
		secs = float(args.rest[0]) if args.rest else 60
		end = time.time() + secs
		while time.time() < end:
			d = c.pump()
			if d:
				sys.stdout.write(d.decode(errors="replace"))
				sys.stdout.flush()
			time.sleep(0.05)


if __name__ == "__main__":
	main()
