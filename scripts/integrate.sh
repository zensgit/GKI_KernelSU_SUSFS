#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <kernel-root> <recipe-root>" >&2
  exit 2
fi

KERNEL_ROOT=$(realpath "$1")
RECIPE_ROOT=$(realpath "$2")
COMMON_DIR="$KERNEL_ROOT/common"
KSU_DIR="$KERNEL_ROOT/KernelSU-Next"
SUSFS_DIR="$KERNEL_ROOT/susfs4ksu"
FIX_DIR="$KERNEL_ROOT/kernel_patches"

COMMON_SHA=e56cf6b09cca2151bcee244b3d334fb68685ff57
KSU_SHA=3b18216f71df189ab3d1b1ce0bdb21be1268e771
SUSFS_SHA=e7b28525f69ca5864bed7db51f77663f5adfe218
FIX_SHA=757201d983e2549dc7945a21fa6a056eb2e55263
KSU_COMBINED_SHA256=944509d27414c9c9c4e728fa17aad447fda4ccd9c50474ee7ce28b6cce5a1476
KERNEL_COMBINED_SHA256=b21dd46c037ae5f68c8c0d4a36c73dfd4f686cb704190a49f6f579402625fc9c

test "$(git -C "$COMMON_DIR" rev-parse HEAD)" = "$COMMON_SHA"
test -z "$(git -C "$COMMON_DIR" status --porcelain)"

git clone --filter=blob:none https://github.com/KernelSU-Next/KernelSU-Next.git "$KSU_DIR"
git -C "$KSU_DIR" checkout --detach "$KSU_SHA"
test "$(git -C "$KSU_DIR" rev-parse HEAD)" = "$KSU_SHA"
test "$(git -C "$KSU_DIR" rev-list --count HEAD)" = 3214

git clone --filter=blob:none --no-checkout https://gitlab.com/simonpunk/susfs4ksu.git "$SUSFS_DIR"
git -C "$SUSFS_DIR" checkout --detach "$SUSFS_SHA"
test "$(git -C "$SUSFS_DIR" rev-parse HEAD)" = "$SUSFS_SHA"
grep -qx 'version=v2.2.0' "$SUSFS_DIR/ksu_module_susfs/module.prop"

git clone --filter=blob:none --no-checkout https://github.com/WildKernels/kernel_patches.git "$FIX_DIR"
git -C "$FIX_DIR" checkout --detach "$FIX_SHA"
test "$(git -C "$FIX_DIR" rev-parse HEAD)" = "$FIX_SHA"

stage_ksu=$(mktemp -d)
rmdir "$stage_ksu"
git -C "$KSU_DIR" worktree add --detach "$stage_ksu" "$KSU_SHA"

set +e
patch --batch --forward -d "$stage_ksu" -p1 \
  < "$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
raw_ksu_rc=$?
set -e
test "$raw_ksu_rc" -eq 1

expected_rejects=$(printf '%s\n' \
  kernel/Kbuild.rej \
  kernel/core/init.c.rej \
  kernel/feature/kernel_umount.c.rej \
  kernel/feature/sucompat.c.rej \
  kernel/hook/setuid_hook.c.rej \
  kernel/supercall/supercall.c.rej)
actual_rejects=$(find "$stage_ksu/kernel" -type f -name '*.rej' -print \
  | sed "s|$stage_ksu/||" | LC_ALL=C sort)
test "$actual_rejects" = "$expected_rejects"

fix_patch_dir="$FIX_DIR/next/susfs_fix_patches/stable/v2.2.0"
for fix_patch in \
  fix_Kbuild.patch \
  fix_init.c.patch \
  fix_kernel_umount.c.patch \
  fix_setuid_hook.c.patch \
  fix_sucompat.c.patch \
  fix_supercall.c.patch; do
  patch --dry-run --batch --forward --no-backup-if-mismatch \
    -d "$stage_ksu" -p1 < "$fix_patch_dir/$fix_patch"
  patch --batch --forward --no-backup-if-mismatch \
    -d "$stage_ksu" -p1 < "$fix_patch_dir/$fix_patch"
done

find "$stage_ksu/kernel" -type f \( -name '*.rej' -o -name '*.orig' \) -delete
ksu_combined=$(mktemp)
git -C "$stage_ksu" diff --binary -- kernel > "$ksu_combined"
test "$(git -C "$stage_ksu" diff --name-only -- kernel | wc -l | tr -d ' ')" = 28
echo "$KSU_COMBINED_SHA256  $ksu_combined" | sha256sum -c -
git -C "$KSU_DIR" apply --check "$ksu_combined"
git -C "$KSU_DIR" apply "$ksu_combined"
test -z "$(find "$KSU_DIR/kernel" -type f \( -name '*.rej' -o -name '*.orig' \) -print)"
git -C "$KSU_DIR" worktree remove --force "$stage_ksu"
rm -f "$ksu_combined"

