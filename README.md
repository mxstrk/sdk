# RFNM SDK

The one-stop development kit for the **RFNM Blue** software-defined-radio motherboard
(i.MX8MP, 4× Cortex-A53) and its daughterboards (**Lime** — LMS7002M, **Yucca** — Metanoia
MT3812, **Breakout**, **Granita**). It clones every open-source component of the board
stack, cross-builds all of it with plain distro toolchains, and deploys onto your board.

```
git clone https://github.com/rfnm/sdk rfnm-sdk && cd rfnm-sdk
./rfnm-sdk init                 # host tool check + clone all components into sources/
cp boards.toml.example boards.toml    # describe your board (IP, login, optional PSU/console)
./rfnm-sdk sysroot blue0        # pull the cross sysroot from your own board over ssh
./rfnm-sdk build                # kernel, LA9310 modules, M4 + M7 firmware, librfnm, daemons, apps
./rfnm-sdk deploy blue0         # rsync the built stack onto the board
```

Host requirements (Debian/Ubuntu): `gcc-aarch64-linux-gnu gcc-arm-none-eabi cmake make git
rsync bison flex bc libssl-dev qemu-user-static sshpass`. No vendor toolchains: the Linux
side builds with the distro aarch64 GCC, the M4/M7 firmware with distro arm-none-eabi GCC.

## What's in the stack

| component (sources/) | repo | what it is |
|---|---|---|
| imx8mp-kernel | [rfnm/imx8mp-kernel](https://github.com/rfnm/imx8mp-kernel) | Linux 6.6.36 for RFNM Blue (`imx8mp_rfnm_defconfig`, `imx8mp-rfnm.dtb`) |
| la93xx_host_sw | [rfnm/la9310-driver](https://github.com/rfnm/la9310-driver) | LA9310 kernel modules: RF datapath, daughterboard drivers, QEC, AGC, scheduling |
| la93xx_freertos | [rfnm/la9310-freertos](https://github.com/rfnm/la9310-freertos) | LA9310 Cortex-M4 firmware (`la9310.bin`) |
| imx8mp-m7 | [rfnm/imx8mp-m7](https://github.com/rfnm/imx8mp-m7) | i.MX8MP Cortex-M7 front-end/GPIO firmware (`rfnm_m7_v0.elf`) |
| librfnm | [rfnm/librfnm](https://github.com/rfnm/librfnm) | the client library (v2 line, branch `dev-v2`) |
| vsg | [rfnm/vsg](https://github.com/rfnm/vsg) | vector signal generator: NEON DSP kernels + vsgd daemon |
| webgui | [rfnm/webgui](https://github.com/rfnm/webgui) | on-board web stack: spectrumd (RTSA), appd, ismmond, ddnsd, GUI, machine API |
| apps | [rfnm/apps](https://github.com/rfnm/apps) | on-board daemons: aisd, cellsyncd, clockgend, iod, lorad, vrtd + shared layer |
| diora-sdk-open-source | [rfnm/diora-sdk-open-source](https://github.com/rfnm/diora-sdk-open-source) | Metanoia MT3812 vendor SDK (BSD-3) — Yucca daughterboard dependency |
| mcux-sdk | [NXP](https://github.com/nxp-mcuxpresso/mcux-sdk) | MCUXpresso SDK @ MCUX_2.14.0 — M7 firmware dependency |

Plugins (opt-in, `./rfnm-sdk init --plugins`): [gr-rfnm](https://github.com/rfnm/gr-rfnm),
[soapy-rfnm](https://github.com/rfnm/soapy-rfnm), [matlab-rfnm](https://github.com/rfnm/matlab-rfnm),
[rfnmctl](https://github.com/rfnm/rfnmctl) (host-side Python API kit). Community integrations
(SDR++, SDRangel, SatDump, OpenWebRX, readsb, gnss-sdr) live in their upstream projects.

The VSPA DSP firmware ships **prebuilt** in `firmware/vspa/` (self-describing `.eld` images —
inspect with `tools/eld_ident.py show`); its source requires an NXP-licensed toolchain and is
not part of the SDK. The board's root filesystem is the stock Debian-based image from the
factory/updater — the SDK does not rebuild it, it builds everything that runs on top.

## Working on the board

- `boards.toml` describes your boards once; every tool and skill reads it.
- `tools/` — reboot (with pluggable programmable-PSU backends), U-Boot serial automation,
  rootfs snapshots, build provenance audit, board status.
- `docs/` — the NFS-boot developer workflow (TFTP kernel + NFS root: edit-build-boot without
  touching eMMC), deploy rules, radio bring-up laws, firmware landscape.
- `skills/` (mirrored in `.claude/skills/`) — instructions for coding agents (Claude Code
  and friends): cross-compile recipes with the full trap list, deploy rituals, first-session
  laws. Point your agent at `CLAUDE.md` and it knows the house rules.

## The iron rules (learned the hard way)

1. Kernel modules, M4 firmware, VSPA image and librfnm are **one deploy unit** — never mix
   build moments across them.
2. After replacing librfnm, **rebuild every consumer** (daemons and apps link it).
3. Cross-compile on the host against the board sysroot. Never compile on the board.
4. After any reboot: no radio use until the driver's ready marker appears in dmesg.
5. The first RX session after boot is a warm-up throwaway; don't judge timing or levels in it.

License: MPL-2.0 (RFNM-authored components); kernel/U-Boot GPL-2.0; NXP/vendor components
keep their own permissive licenses.
