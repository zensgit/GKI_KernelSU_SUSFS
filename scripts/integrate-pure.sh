#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <kernel-root> <recipe-root>" >&2
  exit 2
fi

KERNEL_ROOT=$(realpath "$1")
RECIPE_ROOT=$(realpath "$2")
COMMON_DIR="$KERNEL_ROOT/common"

AOSP_BUILD=15511674
COMMON_SHA=e56cf6b09cca2151bcee244b3d334fb68685ff57
MANIFEST_SHA256=dbaa1ca849500f4e0cc421beb8b431eb957905379a1a1f9d6b0bfd7d6b5fb1c3
WORKSPACE_STATUS_SHA256=e81bc808f245f072c87b20cf2921b935cb015344d748d3a9f7c0c3f64e31ff44
STOCK_IMAGE_SHA256=81181e8321e655acbce601faff94ab1610f9b825869a56a1c0e5bfcf9db1126c

test "$(git -C "$COMMON_DIR" rev-parse HEAD)" = "$COMMON_SHA"
test -z "$(git -C "$COMMON_DIR" status --porcelain)"
test ! -e "$KERNEL_ROOT/KernelSU-Next"
test ! -e "$KERNEL_ROOT/susfs4ksu"
test ! -e "$KERNEL_ROOT/kernel_patches"
test ! -e "$COMMON_DIR/drivers/kernelsu"
test ! -e "$COMMON_DIR/fs/susfs.c"
test ! -e "$COMMON_DIR/include/linux/susfs.h"
test ! -e "$COMMON_DIR/include/linux/susfs_def.h"
if git -C "$COMMON_DIR" grep -in -E 'kernelsu|susfs' -- arch drivers fs include; then
  echo 'unexpected KernelSU or SUSFS content in pinned Android common source' >&2
  exit 1
fi

workspace_status="$RECIPE_ROOT/config/workspace_status.json"
echo "$WORKSPACE_STATUS_SHA256  $workspace_status" | sha256sum -c -
install -m 0644 "$workspace_status" "$COMMON_DIR/workspace_status.json"

git -C "$COMMON_DIR" config user.name 'Xuanyuan reproducible build'
git -C "$COMMON_DIR" config user.email 'xuanyuan-build@localhost'
git -C "$COMMON_DIR" add workspace_status.json
GIT_AUTHOR_DATE='1779954526 +0000' \
GIT_COMMITTER_DATE='1779954526 +0000' \
  git -C "$COMMON_DIR" commit -m 'xuanyuan: pin pure GKI workspace status'
test -z "$(git -C "$COMMON_DIR" status --porcelain)"
test "$(git -C "$COMMON_DIR" diff-tree \
  --no-commit-id --name-only -r HEAD)" = workspace_status.json

test -f "$COMMON_DIR/android/abi_gki_protected_exports_aarch64"
grep -q 'protected_exports_list' "$COMMON_DIR/BUILD.bazel"
grep -q '^CONFIG_MODVERSIONS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_LOCALVERSION="-4k"$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^KMI_GENERATION=8$' "$COMMON_DIR/build.config.common"
grep -q '^BRANCH=android15-6.6$' "$COMMON_DIR/build.config.common"

printf 'FEATURE_SET=pure_gki\nAOSP_BUILD=%s\nCOMMON_BASE=%s\nMANIFEST_SHA256=%s\nWORKSPACE_STATUS_SHA256=%s\nSTOCK_IMAGE_SHA256=%s\n' \
  "$AOSP_BUILD" "$COMMON_SHA" "$MANIFEST_SHA256" \
  "$WORKSPACE_STATUS_SHA256" "$STOCK_IMAGE_SHA256" \
  > "$KERNEL_ROOT/xuanyuan-build-pins.txt"
