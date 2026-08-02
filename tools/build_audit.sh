#!/bin/bash
# build_audit.sh --board <name> — provenance audit: does every DEPLOYED board binary
# match a build artifact on this host? Catches the classic drift class: a binary on
# the board that matches no host-side build product, so nobody can say what source
# it came from.
#
# Verdicts:
#   PASS  = deployed binary is byte-identical to the mapped artifact
#   STALE = artifact exists but differs (pending deploy OR the source moved on — check git)
#   ALIEN = no artifact to compare (provenance unknown — rebuild via the cross-compile skill)
#
# The audit map lives in boards.toml under [audit] ("deployed/path" = "artifact/path"),
# or in an audit.map sidecar next to boards.toml (lines: <deployed-path> <artifact-path>).
# Deployed paths are relative to the board rootfs; artifact paths relative to the SDK root.
# Requires the NFS-boot workflow (board rootfs visible on this host); pure host-side.
set -u

TOOLS=$(cd "$(dirname "$0")" && pwd)
BOARDS="$TOOLS/rfnm_boards.py"

[ "${1:-}" = "--board" ] && [ -n "${2:-}" ] || { echo "usage: $0 --board <name>" >&2; exit 2; }
BOARD=$2

ROOTFS=$(python3 "$BOARDS" get "$BOARD" rootfs "") || exit 1
[ -n "$ROOTFS" ] || { echo "[$BOARD] no rootfs in boards.toml — the audit needs the NFS-boot workflow" >&2; exit 1; }
[ -d "$ROOTFS" ] || { echo "[$BOARD] rootfs '$ROOTFS' does not exist on this host" >&2; exit 1; }

TOML=$(python3 "$BOARDS" path) || exit 1
SDK_ROOT=$(dirname "$TOML")

# audit map: [audit] table first, audit.map sidecar as fallback
MAP=$(python3 "$BOARDS" audit)
if [ -z "$MAP" ] && [ -f "$SDK_ROOT/audit.map" ]; then
	MAP=$(grep -vE '^\s*(#|$)' "$SDK_ROOT/audit.map" | awk '{print $1 "\t" $2}')
fi
[ -n "$MAP" ] || { echo "no audit map: add an [audit] table to boards.toml or an audit.map file (see boards.toml.example)" >&2; exit 1; }

rc=0
echo "== $BOARD ($ROOTFS) =="
while IFS=$'\t' read -r dep art; do
	[ -n "$dep" ] || continue
	d="$ROOTFS/$dep"
	case "$art" in /*) r="$art" ;; *) r="$SDK_ROOT/$art" ;; esac
	# tolerate layout drift: fall back to a basename search under rfnm/
	[ -f "$d" ] || d=$(find "$ROOTFS/rfnm" -maxdepth 3 -name "$(basename "$dep")" -type f 2>/dev/null | head -1)
	[ -n "$d" ] && [ -f "$d" ] || { echo "  -     $dep (not deployed here)"; continue; }
	if [ ! -f "$r" ]; then
		echo "  ALIEN $dep — no build artifact at $r"; rc=1; continue
	fi
	if cmp -s "$d" "$r"; then
		echo "  PASS  $dep"
	else
		echo "  STALE $dep — differs from $r ($(stat -c '%y' "$d" | cut -d. -f1) vs $(stat -c '%y' "$r" | cut -d. -f1))"
		rc=1
	fi
done <<< "$MAP"

# arch sweep: nothing x86 may live under the board's rfnm/ bin dirs
bad=$(find "$ROOTFS/rfnm" -maxdepth 3 -type f -perm -111 \( -path '*/bin/*' -o -path '*/apps/*' \) 2>/dev/null \
	| while read -r f; do file -b "$f" | grep -q 'x86-64' && echo "$f"; done)
if [ -n "$bad" ]; then
	echo "  X86 BINARIES ON BOARD ROOTFS:"
	echo "$bad" | sed 's/^/    /'
	rc=1
fi
exit $rc
