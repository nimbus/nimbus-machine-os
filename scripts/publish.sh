#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: publish.sh [options]

Push a packaged Nimbus machine raw-disk OCI layout to a registry and stage a
release bundle if requested.

Options:
  --layout-dir <path>              OCI image-layout directory to publish
  --layout-summary <path>          Explicit OCI layout summary file
  --build-output-dir <path>        Optional build output dir for release staging
  --image-reference <ref>          Destination image reference
  --additional-reference <ref>     Additional tag/reference to push (repeatable)
  --release-dir <path>             Optional directory for staged release assets
  --layout-ref-name <name>         OCI layout ref name override
  -h, --help                       Show this help

Environment:
  NIMBUS_MACHINE_OS_REGISTRY_USERNAME  Optional registry username
  NIMBUS_MACHINE_OS_REGISTRY_PASSWORD  Optional registry password

Example:
  bash scripts/publish.sh \
    --layout-dir /tmp/nimbus-machine-os/oci-layout \
    --image-reference docker://ghcr.io/nimbus/nimbus-machine-os:vX.Y.Z \
    --additional-reference docker://ghcr.io/nimbus/nimbus-machine-os:stable \
    --release-dir /tmp/nimbus-machine-os/release
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

layout_dir=""
layout_summary=""
build_output_dir=""
image_reference=""
layout_ref_name=""
release_dir=""
declare -a additional_references=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --layout-dir)
      layout_dir="${2:-}"
      shift 2
      ;;
    --layout-summary)
      layout_summary="${2:-}"
      shift 2
      ;;
    --build-output-dir)
      build_output_dir="${2:-}"
      shift 2
      ;;
    --image-reference)
      image_reference="${2:-}"
      shift 2
      ;;
    --additional-reference)
      additional_references+=("${2:-}")
      shift 2
      ;;
    --release-dir)
      release_dir="${2:-}"
      shift 2
      ;;
    --layout-ref-name)
      layout_ref_name="${2:-}"
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

require_command skopeo
require_command sha256sum
require_command mktemp

if [[ -z "${image_reference}" ]]; then
  echo "--image-reference is required" >&2
  exit 64
fi
if [[ -z "${layout_summary}" && -n "${layout_dir}" ]]; then
  layout_summary="${layout_dir%/}/summary.txt"
fi
if [[ -z "${layout_summary}" ]]; then
  echo "--layout-summary or --layout-dir is required" >&2
  exit 64
fi
if [[ ! -f "${layout_summary}" ]]; then
  echo "layout summary file not found: ${layout_summary}" >&2
  exit 66
fi
if [[ -z "${layout_dir}" ]]; then
  layout_dir="$(summary_value "${layout_summary}" layout_dir)"
fi
if [[ ! -d "${layout_dir}" ]]; then
  echo "OCI layout directory not found: ${layout_dir}" >&2
  exit 66
fi
if [[ -z "${layout_ref_name}" ]]; then
  layout_ref_name="$(summary_value "${layout_summary}" ref_name)"
fi
if [[ -z "${layout_ref_name}" ]]; then
  echo "unable to determine OCI layout ref name from ${layout_summary}" >&2
  exit 65
fi

copy_args=(copy --all --retry-times 3)
if [[ -n "${NIMBUS_MACHINE_OS_REGISTRY_USERNAME:-}" || -n "${NIMBUS_MACHINE_OS_REGISTRY_PASSWORD:-}" ]]; then
  if [[ -z "${NIMBUS_MACHINE_OS_REGISTRY_USERNAME:-}" || -z "${NIMBUS_MACHINE_OS_REGISTRY_PASSWORD:-}" ]]; then
    echo "both NIMBUS_MACHINE_OS_REGISTRY_USERNAME and NIMBUS_MACHINE_OS_REGISTRY_PASSWORD are required together" >&2
    exit 64
  fi
  copy_args+=(--dest-creds "${NIMBUS_MACHINE_OS_REGISTRY_USERNAME}:${NIMBUS_MACHINE_OS_REGISTRY_PASSWORD}")
