# The firmware landscape

RFNM Blue is an i.MX8MP (4x Cortex-A53 running Linux, plus a Cortex-M7) carrying
LA9310-based daughterboards (Lime = LMS7002M, Yucca = Metanoia MT3812, Breakout,
Granita). The LA9310 itself contains a Cortex-M4 and a VSPA DSP. Four firmware/software
layers cooperate per board:

| layer | file on the rootfs | built from | runs on |
|---|---|---|---|
| M4 firmware | `/lib/firmware/la9310.bin` | `rfnm/la9310-freertos` | Cortex-M4 in the LA9310 |
| VSPA DSP firmware | `/lib/firmware/rfnm/vspa/*.eld` | prebuilt (shipped) | VSPA DSP in the LA9310 |
| M7 firmware | `/lib/firmware/rfnm_m7_v0.elf` | `rfnm/imx8mp-m7` | i.MX8MP Cortex-M7 |
| kernel modules | `/rfnm/kernel/*.ko` | `rfnm/la9310-driver` | Linux (A53) |

Plus userspace: `librfnm` (`/usr/local/lib/librfnm.so*`, headers in
`/usr/local/include/librfnm/`) — the client API everything streams through.

## Who loads what, when

- The kernel modules are loaded at boot (`/rfnm/scripts/load_drivers`). The LA9310
  driver loads `la9310.bin` into the M4 and boots it, then scans
  `/lib/firmware/rfnm/vspa/`, checksum-verifies each `.eld`, and registers it.
- VSPA images are **capability-selected per session**: each `.eld` self-describes via
  its `.rfnm_ident` section (ABI, capability bits, rank, name, githash, buildtime,
  checksum — `tools/eld_ident.py show` prints it; its docstring is the format contract).
  The driver picks a registered image matching the session's required caps; rank breaks
  ties.
- The M7 firmware is loaded via remoteproc for the low-latency control duties.
- The dmesg `ready_marker` (boards.toml) prints when daughterboard bring-up completed —
  that's the gate for starting any radio client (see docs/radio-bring-up-laws.md).

## What you build vs what you take prebuilt

- **You can rebuild**: kernel modules (`rfnm/la9310-driver`), M4 (`rfnm/la9310-freertos`),
  M7 (`rfnm/imx8mp-m7`), librfnm, and your own apps — all cross-compiled per the
  cross-compile skill.
- **Prebuilt only**: VSPA `.eld` files. The DSP toolchain is NXP-licensed and not part
  of the SDK. You inspect (`eld_ident.py show`), install, and swap the shipped images.

## Swap mechanics

- **VSPA `.eld`**: file replace + LA9310 hard reset (~1 s) — every endpoint re-probe
  re-reads the firmware files. A full board reboot also works and is always correct.
- **M4 / M7 / modules / librfnm**: stage files, then ONE board reboot
  (`tools/reboot_board.sh`), then the ready gate.

## The deploy-together rule (short form; long form docs/deploy-rules.md)

These layers speak private, unversioned protocols to each other. Any change that touches
an inter-layer interface ships all affected layers from one tree moment in one deploy.
Kernel modules additionally carry vermagic — modules and the running kernel must come
from the same kernel build. After any librfnm change, rebuild every consumer.

## STACK_MANIFEST

`/rfnm/STACK_MANIFEST` on each board records what the last deploy shipped: date, git sha
+ artifact md5 per layer, why, who. Read it first when a board misbehaves; write it as
the last step of every deploy; `tools/board_status.sh` prints it fleet-wide next to the
actual on-board md5s so a stale manifest is caught immediately.

```bash
ssh root@192.168.1.50 cat /rfnm/STACK_MANIFEST
python3 tools/eld_ident.py show <rootfs>/lib/firmware/rfnm/vspa/<name>.eld
```
