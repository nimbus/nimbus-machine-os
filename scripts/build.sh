#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: build.sh --nimbus-binary <path> [options]

Build the nimbus-machine-os guest image on a Linux host using the checked-in
direct Fedora bootc image recipe and a pre-built Linux nimbus binary.

Options:
  --nimbus-binary <path>              Linux nimbus binary to install into the guest (required)
  --nimbus-version <tag>              Embedded nimbus version tag recorded in the build summary
  --source-revision <rev>             Source revision recorded in the build summary
  --output-dir <path>                 Output directory passed through to the image recipe
  --image-name <reference>            OCI tag passed through to the image recipe
  --fedora-bootc-base-image <ref>     Fedora bootc base image passed through to the recipe
  --bib-image <reference>             bootc-image-builder image passed through to the recipe
  --rootfs <name>                     bootc-image-builder rootfs passed through to the recipe
  --context-dir <path>                Reused staging context passed through to the image recipe
  --no-cache                          Force a fresh container image build
  -h, --help                          Show this help

Examples:
  sudo bash scripts/build.sh \
    --nimbus-binary /path/to/nimbus-linux-aarch64 \
    --output-dir /tmp/nimbus-machine-os
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "required command not found: ${command_name}" >&2
    exit 69
  fi
}

nimbus_binary=""
nimbus_version=""
source_revision="${NIMBUS_MACHINE_OS_SOURCE_REVISION:-}"
output_dir=""
image_name=""
fedora_bootc_base_image=""
bib_image=""
rootfs=""
context_dir=""
no_cache="${NIMBUS_MACHINE_OS_BUILD_NO_CACHE:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nimbus-binary)
      nimbus_binary="${2:-}"
      shift 2
      ;;
    --nimbus-version)
      nimbus_version="${2:-}"
      shift 2
      ;;
    --source-revision)
      source_revision="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --image-name)
      image_name="${2:-}"
      shift 2
      ;;
    --fedora-bootc-base-image)
      fedora_bootc_base_image="${2:-}"
      shift 2
      ;;
    --bib-image)
      bib_image="${2:-}"
      shift 2
      ;;
    --rootfs)
      rootfs="${2:-}"
      shift 2
      ;;
    --context-dir)
      context_dir="${2:-}"
      shift 2
      ;;
    --no-cache)
      no_cache=1
      shift
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

os_name="${NIMBUS_MACHINE_OS_BUILD_WRAPPER_TEST_UNAME:-$(uname -s)}"
if [[ "${os_name}" != "Linux" ]]; then
  echo "build.sh requires a Linux host" >&2
  exit 69
fi

if [[ -z "${nimbus_binary}" ]]; then
  echo "--nimbus-binary is required" >&2
  usage >&2
  exit 64
fi

require_command bash

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe_script="${repo_root}/image/build.sh"

if [[ ! -f "${recipe_script}" ]]; then
  echo "image recipe entrypoint not found: ${recipe_script}" >&2
  exit 66
fi

if [[ ! -f "${nimbus_binary}" ]]; then
  echo "nimbus binary not found: ${nimbus_binary}" >&2
  exit 66
fi

echo "build.nimbus_binary=${nimbus_binary}"
echo "build.recipe=${recipe_script}"

args=(--nimbus-binary "${nimbus_binary}")
if [[ -n "${output_dir}" ]]; then
  args+=(--output-dir "${output_dir}")
fi
if [[ -n "${nimbus_version}" ]]; then
  args+=(--nimbus-version "${nimbus_version}")
fi
if [[ -n "${source_revision}" ]]; then
  args+=(--source-revision "${source_revision}")
fi
if [[ -n "${image_name}" ]]; then
  args+=(--image-name "${image_name}")
fi
if [[ -n "${fedora_bootc_base_image}" ]]; then
  args+=(--fedora-bootc-base-image "${fedora_bootc_base_image}")
fi
if [[ -n "${bib_image}" ]]; then
  args+=(--bib-image "${bib_image}")
fi
if [[ -n "${rootfs}" ]]; then
  args+=(--rootfs "${rootfs}")
fi
if [[ -n "${context_dir}" ]]; then
  args+=(--context-dir "${context_dir}")
fi
if [[ "${no_cache}" == "1" || "${no_cache}" == "true" ]]; then
  args+=(--no-cache)
fi

bash "${recipe_script}" "${args[@]}"
