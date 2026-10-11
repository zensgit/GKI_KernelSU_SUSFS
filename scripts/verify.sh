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
STOCK_IMAGE_SHA256=3ccbdb1b4bd1c8610b4d6fd987ea9247ca95b43c0ddd21d3e51de771607bad24
EXPECTED_RELEASE=6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k
EXPECTED_KSU_VERSION=33333
EXPECTED_KSU_TAG=v3.4.1
EXPECTED_KSU_UAPI=5
KSU_DEFCONFIG_SHA256=5364f4b6a49522823078fac03bf9ecda3f944901185a4d2cf62560d7ca819658
WORKSPACE_STATUS_SHA256=340496695c860522cbd3db62a543463b14f89c0f1cfb69ecf5f4d90a19271c12
MODULE_SYMVERS_SHA256=49c001544aa6be9dc33c96c47da79717094161dfafca04e2c43aeba258d35ac0
ABI_STG_SHA256=ce7408cd809f8df529298c5b37c7482228931c89e52000e39078eb4734b49d81
ABI_FULL_STG_SHA256=eb879fdf7697034840e3e2b316ed5a6077af0903d4f6fa008bcf2feb3471df9b
STOCK_CERT_PEM_SHA256=87be5106fad3d115b4485996be43640d8059d9ec58bdfbf4eed510aa692ba0b8
STOCK_CERT_DER_SHA256=35378257571909317a22f1a71edd672034b86e877874699cea1d317205353d6e
STOCK_CERT_SERIAL=5A358FA1E4039F06B44982CE80BFE689F8B77239
STOCK_CERT_SKID=3DC58B2897855063AA9941D432B4BAD7CA929532
STOCK_CERT="$KERNEL_ROOT/common/xuanyuan_stock_module_signing_cert.pem"

test -s "$IMAGE"
custom_sha=$(sha256sum "$IMAGE" | awk '{print $1}')
test "$custom_sha" != "$STOCK_IMAGE_SHA256"
strings "$IMAGE" | grep -F "Linux version $EXPECTED_RELEASE"
strings "$IMAGE" | grep -Fx "$EXPECTED_KSU_TAG"
strings "$IMAGE" | grep -Fx 'v2.3.0'
if strings "$IMAGE" | grep -Fx 'v0.0.1' >/dev/null; then
  echo 'unexpected KernelSU fallback tag v0.0.1 in Image' >&2
  exit 1
fi
grep -qx 'KSU_GIT_VERSION := 3333' \
  "$KERNEL_ROOT/KernelSU-Next/kernel/Kbuild"
grep -qx "KSU_GIT_TAG := $EXPECTED_KSU_TAG" \
  "$KERNEL_ROOT/KernelSU-Next/kernel/Kbuild"
test "$(grep -xc 'KSU_GIT_VERSION_VALID := 1' \
  "$KERNEL_ROOT/KernelSU-Next/kernel/Kbuild")" = 2
grep -Fqx "static const __u32 KERNEL_SU_UAPI_VERSION = $EXPECTED_KSU_UAPI;" \
  "$KERNEL_ROOT/KernelSU-Next/uapi/supercall.h"

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
  CONFIG_FRAME_WARN=2048 \
  CONFIG_MODULE_SIG_PROTECT=y \
  CONFIG_MODULE_SIG_ALL=y \
  CONFIG_SYSTEM_TRUSTED_KEYRING=y \
  'CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"' \
  'CONFIG_SYSTEM_TRUSTED_KEYS="xuanyuan_stock_module_signing_cert.pem"' \
  CONFIG_KSU=y \
  CONFIG_THREAD_INFO_IN_TASK=y \
  CONFIG_KSU_SUSFS=y \
  CONFIG_KSU_SUSFS_SUS_PATH=y \
  CONFIG_KSU_SUSFS_SUS_MOUNT=y \
  CONFIG_KSU_SUSFS_SUS_KSTAT=y \
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y \
  CONFIG_KSU_SUSFS_ENABLE_LOG=y \
  CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y \
  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y \
  CONFIG_KSU_SUSFS_OPEN_REDIRECT=y \
  CONFIG_KSU_SUSFS_SUS_MAP=y; do
  grep -qx "$required" "$ARTIFACT_DIR/kernel.config"
