# RFNM SDK — agent instructions

You are working inside the RFNM Blue SDK: everything that runs on an RFNM Blue SDR board
(kernel, LA9310 modules, M4/M7 firmware, librfnm, on-board daemons) is cloned under
`sources/` and cross-built from this directory. `./rfnm-sdk` is the entry point for
init/sysroot/build/deploy/status. The user's boards are described in `boards.toml`.

## Skills
Read the matching skill in `skills/` BEFORE doing any of these:
- building anything for the board → `skills/cross-compile/`
- rebooting or power-cycling a board → `skills/reboot-board/`
- setting up the edit-build-boot dev loop (TFTP kernel + NFS root) → `skills/nfs-boot-setup/`
- replacing kernel modules / firmware / librfnm on a board → `skills/deploy-stack/`
- backing up or restoring a board rootfs → `skills/snapshot-rootfs/`
- verifying what is actually running on a board → `skills/build-audit/`, `skills/board-status/`
- first radio session after boot, RX/TX bring-up → `skills/first-session-laws/`
- anything touching /lib/firmware/rfnm/vspa → `skills/vspa-firmware/`

## Hard rules
- Kernel modules + M4 firmware + VSPA .eld + librfnm are ONE deploy unit. Ship them from
  one build moment; a module built against a different kernel tree fails vermagic.
- After replacing librfnm, rebuild EVERY consumer (webgui daemons, vsgd, apps) before
  judging any behavior.
- Never compile on the board (4 slow cores, and the rootfs is the product). Cross-compile
  against `sysroot/current`, selftest under qemu-aarch64 when possible, then deploy.
- After any board reboot, wait for the ready marker in dmesg (see boards.toml
  `ready_marker`) before starting any radio client. Never replace the marker with sleeps.
- The first RX session after a boot is a throwaway warm-up; do not trust its metrics.
- Keep a `.prev` copy of every board binary you replace.
- TX safety: check `/rfnm/board.conf` `TX_ALLOWED` before transmitting; know which SMA your
  signal leaves. A receive path feeding an LNA must never see TX power.
- Sample-rate/channel/range validation lives device-side (driver/kernel/firmware), not in
  librfnm — do not add client-side compat shims.

## Layout
`sources/` component clones (see manifest.conf) · `sysroot/current` cross sysroot ·
`out/` build artifacts (boot/, modules/, firmware/, rootfs-overlay/) · `tools/` board
tooling · `docs/` the long-form guides · `firmware/` prebuilt VSPA images.
