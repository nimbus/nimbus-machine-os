#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/test-helpers.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

fake_bin="${temp_dir}/bin"
mkdir -p "${fake_bin}"

# Create a fake nimbus binary
write_noop_executable "${temp_dir}/nimbus"

# Create a fake bash that intercepts the recipe script call
write_executable_stub "${fake_bin}/bash" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == *"images/build.sh" ]]; then
  shift
  printf '%s\n' "$*" >>"${TMPDIR}/recipe.log"
  exit 0
fi
exec /bin/bash "$@"
EOF

PATH="${fake_bin}:${PATH}" \
TMPDIR="${temp_dir}" \
NIMBUS_MACHINE_OS_BUILD_WRAPPER_TEST_UNAME=Linux \
bash "${repo_root}/scripts/build.sh" \
  --nimbus-binary "${temp_dir}/nimbus" \
  --nimbus-version v1.2.3 \
  --source-revision abc123def456 \
  --output-dir /tmp/nimbus-machine-os-out \
  --fedora-bootc-base-image quay.io/fedora/fedora-bootc@sha256:187d480948fe37a4cc55211b8a594adfc4f85a7d17ac1991331bf98272eb8f94 \
  --bib-image quay.io/centos-bootc/bootc-image-builder@sha256:754fc17718f977313885379e2c779066aba7d15af88fe04b486baec74759f574 \
  --rootfs ext4

grep -F -- '--nimbus-binary' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--nimbus-version v1.2.3' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--source-revision abc123def456' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--output-dir /tmp/nimbus-machine-os-out' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--fedora-bootc-base-image quay.io/fedora/fedora-bootc@sha256:187d480948fe37a4cc55211b8a594adfc4f85a7d17ac1991331bf98272eb8f94' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--bib-image quay.io/centos-bootc/bootc-image-builder@sha256:754fc17718f977313885379e2c779066aba7d15af88fe04b486baec74759f574' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--rootfs ext4' "${temp_dir}/recipe.log" >/dev/null

PATH="${fake_bin}:${PATH}" \
TMPDIR="${temp_dir}" \
NIMBUS_MACHINE_OS_BUILD_WRAPPER_TEST_UNAME=Linux \
bash "${repo_root}/scripts/build.sh" \
  --nimbus-binary "${temp_dir}/nimbus" \
  --no-cache

grep -F -- '--no-cache' "${temp_dir}/recipe.log" >/dev/null

printf 'verified nimbus machine-os build wrapper\n'
