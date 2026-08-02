#!/usr/bin/env python3
# eld_ident.py — read the .rfnm_ident metadata section in RFNM VSPA firmware images (.eld)
#
# The .eld files are ELF32 little-endian (custom e_machine 0x40c8, VSPA DSP). Shipped
# firmware carries an appended .rfnm_ident section that makes each image self-describing;
# the driver reads it at boot to register the firmware and select it per session by
# capability. `show` prints the fields and verifies the payload checksum.
#
# .rfnm_ident payload layout — packed little-endian, all fields naturally 4-byte aligned,
# TOTAL 104 (0x68) BYTES. The kernel-side C struct matches this exactly:
#
#   off   size  field
#   0x00     4  u32  magic          = 0x52464E49  (LE file bytes 49 4E 46 52 = "INFR")
#   0x04     4  u32  abi
#   0x08     4  u32  caps
#   0x0C     4  u32  rank
#   0x10    32  char name[32]       NUL-padded
#   0x30    24  char githash[24]    NUL-padded
#   0x48    24  char buildtime[24]  NUL-padded, UTC ISO8601 (stamp time)
#   0x60     4  u32  payload_csum   see below
#   0x64     4  u32  orig_size      byte length of the pre-stamp file
#
#   struct rfnm_eld_ident {            /* little-endian, no padding, sizeof == 104 */
#       uint32_t magic;                /* 0x52464E49 */
#       uint32_t abi;
#       uint32_t caps;
#       uint32_t rank;
#       char     name[32];
#       char     githash[24];
#       char     buildtime[24];
#       uint32_t payload_csum;
#       uint32_t orig_size;
#   };
#
# payload_csum algorithm (firmware-loader-style word csum): sum of little-endian u32
# words over bytes [0, orig_size) of the STAMPED file, trailing 1..3 bytes added as
# single byte values, truncated to 32 bits. This covers the stamped prefix — the
# original file bytes with only the e_shoff/e_shnum ELF header fields patched — so the
# checksum can be verified from the stamped file alone, with no extra state.
#
# Usage:
#   eld_ident.py show <file.eld>
#
# Exit 0 = ident present, magic OK, checksum MATCH. Nonzero otherwise.

import argparse
import struct
import sys

MAGIC = 0x52464E49
IDENT_SECNAME = b".rfnm_ident"
IDENT_FMT = "<IIII32s24s24sII"
IDENT_SIZE = struct.calcsize(IDENT_FMT)          # 104
assert IDENT_SIZE == 104

EHDR_SIZE = 52
SHENT_SIZE = 40
E_SHOFF_OFF = 32                                 # u32
SHT_STRTAB = 3


class EldError(Exception):
	pass


def die(msg):
	sys.stderr.write("eld_ident: error: %s\n" % msg)
	sys.exit(2)


def align4(x):
	return (x + 3) & ~3


