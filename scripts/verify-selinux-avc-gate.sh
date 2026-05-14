#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

clean_log="${temp_dir}/clean.log"
cat >"${clean_log}" <<'EOF'
May 13 12:00:00 nimbus audit: USER_LOGIN pid=100 uid=0
May 13 12:00:01 nimbus systemd[1]: Started nimbus.socket.
EOF

bash "${repo_root}/scripts/check-selinux-avcs.sh" --audit-log "${clean_log}" \
  >"${temp_dir}/clean.out"
grep -F 'verified SELinux AVC gate: no AVC denials' "${temp_dir}/clean.out" >/dev/null

blocked_log="${temp_dir}/blocked.log"
cat >"${blocked_log}" <<'EOF'
type=AVC msg=audit(1778700000.1:101): avc:  denied  { connectto write } for  pid=200 comm="curl" path="/run/nimbus/nimbus.sock" scontext=system_u:system_r:sshd_session_t:s0 tcontext=system_u:system_r:init_t:s0 tclass=unix_stream_socket permissive=1
type=AVC msg=audit(1778700000.2:102): avc:  denied  { getattr } for  pid=201 comm="systemd-sysctl" path="/run/sysctl.d/10-netavark-nimbus0.conf" scontext=system_u:system_r:systemd_sysctl_t:s0 tclass=file permissive=0
type=AVC msg=audit(1778700000.3:103): avc:  denied  { read } for  pid=202 comm="lsblk" path="/run/systemd/userdb/io.systemd.NameServiceSwitch" scontext=system_u:system_r:bootupd_t:s0 tclass=file permissive=1
EOF

if bash "${repo_root}/scripts/check-selinux-avcs.sh" --audit-log "${blocked_log}" \
  >"${temp_dir}/blocked.out" 2>"${temp_dir}/blocked.err"; then
  echo "SELinux AVC gate should fail when BMD4 blocker AVCs are present" >&2
  exit 1
fi
grep -F 'SELinux AVC gate failed' "${temp_dir}/blocked.err" >/dev/null
grep -F 'nimbus_socket_avcs=1' "${temp_dir}/blocked.err" >/dev/null
grep -F 'netavark_sysctl_avcs=1' "${temp_dir}/blocked.err" >/dev/null
grep -F 'fedora_base_userdb_avcs=1' "${temp_dir}/blocked.err" >/dev/null
grep -F 'unknown_avcs=0' "${temp_dir}/blocked.err" >/dev/null

unknown_log="${temp_dir}/unknown.log"
cat >"${unknown_log}" <<'EOF'
type=AVC msg=audit(1778700000.4:104): avc:  denied  { read } for  pid=203 comm="mystery" path="/tmp/mystery" tclass=file permissive=0
type=AVC msg=audit(1778700000.5:105): avc:  denied  { read } for  pid=204 comm="mystery" path="/run/systemd/userdb/io.systemd.NameServiceSwitch" scontext=system_u:system_r:mystery_t:s0 tclass=file permissive=0
EOF

if bash "${repo_root}/scripts/check-selinux-avcs.sh" --audit-log "${unknown_log}" \
  >"${temp_dir}/unknown.out" 2>"${temp_dir}/unknown.err"; then
  echo "SELinux AVC gate should fail on unclassified AVCs" >&2
  exit 1
fi
grep -F 'fedora_base_userdb_avcs=0' "${temp_dir}/unknown.err" >/dev/null
grep -F 'unknown_avcs=2' "${temp_dir}/unknown.err" >/dev/null

printf 'verified SELinux AVC promotion gate\n'
