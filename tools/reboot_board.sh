#!/bin/bash
# reboot_board.sh --board <name> [--check | --warm]
#
# Power-cycle an RFNM Blue board and wait until it is genuinely ready: sync the
# board over ssh, cycle power via the configured backend (boards.toml
# [board.<name>.power]), poll until ssh answers, then poll dmesg for the board's
# ready_marker.
#
# LAW: the ready_marker is THE readiness gate. Never add settle sleeps on top of
# this script — if readiness is flaky, fix the marker, not the sleep.
#
# --check: read-only plumbing test — PSU status + ssh probe, cycles nothing.
# --warm:  ssh `reboot` instead of a power cut (keeps PSU state; enough for
#          kernel/module swaps; use a hard cycle when the radio front-end or the
#          LA9310 is wedged).
set -u

TOOLS=$(cd "$(dirname "$0")" && pwd)
BOARDS="$TOOLS/rfnm_boards.py"
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH_POLL_TIMEOUT=120
DMESG_POLL_TIMEOUT=30

BOARD="" MODE=cycle
while [ $# -gt 0 ]; do
	case "$1" in
		--board) BOARD="${2:?--board needs a name}"; shift 2 ;;
		--check) MODE=check; shift ;;
		--warm)  MODE=warm; shift ;;
		*) echo "usage: reboot_board.sh --board <name> [--check|--warm]" >&2; exit 2 ;;
	esac
done
[ -n "$BOARD" ] || { echo "usage: reboot_board.sh --board <name> [--check|--warm]" >&2; exit 2; }

cfg()  { python3 "$BOARDS" get "$BOARD" "$@"; }        # cfg <field> [default]

IP=$(cfg ip) || exit 1
USER=$(cfg user root)
PASS=$(cfg password "")
KEY=$(cfg ssh_key "")
MARKER=$(cfg ready_marker "")
BACKEND=$(cfg power.backend manual)
OFF_SECS=$(cfg power.off_seconds 15)

board_ssh() {
	if [ -n "$KEY" ]; then
		timeout 10 ssh -i "${KEY/#\~/$HOME}" $SSH_OPTS "$USER@$IP" "$@" 2>/dev/null
	elif [ -n "$PASS" ] && command -v sshpass >/dev/null 2>&1; then
		timeout 10 sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$IP" "$@" 2>/dev/null
	else
		timeout 10 ssh -o BatchMode=yes $SSH_OPTS "$USER@$IP" "$@" 2>/dev/null
	fi
}

psu_args() {
	local addr chan
	addr=$(cfg power.address) || exit 1
	chan=$(cfg power.channel CH1)
	echo "--address $addr --channel $chan"
}

power_off() {
	case "$BACKEND" in
		manual)
			echo "[$BOARD] MANUAL power backend: cut the board's power now."
			read -r -p "[$BOARD] press Enter once power is OFF... " _ ;;
		rigol-dp832)        python3 "$TOOLS/psu_rigol_dp832.py" $(psu_args) off || exit 1 ;;
		siglent-spd1168x)   python3 "$TOOLS/psu_siglent_spd1168x.py" $(psu_args) off || exit 1 ;;
		shell)
			local c; c=$(cfg power.off_cmd) || exit 1
			bash -c "$c" || exit 1 ;;
		*) echo "[$BOARD] unknown power backend '$BACKEND'" >&2; exit 1 ;;
	esac
}

power_on() {
	local volts amps
	case "$BACKEND" in
		manual)
			read -r -p "[$BOARD] restore power, then press Enter... " _ ;;
		rigol-dp832)
			volts=$(cfg power.volts ""); amps=$(cfg power.amps "")
			[ -n "$volts" ] && [ -n "$amps" ] && python3 "$TOOLS/psu_rigol_dp832.py" $(psu_args) set "$volts" "$amps"
			python3 "$TOOLS/psu_rigol_dp832.py" $(psu_args) on || exit 1 ;;
		siglent-spd1168x)
			volts=$(cfg power.volts ""); amps=$(cfg power.amps "")
			[ -n "$volts" ] && [ -n "$amps" ] && python3 "$TOOLS/psu_siglent_spd1168x.py" $(psu_args) set "$volts" "$amps"
			python3 "$TOOLS/psu_siglent_spd1168x.py" $(psu_args) on || exit 1 ;;
		shell)
			local c; c=$(cfg power.on_cmd) || exit 1
			bash -c "$c" || exit 1 ;;
	esac
}

if [ "$MODE" = check ]; then
	case "$BACKEND" in
		rigol-dp832)      python3 "$TOOLS/psu_rigol_dp832.py" $(psu_args) status ;;
		siglent-spd1168x) python3 "$TOOLS/psu_siglent_spd1168x.py" $(psu_args) status ;;
		*)                echo "power backend: $BACKEND (no status query)" ;;
	esac
	if board_ssh true; then echo "ssh $USER@$IP: reachable"; else echo "ssh $USER@$IP: NOT reachable"; fi
	exit 0
fi

echo "[$BOARD] syncing filesystems..."
if board_ssh sync; then
	echo "[$BOARD] sync ok"
else
	echo "[$BOARD] WARNING: board unreachable, continuing anyway (unsynced)"
fi

T0=$(date +%s)

if [ "$MODE" = warm ]; then
	echo "[$BOARD] warm reboot over ssh"
	board_ssh reboot
	sleep 5
else
	echo "[$BOARD] power off (${OFF_SECS}s, backend $BACKEND)"
	power_off
	[ "$BACKEND" != manual ] && sleep "$OFF_SECS"
	echo "[$BOARD] power on"
	power_on
fi

echo "[$BOARD] polling ssh..."
while true; do
	board_ssh true && break
	if [ $(( $(date +%s) - T0 )) -ge $SSH_POLL_TIMEOUT ]; then
		echo "[$BOARD] ERROR: ssh not back after ${SSH_POLL_TIMEOUT}s — check the serial console" >&2
		exit 1
	fi
	sleep 2
done
echo "[$BOARD] ssh up after $(( $(date +%s) - T0 ))s"

if [ -n "$MARKER" ]; then
	DEADLINE=$(( $(date +%s) + DMESG_POLL_TIMEOUT ))
	while true; do
		if board_ssh "dmesg | grep -qi '$MARKER'"; then
			echo "[$BOARD] driver ready ('$MARKER') after $(( $(date +%s) - T0 ))s"
			break
		fi
		if [ "$(date +%s)" -ge "$DEADLINE" ]; then
			echo "[$BOARD] WARNING: '$MARKER' not in dmesg after ${DMESG_POLL_TIMEOUT}s extra — radio stack may not be up"
			break
		fi
		sleep 2
	done
fi

echo "[$BOARD] ready, total $(( $(date +%s) - T0 ))s"
