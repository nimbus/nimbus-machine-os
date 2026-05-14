#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: package-oci.sh [options]

Wrap a Nimbus machine raw-disk artifact in the OCI image-layout shape that the
macOS machine manager already consumes from registries.

Options:
  --build-output-dir <path>    Build output directory containing summary.txt
  --summary-file <path>        Explicit build summary file to read
  --raw-disk <path>            Explicit raw/raw.gz/raw.zst machine disk artifact
  --layout-dir <path>          Output OCI image-layout directory
  --image-reference <ref>      Destination image reference used to derive ref name
  --ref-name <name>            Explicit OCI layout ref name (defaults from image reference)
  --arch <arch>                OCI architecture (default: host architecture)
  --os <os>                    OCI operating system (default: linux)
  --disk-type <type>           Provider disk artifact type (default: applehv)
  --source-repository-url <u>  OCI source repository URL
  --source-revision <rev>      Source revision embedded in OCI metadata
  --attestation-repository <r> GitHub repo expected to carry build attestations
  --nimbus-version <tag>       Embedded nimbus version tag (for example vX.Y.Z)
  -h, --help                   Show this help

Examples:
  bash scripts/package-oci.sh \
    --build-output-dir /tmp/nimbus-machine-os \
    --image-reference docker://ghcr.io/nimbus/machine-os:vX.Y.Z \
    --layout-dir /tmp/nimbus-machine-os/oci-layout
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "required command not found: ${command_name}" >&2
    exit 69
  fi
}

summary_value() {
  local summary_file="$1"
  local key="$2"
  awk -F= -v target="${key}" '$1 == target { print substr($0, length($1) + 2) }' "${summary_file}" | tail -n 1
}

normalize_arch() {
  case "$1" in
    aarch64|arm64) printf 'arm64\n' ;;
    x86_64|amd64) printf 'amd64\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

infer_layer_media_type() {
  case "$1" in
    *.raw.gz) printf 'application/vnd.nimbus.machine.disk.layer.v1.raw+gzip\n' ;;
    *.raw.zst) printf 'application/vnd.nimbus.machine.disk.layer.v1.raw+zstd\n' ;;
    *.raw) printf 'application/vnd.nimbus.machine.disk.layer.v1.raw\n' ;;
    *) printf 'application/vnd.nimbus.machine.disk.layer.v1.blob\n' ;;
  esac
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

build_annotation_entries() {
  local ref_name="$1"
  local source_repository_url="$2"
  local source_revision="$3"
  local attestation_repository="$4"
  local nimbus_version="$5"

  printf '"org.opencontainers.image.ref.name":"%s","org.opencontainers.image.source":"%s","io.nimbus.machine.attestation.repository":"%s"' \
    "$(json_escape "${ref_name}")" \
    "$(json_escape "${source_repository_url}")" \
    "$(json_escape "${attestation_repository}")"
  if [[ -n "${source_revision}" ]]; then
    printf ',"org.opencontainers.image.revision":"%s"' "$(json_escape "${source_revision}")"
  fi
  if [[ -n "${nimbus_version}" ]]; then
    printf ',"io.nimbus.machine.nimbus.version":"%s"' "$(json_escape "${nimbus_version}")"
  fi
}

derive_ref_name() {
  local reference="$1"
  local stripped="${reference#docker://}"
  if [[ "${stripped}" == *@* ]]; then
    echo "image reference must use a tag, not a digest, when deriving an OCI layout ref name: ${reference}" >&2
    exit 64
  fi
  local last_component="${stripped##*/}"
  if [[ "${last_component}" == *:* ]]; then
    printf '%s\n' "${last_component##*:}"
  else
    printf 'latest\n'
  fi
}

sha256_hex() {
  sha256sum "$1" | awk '{print $1}'
}

file_size_bytes() {
  wc -c <"$1" | tr -d '[:space:]'
}

