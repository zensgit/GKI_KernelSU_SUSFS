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

COMMON_SHA=c4127a25dcf3c8923daffa62632816f6acf0e135
KSU_SHA=8f902aeb16033024143ae36cf711df902cf02fae
KSU_REV_COUNT=3333
KSU_VERSION=33333
KSU_TAG=v3.4.1
SUSFS_SHA=a0f9c59e2243f8a5db955f4ad1686d5e0ad26e1a
FIX_SHA=757201d983e2549dc7945a21fa6a056eb2e55263
KSU_COMBINED_SHA256=54650f7cca6a897b5b8a83bda6c4bdc6ea279a2779a58be0be17346ec0ff0927
KERNEL_COMBINED_SHA256=094fffbe1eb8201d6ce1ce54807226ed045096946b1037893fb9482eccdc9d37
KSU_PORT_REFERENCE_SHA=c4653cc4ca61a2160ad819d615ea42811e295192
SUSFS_HELPER_SHA256=eb727d479a0ff2d5557369c49a3e7492b5236a7c37499d235260e4ed4d24976d
KSU_VERSION_PATCH_SHA256=7f451103f9f86e933cc46f358c9eff160e06211565f98b7d81d1916d2b970cc2
KSU_DEFCONFIG_SHA256=5364f4b6a49522823078fac03bf9ecda3f944901185a4d2cf62560d7ca819658
WORKSPACE_STATUS_SHA256=340496695c860522cbd3db62a543463b14f89c0f1cfb69ecf5f4d90a19271c12
STOCK_CERT_PEM_SHA256=87be5106fad3d115b4485996be43640d8059d9ec58bdfbf4eed510aa692ba0b8
STOCK_CERT_DER_SHA256=35378257571909317a22f1a71edd672034b86e877874699cea1d317205353d6e
STOCK_CERT_SERIAL=5A358FA1E4039F06B44982CE80BFE689F8B77239
STOCK_CERT_SKID=3DC58B2897855063AA9941D432B4BAD7CA929532

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
grep -qx 'version=v2.3.0' "$SUSFS_DIR/ksu_module_susfs/module.prop"
echo "$SUSFS_HELPER_SHA256  $SUSFS_DIR/ksu_module_susfs/tools/ksu_susfs_arm64" | sha256sum -c -

# The SUSFS 2.3 interfaces are ported from the validated manual-hook recipe to the
# exact official 3.4.1 tree. Keep the reviewed combined patch in this recipe;
# no runtime reject-fixing or fuzzy application is allowed.
ksu_combined="$RECIPE_ROOT/patches/ksun341-susfs230.patch"
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
# SUSFS 2.3 already contains the paired post-exec hook; do not apply the
# previous 2.2 compatibility hunk a second time.
test -z "$(find "$stage_common" -type f \( -name '*.rej' -o -name '*.orig' \) -print)"
test "$(git -C "$stage_common" status --porcelain | wc -l | tr -d ' ')" = 28
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
GIT_AUTHOR_DATE='1784123933 +0000' \
GIT_COMMITTER_DATE='1784123933 +0000' \
  git -C "$COMMON_DIR" commit -m 'xuanyuan: add KernelSU Next 3.4.1 and SUSFS 2.3.0'
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
  fs/super.c \
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

printf 'FEATURE_SET=ksun_susfs_stock_trust\nCOMMON_BASE=%s\nKSU=%s\nKSU_REV_COUNT=%s\nKSU_VERSION=%s\nKSU_TAG=%s\nSUSFS=%s\nFIXES=%s\nKSU_COMBINED_SHA256=%s\nKSU_VERSION_PATCH_SHA256=%s\nKERNEL_COMBINED_SHA256=%s\nKSU_DEFCONFIG_SHA256=%s\nWORKSPACE_STATUS_SHA256=%s\nSTOCK_CERT_PEM_SHA256=%s\nSTOCK_CERT_DER_SHA256=%s\nSTOCK_CERT_SERIAL=%s\nSTOCK_CERT_SKID=%s\nKSU_PORT_REFERENCE=%s\nSUSFS_HELPER_SHA256=%s\n' \
  "$COMMON_SHA" "$KSU_SHA" "$KSU_REV_COUNT" "$KSU_VERSION" "$KSU_TAG" \
  "$SUSFS_SHA" "$FIX_SHA" "$KSU_COMBINED_SHA256" \
  "$KSU_VERSION_PATCH_SHA256" "$KERNEL_COMBINED_SHA256" \
  "$KSU_DEFCONFIG_SHA256" "$WORKSPACE_STATUS_SHA256" \
  "$STOCK_CERT_PEM_SHA256" "$STOCK_CERT_DER_SHA256" \
  "$STOCK_CERT_SERIAL" "$STOCK_CERT_SKID" \
  "$KSU_PORT_REFERENCE_SHA" "$SUSFS_HELPER_SHA256" \
  > "$KERNEL_ROOT/xuanyuan-build-pins.txt"
