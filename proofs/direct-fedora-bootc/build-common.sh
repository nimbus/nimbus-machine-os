#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  /etc/chrony.d \
  /etc/containers/containers.conf.d \
  /etc/containers/registries.conf.d \
  /etc/profile.d \
  /etc/ssh/sshd_config.d \
  /etc/systemd/system/local-fs.target.wants \
  /etc/systemd/system/multi-user.target.wants \
  /etc/systemd/system/sockets.target.wants \
  /etc/systemd/system/user@.service.d \
  /etc/sysctl.d \
  /usr/lib/systemd/system \
  /usr/lib/sysusers.d \
  /usr/lib/tmpfiles.d \
  /usr/share/selinux/packages \
  /var/lib/nimbus/control \
  /var/lib/nimbus/data

cat >/etc/chrony.d/50-nimbus-machine-makestep.conf <<'EOF'
makestep 1 -1
EOF

if [[ -f /etc/chrony.conf ]] && ! grep -F 'confdir /etc/chrony.d' /etc/chrony.conf >/dev/null; then
  echo "confdir /etc/chrony.d" >>/etc/chrony.conf
fi

cat >/etc/profile.d/docker-host.sh <<'EOF'
export DOCKER_HOST="unix://$(podman info -f "{{.Host.RemoteSocket.Path}}")"
EOF

cat >/etc/containers/registries.conf.d/999-nimbus-machine.conf <<'EOF'
unqualified-search-registries=["docker.io"]
EOF

cat >/etc/containers/containers.conf.d/999-nimbus-machine.conf <<'EOF'
[engine]
helper_binaries_dir=["/usr/libexec/podman", {append=true}]
EOF

cat >/etc/ssh/sshd_config.d/99-nimbus-machine-sshd.conf <<'EOF'
PerSourcePenalties authfail:0
MaxStartups 65535
EOF

cat >/etc/systemd/system/user@.service.d/delegate.conf <<'EOF'
[Service]
Delegate=memory pids cpu io
EOF

cat >/etc/sysctl.d/10-nimbus-machine-inotify.conf <<'EOF'
fs.inotify.max_user_instances=524288
EOF

cat >/usr/lib/sysusers.d/nimbus-machine.conf <<'EOF'
u nimbus - "Nimbus machine administrator" /var/lib/nimbus /bin/bash
EOF

cat >/usr/lib/tmpfiles.d/nimbus-machine.conf <<'EOF'
d /var/lib/nimbus 0755 nimbus nimbus -
d /var/lib/nimbus/control 0755 nimbus nimbus -
d /var/lib/nimbus/data 0755 nimbus nimbus -
d /run/nimbus 0755 root root -
d /run/nimbus-machine-config 0755 root root -
EOF

cat >/usr/lib/systemd/system/nimbus.socket <<'EOF'
[Unit]
Description=Nimbus API Socket

[Socket]
ListenStream=/run/nimbus/nimbus.sock
SocketMode=0600
DirectoryMode=0755
ExecStartPost=/usr/bin/chcon -t container_var_run_t /run/nimbus/nimbus.sock

[Install]
WantedBy=sockets.target
EOF

cat >/usr/lib/systemd/system/nimbus.service <<'EOF'
[Unit]
Description=Nimbus API Service
Requires=nimbus.socket nimbus-machine-config.service
After=nimbus.socket nimbus-machine-config.service network-online.target local-fs.target
Wants=network-online.target

[Service]
Type=exec
KillMode=process
WorkingDirectory=/var/lib/nimbus/data
Environment=HOME=/var/lib/nimbus/data
SELinuxContext=system_u:system_r:container_runtime_t:s0
ExecStart=/usr/local/bin/nimbus machine api --socket-activation --control-data-dir /var/lib/nimbus/control
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

cat >'/usr/lib/systemd/system/run-nimbus\x2dmachine\x2dconfig.mount' <<'EOF'
[Unit]
Description=Nimbus Machine Config Mount
DefaultDependencies=no
Before=local-fs.target nimbus-machine-config.service

