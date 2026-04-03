#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <kernel-workspace-root>" >&2
  echo "Example: $0 /Volumes/NEZHA_GKI_BUILD/nezha-a16-6.12-mini-01" >&2
  exit 1
fi

WORKSPACE_ROOT="$(cd "$1" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="$(cd "${WK_ROOT}/.." && pwd)"
PATCH_DIR="${BASE_DIR}/kernel_patches/xiaomi/nezha/6.12"

FRAGMENT_SRC="${PATCH_DIR}/wild_gki.nezha.fragment"
SYMBOL_SRC="${PATCH_DIR}/abi_gki_aarch64_xiaomi.nezha"
FRAGMENT_DST="${WORKSPACE_ROOT}/wild_gki.fragment"

if [[ ! -d "${WORKSPACE_ROOT}/kernel/common" ]]; then
  echo "Missing kernel/common under ${WORKSPACE_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${FRAGMENT_SRC}" || ! -f "${SYMBOL_SRC}" ]]; then
  echo "Missing Nezha patch assets under ${PATCH_DIR}" >&2
  exit 1
fi

touch "${FRAGMENT_DST}"
if ! grep -qxF "# Nezha 6.12 stock-aligned fragment" "${FRAGMENT_DST}" 2>/dev/null; then
  {
    printf '\n# Nezha 6.12 stock-aligned fragment\n'
    cat "${FRAGMENT_SRC}"
  } >> "${FRAGMENT_DST}"
fi

if [[ -f "${WORKSPACE_ROOT}/kernel/common/gki/aarch64/symbols/xiaomi" ]]; then
  ABI_DST="${WORKSPACE_ROOT}/kernel/common/gki/aarch64/symbols/xiaomi"
elif [[ -f "${WORKSPACE_ROOT}/kernel/common/android/abi_gki_aarch64_xiaomi" ]]; then
  ABI_DST="${WORKSPACE_ROOT}/kernel/common/android/abi_gki_aarch64_xiaomi"
else
  echo "Missing Xiaomi KMI symbol list in ${WORKSPACE_ROOT}/kernel/common" >&2
  exit 1
fi

if [[ ! -f "${ABI_DST}" ]]; then
  echo "Missing ABI file: ${ABI_DST}" >&2
  exit 1
fi

tmp_file="$(mktemp)"
cat "${ABI_DST}" > "${tmp_file}"
while IFS= read -r symbol; do
  [[ -z "${symbol}" ]] && continue
  [[ "${symbol}" =~ ^# ]] && continue
  if ! grep -qxF "${symbol}" "${tmp_file}"; then
    echo "${symbol}" >> "${tmp_file}"
  fi
done < "${SYMBOL_SRC}"
sort -u "${tmp_file}" > "${ABI_DST}"
rm -f "${tmp_file}"

echo "Prepared Nezha local build assets in ${WORKSPACE_ROOT}"