build_output_dir=""
summary_file=""
raw_disk_path=""
layout_dir=""
image_reference=""
ref_name=""
oci_arch="$(normalize_arch "${NIMBUS_MACHINE_OS_PACKAGE_TEST_ARCH:-$(uname -m)}")"
oci_os="linux"
disk_type="${NIMBUS_MACHINE_OS_DISK_TYPE:-applehv}"
source_repository_url="${NIMBUS_MACHINE_OS_SOURCE_REPOSITORY_URL:-https://github.com/nimbus/machine-os}"
source_revision="${NIMBUS_MACHINE_OS_SOURCE_REVISION:-}"
attestation_repository="${NIMBUS_MACHINE_OS_ATTESTATION_REPOSITORY:-nimbus/machine-os}"
nimbus_version="${NIMBUS_MACHINE_OS_VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-output-dir)
      build_output_dir="${2:-}"
      shift 2
      ;;
    --summary-file)
      summary_file="${2:-}"
      shift 2
      ;;
    --raw-disk)
      raw_disk_path="${2:-}"
      shift 2
      ;;
    --layout-dir)
      layout_dir="${2:-}"
      shift 2
      ;;
    --image-reference)
      image_reference="${2:-}"
      shift 2
      ;;
    --ref-name)
      ref_name="${2:-}"
      shift 2
      ;;
    --arch)
      oci_arch="$(normalize_arch "${2:-}")"
      shift 2
      ;;
    --os)
      oci_os="${2:-}"
      shift 2
      ;;
    --disk-type)
      disk_type="${2:-}"
      shift 2
      ;;
    --source-repository-url)
      source_repository_url="${2:-}"
      shift 2
      ;;
    --source-revision)
      source_revision="${2:-}"
      shift 2
      ;;
    --attestation-repository)
      attestation_repository="${2:-}"
      shift 2
      ;;
    --nimbus-version)
      nimbus_version="${2:-}"
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

require_command sha256sum
require_command mktemp

if [[ -z "${summary_file}" && -n "${build_output_dir}" ]]; then
  summary_file="${build_output_dir%/}/summary.txt"
fi

if [[ -n "${summary_file}" ]]; then
  if [[ ! -f "${summary_file}" ]]; then
    echo "build summary file not found: ${summary_file}" >&2
    exit 66
  fi
  if [[ -z "${raw_disk_path}" ]]; then
    raw_disk_path="$(summary_value "${summary_file}" compressed_raw_disk_path)"
    if [[ -z "${raw_disk_path}" || "${raw_disk_path}" == "<not-built>" ]]; then
      raw_disk_path="$(summary_value "${summary_file}" raw_disk_path)"
    fi
  fi
  if [[ -z "${nimbus_version}" ]]; then
    nimbus_version="$(summary_value "${summary_file}" nimbus_version)"
    if [[ "${nimbus_version}" == "<unspecified>" ]]; then
      nimbus_version=""
    fi
  fi
  if [[ -z "${source_revision}" ]]; then
    source_revision="$(summary_value "${summary_file}" source_revision)"
    if [[ "${source_revision}" == "<unspecified>" ]]; then
      source_revision=""
    fi
  fi
fi

if [[ -z "${raw_disk_path}" ]]; then
  echo "a raw-disk artifact is required; pass --raw-disk or a summary file with raw_disk_path/compressed_raw_disk_path" >&2
  exit 64
fi
if [[ ! -f "${raw_disk_path}" ]]; then
  echo "raw-disk artifact not found: ${raw_disk_path}" >&2
  exit 66
fi

if [[ -z "${image_reference}" && -z "${ref_name}" ]]; then
  echo "either --image-reference or --ref-name is required" >&2
  exit 64
fi
if [[ -z "${ref_name}" ]]; then
  ref_name="$(derive_ref_name "${image_reference}")"
