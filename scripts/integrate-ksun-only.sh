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

COMMON_SHA=e56cf6b09cca2151bcee244b3d334fb68685ff57
KSU_SHA=3b18216f71df189ab3d1b1ce0bdb21be1268e771
KSU_REV_COUNT=3214
KSU_VERSION=33214
KSU_TAG=v3.3.0
KSU_VERSION_PATCH_SHA256=30be6b8072122a946b22fbf13722a1dae276213127dfbe903783f1db15023d5b
KSU_DEFCONFIG_SHA256=d5ba901cefb26fae7157416c7501c8007d0d5ba922180c40c8d6cfedca0eb2a2
STOCK_CERT_PEM_SHA256=be4ec9f216f2c97735a78441be1f199b1fdaa38f568f20c97c9a2c3b5b8a7279
STOCK_CERT_DER_SHA256=123c66f6dff49a034d0e586fcd4086563e5c3c79500951fd98f00a76402326ee
STOCK_CERT_SERIAL=3B5068B306A89B3E9BCA19AED7F1537A01E9D83B
STOCK_CERT_SKID=2A775BAAF639CF779955063F8D2415E2A529A15A

test "$(git -C "$COMMON_DIR" rev-parse HEAD)" = "$COMMON_SHA"
test -z "$(git -C "$COMMON_DIR" status --porcelain)"
test ! -e "$KERNEL_ROOT/susfs4ksu"
test ! -e "$KERNEL_ROOT/kernel_patches"

git clone --filter=blob:none https://github.com/KernelSU-Next/KernelSU-Next.git "$KSU_DIR"
git -C "$KSU_DIR" checkout --detach "$KSU_SHA"
test "$(git -C "$KSU_DIR" rev-parse HEAD)" = "$KSU_SHA"
test "$(git -C "$KSU_DIR" rev-list --count HEAD)" = "$KSU_REV_COUNT"
test "$(git -C "$KSU_DIR" describe --tags --exact-match HEAD)" = "$KSU_TAG"
test "$KSU_VERSION" = "$((30000 + KSU_REV_COUNT))"

version_patch="$RECIPE_ROOT/patches/ksun-version-pin.patch"
echo "$KSU_VERSION_PATCH_SHA256  $version_patch" | sha256sum -c -
git -C "$KSU_DIR" apply --check "$version_patch"
git -C "$KSU_DIR" apply "$version_patch"
test "$(git -C "$KSU_DIR" diff --name-only)" = kernel/Kbuild
git -C "$KSU_DIR" diff --check
grep -qx "KSU_GIT_VERSION := $KSU_REV_COUNT" "$KSU_DIR/kernel/Kbuild"
grep -qx "KSU_GIT_TAG := $KSU_TAG" "$KSU_DIR/kernel/Kbuild"
test "$(grep -xc 'KSU_GIT_VERSION_VALID := 1' "$KSU_DIR/kernel/Kbuild")" = 2

ln -s ../../KernelSU-Next/kernel "$COMMON_DIR/drivers/kernelsu"
# shellcheck disable=SC2016
grep -qF 'obj-$(CONFIG_KSU) += kernelsu/' "$COMMON_DIR/drivers/Makefile" \
  || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$COMMON_DIR/drivers/Makefile"
grep -qF 'source "drivers/kernelsu/Kconfig"' "$COMMON_DIR/drivers/Kconfig" \
  || printf '\nsource "drivers/kernelsu/Kconfig"\n' >> "$COMMON_DIR/drivers/Kconfig"
ksu_defconfig="$RECIPE_ROOT/config/xuanyuan_ksun_only_defconfig"
stock_cert="$RECIPE_ROOT/config/xuanyuan_stock_module_signing_cert.pem"
echo "$KSU_DEFCONFIG_SHA256  $ksu_defconfig" | sha256sum -c -
echo "$STOCK_CERT_PEM_SHA256  $stock_cert" | sha256sum -c -
test "$(openssl x509 -in "$stock_cert" -outform DER | sha256sum | awk '{print $1}')" = \
  "$STOCK_CERT_DER_SHA256"
test "$(openssl x509 -in "$stock_cert" -noout -serial | cut -d= -f2)" = \
  "$STOCK_CERT_SERIAL"
