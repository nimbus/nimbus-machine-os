# machine-os

Guest OS image for the Nimbus macOS developer machine.

This repository owns the first-party Nimbus bootc appliance image published as
`ghcr.io/nimbus/machine-os:<tag>`. The image is built from a digest-pinned
Fedora bootc base, includes the matching Linux arm64 `nimbus` release binary,
and is packaged as a Podman-compatible raw-disk OCI artifact with
`disktype=applehv` for the macOS krunkit provider.

Nimbus originally forked from the Podman machine-image work to preserve the
right artifact contract, but the current implementation is no longer a
Podman-machine-os-shaped FCOS build. Podman's repository remains an important
compatibility reference; this repository is the canonical source for the
Nimbus bootc guest appliance.

## What's inside

The guest image contains:

- **Nimbus guest control plane** - the Linux arm64 `nimbus` binary from the
  matching `nimbus/nimbus` release, installed at `/usr/local/bin/nimbus` to
  run `nimbus machine api` and `nimbus machine guest-config apply`. This
  versioned control-plane binary is baked into the bootc image.
- **Container tooling** - podman, crun, conmon, buildah, containers-common,
  netavark, aardvark-dns, and fuse-overlayfs.
- **System services** - openssh-server, socat, systemd user delegation, and
  baked `nimbus.socket`, `nimbus.service`, and
  `nimbus-machine-config.service` units.
- **SELinux policy** - `nimbus.service` runs in the Fedora
  `container_runtime_t` domain, `/run/nimbus/nimbus.sock` is relabeled
  `container_var_run_t`, and narrow CIL modules cover the machine API socket
  plus the observed Fedora bootupd userdb path.
- **Provisioning contract** - bootc-native machine config through sysusers,
  tmpfiles, baked units, virtiofs-delivered machine config, and the Nimbus
  guest config command. Ignition is not part of the normal bootc path.

See [docs/architecture.md](docs/architecture.md) for the full guest contract and
[docs/provider-artifacts.md](docs/provider-artifacts.md) for current and
future provider artifact shapes.

## Published artifacts

| Artifact | Location |
|----------|----------|
| Raw-disk OCI image | `ghcr.io/nimbus/machine-os:<tag>` plus a release-recorded digest reference. |
| SBOM | `nimbus-machine-os.sbom.cdx.json` release asset |
| Checksums and digest evidence | `checksums.txt`, `published-digests.txt`, and `machine-image-reference.txt` release assets |
| Build provenance | GitHub Attestations (via `actions/attest`) |

Release assets and OCI annotations are part of the public contract. See
[docs/artifact-contract.md](docs/artifact-contract.md),
[docs/provider-artifacts.md](docs/provider-artifacts.md), and
[docs/release-contract.md](docs/release-contract.md).

## Building locally

Machine image builds require a Linux arm64 host or runner with rootful Podman.
macOS developers normally consume the published artifact rather than building
the disk locally.

```bash
# Download the matching nimbus guest control binary first
curl -fsSL -o /tmp/nimbus_linux_arm64.tar.gz \
  https://github.com/nimbus/nimbus/releases/latest/download/nimbus_linux_arm64.tar.gz
tar xzf /tmp/nimbus_linux_arm64.tar.gz -C /tmp

sudo bash scripts/build.sh \
  --nimbus-binary /tmp/nimbus \
  --nimbus-version vX.Y.Z \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir /tmp/nimbus-machine-os
```

Then package the raw disk as an OCI layout:

```bash
bash scripts/package-oci.sh \
  --build-output-dir /tmp/nimbus-machine-os \
  --image-reference docker://ghcr.io/nimbus/machine-os:vX.Y.Z \
  --layout-dir /tmp/nimbus-machine-os/oci-layout
```

See [docs/local-build.md](docs/local-build.md) for requirements,
troubleshooting, and which checks can run without a Linux image build.

## CI and release

The release flow is intentionally split across repositories:

1. `nimbus/nimbus` builds the Linux arm64 Nimbus release binary.
2. `nimbus/nimbus` stages a machine-os build from this repository at an exact
   source revision.
3. After all Nimbus CLI release targets pass, `nimbus/nimbus` dispatches this
   repository's `publish.yml` workflow.
4. `nimbus/machine-os` publishes to GHCR and creates the machine-os GitHub
   Release from its own repository context.

Standalone `nimbus/machine-os` tag and manual builds are validation lanes only
unless the project intentionally creates an independent machine-os maintenance
stream.

See [docs/release-contract.md](docs/release-contract.md).

## Verification

Fast deterministic checks:

```bash
bash scripts/verify-recipe.sh
bash scripts/verify-build-helper.sh
bash scripts/verify-oci-layout-helper.sh
bash scripts/verify-provider-artifact-contracts.sh
bash scripts/verify-publish-helper.sh
bash scripts/verify-selinux-avc-gate.sh
```

Promotion of a new default image still requires real macOS guest evidence,
including a clean SELinux AVC capture checked with:

```bash
bash scripts/check-selinux-avcs.sh --audit-log <path>
```

See [docs/security-selinux.md](docs/security-selinux.md).

## License

See [LICENSE](LICENSE). This repository keeps attribution for its
Podman-machine-os-derived history while treating the current bootc appliance as
first-party Nimbus infrastructure.
