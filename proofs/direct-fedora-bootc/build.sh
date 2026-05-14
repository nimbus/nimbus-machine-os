#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build.sh --nimbus-binary <path> [options]

Build the direct Fedora bootc Nimbus machine proof image on a Linux host.

Options:
  --nimbus-binary <path>                 Linux nimbus binary to install into the guest
  --nimbus-version <tag>                 Embedded nimbus version tag recorded in summary output
  --source-revision <rev>                Source revision recorded in summary output
  --output-dir <path>                   Output directory (default: ./out)
  --image-name <reference>              Local OCI tag (default: localhost/nimbus-machine-os-fedora-bootc-proof:dev)
  --fedora-bootc-base-image <reference> Fedora bootc base image
  --bib-image <reference>               bootc-image-builder image
  --rootfs <name>                       bootc-image-builder rootfs (default: ext4)
  --context-dir <path>                  Reuse a specific staging context instead of mktemp
  --no-cache                            Force a fresh container image build
  --help                                Show this help
EOF
}

require_linux_root() {
  local os_name="${NIMBUS_DIRECT_BOOTC_BUILD_TEST_UNAME:-$(uname -s)}"
  local uid_value="${NIMBUS_DIRECT_BOOTC_BUILD_TEST_UID:-$(id -u)}"
  if [[ "${os_name}" != "Linux" ]]; then
    echo "direct Fedora bootc proof build requires a Linux host" >&2
    exit 1
  fi
  if [[ "${uid_value}" -ne 0 ]]; then
    echo "direct Fedora bootc proof build requires root" >&2
    exit 1
  fi
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 1
  fi
}

sha256_hex() {
  local target="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${target}" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${target}" | awk '{print $1}'
    return
  fi
  echo "missing required command: sha256sum or shasum" >&2
  exit 1
}

nimbus_binary=""
nimbus_version=""
source_revision="${NIMBUS_MACHINE_OS_SOURCE_REVISION:-}"
output_dir=""
image_name="localhost/nimbus-machine-os-fedora-bootc-proof:dev"
fedora_bootc_base_image="quay.io/fedora/fedora-bootc@sha256:187d480948fe37a4cc55211b8a594adfc4f85a7d17ac1991331bf98272eb8f94"
bib_image="${NIMBUS_BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder@sha256:754fc17718f977313885379e2c779066aba7d15af88fe04b486baec74759f574}"
rootfs="ext4"
context_dir=""
no_cache="${NIMBUS_MACHINE_OS_BUILD_NO_CACHE:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nimbus-binary)
      nimbus_binary="${2:?missing nimbus binary path}"
      shift 2
      ;;
    --nimbus-version)
      nimbus_version="${2:?missing nimbus version}"
      shift 2
      ;;
    --source-revision)
      source_revision="${2:?missing source revision}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?missing output dir}"
      shift 2
      ;;
    --image-name)
      image_name="${2:?missing image name}"
      shift 2
      ;;
    --fedora-bootc-base-image)
      fedora_bootc_base_image="${2:?missing Fedora bootc base image}"
      shift 2
      ;;
    --bib-image)
      bib_image="${2:?missing bootc-image-builder image}"
      shift 2
      ;;
    --rootfs)
      rootfs="${2:?missing rootfs}"
      shift 2
      ;;
    --context-dir)
      context_dir="${2:?missing context dir}"
      shift 2
      ;;
    --no-cache)
      no_cache=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_linux_root
require_command podman

if [[ -z "${nimbus_binary}" ]]; then
  echo "--nimbus-binary is required" >&2
  usage >&2
  exit 1
fi
if [[ ! -f "${nimbus_binary}" ]]; then
  echo "nimbus binary does not exist at ${nimbus_binary}" >&2
  exit 1
fi
if [[ -z "${rootfs}" ]]; then
  echo "--rootfs cannot be empty" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${output_dir:-${script_dir}/out}"
mkdir -p "${output_dir}"

cleanup_context=0
if [[ -z "${context_dir}" ]]; then
  context_dir="$(mktemp -d)"
  cleanup_context=1
fi
mkdir -p "${context_dir}"

if [[ "${cleanup_context}" -eq 1 ]]; then
  trap 'rm -rf "${context_dir}"' EXIT
fi

install -m 0644 "${script_dir}/Containerfile" "${context_dir}/Containerfile"
install -m 0755 "${script_dir}/build-common.sh" "${context_dir}/build-common.sh"
install -m 0755 "${nimbus_binary}" "${context_dir}/nimbus"

