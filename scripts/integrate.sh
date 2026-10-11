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

COMMON_SHA=e56cf6b09cca2151bcee244b3d334fb68685ff57
KSU_SHA=8f902aeb16033024143ae36cf711df902cf02fae
KSU_REV_COUNT=3333
KSU_VERSION=33333
KSU_TAG=v3.4.1
SUSFS_SHA=e7b28525f69ca5864bed7db51f77663f5adfe218
FIX_SHA=757201d983e2549dc7945a21fa6a056eb2e55263
KSU_COMBINED_SHA256=7608282ea245d726054f477aa5d36285fa886f2b1f64a1c584300bb53d3254d0
KERNEL_COMBINED_SHA256=9479f934d6fd479f5b7f31c4944eb485900fb81a7ce63a5fe42b4df07fbc7128
KSU_PORT_REFERENCE_SHA=c4653cc4ca61a2160ad819d615ea42811e295192
POST_EXEC_PATCH_SHA256=1ebe4b46e559a5210326b5182260a56dc95c1fd96ed395ce874a0feb8383baee
KSU_VERSION_PATCH_SHA256=7f451103f9f86e933cc46f358c9eff160e06211565f98b7d81d1916d2b970cc2
KSU_DEFCONFIG_SHA256=5364f4b6a49522823078fac03bf9ecda3f944901185a4d2cf62560d7ca819658
WORKSPACE_STATUS_SHA256=e81bc808f245f072c87b20cf2921b935cb015344d748d3a9f7c0c3f64e31ff44
STOCK_CERT_PEM_SHA256=be4ec9f216f2c97735a78441be1f199b1fdaa38f568f20c97c9a2c3b5b8a7279
STOCK_CERT_DER_SHA256=123c66f6dff49a034d0e586fcd4086563e5c3c79500951fd98f00a76402326ee
STOCK_CERT_SERIAL=3B5068B306A89B3E9BCA19AED7F1537A01E9D83B
STOCK_CERT_SKID=2A775BAAF639CF779955063F8D2415E2A529A15A

test "$(git -C "$COMMON_DIR" rev-parse HEAD)" = "$COMMON_SHA"
test -z "$(git -C "$COMMON_DIR" status --porcelain)"
test ! -e "$KSU_DIR"
test ! -e "$SUSFS_DIR"

git clone --filter=blob:none https://github.com/KernelSU-Next/KernelSU-Next.git "$KSU_DIR"
git -C "$KSU_DIR" checkout --detach "$KSU_SHA"
test "$(git -C "$KSU_DIR" rev-parse HEAD)" = "$KSU_SHA"
test "$(git -C "$KSU_DIR" rev-list --count HEAD)" = "$KSU_REV_COUNT"
test "$(git -C "$KSU_DIR" describe --tags --exact-match HEAD)" = "$KSU_TAG"
test "$KSU_VERSION" = "$((30000 + KSU_REV_COUNT))"

git clone --filter=blob:none --no-checkout https://gitlab.com/simonpunk/susfs4ksu.git "$SUSFS_DIR"
git -C "$SUSFS_DIR" checkout --detach "$SUSFS_SHA"
test "$(git -C "$SUSFS_DIR" rev-parse HEAD)" = "$SUSFS_SHA"
grep -qx 'version=v2.2.0' "$SUSFS_DIR/ksu_module_susfs/module.prop"

