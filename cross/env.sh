# imx8mp cross-compile env — source this for Makefile-based builds:  . cross/env.sh
# Target: RFNM Blue (i.MX8MP, 4x Cortex-A53, aarch64/NEON).
# Sysroot: $RFNM_SYSROOT if set, else the first boards.toml board with a rootfs.
# The sysroot IS a copy of the board's own rootfs — fetch it with `./rfnm-sdk sysroot <board>`.

_rfnm_sdk_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

if [ -z "${RFNM_SYSROOT:-}" ] && [ -e "$_rfnm_sdk_root/sysroot/current" ]; then
	RFNM_SYSROOT="$_rfnm_sdk_root/sysroot/current"    # what `./rfnm-sdk sysroot <board>` produced
fi
if [ -z "${RFNM_SYSROOT:-}" ]; then
	RFNM_SYSROOT="$(python3 "$_rfnm_sdk_root/tools/rfnm_boards.py" first-rootfs 2>/dev/null)"
fi
if [ -z "${RFNM_SYSROOT:-}" ] || [ ! -d "${RFNM_SYSROOT}" ]; then
	echo "cross/env.sh: no sysroot. Set RFNM_SYSROOT, or configure [board.<name>] rootfs in boards.toml" >&2
	echo "cross/env.sh: hint: fetch the board's rootfs with:  ./rfnm-sdk sysroot <board>" >&2
	return 1 2>/dev/null || exit 1
fi

export RFNM_SYSROOT
export CROSS_TRIPLE=aarch64-linux-gnu

# -isystem: Debian cross gcc does NOT search ${sysroot}/usr/local/include (a native gcc would),
# and the board installs librfnm etc. to /usr/local — without this they are invisible.
export CC="${CROSS_TRIPLE}-gcc --sysroot=${RFNM_SYSROOT} -isystem ${RFNM_SYSROOT}/usr/local/include"
export CXX="${CROSS_TRIPLE}-g++ --sysroot=${RFNM_SYSROOT} -isystem ${RFNM_SYSROOT}/usr/local/include"
export AR="${CROSS_TRIPLE}-ar"
export RANLIB="${CROSS_TRIPLE}-ranlib"
export STRIP="${CROSS_TRIPLE}-strip"
export OBJCOPY="${CROSS_TRIPLE}-objcopy"

# A53+NEON always-on baseline; apps stack their own -O3/-ffast-math/etc on top.
export ARCHFLAGS="-mcpu=cortex-a53"
# The sysroot's own lib dirs go FIRST: the cross gcc driver otherwise searches its own
# /usr/aarch64-linux-gnu/lib (the host's, usually newer glibc + libstdc++) before the
# sysroot, and the binary then dies on the board with "GLIBC_2.xx not found".
export CROSS_LDFLAGS="-L${RFNM_SYSROOT}/usr/lib/aarch64-linux-gnu -L${RFNM_SYSROOT}/lib/aarch64-linux-gnu -L${RFNM_SYSROOT}/usr/local/lib -Wl,-rpath-link,${RFNM_SYSROOT}/usr/lib/aarch64-linux-gnu:${RFNM_SYSROOT}/lib/aarch64-linux-gnu:${RFNM_SYSROOT}/usr/local/lib"

# pkg-config confined to the sysroot — host .pc files must never leak into an aarch64 link.
export PKG_CONFIG_SYSROOT_DIR="${RFNM_SYSROOT}"
export PKG_CONFIG_LIBDIR="${RFNM_SYSROOT}/usr/local/lib/pkgconfig:${RFNM_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:${RFNM_SYSROOT}/usr/lib/pkgconfig:${RFNM_SYSROOT}/usr/share/pkgconfig"
unset PKG_CONFIG_PATH

unset _rfnm_sdk_root
