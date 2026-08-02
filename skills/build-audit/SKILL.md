---
name: build-audit
description: Provenance audit — verify every deployed board binary is byte-identical to a host-side build artifact and nothing x86 leaked onto the board rootfs.
---

# Build audit (provenance)

```bash
tools/build_audit.sh --board blue0
```

NFS-boot workflow only (the board rootfs must be visible on this host). Pure host-side,
no board contact.

## When

- After any deploy, before declaring the stack converged.
- When a board binary misbehaves and you need to know which source it came from.
- Whenever you suspect a binary on the board was built somewhere else (on-board compile,
  another machine, an older tree).

## Verdicts

- `PASS` — deployed binary is byte-identical to the mapped build artifact.
- `STALE` — the artifact exists but differs: either you built and forgot to deploy, or
  the source moved on since the deploy. Check git; redeploy or rebuild.
- `ALIEN` — no artifact to compare. Provenance unknown: rebuild from source via the
  cross-compile skill and redeploy so the binary has a traceable origin.
- `X86 BINARIES ON BOARD ROOTFS` — something built for the host leaked into a board bin
  dir. Always a bug; delete or replace with the aarch64 build.

## The map

The audit map pairs deployed paths (relative to the board rootfs) with build artifacts
(relative to the SDK root). Put it in boards.toml:

```toml
[audit]
"rfnm/apps/myapp/myappd" = "sources/myapp/build-imx8mp/myappd"
```

or in an `audit.map` sidecar next to boards.toml (`<deployed-path> <artifact-path>` per
line). Keep the map current as you add apps — an unmapped binary is an unaudited binary.
