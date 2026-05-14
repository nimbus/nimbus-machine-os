#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proof_dir="${repo_root}/proofs/direct-fedora-bootc"
source "${repo_root}/scripts/test-helpers.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

bash -n "${proof_dir}/build.sh"
bash -n "${proof_dir}/build-common.sh"
bash "${proof_dir}/build.sh" --help >/dev/null

grep -F 'FROM ${FEDORA_BOOTC_BASE_IMAGE}' "${proof_dir}/Containerfile" >/dev/null
grep -F 'quay.io/fedora/fedora-bootc@sha256:5f2aa40538a71e32eba8dcdf9059dda10600bac68acef4588cb1aecedcfc6fe2' "${proof_dir}/Containerfile" >/dev/null
grep -F 'u nimbus - "Nimbus machine administrator" /var/lib/nimbus /bin/bash' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/etc/systemd/system/local-fs.target.wants' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/etc/systemd/system/multi-user.target.wants' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/etc/systemd/system/sockets.target.wants' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/lib/systemd/system/bootloader-update.service.d' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/lib/systemd/system/nimbus.socket' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/lib/systemd/system/nimbus.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/share/selinux/packages' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/lib/systemd/system/run-nimbus\x2dmachine\x2dconfig.mount' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/lib/systemd/system/nimbus-machine-config.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F '/usr/lib/systemd/system/nimbus-boot-restorecon.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'WantedBy=sockets.target' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'ExecStartPost=/usr/bin/chcon -t container_var_run_t /run/nimbus/nimbus.sock' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Requires=nimbus.socket nimbus-machine-config.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'After=nimbus.socket nimbus-machine-config.service network-online.target local-fs.target' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Before=nimbus.service sshd.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'WantedBy=multi-user.target' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'SELinuxContext=system_u:system_r:container_runtime_t:s0' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'ExecStart=/usr/local/bin/nimbus machine api --socket-activation --control-data-dir /var/lib/nimbus/control' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'What=nimbus-machine-config' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Where=/run/nimbus-machine-config' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Type=virtiofs' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Requires=run-nimbus\x2dmachine\x2dconfig.mount' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'ExecStart=/usr/local/bin/nimbus machine guest-config apply --config-dir /run/nimbus-machine-config' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'bootloader-update.service.d/10-nimbus-restorecon.conf' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Wants=nimbus-boot-restorecon.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'After=nimbus-boot-restorecon.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'RequiresMountsFor=/boot' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Before=bootloader-update.service' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'ConditionPathExists=/boot/bootupd-state.json' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'mount -o remount,rw /boot' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'restorecon /boot/bootupd-state.json' "${proof_dir}/build-common.sh" >/dev/null
! grep -F 'ConditionPathExists=/run/nimbus-machine-config/machine.json' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'helper_binaries_dir=["/usr/libexec/podman", {append=true}]' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'Delegate=memory pids cpu io' "${proof_dir}/build-common.sh" >/dev/null
grep -F "echo 'nimbus:100000:65536' >>/etc/subuid" "${proof_dir}/build-common.sh" >/dev/null
grep -F "echo 'nimbus:100000:65536' >>/etc/subgid" "${proof_dir}/build-common.sh" >/dev/null
grep -F 'readlink /usr/local' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'mkdir -p /var/usrlocal/bin' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'bootc_image_builder_rootfs=${rootfs}' "${proof_dir}/build.sh" >/dev/null
grep -F 'provisioning_contract=bootc-native-no-ignition-proof-required' "${proof_dir}/build.sh" >/dev/null
grep -F 'provisioning_mechanisms=sysusers.d,tmpfiles.d,baked-systemd-units,machine-config-channel,systemd-credentials-or-guest-agent' "${proof_dir}/build.sh" >/dev/null
grep -F 'admin_user=nimbus' "${proof_dir}/build.sh" >/dev/null
grep -F 'rootless_subid=nimbus:100000:65536' "${proof_dir}/build.sh" >/dev/null
grep -F 'package_inventory=aardvark-dns,buildah,conmon,containers-common,containers-common-extra,cpp,crun,fuse-overlayfs,gvisor-tap-vsock-gvforwarder,git-core,iproute,netavark,openssh-server,policycoreutils,podman,procps-ng,socat' "${proof_dir}/build.sh" >/dev/null
grep -F 'systemd_units=run-nimbus\x2dmachine\x2dconfig.mount,nimbus.socket,nimbus.service,nimbus-machine-config.service,nimbus-boot-restorecon.service,sshd.service' "${proof_dir}/build.sh" >/dev/null
grep -F 'selinux_expectation=container-runtime-domain-container-socket-policy-plus-fedora-bootupd-compat-plus-runtime-avc-gate' "${proof_dir}/build.sh" >/dev/null
grep -F 'quay.io/centos-bootc/bootc-image-builder@sha256:754fc17718f977313885379e2c779066aba7d15af88fe04b486baec74759f574' "${proof_dir}/build.sh" >/dev/null
grep -F 'policycoreutils' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'cat >/usr/share/selinux/packages/nimbus-machine-api.cil' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow sshd_session_t container_var_run_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow sshd_session_t container_runtime_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'nimbus-bootupd-fedora-base.cil' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow bootupd_t mount_var_run_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow bootupd_t passwd_file_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow bootupd_t systemd_userdbd_runtime_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow bootupd_t systemd_userdbd_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'allow bootupd_t systemd_homed_t' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'semodule -i /usr/share/selinux/packages/nimbus-machine-api.cil' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'semodule -i /usr/share/selinux/packages/nimbus-bootupd-fedora-base.cil' "${proof_dir}/build-common.sh" >/dev/null
grep -F 'ostree.prepare-root.composefs=0' "${proof_dir}/bootc-image-builder.toml" >/dev/null
! grep -F 'customizations.filesystem' "${proof_dir}/bootc-image-builder.toml" >/dev/null
grep -F -- '--security-opt label=type:unconfined_t' "${proof_dir}/build.sh" >/dev/null