podman_build_args=(
  build
  -t "${image_name}"
  -f "${context_dir}/Containerfile"
  --build-arg "FEDORA_BOOTC_BASE_IMAGE=${fedora_bootc_base_image}"
)
if [[ "${no_cache}" == "1" || "${no_cache}" == "true" ]]; then
  podman_build_args+=(--no-cache)
fi
podman_build_args+=("${context_dir}")

podman "${podman_build_args[@]}"

oci_archive_path="${output_dir}/nimbus-machine-os-fedora-bootc-proof.ociarchive"
podman save --format oci-archive -o "${oci_archive_path}" "${image_name}"

bib_work_dir="${output_dir}/bootc-image-builder"
bib_output_dir="${bib_work_dir}/output"
rm -rf "${bib_work_dir}"
mkdir -p "${bib_output_dir}"

podman run --rm --privileged \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "${bib_output_dir}:/output" \
  -v "${script_dir}/bootc-image-builder.toml:/config.toml:ro" \
  "${bib_image}" \
  --type raw \
  --rootfs "${rootfs}" \
  --output /output \
  --local \
  --config /config.toml \
  "${image_name}"

raw_disk_source_path="$(find "${bib_output_dir}" -name '*.raw' -type f | head -n 1)"
if [[ -z "${raw_disk_source_path}" || ! -f "${raw_disk_source_path}" ]]; then
  echo "bootc-image-builder did not produce a raw disk image" >&2
  ls -laR "${bib_output_dir}" >&2
  exit 1
fi

require_command gzip
raw_disk_path="${output_dir}/nimbus-machine-os-fedora-bootc-proof.raw"
mv "${raw_disk_source_path}" "${raw_disk_path}"
compressed_raw_disk_path="${output_dir}/nimbus-machine-os-fedora-bootc-proof.raw.gz"
gzip -c "${raw_disk_path}" >"${compressed_raw_disk_path}"
raw_disk_sha256="$(sha256_hex "${raw_disk_path}")"
compressed_raw_disk_sha256="$(sha256_hex "${compressed_raw_disk_path}")"
rm -rf "${bib_work_dir}"

nimbus_binary_sha256="$(sha256_hex "${nimbus_binary}")"
containerfile_sha256="$(sha256_hex "${script_dir}/Containerfile")"
build_common_sha256="$(sha256_hex "${script_dir}/build-common.sh")"
oci_archive_sha256="$(sha256_hex "${oci_archive_path}")"

cat >"${output_dir}/summary.txt" <<EOF
candidate=direct-fedora-bootc
image_name=${image_name}
fedora_bootc_base_image=${fedora_bootc_base_image}
bib_image=${bib_image}
bootc_image_builder_type=raw
bootc_image_builder_rootfs=${rootfs}
provisioning_contract=bootc-native-no-ignition-proof-required
provisioning_mechanisms=sysusers.d,tmpfiles.d,baked-systemd-units,machine-config-channel,systemd-credentials-or-guest-agent
admin_user=nimbus
rootless_subid=nimbus:100000:65536
package_inventory=aardvark-dns,buildah,conmon,containers-common,containers-common-extra,cpp,crun,fuse-overlayfs,gvisor-tap-vsock-gvforwarder,git-core,iproute,netavark,openssh-server,policycoreutils,podman,procps-ng,socat
systemd_units=run-nimbus\x2dmachine\x2dconfig.mount,nimbus.socket,nimbus.service,nimbus-machine-config.service,sshd.service
selinux_expectation=container-runtime-domain-container-socket-policy-plus-runtime-avc-gate
nimbus_socket=/run/nimbus/nimbus.sock
nimbus_control_dir=/var/lib/nimbus/control
nimbus_data_dir=/var/lib/nimbus/data
nimbus_binary=${nimbus_binary}
nimbus_version=${nimbus_version:-<unspecified>}
source_revision=${source_revision:-<unspecified>}
no_cache=${no_cache}
nimbus_binary_sha256=${nimbus_binary_sha256}
containerfile_sha256=${containerfile_sha256}
build_common_sha256=${build_common_sha256}
oci_archive_path=${oci_archive_path}
oci_archive_sha256=${oci_archive_sha256}
raw_disk_path=${raw_disk_path}
raw_disk_sha256=${raw_disk_sha256}
compressed_raw_disk_path=${compressed_raw_disk_path}
compressed_raw_disk_sha256=${compressed_raw_disk_sha256}
EOF

printf 'built direct Fedora bootc proof image at %s\n' "${output_dir}"
