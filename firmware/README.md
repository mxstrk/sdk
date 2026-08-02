# Prebuilt firmware

- `vspa/apm-stock.eld`, `vspa/apm-fdx.eld` — LA9310 VSPA DSP images as shipped on
  production boards. Self-describing (`.rfnm_ident` ELF section: abi/caps/rank/hash —
  inspect with `../tools/eld_ident.py show <file>`); the kernel registers, checksums and
  capability-selects them at boot from /lib/firmware/rfnm/vspa/. Prebuilt because the VSPA
  toolchain is NXP-licensed; everything else in the SDK builds from source.
- `la9310.bin` — LA9310 M4 firmware reference copy (buildable from rfnm/la9310-freertos).
- `rfnm_m7_v0.elf` — i.MX8MP M7 firmware reference copy (buildable from rfnm/imx8mp-m7).
- `SHA256SUMS` — checksums of the above.

A VSPA image swap is: replace the file, one LA9310 hard reset (~1 s). See
skills/vspa-firmware/.
