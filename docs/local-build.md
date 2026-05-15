# Local Build

Most macOS developers consume the published machine-os image. Building a disk
locally is a Linux builder workflow because it needs rootful Podman and
bootc-image-builder.

## Requirements

- Linux arm64 host or GitHub `ubuntu-24.04-arm` runner
- rootful Podman
- `sudo`
- `git`
- `gzip`
- `sha256sum`
- enough free disk for base images, the bootc build context, raw disk output,
  compressed disk output, and OCI layout staging

The release workflow currently pulls digest-pinned Fedora bootc and
bootc-image-builder images before running the build.

## Build

Download or build the matching Linux arm64 Nimbus binary first:

```bash
curl -fsSL -o /tmp/nimbus_linux_arm64.tar.gz \
  https://github.com/nimbus/nimbus/releases/latest/download/nimbus_linux_arm64.tar.gz
tar xzf /tmp/nimbus_linux_arm64.tar.gz -C /tmp
```

Build the guest image:

```bash
sudo bash scripts/build.sh \
  --nimbus-binary /tmp/nimbus \
  --nimbus-version vX.Y.Z \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir /tmp/nimbus-machine-os
```

The wrapper calls the checked-in image recipe and writes:

- `nimbus-machine-os.ociarchive`
- `nimbus-machine-os.raw`
- `nimbus-machine-os.raw.gz`
- `nimbus-machine-os.sbom.cdx.json`
- `summary.txt`

## Package

Package the raw disk into the OCI layout that the host selector consumes:

```bash
bash scripts/package-oci.sh \
  --build-output-dir /tmp/nimbus-machine-os \
  --image-reference docker://ghcr.io/nimbus/machine-os:vX.Y.Z \
  --layout-dir /tmp/nimbus-machine-os/oci-layout \
  --arch arm64 \
  --source-repository-url https://github.com/nimbus/machine-os \
  --source-revision "$(git rev-parse HEAD)" \
  --attestation-repository nimbus/machine-os \
  --nimbus-version vX.Y.Z
```

## Publish

Publishing is normally done by `.github/workflows/publish.yml` after a staged
bundle is produced by the `nimbus/nimbus` release workflow. Manual publishing
should use a controlled token and should not bypass release evidence creation.

```bash
bash scripts/publish.sh \
  --layout-dir /tmp/nimbus-machine-os/oci-layout \
  --image-reference docker://ghcr.io/nimbus/machine-os:vX.Y.Z \
  --release-dir /tmp/nimbus-machine-os/release
```

## macOS-Friendly Checks

These deterministic checks can run without a Linux image build:

```bash
bash scripts/verify-recipe.sh
bash scripts/verify-build-helper.sh
bash scripts/verify-oci-layout-helper.sh
bash scripts/verify-provider-artifact-contracts.sh
bash scripts/verify-publish-helper.sh
bash scripts/verify-selinux-avc-gate.sh
```

They validate script behavior, metadata, and helper parsing. They do not prove
that a real VM boots, that SELinux is clean, or that bootc lifecycle operations
work on macOS.

## Common Problems

- **Not enough disk:** remove old build output under `/tmp`, prune rootful
  Podman images only when you do not need them, or use a larger runner/machine.
- **Rootless build failure:** build with rootful Podman through `sudo`.
- **Missing Nimbus binary:** pass an absolute Linux arm64 binary path with
  `--nimbus-binary`.
- **SELinux uncertainty:** capture real guest audit output and run
  `bash scripts/check-selinux-avcs.sh --audit-log <path>`.
