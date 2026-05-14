# nimbus-machine-os

Guest OS image for the nimbus macOS developer machine. Built as a
direct Fedora bootc image with nimbus and container tooling pre-installed.

The current shipped Nimbus macOS default still uses the pinned Podman
`machine-os` artifact until the bootc-native path passes full parity. This
repository owns the replacement path: a Nimbus-owned bootc image published as
a Podman-compatible `disktype=applehv` raw-disk OCI artifact.

## What's inside

The guest image includes:

- **Nimbus guest control plane** — the Linux arm64 `nimbus` binary from the
  matching `nimbus/nimbus` release, installed at `/usr/local/bin/nimbus` to
  run `nimbus machine api` and `nimbus machine guest-config apply`. This
  versioned control-plane binary is baked into the bootc image rather than
  synced by the host during normal startup.
- **Container tooling** — podman, crun, conmon, buildah, containers-common,
  netavark, aardvark-dns, fuse-overlayfs
- **System services** — openssh-server, socat, systemd user delegation, and
  baked `nimbus.socket`, `nimbus.service`, and
  `nimbus-machine-config.service`
- **SELinux policy** — `nimbus.service` runs in the Fedora
  `container_runtime_t` domain, `/run/nimbus/nimbus.sock` is relabeled
  `container_var_run_t`, and a narrow `nimbus-machine-api` CIL module permits
  the host-forwarded SSH session to connect to that socket. A separate narrow
  Fedora-base bootupd compatibility module covers the observed `bootupd_t`
  userdb lookups that Fedora currently ships as a permissive-domain path, and
  `nimbus-boot-restorecon.service` relabels `/boot/bootupd-state.json` before
  Fedora's bootloader update service runs.
- **Provisioning contract** — bootc-native machine config via sysusers,
  tmpfiles, baked units, and the Nimbus machine-config channel; Ignition is
  not part of the target bootc path

The image is built from digest-pinned `quay.io/fedora/fedora-bootc:44` and
converted to a raw disk image via a digest-pinned `bootc-image-builder`.

## Published artifacts

| Artifact | Location |
|----------|----------|
| Raw-disk OCI image | `ghcr.io/nimbus/nimbus-machine-os:<tag>` plus a release-recorded digest reference |
| SBOM | `nimbus-machine-os.sbom.cdx.json` release asset |
| Checksums and digest evidence | `checksums.txt`, `published-digests.txt`, and `machine-image-reference.txt` release assets |
| Build provenance | GitHub Attestations (via `actions/attest`) |

## Bootc Promotion Rule

This repository may publish bootc-native artifacts before Nimbus switches the
macOS default. The host default changes only after the bootc artifact passes
the build, machine-config, macOS boot parity, and bootc lifecycle gates in
`docs/plans/bootc-machine-default-plan.md` in the main Nimbus repository.
Promotion evidence must include a real guest audit capture checked with
`scripts/check-selinux-avcs.sh --audit-log <path>`. The current image recipe
records `selinux_expectation=container-runtime-domain-container-socket-policy-plus-fedora-bootupd-compat-plus-runtime-avc-gate`;
deterministic helper tests only prove the gate parser, not SELinux runtime
safety. Fedora-base `bootupd`/`lsblk` userdb AVCs are handled only by the
observed-permission compatibility module above; promotion still requires a
clean real guest audit capture, and any new or broader AVC remains a blocker.

## Building locally

Requires a Linux host with podman and root access:

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

`--nimbus-version` and `--source-revision` are optional for ad hoc local
builds, but release and CI lanes should pass them so the build summary and
packaged OCI metadata record the embedded Nimbus version and source revision
explicitly.

## CI

The GitHub Actions workflow (`.github/workflows/build.yml`) runs on
`ubuntu-24.04-arm` and:

1. **verify-contract** — script syntax, help entrypoints, deterministic
   helper tests
2. **build-arm64** — downloads or receives the matching nimbus Linux binary,
   builds the guest image, packages it as OCI layout, publishes to GHCR on
   `v*` tags, and attests the build output

Primary release path:

- `nimbus/nimbus` `v*` releases call `build.yml` first as the staging
  lane that verifies the machine-os repo and builds the raw-disk OCI bundle
- that staging lane uploads a reusable machine-os artifact bundle inside the
  caller's workflow run
- after the host `nimbus/nimbus` release succeeds, the caller invokes
  `publish.yml`, which downloads that staged bundle and publishes/releases it
  without rebuilding the machine image
- the publish/release call must pass `release_app_id` plus the
  `MACHINE_OS_RELEASE_APP_PRIVATE_KEY` secret so the reusable workflow can
  mint its own installation token for `nimbus/nimbus-machine-os`
- the reusable workflow uses that GitHub App token for both GHCR publishing
  and `gh release ... --repo nimbus/nimbus-machine-os`; standalone
  runs in this repository continue to use the native `github.token`
- standalone `nimbus/nimbus-machine-os` `v*` tags are expected to use
  the same `v*` tag as the embedded nimbus release; the workflow resolves the
  binary from `nimbus/nimbus/releases/download/<same-tag>/...`
- non-release validation runs may float to Nimbus's latest published release,
  but they do not publish immutable artifacts

Published OCI metadata includes:

- `org.opencontainers.image.source=https://github.com/nimbus/nimbus-machine-os`
- `org.opencontainers.image.revision=<machine-os source revision>`
- `io.nimbus.machine.attestation.repository=<repo that owns the attestation>`
- `io.nimbus.machine.nimbus.version=<embedded nimbus tag>`

Promotion into the Nimbus macOS default must pin the digest reference recorded
in `machine-image-reference.txt`, not only the version tag.

Triggered by pushes to main (path-filtered), `v*` tags, `workflow_call`, and
`workflow_dispatch`.

## License

See [LICENSE](LICENSE).
