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
STOCK_CERT_PEM_SHA256=be4ec9f216f2c97735a78441be1f199b1fdaa38f568f20c97c9a2c3b5b8a7279
STOCK_CERT_DER_SHA256=123c66f6dff49a034d0e586fcd4086563e5c3c79500951fd98f00a76402326ee
STOCK_CERT_SERIAL=3B5068B306A89B3E9BCA19AED7F1537A01E9D83B
STOCK_CERT_SKID=2A775BAAF639CF779955063F8D2415E2A529A15A
STOCK_CERT="$KERNEL_ROOT/common/xuanyuan_stock_module_signing_cert.pem"

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
expected_common_changes=$(printf '%s\n' \
  BUILD.bazel \
  workspace_status.json \
  xuanyuan_stock_module_signing_cert.pem \
  xuanyuan_stock_trust_defconfig)
actual_common_changes=$(git -C "$KERNEL_ROOT/common" diff-tree \
  --no-commit-id --name-only -r HEAD | LC_ALL=C sort)
test "$actual_common_changes" = "$expected_common_changes"

mkdir -p "$ARTIFACT_DIR"
"$KERNEL_ROOT/common/scripts/extract-ikconfig" "$IMAGE" \
  > "$ARTIFACT_DIR/kernel.config"

for required in \
  CONFIG_ARM64_4K_PAGES=y \
  CONFIG_LTO_NONE=y \
  CONFIG_CFI_CLANG=y \
  CONFIG_MODVERSIONS=y \
  CONFIG_FRAME_WARN=2048 \
  CONFIG_MODULE_SIG_PROTECT=y \
  CONFIG_MODULE_SIG_ALL=y \
  CONFIG_SYSTEM_TRUSTED_KEYRING=y \
  'CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"' \
  'CONFIG_SYSTEM_TRUSTED_KEYS="xuanyuan_stock_module_signing_cert.pem"'; do
  grep -qx "$required" "$ARTIFACT_DIR/kernel.config"
done
grep -qx '# CONFIG_MODULE_SIG_FORCE is not set' \
  "$ARTIFACT_DIR/kernel.config"
grep -qx '# CONFIG_SECONDARY_TRUSTED_KEYRING is not set' \
  "$ARTIFACT_DIR/kernel.config"
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

grep -qx 'FEATURE_SET=pure_gki_stock_trust' \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx 'AOSP_BUILD=15511674' "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_IMAGE_SHA256=$STOCK_IMAGE_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_PEM_SHA256=$STOCK_CERT_PEM_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_DER_SHA256=$STOCK_CERT_DER_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_SERIAL=$STOCK_CERT_SERIAL" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_SKID=$STOCK_CERT_SKID" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
if grep -Eiq 'KSU|KernelSU|SUSFS' "$KERNEL_ROOT/xuanyuan-build-pins.txt"; then
  echo 'unexpected KernelSU or SUSFS pin in pure GKI metadata' >&2
  exit 1
fi

echo "$STOCK_CERT_PEM_SHA256  $STOCK_CERT" | sha256sum -c -
test "$(openssl x509 -in "$STOCK_CERT" -outform DER | sha256sum | awk '{print $1}')" = \
  "$STOCK_CERT_DER_SHA256"
test "$(openssl x509 -in "$STOCK_CERT" -noout -serial | cut -d= -f2)" = \
  "$STOCK_CERT_SERIAL"
actual_skid=$(openssl x509 -in "$STOCK_CERT" -noout \
  -ext subjectKeyIdentifier | sed -n '2p' | tr -d ' :')
test "$actual_skid" = "$STOCK_CERT_SKID"
stock_der=$(mktemp)
openssl x509 -in "$STOCK_CERT" -outform DER -out "$stock_der"
stock_cert_count=$(python3 -c \
  'import pathlib, sys; print(pathlib.Path(sys.argv[1]).read_bytes().count(pathlib.Path(sys.argv[2]).read_bytes()))' \
  "$IMAGE" "$stock_der")
rm -f "$stock_der"
test "$stock_cert_count" = 1

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
install -m 0644 "$STOCK_CERT" \
  "$ARTIFACT_DIR/stock-module-signing-cert.pem"
printf 'stock_module_cert_embedded=true\nstock_cert_pem_sha256=%s\nstock_cert_der_sha256=%s\nstock_cert_serial=%s\nstock_cert_skid=%s\n' \
  "$STOCK_CERT_PEM_SHA256" "$STOCK_CERT_DER_SHA256" \
  "$STOCK_CERT_SERIAL" "$STOCK_CERT_SKID" \
  > "$ARTIFACT_DIR/stock-module-cert.txt"
printf 'stock_image_match=%s\nexpected_stock_image_sha256=%s\nactual_image_sha256=%s\n' \
  "$stock_image_match" "$STOCK_IMAGE_SHA256" "$custom_sha" \
  > "$ARTIFACT_DIR/stock-image-comparison.txt"
printf 'feature_set=pure_gki_stock_trust\nkernel_release=%s\nimage_size=%s\nstock_module_cert_embedded=true\nstock_cert_skid=%s\nstock_image_match=%s\nexpected_stock_image_sha256=%s\nactual_image_sha256=%s\n' \
  "$EXPECTED_RELEASE" "$(stat -c %s "$IMAGE")" "$STOCK_CERT_SKID" \
  "$stock_image_match" "$STOCK_IMAGE_SHA256" "$custom_sha" \
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
    stock-module-signing-cert.pem \
    stock-module-cert.txt \
    stock-image-comparison.txt \
    build-metadata.txt \
    > SHA256SUMS
)

echo "Validated pure GKI Image SHA-256: $custom_sha"
echo "Stock module certificate embedded: true"
echo "Stock Image byte identity: $stock_image_match"