fi
if [[ -z "${layout_dir}" ]]; then
  base_dir="${build_output_dir:-$(dirname "${raw_disk_path}")}"
  layout_dir="${base_dir%/}/oci-layout"
fi
if [[ -z "${source_repository_url}" ]]; then
  echo "--source-repository-url cannot be empty" >&2
  exit 64
fi
if [[ -z "${attestation_repository}" ]]; then
  echo "--attestation-repository cannot be empty" >&2
  exit 64
fi
if [[ -z "${disk_type}" ]]; then
  echo "--disk-type cannot be empty" >&2
  exit 64
fi

rm -rf "${layout_dir}"
mkdir -p "${layout_dir}/blobs/sha256"

layer_title="$(basename "${raw_disk_path}")"
layer_media_type="$(infer_layer_media_type "${raw_disk_path}")"
layer_size="$(file_size_bytes "${raw_disk_path}")"
layer_hex="$(sha256_hex "${raw_disk_path}")"
layer_digest="sha256:${layer_hex}"
layer_blob_path="${layout_dir}/blobs/sha256/${layer_hex}"
cp "${raw_disk_path}" "${layer_blob_path}"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

manifest_annotations="$(build_annotation_entries \
  "${ref_name}" \
  "${source_repository_url}" \
  "${source_revision}" \
  "${attestation_repository}" \
  "${nimbus_version}")"
index_annotations="$(printf '"disktype":"%s",%s' "$(json_escape "${disk_type}")" "${manifest_annotations}")"

config_path="${temp_dir}/config.json"
cat >"${config_path}" <<EOF
{"architecture":"${oci_arch}","os":"${oci_os}","rootfs":{"type":"layers","diff_ids":[]},"config":{"Labels":{"org.opencontainers.image.source":"$(json_escape "${source_repository_url}")"}}}
EOF
config_size="$(file_size_bytes "${config_path}")"
config_hex="$(sha256_hex "${config_path}")"
config_digest="sha256:${config_hex}"
cp "${config_path}" "${layout_dir}/blobs/sha256/${config_hex}"

manifest_path="${temp_dir}/manifest.json"
cat >"${manifest_path}" <<EOF
{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","annotations":{${manifest_annotations}},"config":{"mediaType":"application/vnd.oci.image.config.v1+json","size":${config_size},"digest":"${config_digest}"},"layers":[{"mediaType":"${layer_media_type}","size":${layer_size},"digest":"${layer_digest}","annotations":{"org.opencontainers.image.title":"${layer_title}"}}]}
EOF
manifest_size="$(file_size_bytes "${manifest_path}")"
manifest_hex="$(sha256_hex "${manifest_path}")"
manifest_digest="sha256:${manifest_hex}"
cp "${manifest_path}" "${layout_dir}/blobs/sha256/${manifest_hex}"

cat >"${layout_dir}/index.json" <<EOF
{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","size":${manifest_size},"digest":"${manifest_digest}","platform":{"architecture":"${oci_arch}","os":"${oci_os}"},"annotations":{${index_annotations}}}]}
EOF
printf '{"imageLayoutVersion":"1.0.0"}\n' >"${layout_dir}/oci-layout"

summary_output="${layout_dir}/summary.txt"
cat >"${summary_output}" <<EOF
raw_disk_path=${raw_disk_path}
image_reference=${image_reference:-<unspecified>}
ref_name=${ref_name}
oci_arch=${oci_arch}
oci_os=${oci_os}
disk_type=${disk_type}
source_repository_url=${source_repository_url}
source_revision=${source_revision:-<unspecified>}
attestation_repository=${attestation_repository}
nimbus_version=${nimbus_version:-<unspecified>}
layer_media_type=${layer_media_type}
layer_title=${layer_title}
layer_digest=${layer_digest}
manifest_digest=${manifest_digest}
layout_dir=${layout_dir}
EOF

printf 'packaged machine OCI layout at %s\n' "${layout_dir}"
