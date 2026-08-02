---
name: nfs-boot-setup
description: Switch an RFNM Blue board to TFTP kernel + NFS rootfs served by the dev host — the fast developer loop (edit rootfs on the host, publish kernels by copying a file). Long form in docs/nfs-boot.md.
---

# NFS-boot developer workflow

Goal: the board boots a kernel from your TFTP server and mounts its rootfs over NFS from
your dev host. Then: deploying = writing files on the host; publishing a kernel = copying
`Image` into the TFTP dir; the rootfs doubles as your cross sysroot. Full walkthrough
with all commands: `docs/nfs-boot.md`.

## Host side (dev host, e.g. 192.168.1.2)

1. tftpd (e.g. `tftpd-hpa`) serving `host.tftp_root` (boards.toml). Per board, a subdir
   `<tftp_dir>` holds `Image` + `imx8mp-rfnm.dtb`.
2. NFS export of the rootfs dir (the boards.toml `rootfs` path), in `/etc/exports`:
   `rw,no_root_squash,no_subtree_check,async,insecure` — `insecure` is required
   (U-Boot/kernel NFS clients use high ports); `no_root_squash` because the board is root.
3. Rootfs content: clone the running board (`rsync -aHx` from `/` with /proc /sys /dev
   /run /tmp excluded) or unpack an RFNM OS image.
4. DHCP on the bench network, or static `ipaddr` in U-Boot.

## U-Boot side (over serial console, 115200 8N1)

The factory boot chain must STAY INTACT — you are adding a leaf next to it, and renaming
the old one so the way back is one `setenv`:

```
setenv rfnm_run_normal_boot_mmc "<paste the CURRENT rfnm_run_normal_boot value here>"
setenv rfnm_nfsroot 192.168.1.2:/srv/rfnm/blue0-rootfs,v3,tcp,nolock
setenv rfnm_run_nfs_boot 'setenv bootargs console=ttymxc1,115200 root=/dev/nfs rw nfsroot=${rfnm_nfsroot} ip=dhcp; tftp ${loadaddr} blue0/Image; tftp ${fdt_addr_r} blue0/imx8mp-rfnm.dtb; booti ${loadaddr} - ${fdt_addr_r};'
setenv rfnm_run_normal_boot 'run rfnm_run_nfs_boot;'
setenv serverip 192.168.1.2
setenv ipaddr 192.168.1.50
setenv bootdelay 3
saveenv
```

Going back to eMMC boot: `setenv rfnm_run_normal_boot 'run rfnm_run_normal_boot_mmc;'; saveenv`.

## The catch ritual (getting to the U-Boot prompt)

Factory `bootdelay=0` gives you ONE interrupt window per power-on. Start the catcher
BEFORE powering the board:

```bash
python3 tools/uboot_serial.py --port <console from boards.toml> --log /tmp/blue0-uboot.log catch
# ... power the board on (tools/reboot_board.sh --board blue0, or manually) ...
# "OK: at U-Boot prompt" → then:
python3 tools/uboot_serial.py --port <console> --log /tmp/blue0-uboot.log cmd "printenv"
```

Once `bootdelay=3` is saved, future catches are easy.

## The kernel-publish loop

```
build Image + dtb  →  cp into <tftp_root>/<tftp_dir>/  →  tools/reboot_board.sh --board <name>
```

No board-side install step, ever. The board picks up the new kernel on the next boot.

## Traps

- **dtb identity**: always copy `Image` + `imx8mp-rfnm.dtb` as a PAIR from your own kernel
  build. A kernel booted against a foreign dtb half-works in ways that waste days.
- **eMMC goes stale** the moment you switch: nothing you deploy to the NFS rootfs exists
  on eMMC. Booting back to eMMC later = time-traveling to the switch date. Plan for it.
- **fstab**: in the NFS rootfs, comment out the eMMC root-remount and swap lines — both
  are wrong under NFS root and can hang boot.
- **Cloned rootfs identity**: a rootfs cloned from another board needs a new
  `/etc/machine-id`, regenerated ssh host keys, and its own hostname.
- After every reboot, the ready_marker gate applies (reboot-board skill).