done
grep -qx '# CONFIG_MODULE_SIG_FORCE is not set' \
  "$ARTIFACT_DIR/kernel.config"
grep -qx '# CONFIG_SECONDARY_TRUSTED_KEYRING is not set' \
  "$ARTIFACT_DIR/kernel.config"
for disabled in KSU_DEBUG KSU_DISABLE_MANAGER KSU_DISABLE_POLICY; do
  grep -qx "# CONFIG_${disabled} is not set" "$ARTIFACT_DIR/kernel.config"
done

grep -qx 'FEATURE_SET=ksun_susfs_stock_trust' \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "KSU_DEFCONFIG_SHA256=$KSU_DEFCONFIG_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
echo "$KSU_DEFCONFIG_SHA256  $KERNEL_ROOT/common/xuanyuan_ksun_susfs_defconfig" \
  | sha256sum -c -
grep -qx "WORKSPACE_STATUS_SHA256=$WORKSPACE_STATUS_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
echo "$WORKSPACE_STATUS_SHA256  $KERNEL_ROOT/common/workspace_status.json" \
  | sha256sum -c -
grep -qx "STOCK_CERT_PEM_SHA256=$STOCK_CERT_PEM_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_DER_SHA256=$STOCK_CERT_DER_SHA256" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_SERIAL=$STOCK_CERT_SERIAL" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"
grep -qx "STOCK_CERT_SKID=$STOCK_CERT_SKID" \
  "$KERNEL_ROOT/xuanyuan-build-pins.txt"

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

grep -Eq ' [Tt] ksu_' "$DIST_DIR/System.map"
grep -Eq ' T ksu_handle_post_execveat_sucompat$' "$DIST_DIR/System.map"
grep -Eq ' T ksu_app_profile_init$' "$DIST_DIR/System.map"
grep -Eq ' T susfs_init$' "$DIST_DIR/System.map"
grep -Eq ' T susfs_show_version$' "$DIST_DIR/System.map"

echo "$MODULE_SYMVERS_SHA256  $DIST_DIR/kernel_aarch64_Module.symvers" \
  | sha256sum -c -
echo "$ABI_STG_SHA256  $DIST_DIR/abi.stg" | sha256sum -c -
echo "$ABI_FULL_STG_SHA256  $DIST_DIR/abi-full.stg" | sha256sum -c -
if grep -Eq '[[:space:]](ksu_|susfs_)' \
  "$DIST_DIR/kernel_aarch64_Module.symvers"; then
  echo 'unexpected KernelSU/SUSFS KMI export' >&2
  exit 1
fi

install -m 0644 "$IMAGE" "$ARTIFACT_DIR/Image"
for required_artifact in kernel_aarch64_Module.symvers System.map abi.stg abi-full.stg; do
  test -s "$DIST_DIR/$required_artifact"
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
printf 'feature_set=ksun_susfs_stock_trust\nkernel_release=%s\nksu_version=%s\nksu_tag=%s\nksu_uapi=%s\nsusfs_version=v2.3.0\nimage_size=%s\nstock_module_cert_embedded=true\nstock_cert_skid=%s\nstock_image_sha256=%s\ncustom_image_sha256=%s\n' \
  "$EXPECTED_RELEASE" "$EXPECTED_KSU_VERSION" "$EXPECTED_KSU_TAG" \
  "$EXPECTED_KSU_UAPI" \
  "$(stat -c %s "$IMAGE")" "$STOCK_CERT_SKID" \
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
    stock-module-signing-cert.pem \
    stock-module-cert.txt \
    build-metadata.txt \
    > SHA256SUMS
)

echo "Validated Image SHA-256: $custom_sha"
echo "Stock module certificate embedded: true"
