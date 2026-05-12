#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/test-helpers.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

raw_disk_path="${temp_dir}/nimbus-machine-os.raw.gz"
printf 'raw-disk-bytes-for-publish-test' | gzip -c >"${raw_disk_path}"

layout_dir="${temp_dir}/oci-layout"
bash "${repo_root}/scripts/package-oci.sh" \
  --raw-disk "${raw_disk_path}" \
  --image-reference docker://ghcr.io/nimbus/nimbus-machine-os:latest \
  --layout-dir "${layout_dir}" \
  --arch arm64 \
  --source-repository-url https://github.com/nimbus/nimbus-machine-os \
  --attestation-repository nimbus/nimbus-machine-os \
  --nimbus-version v9.9.9

mkdir -p "${temp_dir}/bin"
write_executable_stub "${temp_dir}/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TMPDIR}/skopeo.log"
exit 0
EOF

release_dir="${temp_dir}/release"
PATH="${temp_dir}/bin:${PATH}" \
TMPDIR="${temp_dir}" \
NIMBUS_MACHINE_OS_REGISTRY_USERNAME=nimbus \
NIMBUS_MACHINE_OS_REGISTRY_PASSWORD=secret \
bash "${repo_root}/scripts/publish.sh" \
  --layout-dir "${layout_dir}" \
  --image-reference docker://ghcr.io/nimbus/nimbus-machine-os:latest \
  --additional-reference docker://ghcr.io/nimbus/nimbus-machine-os:next \
  --release-dir "${release_dir}"

grep -F -- '--dest-creds nimbus:secret' "${temp_dir}/skopeo.log" >/dev/null
grep -F -- "oci:${layout_dir}:latest" "${temp_dir}/skopeo.log" >/dev/null
grep -F -- 'docker://ghcr.io/nimbus/nimbus-machine-os:latest' "${temp_dir}/skopeo.log" >/dev/null
grep -F -- 'docker://ghcr.io/nimbus/nimbus-machine-os:next' "${temp_dir}/skopeo.log" >/dev/null
test -f "${release_dir}/oci-layout-summary.txt"
test -f "${release_dir}/checksums.txt"
test -f "${release_dir}/publish-summary.txt"
grep -F 'image_reference=docker://ghcr.io/nimbus/nimbus-machine-os:latest' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'additional_references=docker://ghcr.io/nimbus/nimbus-machine-os:next' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'source_repository_url=https://github.com/nimbus/nimbus-machine-os' "${release_dir}/oci-layout-summary.txt" >/dev/null
grep -F 'attestation_repository=nimbus/nimbus-machine-os' "${release_dir}/oci-layout-summary.txt" >/dev/null
grep -F 'nimbus_version=v9.9.9' "${release_dir}/oci-layout-summary.txt" >/dev/null

printf 'verified nimbus machine-os publish wrapper\n'