# The original SUSFS 2.2 / WildKernels compatibility patch is ported to the
# exact official 3.4.1 tree. Keep the reviewed combined patch in this recipe;
# no runtime reject-fixing or fuzzy application is allowed.
ksu_combined="$RECIPE_ROOT/patches/ksun341-susfs220.patch"
echo "$KSU_COMBINED_SHA256  $ksu_combined" | sha256sum -c -
git -C "$KSU_DIR" apply --check "$ksu_combined"
git -C "$KSU_DIR" apply "$ksu_combined"
test "$(git -C "$KSU_DIR" diff --name-only -- kernel | wc -l | tr -d ' ')" = 24
test "$(git -C "$KSU_DIR" diff --binary --full-index -- kernel | sha256sum | awk '{print $1}')" = "$KSU_COMBINED_SHA256"
grep -q 'KERNEL_SU_UAPI_VERSION = 5;' "$KSU_DIR/kernel/include/uapi/supercall.h"
grep -q 'ksu_app_profile_init();' "$KSU_DIR/kernel/core/init.c"
grep -q 'ksu_is_su_session_fd(filp)' "$KSU_DIR/kernel/supercall/dispatch.c"
version_patch="$RECIPE_ROOT/patches/ksun-version-pin.patch"
echo "$KSU_VERSION_PATCH_SHA256  $version_patch" | sha256sum -c -
git -C "$KSU_DIR" apply --check "$version_patch"
git -C "$KSU_DIR" apply "$version_patch"
grep -qx "KSU_GIT_VERSION := $KSU_REV_COUNT" "$KSU_DIR/kernel/Kbuild"
grep -qx "KSU_GIT_TAG := $KSU_TAG" "$KSU_DIR/kernel/Kbuild"
test "$(grep -xc 'KSU_GIT_VERSION_VALID := 1' "$KSU_DIR/kernel/Kbuild")" = 2
test -z "$(find "$KSU_DIR/kernel" -type f \( -name '*.rej' -o -name '*.orig' \) -print)"

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
# Paired post-exec hook adapted from the pinned reference above. The core
# SUSFS 2.2 patch and userspace ABI remain unchanged.
post_exec_patch="$RECIPE_ROOT/patches/susfs220-ksun341-post-exec.patch"
echo "$POST_EXEC_PATCH_SHA256  $post_exec_patch" | sha256sum -c -
git -C "$stage_common" apply --check "$post_exec_patch"
git -C "$stage_common" apply "$post_exec_patch"
test -z "$(find "$stage_common" -type f \( -name '*.rej' -o -name '*.orig' \) -print)"
test "$(git -C "$stage_common" status --porcelain | wc -l | tr -d ' ')" = 27
git -C "$stage_common" add -N \
  fs/susfs.c \
  include/linux/susfs.h \
  include/linux/susfs_def.h
kernel_combined=$(mktemp)
git -C "$stage_common" diff --binary --full-index > "$kernel_combined"
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
ksu_defconfig="$RECIPE_ROOT/config/xuanyuan_ksun_susfs_defconfig"
echo "$KSU_DEFCONFIG_SHA256  $ksu_defconfig" | sha256sum -c -
install -m 0644 "$ksu_defconfig" \
  "$COMMON_DIR/xuanyuan_ksun_susfs_defconfig"
stock_cert="$RECIPE_ROOT/config/xuanyuan_stock_module_signing_cert.pem"
echo "$STOCK_CERT_PEM_SHA256  $stock_cert" | sha256sum -c -
test "$(openssl x509 -in "$stock_cert" -outform DER | sha256sum | awk '{print $1}')" = \
  "$STOCK_CERT_DER_SHA256"
test "$(openssl x509 -in "$stock_cert" -noout -serial | cut -d= -f2)" = \
  "$STOCK_CERT_SERIAL"
actual_skid=$(openssl x509 -in "$stock_cert" -noout \
  -ext subjectKeyIdentifier | sed -n '2p' | tr -d ' :')
test "$actual_skid" = "$STOCK_CERT_SKID"
install -m 0644 "$stock_cert" \
  "$COMMON_DIR/xuanyuan_stock_module_signing_cert.pem"
workspace_status="$RECIPE_ROOT/config/workspace_status.json"
echo "$WORKSPACE_STATUS_SHA256  $workspace_status" | sha256sum -c -
install -m 0644 "$workspace_status" \
  "$COMMON_DIR/workspace_status.json"
grep -qF '"xuanyuan_ksun_susfs_defconfig"' "$COMMON_DIR/BUILD.bazel" \
  || printf '\nexports_files(["xuanyuan_ksun_susfs_defconfig"])\n' >> "$COMMON_DIR/BUILD.bazel"