stage_common=$(mktemp -d)
rmdir "$stage_common"
git -C "$COMMON_DIR" worktree add --detach "$stage_common" "$COMMON_SHA"
install -m 0644 "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$stage_common/fs/susfs.c"
install -m 0644 "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" "$stage_common/include/linux/susfs.h"
install -m 0644 "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$stage_common/include/linux/susfs_def.h"
patch --dry-run --batch --forward --no-backup-if-mismatch \
  -d "$stage_common" -p1 \
  < "$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
patch --batch --forward --no-backup-if-mismatch \
  -d "$stage_common" -p1 \
  < "$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
test -z "$(find "$stage_common" -type f \( -name '*.rej' -o -name '*.orig' \) -print)"
test "$(git -C "$stage_common" status --porcelain | wc -l | tr -d ' ')" = 27
git -C "$stage_common" add -N \
  fs/susfs.c \
  include/linux/susfs.h \
  include/linux/susfs_def.h
kernel_combined=$(mktemp)
git -C "$stage_common" diff --binary > "$kernel_combined"
kernel_combined_sha=$(sha256sum "$kernel_combined" | awk '{print $1}')
echo "Rebased Android common SUSFS patch: $kernel_combined_sha"
echo "$KERNEL_COMBINED_SHA256  $kernel_combined" | sha256sum -c -
git -C "$COMMON_DIR" apply --check "$kernel_combined"
git -C "$COMMON_DIR" apply "$kernel_combined"
git -C "$COMMON_DIR" worktree remove --force "$stage_common"
rm -f "$kernel_combined"

ln -s ../../KernelSU-Next/kernel "$COMMON_DIR/drivers/kernelsu"
# shellcheck disable=SC2016
grep -qF 'obj-$(CONFIG_KSU) += kernelsu/' "$COMMON_DIR/drivers/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$COMMON_DIR/drivers/Makefile"
grep -qF 'source "drivers/kernelsu/Kconfig"' "$COMMON_DIR/drivers/Kconfig" \
  || printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$COMMON_DIR/drivers/Kconfig"
install -m 0644 "$RECIPE_ROOT/config/xuanyuan_ksun_susfs_defconfig" \
  "$COMMON_DIR/xuanyuan_ksun_susfs_defconfig"
install -m 0644 "$RECIPE_ROOT/config/workspace_status.json" \
  "$COMMON_DIR/workspace_status.json"
grep -qF '"xuanyuan_ksun_susfs_defconfig"' "$COMMON_DIR/BUILD.bazel" \
  || printf '\nexports_files(["xuanyuan_ksun_susfs_defconfig"])\n' >> "$COMMON_DIR/BUILD.bazel"

test -f "$COMMON_DIR/android/abi_gki_protected_exports_aarch64"
grep -q 'protected_exports_list' "$COMMON_DIR/BUILD.bazel"
grep -q '^CONFIG_MODVERSIONS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_LOCALVERSION="-4k"$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^KMI_GENERATION=8$' "$COMMON_DIR/build.config.common"
grep -q '^BRANCH=android15-6.6$' "$COMMON_DIR/build.config.common"

git -C "$COMMON_DIR" config user.name 'Xuanyuan reproducible build'
git -C "$COMMON_DIR" config user.email 'xuanyuan-build@localhost'
git -C "$COMMON_DIR" add -A
GIT_AUTHOR_DATE='1779954526 +0000' \
GIT_COMMITTER_DATE='1779954526 +0000' \
  git -C "$COMMON_DIR" commit -m 'xuanyuan: add KernelSU Next 3.3.0 and SUSFS 2.2.0'
test -z "$(git -C "$COMMON_DIR" status --porcelain)"

printf 'COMMON_BASE=%s\nKSU=%s\nSUSFS=%s\nFIXES=%s\nKSU_COMBINED_SHA256=%s\nKERNEL_COMBINED_SHA256=%s\n' \
  "$COMMON_SHA" "$KSU_SHA" "$SUSFS_SHA" "$FIX_SHA" \
  "$KSU_COMBINED_SHA256" "$KERNEL_COMBINED_SHA256" \
  > "$KERNEL_ROOT/xuanyuan-build-pins.txt"
