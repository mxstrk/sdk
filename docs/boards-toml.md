# boards.toml reference

`boards.toml` at the SDK root is the single source of truth for every SDK tool. Copy
`boards.toml.example` there and edit. All scripts take `--board <name>` and resolve
fields through `tools/rfnm_boards.py`; nothing else hardcodes addresses or paths.

Resolution order for the file itself: `$RFNM_BOARDS_TOML`, then `./boards.toml`, then
`<sdk root>/boards.toml`. Shell access to any field:

```bash
python3 tools/rfnm_boards.py get blue0 ip            # 192.168.1.50
python3 tools/rfnm_boards.py get blue0 power.backend # dotted paths for subtables
python3 tools/rfnm_boards.py host tftp_root
python3 tools/rfnm_boards.py list
```

Missing file / board / field without a default = loud error, exit 1.

## [host]

| key | default | used by |
|---|---|---|
| `tftp_root` | `/srv/tftp` | NFS-boot workflow: TFTP server root; each board's `tftp_dir` is a subdir of it |
| `snapshot_root` | `/srv/rfnm/snapshots` | `snapshot_rootfs.sh`: where snapshots land |
| `snapshot_keep` | `6` | `snapshot_rootfs.sh`: retention (newest N; `-keep` names never pruned) |

## [board.<name>]

Core fields (every workflow):

| key | notes |
|---|---|
| `ip` | board address, e.g. `192.168.1.50` (required) |
| `user` | ssh user, default `root` |
| `password` | ssh password (factory default `rfnm`); used via sshpass when installed |
| `ssh_key` | alternative to `password`: path to a private key (takes precedence) |

NFS-boot developer workflow (all optional — leave empty if you don't use it):

| key | notes |
|---|---|
| `rootfs` | host path of the exported NFS rootfs; doubles as the cross sysroot (`cross/env.sh` falls back to the FIRST board with a non-empty rootfs) |
| `tftp_dir` | subdir of `host.tftp_root` holding `Image` + `imx8mp-rfnm.dtb` |
| `console` | serial console device, `/dev/serial/by-id/...` (FTDI, 115200 8N1) — for `uboot_serial.py` |
| `ready_marker` | dmesg line that gates radio readiness after reboot (see reboot-board skill). If your firmware's line differs, set what dmesg actually prints |

## [board.<name>.power]

Optional: lets `reboot_board.sh` do hard power-cycles for you.

| key | notes |
|---|---|
| `backend` | `manual` (default; script prompts you), `rigol-dp832`, `siglent-spd1168x`, or `shell` |
| `address` | SCPI `host[:port]` for the instrument backends (DP832 default port 5555, SPD1168X 5025) |
| `channel` | instrument channel, default `CH1` |
| `volts`, `amps` | setpoint re-asserted before power-on (instrument backends) |
| `off_seconds` | how long power stays cut. Default 15 — generous on purpose: shallow cycles can leave residual state in attached hardware that a firm zero clears |
| `off_cmd`, `on_cmd` | `backend = "shell"` only: arbitrary commands (e.g. a smart-plug CLI) |

PSU tools are also usable standalone:

```bash
python3 tools/psu_rigol_dp832.py --address 192.168.1.30 --channel CH2 status
python3 tools/psu_siglent_spd1168x.py --address 192.168.1.31 set 12.0 3.0
```

## [audit]

Optional map for `tools/build_audit.sh`: deployed path (relative to the board rootfs) =
build artifact (relative to the SDK root). TOML requires quoting keys containing `/`:

```toml
[audit]
"rfnm/apps/myapp/myappd" = "sources/myapp/build-imx8mp/myappd"
```

Alternative: an `audit.map` sidecar next to boards.toml, one `<deployed> <artifact>`
pair per line, `#` comments allowed.

## Multiple boards

Add more `[board.<name>]` tables. Order matters in one place only: the cross sysroot
fallback picks the FIRST board with a non-empty `rootfs`. Set `$RFNM_SYSROOT` explicitly
to override.
