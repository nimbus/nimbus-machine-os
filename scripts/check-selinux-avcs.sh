#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: check-selinux-avcs.sh --audit-log <path>

Fail if a captured SELinux audit log contains AVC denials. This is a release
promotion gate for the bootc machine image; clean helper tests are not a
substitute for running this against real macOS boot parity evidence.

Options:
  --audit-log <path>  File containing ausearch, audit.log, or journal AVC text
  -h, --help          Show this help
EOF
}

audit_log=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-log)
      audit_log="${2:-}"
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

if [[ -z "${audit_log}" ]]; then
  echo "--audit-log is required" >&2
  exit 64
fi
if [[ ! -f "${audit_log}" ]]; then
  echo "audit log not found: ${audit_log}" >&2
  exit 66
fi

avc_lines="$(mktemp)"
trap 'rm -f "${avc_lines}"' EXIT

awk '
  BEGIN { IGNORECASE = 1 }
  /type=AVC/ || /avc:[[:space:]]+denied/ || /avc:.*denied/ || /denied.*avc/ {
    print
  }
' "${audit_log}" >"${avc_lines}"

if [[ ! -s "${avc_lines}" ]]; then
  printf 'verified SELinux AVC gate: no AVC denials in %s\n' "${audit_log}"
  exit 0
fi

nimbus_socket_count=0
netavark_sysctl_count=0
fedora_base_userdb_count=0
unknown_count=0

while IFS= read -r line; do
  if [[ "${line}" == *"nimbus.sock"* || "${line}" == *"sshd_session_t"* ]]; then
    nimbus_socket_count=$((nimbus_socket_count + 1))
  elif [[ "${line}" == *"systemd_sysctl_t"* || "${line}" == *"10-netavark-nimbus0.conf"* ]]; then
    netavark_sysctl_count=$((netavark_sysctl_count + 1))
  elif [[ "${line}" == *"bootupd_t"* ]] && \
    [[ "${line}" == *"mount_var_run_t"* || \
       "${line}" == *"passwd_file_t"* || \
       "${line}" == *"systemd_userdbd_runtime_t"* || \
       "${line}" == *"systemd_userdbd_t"* || \
       "${line}" == *"systemd_homed_t"* || \
       "${line}" == *"userdb"* || \
       "${line}" == *"/etc/group"* ]]; then
    fedora_base_userdb_count=$((fedora_base_userdb_count + 1))
  else
    unknown_count=$((unknown_count + 1))
  fi
done <"${avc_lines}"

{
  printf 'SELinux AVC gate failed for %s\n' "${audit_log}"
  printf 'nimbus_socket_avcs=%s\n' "${nimbus_socket_count}"
  printf 'netavark_sysctl_avcs=%s\n' "${netavark_sysctl_count}"
  printf 'fedora_base_userdb_avcs=%s\n' "${fedora_base_userdb_count}"
  printf 'unknown_avcs=%s\n' "${unknown_count}"
  printf 'Promotion requires zero AVC denials or an explicit documented policy disposition before this image can become the macOS default.\n'
} >&2

exit 1
