#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/test-helpers.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

raw_disk_path="${temp_dir}/nimbus-machine-os.raw.gz"
printf 'raw-disk-bytes-for-publish-test' | gzip -c >"${raw_disk_path}"
sbom_path="${temp_dir}/nimbus-machine-os.sbom.cdx.json"
cat >"${sbom_path}" <<'EOF'
{"bomFormat":"CycloneDX","specVersion":"1.5","version":1}
EOF

layout_dir="${temp_dir}/oci-layout"
bash "${repo_root}/scripts/package-oci.sh" \
  --raw-disk "${raw_disk_path}" \
  --image-reference docker://ghcr.io/nimbus/machine-os:latest \
  --layout-dir "${layout_dir}" \
  --arch arm64 \
  --source-repository-url https://github.com/nimbus/machine-os \
  --source-revision fedcba987654 \
  --attestation-repository nimbus/machine-os \
  --nimbus-version v9.9.9

mkdir -p "${temp_dir}/bin"
write_executable_stub "${temp_dir}/bin/skopeo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TMPDIR}/skopeo.log"
for ((index = 1; index <= $#; index++)); do
  if [[ "${!index}" == "--digestfile" ]]; then
    next_index=$((index + 1))
    printf 'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n' >"${!next_index}"
  fi
done
exit 0
EOF

release_dir="${temp_dir}/release"
build_output_dir="${temp_dir}/build-output"
mkdir -p "${build_output_dir}"
cat >"${build_output_dir}/summary.txt" <<EOF
compressed_raw_disk_path=${raw_disk_path}
sbom_path=${sbom_path}
EOF
PATH="${temp_dir}/bin:${PATH}" \
TMPDIR="${temp_dir}" \
NIMBUS_MACHINE_OS_REGISTRY_USERNAME=nimbus \
NIMBUS_MACHINE_OS_REGISTRY_PASSWORD=secret \
bash "${repo_root}/scripts/publish.sh" \
  --layout-dir "${layout_dir}" \
  --build-output-dir "${build_output_dir}" \
  --image-reference docker://ghcr.io/nimbus/machine-os:latest \
  --additional-reference docker://ghcr.io/nimbus/machine-os:next \
  --release-dir "${release_dir}"

grep -F -- '--dest-creds nimbus:secret' "${temp_dir}/skopeo.log" >/dev/null
grep -F -- "oci:${layout_dir}:latest" "${temp_dir}/skopeo.log" >/dev/null
grep -F -- 'docker://ghcr.io/nimbus/machine-os:latest' "${temp_dir}/skopeo.log" >/dev/null
grep -F -- 'docker://ghcr.io/nimbus/machine-os:next' "${temp_dir}/skopeo.log" >/dev/null
test -f "${release_dir}/oci-layout-summary.txt"
test -f "${release_dir}/build-summary.txt"
test -f "${release_dir}/nimbus-machine-os.raw.gz"
test -f "${release_dir}/nimbus-machine-os.sbom.cdx.json"
test -f "${release_dir}/checksums.txt"
test -f "${release_dir}/publish-summary.txt"
grep -F 'image_reference=docker://ghcr.io/nimbus/machine-os:latest' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'image_digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'image_digest_reference=ghcr.io/nimbus/machine-os:latest@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'additional_references=docker://ghcr.io/nimbus/machine-os:next' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'published_digests=ghcr.io/nimbus/machine-os:latest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef,ghcr.io/nimbus/machine-os:next=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "${release_dir}/publish-summary.txt" >/dev/null
grep -F 'source_repository_url=https://github.com/nimbus/machine-os' "${release_dir}/oci-layout-summary.txt" >/dev/null
grep -F 'source_revision=fedcba987654' "${release_dir}/oci-layout-summary.txt" >/dev/null
grep -F 'attestation_repository=nimbus/machine-os' "${release_dir}/oci-layout-summary.txt" >/dev/null
grep -F 'nimbus_version=v9.9.9' "${release_dir}/oci-layout-summary.txt" >/dev/null
grep -F 'disk_type=applehv' "${release_dir}/oci-layout-summary.txt" >/dev/null
test -f "${release_dir}/published-digests.txt"
test -f "${release_dir}/machine-image-reference.txt"
grep -F 'ghcr.io/nimbus/machine-os:latest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "${release_dir}/published-digests.txt" >/dev/null
grep -F 'tag_reference=ghcr.io/nimbus/machine-os:latest' "${release_dir}/machine-image-reference.txt" >/dev/null
grep -F 'digest_reference=ghcr.io/nimbus/machine-os:latest@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "${release_dir}/machine-image-reference.txt" >/dev/null
grep -F 'publish-summary.txt' "${release_dir}/checksums.txt" >/dev/null
grep -F 'published-digests.txt' "${release_dir}/checksums.txt" >/dev/null
grep -F 'machine-image-reference.txt' "${release_dir}/checksums.txt" >/dev/null
if grep -F 'disk_type=raw' "${release_dir}/oci-layout-summary.txt" >/dev/null; then
  echo "published macOS OCI artifact must record disk_type=applehv, not raw" >&2
  exit 1
fi

printf 'verified nimbus machine-os publish wrapper\n'
