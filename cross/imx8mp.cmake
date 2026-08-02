# CMake toolchain file — RFNM Blue (i.MX8MP, 4x Cortex-A53, aarch64/NEON)
# Usage: cmake -S . -B build-imx8mp -DCMAKE_TOOLCHAIN_FILE=<sdk>/cross/imx8mp.cmake
# Sysroot: $RFNM_SYSROOT if set, else the first boards.toml board with a rootfs.
# The sysroot IS a copy of the board's own rootfs — fetch it with `./rfnm-sdk sysroot <board>`.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

if(DEFINED ENV{RFNM_SYSROOT})
	set(CMAKE_SYSROOT $ENV{RFNM_SYSROOT})
else()
	execute_process(
		COMMAND python3 ${CMAKE_CURRENT_LIST_DIR}/../tools/rfnm_boards.py first-rootfs
		OUTPUT_VARIABLE _rfnm_sysroot
		OUTPUT_STRIP_TRAILING_WHITESPACE
		RESULT_VARIABLE _rfnm_rc
		ERROR_QUIET)
	if(_rfnm_rc EQUAL 0 AND IS_DIRECTORY "${_rfnm_sysroot}")
		set(CMAKE_SYSROOT ${_rfnm_sysroot})
	else()
		message(FATAL_ERROR "No sysroot: set RFNM_SYSROOT or configure [board.<name>] rootfs in boards.toml. Hint: fetch one with `./rfnm-sdk sysroot <board>`.")
	endif()
endif()

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_ASM_COMPILER aarch64-linux-gnu-gcc)

# A53 + NEON always; per-project flags stack on top of these.
# -isystem: Debian cross gcc does NOT search ${sysroot}/usr/local/include (a native gcc would),
# and the board installs librfnm etc. to /usr/local — without this they are invisible.
set(CMAKE_C_FLAGS_INIT "-mcpu=cortex-a53 -isystem ${CMAKE_SYSROOT}/usr/local/include")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a53 -isystem ${CMAKE_SYSROOT}/usr/local/include")

# Transitive shared-lib resolution inside the sysroot (rootfs paths, not host paths);
# -L /usr/local/lib for the same Debian-cross-gcc gap as the -isystem above.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L${CMAKE_SYSROOT}/usr/local/lib -Wl,-rpath-link,${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu:${CMAKE_SYSROOT}/lib/aarch64-linux-gnu:${CMAKE_SYSROOT}/usr/local/lib")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${CMAKE_EXE_LINKER_FLAGS_INIT}")

# Search ONLY the sysroot for libs/headers/packages; host stays for build programs.
set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT}/usr/local ${CMAKE_SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# pkg-config must resolve inside the sysroot (host .pc leakage = x86 libs in an aarch64 link).
set(ENV{PKG_CONFIG_DIR} "")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CMAKE_SYSROOT}")
set(ENV{PKG_CONFIG_LIBDIR} "${CMAKE_SYSROOT}/usr/local/lib/pkgconfig:${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:${CMAKE_SYSROOT}/usr/lib/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig")

if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()
