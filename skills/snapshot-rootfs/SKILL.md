---
name: snapshot-rootfs
description: Snapshot a board's NFS rootfs tree (hardlink-incremental, automatic retention) before deploys or risky on-board experiments.
---

# Snapshot a board rootfs

NFS-boot workflow only (boards.toml `rootfs` must be set — the exported tree lives on
this host).

```bash
tools/snapshot_rootfs.sh --board blue0                 # plain snapshot
tools/snapshot_rootfs.sh --board blue0 pre-deploy      # tagged
tools/snapshot_rootfs.sh --board blue0 golden-keep     # 'keep' in the tag = never pruned
tools/snapshot_rootfs.sh --list
```

## When

- BEFORE any stack deploy (deploy-stack skill step 0).
- Before risky on-board experiments (driver hacking, apt operations, init changes).
- After reaching a known-good state you may want to return to (tag it `-keep`).

## How it works

Snapshots land in `<host.snapshot_root>/<board>/<UTC-stamp>[-tag]/` via
`rsync --link-dest` against the previous snapshot: unchanged files are hardlinks, so only
the first snapshot costs full size and later ones are near-free. Retention runs on every
invocation — the newest `host.snapshot_keep` survive; names containing `-keep` are never
pruned.

## Restore

```bash
# board powered off, or reboot it immediately after:
rsync -aHx --delete <snapshot_root>/blue0/<stamp>/ <rootfs>/
tools/reboot_board.sh --board blue0
```

Never restore under a live board without an immediate reboot — running daemons will
partially rewrite what you just restored.