fake_bin="${temp_dir}/bin"
context_dir="${temp_dir}/context"
output_dir="${temp_dir}/out"
layout_dir="${temp_dir}/layout"
mkdir -p "${fake_bin}" "${context_dir}" "${output_dir}"

write_executable_stub "${fake_bin}/podman" <<'FAKEOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TMPDIR}/podman.log"
if [[ "${1:-}" == "save" ]]; then
  for i in "$@"; do
    case "${prev:-}" in
      -o) mkdir -p "$(dirname "$i")"; : >"$i" ;;
    esac
    prev="$i"
  done
fi
if [[ "${1:-}" == "run" ]]; then
  for i in "$@"; do
    if [[ "${prev:-}" == "-v" && "$i" == *:/output ]]; then
      bib_out="${i%%:*}"
      mkdir -p "${bib_out}/image"
      printf 'direct-fedora-bootc-raw-proof' >"${bib_out}/image/disk.raw"
    fi
    prev="$i"
  done
fi
exit 0
FAKEOF

nimbus_binary="${temp_dir}/nimbus"
write_noop_executable "${nimbus_binary}"

TMPDIR="${temp_dir}" \
PATH="${fake_bin}:${PATH}" \
NIMBUS_DIRECT_BOOTC_BUILD_TEST_UNAME=Linux \
NIMBUS_DIRECT_BOOTC_BUILD_TEST_UID=0 \
bash "${proof_dir}/build.sh" \
  --nimbus-binary "${nimbus_binary}" \
  --nimbus-version v1.2.3 \
  --source-revision fedora-bootc-proof-rev \
  --output-dir "${output_dir}" \
  --context-dir "${context_dir}" \
  --no-cache

