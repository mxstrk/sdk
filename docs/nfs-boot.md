# NFS-boot developer workflow

The single biggest quality-of-life upgrade for RFNM Blue development: the board boots its
kernel over TFTP and mounts its rootfs over NFS, both served by your dev host. After the
switch:

- Deploying anything = writing a file on your host. No scp loops, no eMMC writes.
- Publishing a kernel = `cp Image <tftp_dir>/` + reboot. No board-side install, ever.
- The exported rootfs doubles as your cross-compile sysroot (`cross/env.sh`).
- Rootfs snapshots/restores become host-side rsync operations (`tools/snapshot_rootfs.sh`).

Throughout: dev host `192.168.1.2`, board `192.168.1.50`, board name `blue0`. Adjust to
your boards.toml.

## 1. Host side

### TFTP

Install a TFTP server (e.g. `tftpd-hpa`) serving `host.tftp_root` from boards.toml
(default `/srv/tftp`). Each board gets a subdir — the boards.toml `tftp_dir`:

```
/srv/tftp/blue0/Image
/srv/tftp/blue0/imx8mp-rfnm.dtb
```

### Rootfs

Pick a host path and record it as `rootfs` in boards.toml, e.g.
`/srv/rfnm/blue0-rootfs`. Populate it by cloning the running board:

```bash
mkdir -p /srv/rfnm/blue0-rootfs
rsync -aHxAX --numeric-ids \
    --exclude=/proc/ --exclude=/sys/ --exclude=/dev/ --exclude=/run/ --exclude=/tmp/ \
    root@192.168.1.50:/ /srv/rfnm/blue0-rootfs/
mkdir -p /srv/rfnm/blue0-rootfs/{proc,sys,dev,run,tmp}
```

(or unpack an RFNM OS image). Then fix the tree for NFS root:

- **fstab**: comment out the eMMC root-remount line and any swap line in `etc/fstab` —
  both are wrong under NFS root and can hang boot. `/tmp` stays tmpfs.
- **Identity** (only if cloned from a different board than the one that will boot it):
  fresh `etc/machine-id` (empty file, regenerates on boot), delete `etc/ssh/ssh_host_*`
  (regenerate on boot or via `ssh-keygen -A`), set `etc/hostname`.

### NFS export

In `/etc/exports`:

```
/srv/rfnm/blue0-rootfs 192.168.1.0/24(rw,no_root_squash,no_subtree_check,async,insecure)
```

`exportfs -ra`. Flags matter: `insecure` because U-Boot and kernel NFS clients come from
high ports; `no_root_squash` because the board genuinely is root in its own rootfs.

### Addressing

Run DHCP on the bench network (the boot command below uses `ip=dhcp`), or use static
`ipaddr`/`serverip` U-Boot variables only.

## 2. U-Boot side

You need the serial console (`console` in boards.toml, FTDI at 115200 8N1).

### The catch ritual

The factory environment has `bootdelay=0`: exactly ONE autoboot-interrupt window per
power-on, a fraction of a second wide. Do not try to catch it by hand — start the
catcher FIRST, then power on:

```bash
python3 tools/uboot_serial.py --port /dev/serial/by-id/<your-ftdi> \
    --log /tmp/blue0-uboot.log catch &
tools/reboot_board.sh --board blue0        # or power on manually
```

`catch` waits for the U-Boot banner and hammers interrupt characters until it lands at
the prompt, then prints `OK: at U-Boot prompt`. From there use `cmd`:

```bash
python3 tools/uboot_serial.py --port <port> --log /tmp/blue0-uboot.log cmd "printenv"
```

### Environment changes

**Keep the factory boot chain intact.** The pattern: save the factory leaf under an
`_mmc` name, add an NFS leaf, repoint the chain head. The way back is then one `setenv`.

First `printenv rfnm_run_normal_boot` and copy its current value. Then:

```
setenv rfnm_run_normal_boot_mmc "<the value you just copied>"
setenv rfnm_nfsroot 192.168.1.2:/srv/rfnm/blue0-rootfs,v3,tcp,nolock
setenv rfnm_run_nfs_boot 'setenv bootargs console=ttymxc1,115200 root=/dev/nfs rw nfsroot=${rfnm_nfsroot} ip=dhcp; tftp ${loadaddr} blue0/Image; tftp ${fdt_addr_r} blue0/imx8mp-rfnm.dtb; booti ${loadaddr} - ${fdt_addr_r};'
setenv rfnm_run_normal_boot 'run rfnm_run_nfs_boot;'
setenv serverip 192.168.1.2
setenv ipaddr 192.168.1.50
setenv bootdelay 3
saveenv
boot
```

`bootdelay=3` means every future boot has a comfortable interrupt window — the catch
ritual is only ever hard once.

Back to factory eMMC boot at any time:

```
setenv rfnm_run_normal_boot 'run rfnm_run_normal_boot_mmc;'
saveenv
```

### Verify

After boot, on the board:

```bash
cat /proc/cmdline        # root=/dev/nfs ... nfsroot=192.168.1.2:/srv/rfnm/blue0-rootfs
mount | grep ' / '       # / type nfs
```

## 3. The kernel-publish loop

Build your kernel, then:

```bash
cp arch/arm64/boot/Image /srv/tftp/blue0/Image
cp arch/arm64/boot/dts/freescale/imx8mp-rfnm.dtb /srv/tftp/blue0/imx8mp-rfnm.dtb
sync
tools/reboot_board.sh --board blue0
```

That's the whole deploy. Kernel modules go into the exported rootfs (they must come from
the same kernel build — vermagic).

## 4. Traps

- **dtb identity**: always copy `Image` + `imx8mp-rfnm.dtb` as a PAIR from the same
  build. A kernel booted against a mismatched dtb produces subtle half-working hardware
  — the most expensive class of debugging there is.
- **eMMC goes stale**: from the switch onward, nothing you deploy exists on eMMC.
  Booting back to eMMC is a time-travel to the switch date — fine for recovery, but
  don't mix observations from the two worlds.
- **fstab**, **machine-id / ssh host keys / hostname**: see the rootfs preparation
  above; each omission costs a confusing boot or an ssh identity collision.
- **NFS attribute caching**: the board may take a few seconds to see a freshly copied
  binary as executable. Wait, don't debug.
- **The exported rootfs is LIVE**: writing into it while the board runs is an in-place
  deploy of a running system. For anything beyond copying one app binary, snapshot first
  (`tools/snapshot_rootfs.sh`) and follow the deploy rules (`docs/deploy-rules.md`).
