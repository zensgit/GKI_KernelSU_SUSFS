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
STOCK_CERT_PEM_SHA256=be4ec9f216f2c97735a78441be1f199b1fdaa38f568f20c97c9a2c3b5b8a7279
STOCK_CERT_DER_SHA256=123c66f6dff49a034d0e586fcd4086563e5c3c79500951fd98f00a76402326ee
STOCK_CERT_SERIAL=3B5068B306A89B3E9BCA19AED7F1537A01E9D83B
STOCK_CERT_SKID=2A775BAAF639CF779955063F8D2415E2A529A15A
TRUST_FRAGMENT_SHA256=04fb2e7854d8d1b58aeda50d204cc2170ee243bb63d5de6cace366ad3c8c11ba

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
stock_cert="$RECIPE_ROOT/config/xuanyuan_stock_module_signing_cert.pem"
trust_fragment="$RECIPE_ROOT/config/xuanyuan_stock_trust_defconfig"
echo "$STOCK_CERT_PEM_SHA256  $stock_cert" | sha256sum -c -
echo "$TRUST_FRAGMENT_SHA256  $trust_fragment" | sha256sum -c -
test "$(openssl x509 -in "$stock_cert" -outform DER | sha256sum | awk '{print $1}')" = \
  "$STOCK_CERT_DER_SHA256"
test "$(openssl x509 -in "$stock_cert" -noout -serial | cut -d= -f2)" = \
  "$STOCK_CERT_SERIAL"
actual_skid=$(openssl x509 -in "$stock_cert" -noout \
  -ext subjectKeyIdentifier | sed -n '2p' | tr -d ' :')
test "$actual_skid" = "$STOCK_CERT_SKID"
install -m 0644 "$workspace_status" "$COMMON_DIR/workspace_status.json"
install -m 0644 "$stock_cert" \
  "$COMMON_DIR/xuanyuan_stock_module_signing_cert.pem"
install -m 0644 "$trust_fragment" \
  "$COMMON_DIR/xuanyuan_stock_trust_defconfig"
grep -qF '"xuanyuan_stock_trust_defconfig"' "$COMMON_DIR/BUILD.bazel" \
  || printf '\nexports_files(["xuanyuan_stock_trust_defconfig"])\n' \
    >> "$COMMON_DIR/BUILD.bazel"

git -C "$COMMON_DIR" config user.name 'Xuanyuan reproducible build'
git -C "$COMMON_DIR" config user.email 'xuanyuan-build@localhost'
git -C "$COMMON_DIR" add -A
GIT_AUTHOR_DATE='1779954526 +0000' \
GIT_COMMITTER_DATE='1779954526 +0000' \
  git -C "$COMMON_DIR" commit -m 'xuanyuan: trust stock GKI module certificate'
test -z "$(git -C "$COMMON_DIR" status --porcelain)"
expected_common_changes=$(printf '%s\n' \
  BUILD.bazel \
  workspace_status.json \
  xuanyuan_stock_module_signing_cert.pem \
  xuanyuan_stock_trust_defconfig)
actual_common_changes=$(git -C "$COMMON_DIR" diff-tree \
  --no-commit-id --name-only -r HEAD | LC_ALL=C sort)
test "$actual_common_changes" = "$expected_common_changes"

test -f "$COMMON_DIR/android/abi_gki_protected_exports_aarch64"
grep -q 'protected_exports_list' "$COMMON_DIR/BUILD.bazel"
grep -q '^CONFIG_MODVERSIONS=y$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^CONFIG_LOCALVERSION="-4k"$' "$COMMON_DIR/arch/arm64/configs/gki_defconfig"
grep -q '^KMI_GENERATION=8$' "$COMMON_DIR/build.config.common"
grep -q '^BRANCH=android15-6.6$' "$COMMON_DIR/build.config.common"

printf 'FEATURE_SET=pure_gki_stock_trust\nAOSP_BUILD=%s\nCOMMON_BASE=%s\nMANIFEST_SHA256=%s\nWORKSPACE_STATUS_SHA256=%s\nSTOCK_IMAGE_SHA256=%s\nSTOCK_CERT_PEM_SHA256=%s\nSTOCK_CERT_DER_SHA256=%s\nSTOCK_CERT_SERIAL=%s\nSTOCK_CERT_SKID=%s\nTRUST_FRAGMENT_SHA256=%s\n' \
  "$AOSP_BUILD" "$COMMON_SHA" "$MANIFEST_SHA256" \
  "$WORKSPACE_STATUS_SHA256" "$STOCK_IMAGE_SHA256" \
  "$STOCK_CERT_PEM_SHA256" "$STOCK_CERT_DER_SHA256" \
  "$STOCK_CERT_SERIAL" "$STOCK_CERT_SKID" "$TRUST_FRAGMENT_SHA256" \
  > "$KERNEL_ROOT/xuanyuan-build-pins.txt"