test -f "$COMMON_DIR/android/abi_gki_protected_exports_aarch64"
test "$(readlink "$COMMON_DIR/drivers/kernelsu")" = ../../KernelSU-Next/kernel
grep -q 'protected_exports_list' "$COMMON_DIR/BUILD.bazel"
grep -q '^CONFIG_MODVERSIONS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_LOCALVERSION="-4k"$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_KPROBES=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_EXT4_FS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^KMI_GENERATION=8$' "$COMMON_DIR/build.config.common"
grep -q '^BRANCH=android15-6.6$' "$COMMON_DIR/build.config.common"

git -C "$COMMON_DIR" config user.name 'Xuanyuan reproducible build'
git -C "$COMMON_DIR" config user.email 'xuanyuan-build@localhost'
git -C "$COMMON_DIR" add -A
GIT_AUTHOR_DATE='1779954526 +0000' \
GIT_COMMITTER_DATE='1779954526 +0000' \
  git -C "$COMMON_DIR" commit -m 'xuanyuan: add KernelSU Next 3.4.1 and SUSFS 2.2.0'
test -z "$(git -C "$COMMON_DIR" status --porcelain)"

expected_common_changes=$(printf '%s\n' \
  BUILD.bazel \
  drivers/Kconfig \
  drivers/Makefile \
  drivers/input/input.c \
  drivers/kernelsu \
  fs/Makefile \
  fs/exec.c \
  fs/namei.c \
  fs/namespace.c \
  fs/notify/fdinfo.c \
  fs/open.c \
  fs/proc/base.c \
  fs/proc/bootconfig.c \
  fs/proc/fd.c \
  fs/proc/task_mmu.c \
  fs/proc_namespace.c \
  fs/read_write.c \
  fs/readdir.c \
  fs/stat.c \
  fs/statfs.c \
  fs/susfs.c \
  include/linux/susfs.h \
  include/linux/susfs_def.h \
  kernel/kallsyms.c \
  kernel/reboot.c \
  kernel/sys.c \
  mm/memory.c \
  security/selinux/avc.c \
  security/selinux/hooks.c \
  security/selinux/selinuxfs.c \
  security/selinux/ss/services.c \
  workspace_status.json \
  xuanyuan_ksun_susfs_defconfig \
  xuanyuan_stock_module_signing_cert.pem)
actual_common_changes=$(git -C "$COMMON_DIR" diff-tree \
  --no-commit-id --name-only -r HEAD | LC_ALL=C sort)
test "$actual_common_changes" = "$expected_common_changes"

printf 'FEATURE_SET=ksun_susfs_stock_trust\nCOMMON_BASE=%s\nKSU=%s\nKSU_REV_COUNT=%s\nKSU_VERSION=%s\nKSU_TAG=%s\nSUSFS=%s\nFIXES=%s\nKSU_COMBINED_SHA256=%s\nKSU_VERSION_PATCH_SHA256=%s\nKERNEL_COMBINED_SHA256=%s\nKSU_DEFCONFIG_SHA256=%s\nWORKSPACE_STATUS_SHA256=%s\nSTOCK_CERT_PEM_SHA256=%s\nSTOCK_CERT_DER_SHA256=%s\nSTOCK_CERT_SERIAL=%s\nSTOCK_CERT_SKID=%s\nKSU_PORT_REFERENCE=%s\nPOST_EXEC_PATCH_SHA256=%s\n' \
  "$COMMON_SHA" "$KSU_SHA" "$KSU_REV_COUNT" "$KSU_VERSION" "$KSU_TAG" \
  "$SUSFS_SHA" "$FIX_SHA" "$KSU_COMBINED_SHA256" \
  "$KSU_VERSION_PATCH_SHA256" "$KERNEL_COMBINED_SHA256" \
  "$KSU_DEFCONFIG_SHA256" "$WORKSPACE_STATUS_SHA256" \
  "$STOCK_CERT_PEM_SHA256" "$STOCK_CERT_DER_SHA256" \
  "$STOCK_CERT_SERIAL" "$STOCK_CERT_SKID" \
  "$KSU_PORT_REFERENCE_SHA" "$POST_EXEC_PATCH_SHA256" \
  > "$KERNEL_ROOT/xuanyuan-build-pins.txt"
