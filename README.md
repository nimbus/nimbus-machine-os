# nimbus-machine-os

Guest OS image for the nimbus macOS developer machine. Built on Fedora bootc
with nimbus and container tooling pre-installed.

This is the nimbus equivalent of
[containers/podman-machine-os](https://github.com/containers/podman-machine-os).

## What's inside

The guest image includes:

- **nimbus** — the nimbus server binary (from `nimbus/nimbus` releases)
- **Container tooling** — crun, conmon, buildah, containers-common, netavark,
  aardvark-dns, fuse-overlayfs, catatonit, passt
- **System services** — openssh-server, socat, cloud-init

The image is built from `quay.io/fedora/fedora-bootc:42` and converted to a
raw disk image via `bootc-image-builder`.

## Published artifacts

| Artifact | Location |
|----------|----------|
| Raw-disk OCI image | `ghcr.io/nimbus/nimbus-machine-os` |
| Build provenance | GitHub Attestations (via `actions/attest`) |

## Building locally

Requires a Linux host with podman and root access:

```bash
# Download a nimbus binary first
curl -fsSL -o /tmp/nimbus_linux_arm64.tar.gz \
  https://github.com/nimbus/nimbus/releases/latest/download/nimbus_linux_arm64.tar.gz
tar xzf /tmp/nimbus_linux_arm64.tar.gz -C /tmp

sudo bash scripts/build.sh \
  --nimbus-binary /tmp/nimbus \
  --nimbus-version vX.Y.Z \
  --output-dir /tmp/nimbus-machine-os
```

`--nimbus-version` is optional for ad hoc local builds, but release and CI
lanes should pass it so the build summary and packaged OCI metadata record the
embedded Nimbus version explicitly.

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
- `io.nimbus.machine.attestation.repository=<repo that owns the attestation>`
- `io.nimbus.machine.nimbus.version=<embedded nimbus tag>`

Triggered by pushes to main (path-filtered), `v*` tags, `workflow_call`, and
`workflow_dispatch`.

## License

See [LICENSE](LICENSE).
