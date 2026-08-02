#!/bin/bash
# board_status.sh [--board <name>] — READ-ONLY survey. Prints a compact report:
# local source checkouts (branch / HEAD / dirty count) and, per board, an ssh
# survey (uname, uptime, /rfnm/STACK_MANIFEST, librfnm .so, kernel module md5s,
# firmware md5s). Writes NOTHING — not on this host, not on the boards.
set -u

TOOLS=$(cd "$(dirname "$0")" && pwd)
BOARDS="$TOOLS/rfnm_boards.py"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

TOML=$(python3 "$BOARDS" path) || exit 1
SDK_ROOT=$(dirname "$TOML")

ONLY_BOARD=""
[ "${1:-}" = "--board" ] && ONLY_BOARD="${2:?--board needs a name}"

echo "=== BOARD STATUS $(date -u '+%Y-%m-%d %H:%M:%SZ') ==="
echo
echo "== source checkouts ($SDK_ROOT/sources) =="
if compgen -G "$SDK_ROOT/sources/*/" >/dev/null; then
	printf '%-28s %-16s %-10s %5s  %s\n' "repo" "branch" "HEAD" "dirty" "subject"
	for r in "$SDK_ROOT"/sources/*/; do
		r=${r%/}; name=$(basename "$r")
		if [ ! -e "$r/.git" ]; then
			printf '%-28s %s\n' "$name" "(not a git repo)"
			continue
		fi
		branch=$(git -C "$r" symbolic-ref --short -q HEAD || echo 'DETACHED')
		head=$(git -C "$r" rev-parse --short HEAD 2>/dev/null || echo '-')
		subject=$(git -C "$r" log -1 --format=%s 2>/dev/null | cut -c1-56)
		dirty=$(git -C "$r" status --porcelain 2>/dev/null | wc -l)
		printf '%-28s %-16s %-10s %5s  %s\n' "$name" "$branch" "$head" "$dirty" "$subject"
	done
else
	echo "(no sources/ checkouts yet)"
fi

survey() {
	local board=$1 ip user pass key
	ip=$(python3 "$BOARDS" get "$board" ip) || return 1
	user=$(python3 "$BOARDS" get "$board" user root)
	pass=$(python3 "$BOARDS" get "$board" password "")
	key=$(python3 "$BOARDS" get "$board" ssh_key "")
	echo
	echo "== board $board ($ip) =="
	local ssh_cmd=(ssh $SSH_OPTS "$user@$ip" 'bash -s')
	if [ -n "$key" ]; then
		ssh_cmd=(ssh -i "${key/#\~/$HOME}" $SSH_OPTS "$user@$ip" 'bash -s')
	elif [ -n "$pass" ] && command -v sshpass >/dev/null 2>&1; then
		ssh_cmd=(sshpass -p "$pass" ssh $SSH_OPTS "$user@$ip" 'bash -s')
	fi
	if ! "${ssh_cmd[@]}" 2>/dev/null <<'REMOTE'
echo "kernel:  $(uname -r)"
echo "uptime:  $(uptime | sed 's/^ *//')"
if [ -f /rfnm/STACK_MANIFEST ]; then
	echo "STACK_MANIFEST:"
	sed 's/^/  /' /rfnm/STACK_MANIFEST | head -12
else
	echo "STACK_MANIFEST: (none)"
fi
echo "librfnm (/usr/local/lib):"
so=$(ls -1 /usr/local/lib/librfnm.so* 2>/dev/null)
if [ -n "$so" ]; then echo "$so" | sed 's/^/  /'; else echo "  (none)"; fi
echo "kernel modules (/rfnm/kernel):"
md5sum /rfnm/kernel/*.ko 2>/dev/null | awk '{n=split($2,p,"/"); printf "  %-28s %.8s\n", p[n], $1}'
echo "firmware:"
for f in /lib/firmware/la9310.bin /lib/firmware/rfnm_m7_v0.elf /lib/firmware/rfnm/vspa/*.eld; do
	[ -f "$f" ] && echo "  $(basename "$f"): $(md5sum "$f" | cut -c1-8)"
done
exit 0
REMOTE
	then
		echo "UNREACHABLE (ssh, 5 s timeout)"
	fi
}

if [ -n "$ONLY_BOARD" ]; then
	survey "$ONLY_BOARD"
else
	python3 "$BOARDS" list | while read -r b; do
		survey "$b"
	done
fi
