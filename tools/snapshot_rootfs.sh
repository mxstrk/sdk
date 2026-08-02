#!/bin/bash
# snapshot_rootfs.sh — hardlink-incremental snapshots of a board's NFS rootfs tree.
#
#   snapshot_rootfs.sh --board <name> [tag]     # snapshot that board's rootfs
#   snapshot_rootfs.sh --list                   # list snapshots for all boards
#
# Requires the NFS-boot developer workflow: [board.<name>] rootfs must point at
# the host-side exported rootfs. Snapshots land in
# <host.snapshot_root>/<board>/<UTC-stamp>[-tag]/ using rsync --link-dest against
# the previous snapshot: unchanged files are hardlinks (near-free), so only the
# first snapshot costs full size. Retention runs on every invocation: keep the
# newest <host.snapshot_keep>; snapshots whose name contains "-keep" are never
# pruned. Restore = rsync the snapshot back over the exported tree (board
# powered off, or rebooted immediately afterwards).
set -u

TOOLS=$(cd "$(dirname "$0")" && pwd)
BOARDS="$TOOLS/rfnm_boards.py"
LOCK=/tmp/rfnm_snapshot_rootfs.lock

ROOT=$(python3 "$BOARDS" host snapshot_root /srv/rfnm/snapshots) || exit 1
KEEP=$(python3 "$BOARDS" host snapshot_keep 6) || exit 1

usage() { echo "usage: $0 --board <name> [tag] | --list   (tag containing 'keep' pins the snapshot)" >&2; exit 2; }

snap_one() {
	local board=$1 tag=${2:-}
	local src dst_root stamp dst latest
	src=$(python3 "$BOARDS" get "$board" rootfs "") || exit 1
	[ -n "$src" ] || { echo "[$board] no rootfs configured in boards.toml — snapshots need the NFS-boot workflow" >&2; return 1; }
	[ -d "$src" ] || { echo "[$board] rootfs '$src' does not exist on this host" >&2; return 1; }
	dst_root=$ROOT/$board
	stamp=$(date -u +%Y%m%d-%H%M%S)${tag:+-$tag}
	dst=$dst_root/$stamp
	mkdir -p "$dst_root"
	latest=$(ls -1d "$dst_root"/2* 2>/dev/null | tail -1)
	echo "[$board] snapshot -> $dst ${latest:+(link-dest $(basename "$latest"))}"
	rsync -aHx --delete \
		--exclude=/proc/ --exclude=/sys/ --exclude=/dev/ --exclude=/run/ \
		--exclude=/tmp/ --exclude=/var/tmp/ --exclude=/var/log/journal/ \
		--exclude=/var/cache/ \
		${latest:+--link-dest="$latest"} \
		"$src"/ "$dst"/ || { echo "[$board] rsync FAILED (rc=$?)"; rm -rf "$dst"; return 1; }
	echo "[$board] done: $(du -sh "$dst" 2>/dev/null | cut -f1) apparent, $(df -h "$ROOT" | awk 'NR==2{print $4}') free"

	# retention: newest $KEEP survive; "-keep" names always survive
	local prunable p
	prunable=$(ls -1d "$dst_root"/2* 2>/dev/null | grep -v -- '-keep' | head -n -"$KEEP")
	for p in $prunable; do
		echo "[$board] prune $(basename "$p")"
		rm -rf "$p"
	done
}

case "${1:-}" in
	--list)
		python3 "$BOARDS" list | while read -r b; do
			echo "== $b =="
			ls -1d "$ROOT/$b"/2* 2>/dev/null | while read -r d; do
				printf "  %s  %s\n" "$(basename "$d")" "$(du -sh "$d" 2>/dev/null | cut -f1)"
			done
		done
		exit 0 ;;
	--board)
		BOARD="${2:-}"; TAG="${3:-}"
		[ -n "$BOARD" ] || usage ;;
	*)
		usage ;;
esac

exec 9>"$LOCK"
flock -n 9 || { echo "another snapshot is running"; exit 1; }

snap_one "$BOARD" "$TAG"