def wordsum(buf):
	# 32-bit LE word-sum, trailing bytes added as single bytes (LA9310 fw csum algorithm)
	n = len(buf) & ~3
	s = 0
	if n:
		s = sum(struct.unpack_from("<%dI" % (n // 4), buf, 0))
	for b in memoryview(buf)[n:]:
		s += b
	return s & 0xFFFFFFFF


def read_cstr(blob, off):
	if off >= len(blob):
		raise EldError("string offset 0x%x beyond strtab (len 0x%x)" % (off, len(blob)))
	end = blob.find(b"\0", off)
	if end < 0:
		end = len(blob)
	return blob[off:end]


class Elf32:
	# minimal ELF32-LE section-view parser
	def __init__(self, data, path):
		self.data = data
		self.path = path
		if len(data) < EHDR_SIZE or data[0:4] != b"\x7fELF":
			raise EldError("%s: not an ELF file" % path)
		if data[4] != 1:
			raise EldError("%s: not ELF32 (EI_CLASS=%d) — only ELF32 little-endian is supported" % (path, data[4]))
		if data[5] != 1:
			raise EldError("%s: not little-endian (EI_DATA=%d) — only ELF32 little-endian is supported" % (path, data[5]))
		if data[6] != 1:
			raise EldError("%s: bad EI_VERSION %d" % (path, data[6]))
		(self.e_shoff,) = struct.unpack_from("<I", data, E_SHOFF_OFF)
		(self.e_shentsize, self.e_shnum, self.e_shstrndx) = struct.unpack_from("<HHH", data, 46)
		if self.e_shoff == 0 or self.e_shnum == 0:
			raise EldError("%s: no section header table (e_shoff=%d e_shnum=%d)" % (path, self.e_shoff, self.e_shnum))
		if self.e_shentsize != SHENT_SIZE:
			raise EldError("%s: e_shentsize %d != %d (not a plain ELF32 shdr table)" % (path, self.e_shentsize, SHENT_SIZE))
		if self.e_shnum >= 0xFF00 or self.e_shstrndx >= 0xFF00:
			raise EldError("%s: reserved/extended e_shnum/e_shstrndx not supported" % path)
		if self.e_shoff + self.e_shnum * SHENT_SIZE > len(data):
			raise EldError("%s: section header table runs past EOF" % path)
		if self.e_shstrndx == 0 or self.e_shstrndx >= self.e_shnum:
			raise EldError("%s: bad e_shstrndx %d (e_shnum %d)" % (path, self.e_shstrndx, self.e_shnum))
		# shdr = (sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info, sh_addralign, sh_entsize)
		self.shdrs = [struct.unpack_from("<10I", data, self.e_shoff + i * SHENT_SIZE) for i in range(self.e_shnum)]
		st = self.shdrs[self.e_shstrndx]
		if st[1] != SHT_STRTAB:
			raise EldError("%s: e_shstrndx section is not SHT_STRTAB (type %d)" % (path, st[1]))
		if st[4] + st[5] > len(data):
			raise EldError("%s: shstrtab runs past EOF" % path)
		self.strtab = data[st[4]:st[4] + st[5]]
		self.names = [read_cstr(self.strtab, sh[0]) for sh in self.shdrs]

	def find_section(self, name):
		for i, n in enumerate(self.names):
			if n == name:
				return i
		return None


def parse_ident(payload, path):
	if len(payload) != IDENT_SIZE:
		raise EldError("%s: .rfnm_ident size %d != %d (unknown ident layout)" % (path, len(payload), IDENT_SIZE))
	(magic, abi, caps, rank, name, githash, buildtime, payload_csum, orig_size) = struct.unpack(IDENT_FMT, payload)
	return {
		"magic": magic, "abi": abi, "caps": caps, "rank": rank,
		"name": name.rstrip(b"\0").decode("ascii", "replace"),
		"githash": githash.rstrip(b"\0").decode("ascii", "replace"),
		"buildtime": buildtime.rstrip(b"\0").decode("ascii", "replace"),
		"payload_csum": payload_csum, "orig_size": orig_size,
	}


def show_fields(data, path):
	# returns (fields, ident_shdr) or raises EldError
	elf = Elf32(data, path)
	idx = elf.find_section(IDENT_SECNAME)
	if idx is None:
		raise EldError("%s: no .rfnm_ident section (file is not stamped)" % path)
	sh = elf.shdrs[idx]
	if sh[4] + sh[5] > len(data):
		raise EldError("%s: .rfnm_ident runs past EOF" % path)
	return parse_ident(data[sh[4]:sh[4] + sh[5]], path), sh


def cmd_show(args):
	try:
		data = open(args.file, "rb").read()
	except OSError as e:
		die(str(e))
	try:
		f, sh = show_fields(data, args.file)
	except EldError as e:
		die(str(e))
	magic_ok = f["magic"] == MAGIC
	print("file:          %s  (%d bytes)" % (args.file, len(data)))
	print("section:       .rfnm_ident @ sh_offset 0x%x, sh_size %d" % (sh[4], sh[5]))
	print("magic:         0x%08X  %s" % (f["magic"], "OK" if magic_ok else "BAD (expected 0x%08X)" % MAGIC))
	print("abi:           %u" % f["abi"])
	print("caps:          0x%X" % f["caps"])
	print("rank:          %u" % f["rank"])
	print("name:          %s" % f["name"])
	print("githash:       %s" % f["githash"])
	print("buildtime:     %s" % f["buildtime"])
	print("orig_size:     %u" % f["orig_size"])
	if f["orig_size"] < EHDR_SIZE or f["orig_size"] > len(data):
		die("%s: stored orig_size %d is not sane for a %d-byte file" % (args.file, f["orig_size"], len(data)))
	if align4(f["orig_size"]) != sh[4]:
		print("warning:       align4(orig_size)=0x%x != ident sh_offset 0x%x" % (align4(f["orig_size"]), sh[4]))
	computed = wordsum(data[0:f["orig_size"]])
	verdict = "MATCH" if computed == f["payload_csum"] else "MISMATCH"
	print("payload_csum:  stored 0x%08X, computed 0x%08X over first %d bytes -> %s" % (f["payload_csum"], computed, f["orig_size"], verdict))
	if not magic_ok or verdict != "MATCH":
		sys.exit(1)


def main():
	ap = argparse.ArgumentParser(prog="eld_ident.py", description="read the .rfnm_ident metadata section in RFNM VSPA .eld firmware images")
	sub = ap.add_subparsers(dest="cmd", required=True)
	sh = sub.add_parser("show", help="print the .rfnm_ident fields and verify payload_csum")
	sh.add_argument("file", metavar="file.eld")
	args = ap.parse_args()
	cmd_show(args)


if __name__ == "__main__":
	main()
