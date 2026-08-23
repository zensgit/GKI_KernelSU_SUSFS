#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <kernel-root> <dist-dir> <artifact-dir>" >&2
  exit 2
fi

KERNEL_ROOT=$(realpath "$1")
DIST_DIR=$(realpath "$2")
ARTIFACT_DIR=$3
IMAGE="$DIST_DIR/Image"
STOCK_IMAGE_SHA256=81181e8321e655acbce601faff94ab1610f9b825869a56a1c0e5bfcf9db1126c
EXPECTED_RELEASE=6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k

test -s "$IMAGE"
custom_sha=$(sha256sum "$IMAGE" | awk '{print $1}')
strings "$IMAGE" | grep -F "Linux version $EXPECTED_RELEASE"
if strings "$IMAGE" | grep -Ei 'KernelSU|SUSFS|v3\.3\.0' >/dev/null; then
  echo 'unexpected KernelSU or SUSFS content in pure GKI Image' >&2
  exit 1
fi

test ! -e "$KERNEL_ROOT/KernelSU-Next"
test ! -e "$KERNEL_ROOT/susfs4ksu"
test ! -e "$KERNEL_ROOT/kernel_patches"
test ! -e "$KERNEL_ROOT/common/drivers/kernelsu"
test ! -e "$KERNEL_ROOT/common/fs/susfs.c"
test ! -e "$KERNEL_ROOT/common/include/linux/susfs.h"
test ! -e "$KERNEL_ROOT/common/include/linux/susfs_def.h"
test -z "$(git -C "$KERNEL_ROOT/common" status --porcelain)"
test "$(git -C "$KERNEL_ROOT/common" diff-tree \
  --no-commit-id --name-only -r HEAD)" = workspace_status.json

mkdir -p "$ARTIFACT_DIR"
"$KERNEL_ROOT/common/scripts/extract-ikconfig" "$IMAGE" \
  > "$ARTIFACT_DIR/kernel.config"

for required in \
  CONFIG_ARM64_4K_PAGES=y \
  CONFIG_LTO_NONE=y \
  CONFIG_CFI_CLANG=y \
  CONFIG_MODVERSIONS=y \
  CONFIG_FRAME_WARN=2048; do
  grep -qx "$required" "$ARTIFACT_DIR/kernel.config"
done
if grep -Eiq 'CONFIG_KSU|KernelSU|SUSFS' "$ARTIFACT_DIR/kernel.config"; then
  echo 'unexpected KernelSU or SUSFS configuration in pure GKI Image' >&2
  exit 1
fi

for required_artifact in kernel_aarch64_Module.symvers System.map abi.stg abi-full.stg; do
  test -s "$DIST_DIR/$required_artifact"
done
if grep -Eiq 'ksu_|kernelsu|susfs' "$DIST_DIR/System.map"; then
  echo 'unexpected KernelSU or SUSFS symbol in System.map' >&2
  exit 1
fi
if grep -Eiq 'ksu_|kernelsu|susfs' "$DIST_DIR/kernel_aarch64_Module.symvers"; then
  echo 'unexpected KernelSU or SUSFS symbol in Module.symvers' >&2
  exit 1
fi

grep -qx 'FEATURE_SET=pure_gki' "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx 'AOSP_BUILD=15511674' "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_IMAGE_SHA256=$STOCK_IMAGE_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
if grep -Eiq 'KSU|KernelSU|SUSFS' "$KERNEL_ROOT/xuanyuan-build-pins.txt"; then
  echo 'unexpected KernelSU or SUSFS pin in pure GKI metadata' >&2
  exit 1
fi

if [[ "$custom_sha" = "$STOCK_IMAGE_SHA256" ]]; then
  stock_image_match=true
else
  stock_image_match=false
fi

install -m 0644 "$IMAGE" "$ARTIFACT_DIR/Image"
for required_artifact in kernel_aarch64_Module.symvers System.map abi.stg abi-full.stg; do
  install -m 0644 "$DIST_DIR/$required_artifact" \
    "$ARTIFACT_DIR/$required_artifact"
done
install -m 0644 "$KERNEL_ROOT/xuanyuan-build-pins.txt" \
  "$ARTIFACT_DIR/xuanyuan-build-pins.txt"
printf 'stock_image_match=%s\nexpected_stock_image_sha256=%s\nactual_image_sha256=%s\n' \
  "$stock_image_match" "$STOCK_IMAGE_SHA256" "$custom_sha" \
  > "$ARTIFACT_DIR/stock-image-comparison.txt"
printf 'feature_set=pure_gki\nkernel_release=%s\nimage_size=%s\nstock_image_match=%s\nexpected_stock_image_sha256=%s\nactual_image_sha256=%s\n' \
  "$EXPECTED_RELEASE" "$(stat -c %s "$IMAGE")" "$stock_image_match" \
  "$STOCK_IMAGE_SHA256" "$custom_sha" \
  > "$ARTIFACT_DIR/build-metadata.txt"
(
  cd "$ARTIFACT_DIR"
  sha256sum \
    Image \
    kernel.config \
    kernel_aarch64_Module.symvers \
    System.map \
    abi.stg \
    abi-full.stg \
    xuanyuan-build-pins.txt \
    stock-image-comparison.txt \
    build-metadata.txt \
    > SHA256SUMS
)

echo "Validated pure GKI Image SHA-256: $custom_sha"
echo "Stock Image byte identity: $stock_image_match"
