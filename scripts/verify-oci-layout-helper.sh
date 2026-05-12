#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

raw_disk_path="${temp_dir}/nimbus-machine-os.raw.gz"
printf 'raw-disk-bytes-for-layout-test' | gzip -c >"${raw_disk_path}"

layout_dir="${temp_dir}/oci-layout"
bash "${repo_root}/scripts/package-oci.sh" \
  --raw-disk "${raw_disk_path}" \
  --image-reference docker://ghcr.io/nimbus/nimbus-machine-os:v1.2.3 \
  --layout-dir "${layout_dir}" \
  --arch arm64 \
  --source-repository-url https://github.com/nimbus/nimbus-machine-os \
  --attestation-repository nimbus/nimbus \
  --nimbus-version v1.2.3

test -f "${layout_dir}/oci-layout"
test -f "${layout_dir}/index.json"
test -f "${layout_dir}/summary.txt"
grep -F '"disktype":"raw"' "${layout_dir}/index.json" >/dev/null
grep -F '"org.opencontainers.image.ref.name":"v1.2.3"' "${layout_dir}/index.json" >/dev/null
grep -F '"org.opencontainers.image.source":"https://github.com/nimbus/nimbus-machine-os"' "${layout_dir}/index.json" >/dev/null
grep -F '"io.nimbus.machine.attestation.repository":"nimbus/nimbus"' "${layout_dir}/index.json" >/dev/null
grep -F '"io.nimbus.machine.nimbus.version":"v1.2.3"' "${layout_dir}/index.json" >/dev/null
grep -F 'layer_media_type=application/vnd.nimbus.machine.disk.layer.v1.raw+gzip' "${layout_dir}/summary.txt" >/dev/null
grep -F 'oci_arch=arm64' "${layout_dir}/summary.txt" >/dev/null
grep -F 'image_reference=docker://ghcr.io/nimbus/nimbus-machine-os:v1.2.3' "${layout_dir}/summary.txt" >/dev/null
grep -F 'source_repository_url=https://github.com/nimbus/nimbus-machine-os' "${layout_dir}/summary.txt" >/dev/null
grep -F 'attestation_repository=nimbus/nimbus' "${layout_dir}/summary.txt" >/dev/null
grep -F 'nimbus_version=v1.2.3' "${layout_dir}/summary.txt" >/dev/null

printf 'verified nimbus machine-os OCI layout packaging\n'
