#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: write-sbom.sh --build-summary <path> --output <path> [--oci-summary <path>]

Write a deterministic CycloneDX JSON SBOM for a Nimbus machine-os build from
the build and OCI packaging summaries.

Options:
  --build-summary <path>  Build summary produced by image/build.sh
  --oci-summary <path>    Optional OCI layout summary produced by package-oci.sh
  --output <path>         Output SBOM path
  -h, --help              Show this help
EOF
}

summary_value() {
  local summary_file="$1"
  local key="$2"
  if [[ -z "${summary_file}" || ! -f "${summary_file}" ]]; then
    return
  fi
  awk -F= -v target="${key}" '$1 == target { print substr($0, length($1) + 2) }' "${summary_file}" | tail -n 1
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

json_pair() {
  local name="$1"
  local value="$2"
  printf '{"name":"%s","value":"%s"}' \
    "$(json_escape "${name}")" \
    "$(json_escape "${value}")"
}

component_property_block() {
  local first=1
  for pair in "$@"; do
    local name="${pair%%=*}"
    local value="${pair#*=}"
    if [[ -z "${value}" || "${value}" == "<unspecified>" || "${value}" == "<not-built>" ]]; then
      continue
    fi
    if [[ "${first}" -eq 0 ]]; then
      printf ','
    fi
    json_pair "${name}" "${value}"
    first=0
  done
}

component_hash_block() {
  local first=1
  for pair in "$@"; do
    local algorithm="${pair%%=*}"
    local content="${pair#*=}"
    if [[ -z "${content}" || "${content}" == "<unspecified>" || "${content}" == "<not-built>" ]]; then
      continue
    fi
    if [[ "${first}" -eq 0 ]]; then
      printf ','
    fi
    printf '{"alg":"%s","content":"%s"}' \
      "$(json_escape "${algorithm}")" \
      "$(json_escape "${content}")"
    first=0
  done
}

build_summary=""
oci_summary=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-summary)
      build_summary="${2:-}"
      shift 2
      ;;
    --oci-summary)
      oci_summary="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "${build_summary}" ]]; then
  echo "--build-summary is required" >&2
  exit 64
fi
if [[ ! -f "${build_summary}" ]]; then
  echo "build summary not found: ${build_summary}" >&2
  exit 66
fi
if [[ -z "${output_path}" ]]; then
  echo "--output is required" >&2
  exit 64
fi
if [[ -n "${oci_summary}" && ! -f "${oci_summary}" ]]; then
  echo "OCI summary not found: ${oci_summary}" >&2
  exit 66
fi

mkdir -p "$(dirname "${output_path}")"

nimbus_version="$(summary_value "${build_summary}" nimbus_version)"
source_revision="$(summary_value "${build_summary}" source_revision)"
fedora_bootc_base_image="$(summary_value "${build_summary}" fedora_bootc_base_image)"
bib_image="$(summary_value "${build_summary}" bib_image)"
rootfs="$(summary_value "${build_summary}" bootc_image_builder_rootfs)"
provisioning_contract="$(summary_value "${build_summary}" provisioning_contract)"
package_inventory="$(summary_value "${build_summary}" package_inventory)"
nimbus_binary_sha256="$(summary_value "${build_summary}" nimbus_binary_sha256)"
raw_disk_sha256="$(summary_value "${build_summary}" raw_disk_sha256)"
compressed_raw_disk_sha256="$(summary_value "${build_summary}" compressed_raw_disk_sha256)"
oci_archive_sha256="$(summary_value "${build_summary}" oci_archive_sha256)"
manifest_digest="$(summary_value "${oci_summary}" manifest_digest)"
layer_digest="$(summary_value "${oci_summary}" layer_digest)"
disk_type="$(summary_value "${oci_summary}" disk_type)"

{
  printf '{\n'
  printf '  "bomFormat": "CycloneDX",\n'
  printf '  "specVersion": "1.5",\n'
  printf '  "version": 1,\n'
  printf '  "metadata": {\n'
  printf '    "tools": [{"vendor": "Nimbus", "name": "scripts/write-sbom.sh"}],\n'
  printf '    "component": {\n'
  printf '      "type": "operating-system",\n'
  printf '      "name": "nimbus-machine-os",\n'
  printf '      "version": "%s",\n' "$(json_escape "${nimbus_version:-unknown}")"
  printf '      "properties": ['
  component_property_block \
    "org.opencontainers.image.revision=${source_revision}" \
    "io.nimbus.machine.fedora_bootc_base_image=${fedora_bootc_base_image}" \
    "io.nimbus.machine.bootc_image_builder=${bib_image}" \
    "io.nimbus.machine.rootfs=${rootfs}" \
    "io.nimbus.machine.provisioning_contract=${provisioning_contract}" \
    "io.nimbus.machine.disk_type=${disk_type}" \
    "io.nimbus.machine.oci_manifest_digest=${manifest_digest}" \
    "io.nimbus.machine.oci_layer_digest=${layer_digest}"
  printf ']\n'
  printf '    }\n'
  printf '  },\n'
  printf '  "components": [\n'
  printf '    {"type": "application", "name": "nimbus", "version": "%s", "hashes": [' "$(json_escape "${nimbus_version:-unknown}")"
  component_hash_block "SHA-256=${nimbus_binary_sha256}"
  printf ']},\n'
  printf '    {"type": "container", "name": "fedora-bootc-base", "version": "%s"},\n' "$(json_escape "${fedora_bootc_base_image}")"
  printf '    {"type": "container", "name": "bootc-image-builder", "version": "%s"},\n' "$(json_escape "${bib_image}")"
  printf '    {"type": "file", "name": "nimbus-machine-os.raw", "hashes": ['
  component_hash_block "SHA-256=${raw_disk_sha256}"
  printf ']},\n'
  printf '    {"type": "file", "name": "nimbus-machine-os.raw.gz", "hashes": ['
  component_hash_block "SHA-256=${compressed_raw_disk_sha256}"
  printf ']},\n'
  printf '    {"type": "file", "name": "nimbus-machine-os.ociarchive", "hashes": ['
  component_hash_block "SHA-256=${oci_archive_sha256}"
  printf ']}'

  if [[ -n "${package_inventory}" ]]; then
    IFS=',' read -r -a packages <<<"${package_inventory}"
    for package in "${packages[@]}"; do
      package="${package#"${package%%[![:space:]]*}"}"
      package="${package%"${package##*[![:space:]]}"}"
      if [[ -z "${package}" ]]; then
        continue
      fi
      printf ',\n'
      printf '    {"type": "library", "name": "%s", "properties": [' "$(json_escape "${package}")"
      component_property_block "io.nimbus.machine.package_source=fedora-44"
      printf ']}'
    done
  fi
  printf '\n'
  printf '  ]\n'
  printf '}\n'
} >"${output_path}"

printf 'wrote machine-os SBOM at %s\n' "${output_path}"