[Mount]
What=nimbus-machine-config
Where=/run/nimbus-machine-config
Type=virtiofs
Options=ro

[Install]
WantedBy=local-fs.target
EOF

cat >/usr/lib/systemd/system/nimbus-machine-config.service <<'EOF'
[Unit]
Description=Nimbus Machine Config Apply
Requires=run-nimbus\x2dmachine\x2dconfig.mount
After=run-nimbus\x2dmachine\x2dconfig.mount
Before=nimbus.service sshd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nimbus machine guest-config apply --config-dir /run/nimbus-machine-config
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

dnf install --best -y \
  aardvark-dns \
  buildah \
  conmon \
  containers-common \
  containers-common-extra \
  cpp \
  crun \
  fuse-overlayfs \
  git-core \
  iproute \
  netavark \
  openssh-server \
  policycoreutils \
  podman \
  procps-ng \
  socat

dnf remove -y moby-engine containerd runc toolbox docker-cli || true

cat >/usr/share/selinux/packages/nimbus-machine-api.cil <<'EOF'
(block nimbus_machine_api
  (allow sshd_session_t container_var_run_t (sock_file (write getattr read open)))
  (allow sshd_session_t container_runtime_t (unix_stream_socket (connectto)))
)
EOF

semodule -i /usr/share/selinux/packages/nimbus-machine-api.cil

if command -v systemd-sysusers >/dev/null 2>&1; then
  systemd-sysusers /usr/lib/sysusers.d/nimbus-machine.conf
fi
if ! getent passwd nimbus >/dev/null; then
  useradd --create-home --home-dir /var/lib/nimbus --user-group --groups wheel --shell /bin/bash nimbus
fi
usermod -aG wheel nimbus || true
grep -q '^nimbus:' /etc/subuid 2>/dev/null || echo 'nimbus:100000:65536' >>/etc/subuid
grep -q '^nimbus:' /etc/subgid 2>/dev/null || echo 'nimbus:100000:65536' >>/etc/subgid

if command -v systemd-tmpfiles >/dev/null 2>&1; then
  systemd-tmpfiles --create /usr/lib/tmpfiles.d/nimbus-machine.conf || true
fi

ln -fs /usr/lib/systemd/system/sshd.service \
  /etc/systemd/system/multi-user.target.wants/sshd.service
ln -fs '/usr/lib/systemd/system/run-nimbus\x2dmachine\x2dconfig.mount' \
  '/etc/systemd/system/local-fs.target.wants/run-nimbus\x2dmachine\x2dconfig.mount'
ln -fs /usr/lib/systemd/system/nimbus.socket \
  /etc/systemd/system/sockets.target.wants/nimbus.socket
ln -fs /usr/lib/systemd/system/nimbus-machine-config.service \
  /etc/systemd/system/multi-user.target.wants/nimbus-machine-config.service

if [[ -L /usr/local && "$(readlink /usr/local)" =~ ^(\.\./)?var/usrlocal$ ]]; then
  mkdir -p /var/usrlocal/bin
  chmod 0755 /var/usrlocal /var/usrlocal/bin
else
  mkdir -p /usr/local/bin
  chmod 0755 /usr/local /usr/local/bin
fi
chown -R nimbus:nimbus /var/lib/nimbus
chmod 0755 /var/lib/nimbus /var/lib/nimbus/control /var/lib/nimbus/data
restorecon -RFv \
  /usr/lib/systemd/system/nimbus.service \
  /usr/lib/systemd/system/nimbus.socket \
  '/usr/lib/systemd/system/run-nimbus\x2dmachine\x2dconfig.mount' \
  /usr/lib/systemd/system/nimbus-machine-config.service \
  /var/lib/nimbus >/dev/null 2>&1 || true

rm -rf /var/cache /usr/share/man
dnf clean all -y
