---
name: cross-compile
description: Cross-compile librfnm clients and board apps for RFNM Blue (i.MX8MP, 4x Cortex-A53, aarch64/NEON) on the dev host against the board's own rootfs as sysroot — no on-board compiles.
---

# Cross-compile for RFNM Blue (i.MX8MP)

The board is 4x Cortex-A53 (aarch64, NEON). ALL board binaries are cross-compiled on the
dev host — never compile on the board (slow, and native-built binaries drift from your
source tree with no provenance). Target the A53 always: `-mcpu=cortex-a53`; NEON paths
compile in automatically (`__aarch64__`).

Prereqs: `gcc-aarch64-linux-gnu`, `g++-aarch64-linux-gnu`, `qemu-user-static`.

## The sysroot is the board's own rootfs

Every build links against a local copy of the board's rootfs (headers + libs exactly as
deployed). Fetch/refresh it with `./rfnm-sdk sysroot <board>` (rsync from the board into
the path configured as `rootfs` in boards.toml). Both cross entry points resolve the
sysroot from `$RFNM_SYSROOT`, falling back to the first boards.toml board with a rootfs.

## The two entry points (both in cross/)

| build system | entry point | usage |
|---|---|---|
| CMake | `cross/imx8mp.cmake` | `cmake -S . -B build-imx8mp -DCMAKE_TOOLCHAIN_FILE=<sdk>/cross/imx8mp.cmake` |
| Makefile | `cross/env.sh` | `. <sdk>/cross/env.sh` then `make …` (exports CC/CXX/ARCHFLAGS/CROSS_LDFLAGS + pkg-config isolation) |

**Always build CMake projects into `build-imx8mp/`** (never `build/` — keep that for the
x86 host build) and **always `make clean` a Makefile project before switching arch** —
stray host `.o` files in a cross link are a classic failure mode.

## Acceptance ritual (before any deploy)

1. `file <bin>` → must say `ELF 64-bit … ARM aarch64`.
2. If the program has a selftest, run it under qemu against the real rootfs (NEVER run a
   cross-built selftest natively — it execs the aarch64 binary on x86):

```bash
qemu-aarch64-static -L $RFNM_SYSROOT \
  -E LD_LIBRARY_PATH=$RFNM_SYSROOT/usr/lib/aarch64-linux-gnu:$RFNM_SYSROOT/usr/local/lib \
  ./<bin> --selftest
```

   Green under qemu = deployable. This catches missing libs, wrong glibc, and bad flags
   before the board ever sees the binary. No qemu on the host? Copy the binary to the
   board's `/tmp` and run the selftest there — never over the deployed one.
3. Check the symbol versions against the sysroot — the link itself never complains:

```bash
aarch64-linux-gnu-objdump -T <bin> | grep -oE 'GLIBC_[0-9.]+|GLIBCXX_[0-9.]+' | sort -Vu | tail -3
strings $RFNM_SYSROOT/usr/lib/aarch64-linux-gnu/libc.so.6 | grep -oE '^GLIBC_2\.[0-9]+$' | sort -V | tail -1
```

   The binary's highest `GLIBC_`/`GLIBCXX_` must not exceed the sysroot's (trap 10).
4. Deploy per the deploy-stack skill (keep a `.prev` backup of anything you replace).

## Traps (each one costs a debug round — read before improvising)

1. **A build can "succeed" without the feature you wanted.** Optional-dependency probes
   (pkg-config checks, `WITH_X` flags) silently skip targets when misconfigured. After
   building, verify the binary exists and contains the feature (`strings <bin> | grep`
   for a marker, or run `--help`/selftest under qemu).
2. **Debian cross gcc does not search `${sysroot}/usr/local/include` or `/usr/local/lib`**
   (a native gcc would) — and that is where librfnm lives on the board. env.sh and
   imx8mp.cmake inject `-isystem`/`-L` for this; bypass them and librfnm goes invisible.
3. **pkg-config leakage**: without `PKG_CONFIG_SYSROOT_DIR` + `PKG_CONFIG_LIBDIR` (both
   entry points set them) the host's x86 `.pc` files win and you link x86 libraries into
   an aarch64 binary. Never set `PKG_CONFIG_PATH` around a cross build.
4. **Both CC and CXX must be cross.** Mixed C/C++ projects that only override CC get one
   x86 object in an aarch64 link — the error appears at link time and looks unrelated.
5. **The sysroot may be a LIVE exported rootfs** (NFS-boot workflow). Building against it
   read-only is free; `make install`/`cmake --install` INTO it is a deploy — treat it as
   one (snapshot first, restart discipline, deploy-together rule). Never run apt or
   ldconfig in it casually.
6. **librfnm ABI = deploy-together**: after any librfnm change, rebuild every consumer
   and ship lib + apps in one deploy (see deploy-stack). Stale-ABI binaries fail with
   symbol errors at best, heap corruption at worst.
7. **NFS attribute caching**: an NFS-booted board may fail to exec a freshly copied
   binary for a few seconds. Wait, don't debug.
8. **Missing dev symlink, not missing lib**: if the link fails with `cannot find -lfoo`
   but `libfoo.so.N` exists in the sysroot, create the `libfoo.so` symlink in the sysroot
   — do not apt-install into it (trap 5).
9. **DSP-heavy code**: prefer `-O3 -ftree-vectorize` + NEON intrinsics behind
   `__aarch64__`; `-fcx-limited-range` kills the per-complex-multiply libgcc call. Do NOT
   blanket `-ffast-math` — it shifts near-threshold numerical results.
10. **The link "succeeds" against the HOST glibc.** Two ways in, both silent (2026-11-10,
   lorad for blue126: built fine, then `GLIBC_2.43 not found` on the board, which has 2.39):
   (a) a sysroot without `/lib` — on usrmerge images `/lib` is a symlink, and the
   `libc.so`/`libm.so` linker scripts name `/lib/aarch64-linux-gnu/…`; `./rfnm-sdk sysroot`
   now pulls/creates the `lib -> usr/lib` link, older sysroots need
   `ln -s usr/lib <sysroot>/lib`. (b) the cross gcc driver searches its own
   `/usr/aarch64-linux-gnu/lib` before the sysroot — `env.sh`/`imx8mp.cmake` now put
   `-L<sysroot>/usr/lib/aarch64-linux-gnu` first; a hand-rolled LDFLAGS must do the same.
   The host cross g++ (GCC 15) is newer than the board's libstdc++; linking against the
   sysroot's `libstdc++.so.6` makes a too-new `GLIBCXX_` symbol a hard link error instead
   of a board-side surprise. Prefer that over `-static-libstdc++` — librfnm itself uses
   the board's libstdc++. `-Wl,--trace` shows which libc/libm/libstdc++ the link used.

See `samples/` for a working cross-built librfnm client + Makefile.