test -f "${output_dir}/nimbus-machine-os-fedora-bootc-proof.ociarchive"
test -f "${output_dir}/nimbus-machine-os-fedora-bootc-proof.raw"
test -f "${output_dir}/nimbus-machine-os-fedora-bootc-proof.raw.gz"
test -f "${output_dir}/summary.txt"
grep -F -- '--build-arg FEDORA_BOOTC_BASE_IMAGE=' "${temp_dir}/podman.log" >/dev/null
grep -F -- '--no-cache' "${temp_dir}/podman.log" >/dev/null
grep -F -- 'quay.io/fedora/fedora-bootc@sha256:5f2aa40538a71e32eba8dcdf9059dda10600bac68acef4588cb1aecedcfc6fe2' "${temp_dir}/podman.log" >/dev/null
grep -F -- 'quay.io/centos-bootc/bootc-image-builder@sha256:754fc17718f977313885379e2c779066aba7d15af88fe04b486baec74759f574' "${temp_dir}/podman.log" >/dev/null
grep -F -- '--type raw' "${temp_dir}/podman.log" >/dev/null
grep -F -- '--rootfs ext4' "${temp_dir}/podman.log" >/dev/null
grep -F -- '--output /output' "${temp_dir}/podman.log" >/dev/null
! grep -F -- '--store /store' "${temp_dir}/podman.log" >/dev/null
! grep -F -- ':/var/tmp' "${temp_dir}/podman.log" >/dev/null
grep -F 'candidate=direct-fedora-bootc' "${output_dir}/summary.txt" >/dev/null
grep -F 'bootc_image_builder_type=raw' "${output_dir}/summary.txt" >/dev/null
grep -F 'bootc_image_builder_rootfs=ext4' "${output_dir}/summary.txt" >/dev/null
grep -F 'provisioning_contract=bootc-native-no-ignition-proof-required' "${output_dir}/summary.txt" >/dev/null
grep -F 'provisioning_mechanisms=sysusers.d,tmpfiles.d,baked-systemd-units,machine-config-channel,systemd-credentials-or-guest-agent' "${output_dir}/summary.txt" >/dev/null
grep -F 'admin_user=nimbus' "${output_dir}/summary.txt" >/dev/null
grep -F 'rootless_subid=nimbus:100000:65536' "${output_dir}/summary.txt" >/dev/null
grep -F 'package_inventory=aardvark-dns,buildah,conmon,containers-common,containers-common-extra,cpp,crun,fuse-overlayfs,gvisor-tap-vsock-gvforwarder,git-core,iproute,netavark,openssh-server,policycoreutils,podman,procps-ng,socat' "${output_dir}/summary.txt" >/dev/null
grep -F 'systemd_units=run-nimbus\x2dmachine\x2dconfig.mount,nimbus.socket,nimbus.service,nimbus-machine-config.service,nimbus-boot-restorecon.service,sshd.service' "${output_dir}/summary.txt" >/dev/null
grep -F 'selinux_expectation=container-runtime-domain-container-socket-policy-plus-fedora-bootupd-compat-plus-runtime-avc-gate' "${output_dir}/summary.txt" >/dev/null
grep -F 'source_revision=fedora-bootc-proof-rev' "${output_dir}/summary.txt" >/dev/null
grep -F 'no_cache=1' "${output_dir}/summary.txt" >/dev/null
grep -F "raw_disk_path=${output_dir}/nimbus-machine-os-fedora-bootc-proof.raw" "${output_dir}/summary.txt" >/dev/null
gzip -dc "${output_dir}/nimbus-machine-os-fedora-bootc-proof.raw.gz" >/dev/null

bash "${repo_root}/scripts/package-oci.sh" \
  --build-output-dir "${output_dir}" \
  --image-reference docker://ghcr.io/nimbus/machine-os:fedora-bootc-proof \
  --layout-dir "${layout_dir}" \
  --arch arm64 \
  --source-repository-url https://github.com/nimbus/machine-os \
  --attestation-repository nimbus/machine-os

grep -F '"disktype":"applehv"' "${layout_dir}/index.json" >/dev/null
grep -F 'disk_type=applehv' "${layout_dir}/summary.txt" >/dev/null
grep -F 'source_revision=fedora-bootc-proof-rev' "${layout_dir}/summary.txt" >/dev/null

printf 'verified direct Fedora bootc proof lane\n'
