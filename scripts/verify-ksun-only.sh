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
EXPECTED_KSU_VERSION=33214
EXPECTED_KSU_TAG=v3.3.0

test -s "$IMAGE"
custom_sha=$(sha256sum "$IMAGE" | awk '{print $1}')
test "$custom_sha" != "$STOCK_IMAGE_SHA256"
strings "$IMAGE" | grep -F "Linux version $EXPECTED_RELEASE"
strings "$IMAGE" | grep -Fx "$EXPECTED_KSU_TAG"
if strings "$IMAGE" | grep -Fx 'v0.0.1' >/dev/null; then
  echo 'unexpected KernelSU fallback tag v0.0.1 in Image' >&2
  exit 1
fi
if strings "$IMAGE" | grep -Fi susfs >/dev/null; then
  echo 'unexpected SUSFS content in Image' >&2
  exit 1
fi

grep -qx 'KSU_GIT_VERSION := 3214' \
  "$KERNEL_ROOT/KernelSU-Next/kernel/Kbuild"
grep -qx "KSU_GIT_TAG := $EXPECTED_KSU_TAG" \
  "$KERNEL_ROOT/KernelSU-Next/kernel/Kbuild"
test "$(grep -xc 'KSU_GIT_VERSION_VALID := 1' \
  "$KERNEL_ROOT/KernelSU-Next/kernel/Kbuild")" = 2
test "$(git -C "$KERNEL_ROOT/KernelSU-Next" diff --name-only)" = kernel/Kbuild
test ! -e "$KERNEL_ROOT/susfs4ksu"
test ! -e "$KERNEL_ROOT/kernel_patches"
test ! -e "$KERNEL_ROOT/common/fs/susfs.c"
test ! -e "$KERNEL_ROOT/common/include/linux/susfs.h"
test ! -e "$KERNEL_ROOT/common/include/linux/susfs_def.h"
test -z "$(find "$KERNEL_ROOT/common" "$KERNEL_ROOT/KernelSU-Next/kernel" \
  -iname '*susfs*' -print -quit)"

mkdir -p "$ARTIFACT_DIR"
"$KERNEL_ROOT/common/scripts/extract-ikconfig" "$IMAGE" \
  > "$ARTIFACT_DIR/kernel.config"

for required in \
  CONFIG_ARM64_4K_PAGES=y \
  CONFIG_LTO_NONE=y \
  CONFIG_CFI_CLANG=y \
  CONFIG_MODVERSIONS=y \
  CONFIG_KPROBES=y \
  CONFIG_EXT4_FS=y \
  CONFIG_KSU=y; do
  grep -qx "$required" "$ARTIFACT_DIR/kernel.config"
done
for disabled in KSU_DEBUG KSU_DISABLE_MANAGER KSU_DISABLE_POLICY; do
  grep -qx "# CONFIG_${disabled} is not set" "$ARTIFACT_DIR/kernel.config"
done
if grep -Fiq susfs "$ARTIFACT_DIR/kernel.config"; then
  echo 'unexpected SUSFS configuration in Image' >&2
  exit 1
fi

for required_artifact in kernel_aarch64_Module.symvers System.map abi.stg abi-full.stg; do
  test -s "$DIST_DIR/$required_artifact"
done
grep -Eq ' [Tt] ksu_' "$DIST_DIR/System.map"
if grep -Fiq susfs "$DIST_DIR/System.map"; then
  echo 'unexpected SUSFS symbol in System.map' >&2
  exit 1
fi
if grep -Fiq susfs "$DIST_DIR/kernel_aarch64_Module.symvers"; then
  echo 'unexpected SUSFS symbol in Module.symvers' >&2
  exit 1
fi

grep -qx 'FEATURE_SET=ksun_builtin_only' \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "KSU_VERSION=$EXPECTED_KSU_VERSION" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "KSU_TAG=$EXPECTED_KSU_TAG" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
if grep -Fiq susfs "$KERNEL_ROOT/xuanyuan-build-pins.txt"; then
  echo 'unexpected SUSFS pin in built-in-only build metadata' >&2
  exit 1
fi

install -m 0644 "$IMAGE" "$ARTIFACT_DIR/Image"
for required_artifact in kernel_aarch64_Module.symvers System.map abi.stg abi-full.stg; do
  install -m 0644 "$DIST_DIR/$required_artifact" \
    "$ARTIFACT_DIR/$required_artifact"
done
install -m 0644 "$KERNEL_ROOT/xuanyuan-build-pins.txt" \
  "$ARTIFACT_DIR/xuanyuan-build-pins.txt"
printf 'feature_set=ksun_builtin_only\nkernel_release=%s\nksu_version=%s\nksu_tag=%s\nimage_size=%s\nstock_image_sha256=%s\ncustom_image_sha256=%s\n' \
  "$EXPECTED_RELEASE" "$EXPECTED_KSU_VERSION" "$EXPECTED_KSU_TAG" \
  "$(stat -c %s "$IMAGE")" "$STOCK_IMAGE_SHA256" "$custom_sha" \
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
    build-metadata.txt \
    > SHA256SUMS
)

echo "Validated built-in-only Image SHA-256: $custom_sha"