actual_skid=$(openssl x509 -in "$stock_cert" -noout \
  -ext subjectKeyIdentifier | sed -n '2p' | tr -d ' :')
test "$actual_skid" = "$STOCK_CERT_SKID"
install -m 0644 "$ksu_defconfig" \
  "$COMMON_DIR/xuanyuan_ksun_only_defconfig"
install -m 0644 "$stock_cert" \
  "$COMMON_DIR/xuanyuan_stock_module_signing_cert.pem"
install -m 0644 "$RECIPE_ROOT/config/workspace_status.json" \
  "$COMMON_DIR/workspace_status.json"
grep -qF '"xuanyuan_ksun_only_defconfig"' "$COMMON_DIR/BUILD.bazel" \
  || printf '\nexports_files(["xuanyuan_ksun_only_defconfig"])\n' >> "$COMMON_DIR/BUILD.bazel"

test "$(readlink "$COMMON_DIR/drivers/kernelsu")" = ../../KernelSU-Next/kernel
test -f "$COMMON_DIR/android/abi_gki_protected_exports_aarch64"
grep -q 'protected_exports_list' "$COMMON_DIR/BUILD.bazel"
grep -q '^CONFIG_MODVERSIONS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_LOCALVERSION="-4k"$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_KPROBES=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_EXT4_FS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^KMI_GENERATION=8$' "$COMMON_DIR/build.config.common"
grep -q '^BRANCH=android15-6.6$' "$COMMON_DIR/build.config.common"

test ! -e "$COMMON_DIR/fs/susfs.c"
test ! -e "$COMMON_DIR/include/linux/susfs.h"
test ! -e "$COMMON_DIR/include/linux/susfs_def.h"
test -z "$(find "$COMMON_DIR" "$KSU_DIR/kernel" -iname '*susfs*' -print -quit)"
if git -C "$KSU_DIR" grep -in susfs -- kernel; then
  echo 'unexpected SUSFS content in KernelSU-Next kernel source' >&2
  exit 1
fi
if git -C "$COMMON_DIR" grep -in susfs -- fs include drivers; then
  echo 'unexpected SUSFS content in Android common source' >&2
  exit 1
fi

git -C "$COMMON_DIR" config user.name 'Xuanyuan reproducible build'
git -C "$COMMON_DIR" config user.email 'xuanyuan-build@localhost'
git -C "$COMMON_DIR" add -A
GIT_AUTHOR_DATE='1779954526 +0000' \
GIT_COMMITTER_DATE='1779954526 +0000' \
  git -C "$COMMON_DIR" commit -m \
    'xuanyuan: add KernelSU Next 3.3.0 with stock module trust'
test -z "$(git -C "$COMMON_DIR" status --porcelain)"

expected_common_changes=$(printf '%s\n' \
  BUILD.bazel \
  drivers/Kconfig \
  drivers/Makefile \
  drivers/kernelsu \
  workspace_status.json \
  xuanyuan_ksun_only_defconfig \
  xuanyuan_stock_module_signing_cert.pem)
actual_common_changes=$(git -C "$COMMON_DIR" diff-tree \
  --no-commit-id --name-only -r HEAD | LC_ALL=C sort)
test "$actual_common_changes" = "$expected_common_changes"

printf 'FEATURE_SET=ksun_builtin_only_stock_trust\nCOMMON_BASE=%s\nKSU=%s\nKSU_REV_COUNT=%s\nKSU_VERSION=%s\nKSU_TAG=%s\nKSU_VERSION_PATCH_SHA256=%s\nKSU_DEFCONFIG_SHA256=%s\nSTOCK_CERT_PEM_SHA256=%s\nSTOCK_CERT_DER_SHA256=%s\nSTOCK_CERT_SERIAL=%s\nSTOCK_CERT_SKID=%s\n' \
  "$COMMON_SHA" "$KSU_SHA" "$KSU_REV_COUNT" "$KSU_VERSION" "$KSU_TAG" \
  "$KSU_VERSION_PATCH_SHA256" "$KSU_DEFCONFIG_SHA256" \
  "$STOCK_CERT_PEM_SHA256" "$STOCK_CERT_DER_SHA256" \
  "$STOCK_CERT_SERIAL" "$STOCK_CERT_SKID" \
  > "$KERNEL_ROOT/xuanyuan-build-pins.txt"
