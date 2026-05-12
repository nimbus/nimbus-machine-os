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
  --output-dir /tmp/nimbus-machine-os-out

grep -F -- '--nimbus-binary' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--nimbus-version v1.2.3' "${temp_dir}/recipe.log" >/dev/null
grep -F -- '--output-dir /tmp/nimbus-machine-os-out' "${temp_dir}/recipe.log" >/dev/null

printf 'verified nimbus machine-os build wrapper\n'
