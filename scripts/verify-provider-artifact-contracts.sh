#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

summary_value() {
  local summary_file="$1"
  local key="$2"
  awk -F= -v target="${key}" '$1 == target { print substr($0, length($1) + 2) }' "${summary_file}" | tail -n 1
}

verify_layout() {
  local layout_dir="$1"
  local expected_disk_type="$2"
  local expected_media_type="$3"
  local expected_arch="$4"
  local expected_ref="$5"

  test -f "${layout_dir}/oci-layout"
  test -f "${layout_dir}/index.json"
  test -f "${layout_dir}/summary.txt"
  grep -F '"disktype":"'"${expected_disk_type}"'"' "${layout_dir}/index.json" >/dev/null
  grep -F "disk_type=${expected_disk_type}" "${layout_dir}/summary.txt" >/dev/null
  grep -F "layer_media_type=${expected_media_type}" "${layout_dir}/summary.txt" >/dev/null
  grep -F "oci_arch=${expected_arch}" "${layout_dir}/summary.txt" >/dev/null
  grep -F "image_reference=${expected_ref}" "${layout_dir}/summary.txt" >/dev/null
  grep -F 'artifact_path=' "${layout_dir}/summary.txt" >/dev/null
}

macos_artifact="${temp_dir}/nimbus-machine-os.raw.gz"
printf 'macos-raw-bytes' | gzip -c >"${macos_artifact}"
macos_layout="${temp_dir}/applehv-layout"
bash "${repo_root}/scripts/package-oci.sh" \
  --artifact "${macos_artifact}" \
  --image-reference docker://ghcr.io/nimbus/machine-os:v9.9.9 \
  --layout-dir "${macos_layout}" \
  --arch arm64 \
  --disk-type applehv \
  --source-repository-url https://github.com/nimbus/machine-os \
  --source-revision applehvrev \
  --attestation-repository nimbus/machine-os \
  --nimbus-version v9.9.9
verify_layout \
  "${macos_layout}" \
  applehv \
  application/vnd.nimbus.machine.disk.layer.v1.raw+gzip \
  arm64 \
  docker://ghcr.io/nimbus/machine-os:v9.9.9
if grep -F '"disktype":"raw"' "${macos_layout}/index.json" >/dev/null; then
  echo "macOS artifact must be selected with disktype=applehv, not raw" >&2
  exit 1
fi

rootfs_dir="${temp_dir}/rootfs"
mkdir -p "${rootfs_dir}/etc" "${rootfs_dir}/usr/local/bin"
printf 'NAME=Nimbus WSL Rootfs Proof\n' >"${rootfs_dir}/etc/os-release"
printf '#!/bin/sh\nexit 0\n' >"${rootfs_dir}/usr/local/bin/nimbus"
chmod +x "${rootfs_dir}/usr/local/bin/nimbus"
wsl_artifact="${temp_dir}/nimbus-machine-os-wsl-rootfs.tar.gz"
tar -C "${rootfs_dir}" -czf "${wsl_artifact}" .
wsl_layout="${temp_dir}/wsl-layout"
bash "${repo_root}/scripts/package-oci.sh" \
  --artifact "${wsl_artifact}" \
  --image-reference docker://ghcr.io/nimbus/machine-os:v9.9.9-wsl-proof \
  --layout-dir "${wsl_layout}" \
  --arch amd64 \
  --disk-type wsl \
  --source-repository-url https://github.com/nimbus/machine-os \
  --source-revision wslrev \
  --attestation-repository nimbus/machine-os \
  --nimbus-version v9.9.9
verify_layout \
  "${wsl_layout}" \
  wsl \
  application/vnd.nimbus.machine.rootfs.layer.v1.tar+gzip \
  amd64 \
  docker://ghcr.io/nimbus/machine-os:v9.9.9-wsl-proof
if grep -F '"disktype":"applehv"' "${wsl_layout}/index.json" >/dev/null; then
  echo "WSL proof artifact must not be labeled as applehv" >&2
  exit 1
fi

test "$(summary_value "${wsl_layout}/summary.txt" layer_title)" = "$(basename "${wsl_artifact}")"

hyperv_artifact="${temp_dir}/nimbus-machine-os-hyperv.vhdx"
printf 'hyperv-vhdx-proof-bytes' >"${hyperv_artifact}"
hyperv_layout="${temp_dir}/hyperv-layout"
bash "${repo_root}/scripts/package-oci.sh" \
  --artifact "${hyperv_artifact}" \
  --image-reference docker://ghcr.io/nimbus/machine-os:v9.9.9-hyperv-proof \
  --layout-dir "${hyperv_layout}" \
  --arch amd64 \
  --disk-type hyperv \
  --source-repository-url https://github.com/nimbus/machine-os \
  --source-revision hypervrev \
  --attestation-repository nimbus/machine-os \
  --nimbus-version v9.9.9
verify_layout \
  "${hyperv_layout}" \
  hyperv \
  application/vnd.nimbus.machine.disk.layer.v1.vhdx \
  amd64 \
  docker://ghcr.io/nimbus/machine-os:v9.9.9-hyperv-proof

printf 'verified nimbus machine-os provider artifact contracts\n'
