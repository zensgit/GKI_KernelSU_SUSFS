# Xuanyuan Android 17 KernelSU Next 3.4.1 + SUSFS 2.3

This branch builds a kernel for Xiaomi 15 Ultra `xuanyuan_eea` running
`OS4.0.0.6.XOAEUXM`. It uses the exact Android 17 stock GKI source and embeds
that build's public module-signing certificate to preserve vendor-module trust.
The workflow does not flash the phone.

## Pinned inputs

- AOSP build: `15863337`, `android15-6.6-2026-01_r37`
- Android common: `c4127a25dcf3c8923daffa62632816f6acf0e135`
- Kernel build tools: `f71dbd37ecb1a45fadbcce80d1beeb5fb1833166`
- Kernel release: `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k`
- KernelSU Next: `v3.4.1`, `8f902aeb16033024143ae36cf711df902cf02fae`, version `33333`
- SUSFS: `v2.3.0`, `a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a`
- Manifest SHA-256: `b72b737069e5678b7cccf3c6bc5650f7dfec28e2c88d7da54b59432e1d63b0e7`

## Validation

Patch application is pinned and checked before application. The workflow retains
AOSP protected exports, strict ABI checks, module versions, 4 KiB pages, and
compiler error checks. Module.symvers and both ABI representations must exactly
match the published stock build. The stock module-signing certificate must be
embedded exactly once. No module-version or signature-check bypass is added.

The resulting Image must be packed into the Android 17 stock boot image and
verified with temporary fastboot boot before a permanent write to boot_a.
The stock Android 17 init_boot must remain in place for this built-in kernel;
do not combine it with a KernelSU LKM-patched init_boot.

Android common is GPL-2.0-only; KernelSU Next and SUSFS are GPL-3.0. This recipe
is for personal device testing; review licensing before redistributing binaries.
