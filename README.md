# Xuanyuan TW302 GKI + KernelSU Next + SUSFS

This branch builds a single, device-matched test kernel for Xiaomi `xuanyuan`
running `OS3.0.302.0.WOATWXM`. It does not flash a phone and does not modify
the repository default branch.

## Reproducibility pins

- AOSP GKI build: `15511674`
- Android common: `e56cf6b09cca2151bcee244b3d334fb68685ff57`
- Kernel: `6.6.118`, `android15-8`, 4 KiB pages
- KernelSU Next: `v3.3.0`, commit `3b18216f71df189ab3d1b1ce0bdb21be1268e771`, version `33214`
- SUSFS: `v2.2.0`, commit `e7b28525f69ca5864bed7db51f77663f5adfe218`
- KernelSU Next compatibility fixes: `WildKernels/kernel_patches@757201d983e2549dc7945a21fa6a056eb2e55263`

The checked-in AOSP manifest is the exact manifest published for build
`15511674`; its SHA-256 is
`dbaa1ca849500f4e0cc421beb8b431eb957905379a1a1f9d6b0bfd7d6b5fb1c3`.

## Safety gates

The workflow keeps AOSP protected exports, strict KMI checks,
`CONFIG_MODVERSIONS`, `android15-8`, and 4 KiB pages. It does not add module
version bypasses, manual hooks, BBG, networking tweaks, or Wild branding.
Patch application is pinned and fail-closed. The six expected KernelSU Next
conflicts are resolved in a temporary staging tree, converted into one clean
patch, hash-checked, and then applied to the real build tree with
`git apply --check`.

A successful run uploads only validated build artifacts. The resulting Image
still requires local stock-boot repacking and a temporary `fastboot boot`
test before any persistent flash.

The phone currently has a KernelSU Next LKM-patched `init_boot_b`. Restore the
saved stock `init_boot_b` before testing this built-in KernelSU Image; otherwise
the built-in kernel and LKM may load together. `CONFIG_KSU_SUSFS_ENABLE_LOG=y`
is intentional for the first diagnostic boot and should be disabled for a
later long-term build after runtime validation.

## License boundary

Android common is GPL-2.0-only; KernelSU Next and SUSFS are GPL-3.0. The six
third-party compatibility patches are pinned for personal testing, but their
source repository currently has no declared license. Do not redistribute a
resulting binary without reviewing that licensing boundary.
