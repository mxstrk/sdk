# RFNM SDK skills

Agent skills for developing against RFNM Blue. Each directory holds one `SKILL.md`
(frontmatter: `name`, `description`; then the instructions). All tools they reference
live in `tools/` and read their board table from `boards.toml` at the SDK root.

| skill | what it covers |
|---|---|
| [cross-compile](cross-compile/SKILL.md) | Cross-building for the board (aarch64/A53) against the board rootfs sysroot; qemu selftest ritual; the trap list |
| [reboot-board](reboot-board/SKILL.md) | Warm vs hard reboots via `tools/reboot_board.sh`; the ready_marker-is-the-gate law |
| [nfs-boot-setup](nfs-boot-setup/SKILL.md) | Switching a board to TFTP kernel + NFS rootfs — the fast developer loop (long form: `docs/nfs-boot.md`) |
| [snapshot-rootfs](snapshot-rootfs/SKILL.md) | Hardlink-incremental rootfs snapshots before deploys/experiments; restore procedure |
| [build-audit](build-audit/SKILL.md) | Provenance audit: deployed binaries vs build artifacts; x86-leak sweep |
| [board-status](board-status/SKILL.md) | Read-only fleet survey: manifests, module/firmware md5s, source checkouts |
| [deploy-stack](deploy-stack/SKILL.md) | The deploy iron rules: deploy-together, rebuild consumers, one reboot, real acceptance gate, .prev backups (long form: `docs/deploy-rules.md`) |
| [first-session-laws](first-session-laws/SKILL.md) | Post-boot radio laws: throwaway session 1, RX before TX, no cold verdicts (long form: `docs/radio-bring-up-laws.md`) |
| [vspa-firmware](vspa-firmware/SKILL.md) | The prebuilt VSPA `.eld` firmware model: ident sections, boot registry, swap procedure |

Suggested reading order for a new setup: nfs-boot-setup → cross-compile → deploy-stack →
reboot-board → first-session-laws.