fi

source_ref="oci:${layout_dir}:${layout_ref_name}"
refs_to_publish=("${image_reference}" "${additional_references[@]}")
digest_dir="$(mktemp -d)"
trap 'rm -rf "${digest_dir}"' EXIT
declare -a published_digest_entries=()
primary_digest=""
primary_digest_reference=""

for index in "${!refs_to_publish[@]}"; do
  reference="${refs_to_publish[${index}]}"
  destination_ref="docker://${reference#docker://}"
  digest_file="${digest_dir}/digest-${index}.txt"
  skopeo "${copy_args[@]}" --digestfile "${digest_file}" "${source_ref}" "${destination_ref}"
  published_digest="$(tr -d '[:space:]' <"${digest_file}")"
  if [[ -z "${published_digest}" ]]; then
    echo "skopeo did not write a published manifest digest for ${destination_ref}" >&2
    exit 65
  fi
  digest_reference="${destination_ref#docker://}@${published_digest}"
  published_digest_entries+=("${destination_ref#docker://}=${published_digest}")
  if [[ "${index}" -eq 0 ]]; then
    primary_digest="${published_digest}"
    primary_digest_reference="${digest_reference}"
  fi
done

if [[ -n "${release_dir}" ]]; then
  mkdir -p "${release_dir}"

  if [[ -n "${build_output_dir}" && -f "${build_output_dir%/}/summary.txt" ]]; then
    cp "${build_output_dir%/}/summary.txt" "${release_dir}/build-summary.txt"
    raw_disk_path="$(summary_value "${build_output_dir%/}/summary.txt" compressed_raw_disk_path)"
    if [[ -z "${raw_disk_path}" || "${raw_disk_path}" == "<not-built>" ]]; then
      raw_disk_path="$(summary_value "${build_output_dir%/}/summary.txt" raw_disk_path)"
    fi
    if [[ -n "${raw_disk_path}" && "${raw_disk_path}" != "<not-built>" && -f "${raw_disk_path}" ]]; then
      cp "${raw_disk_path}" "${release_dir}/$(basename "${raw_disk_path}")"
    fi
    sbom_path="$(summary_value "${build_output_dir%/}/summary.txt" sbom_path)"
    if [[ -n "${sbom_path}" && "${sbom_path}" != "<not-built>" && -f "${sbom_path}" ]]; then
      cp "${sbom_path}" "${release_dir}/$(basename "${sbom_path}")"
    fi
  fi

  cp "${layout_summary}" "${release_dir}/oci-layout-summary.txt"
  printf '%s\n' "${published_digest_entries[@]}" >"${release_dir}/published-digests.txt"
  {
    printf 'tag_reference=%s\n' "${image_reference#docker://}"
    printf 'digest_reference=%s\n' "${primary_digest_reference}"
    printf 'digest=%s\n' "${primary_digest}"
  } >"${release_dir}/machine-image-reference.txt"
fi

publish_summary="${release_dir:-${layout_dir}}/publish-summary.txt"
{
  printf 'layout_dir=%s\n' "${layout_dir}"
  printf 'layout_ref_name=%s\n' "${layout_ref_name}"
  printf 'image_reference=%s\n' "${image_reference}"
  printf 'image_digest=%s\n' "${primary_digest}"
  printf 'image_digest_reference=%s\n' "${primary_digest_reference}"
  if [[ ${#additional_references[@]} -gt 0 ]]; then
    printf 'additional_references=%s\n' "$(IFS=,; printf '%s' "${additional_references[*]}")"
  else
    printf 'additional_references=<none>\n'
  fi
  printf 'published_digests=%s\n' "$(IFS=,; printf '%s' "${published_digest_entries[*]}")"
  printf 'release_dir=%s\n' "${release_dir:-<not-staged>}"
} >"${publish_summary}"

if [[ -n "${release_dir}" ]]; then
  (
    cd "${release_dir}"
    rm -f checksums.txt
    sha256sum ./* >checksums.txt
  )
fi

printf 'published machine OCI layout from %s\n' "${layout_dir}"
