# Artifact Contract

Nimbus publishes the machine image as a raw disk wrapped in an OCI image
layout. This lets the macOS host use a registry as the VM image distribution
channel while still selecting a concrete provider disk artifact.

## Required Shape

The macOS host expects:

- OCI operating system: `linux`
- OCI architecture: current guest architecture, currently `arm64`
- provider disk annotation: `disktype=applehv`
- exactly one disk layer for the selected manifest
- disk layer title ending in `.raw`, `.raw.gz`, or `.raw.zst`

`scripts/package-oci.sh` owns this shape.

## Required Annotations

Packaged artifacts should include:

- `org.opencontainers.image.source=https://github.com/nimbus/machine-os`
- `org.opencontainers.image.revision=<machine-os source revision>`
- `org.opencontainers.image.ref.name=<tag>`
- `io.nimbus.machine.attestation.repository=nimbus/machine-os`
- `io.nimbus.machine.nimbus.version=<embedded Nimbus tag>`

These annotations allow the host, release verifiers, and humans to connect a
registry image back to the source repository, release graph, and attestation
owner.

## Release Assets

The machine-os GitHub Release should contain:

- `nimbus-machine-os.raw.gz`
- `nimbus-machine-os.sbom.cdx.json`
- `build-summary.txt`
- `oci-layout-summary.txt`
- `checksums.txt`
- `publish-summary.txt`
- `published-digests.txt`
- `machine-image-reference.txt`

`machine-image-reference.txt` records the tag reference, digest reference, and
published digest. Nimbus default promotions should pin the digest reference,
not only the version tag.

## Build Summary

The build summary is the handoff from image build to OCI packaging. It records
the facts needed for provenance and troubleshooting, including:

- candidate name
- embedded Nimbus version
- embedded Nimbus binary SHA-256
- machine-os source revision
- Fedora bootc base image digest
- bootc-image-builder digest
- rootfs choice
- provisioning contract
- administrative user and subuid/subgid baseline
- package inventory
- systemd unit inventory
- SELinux expectation
- raw disk, compressed disk, OCI archive, and SBOM paths plus hashes

## Compatibility Boundary

The artifact contract intentionally resembles the Podman machine image
selection boundary. That does not mean this repository should keep Podman's
FCOS build system or branch structure.

The compatibility target is:

- a provider-selectable raw disk artifact
- a guest with Podman-compatible container behavior
- enough OCI metadata for host-side selection and release evidence

The implementation target is:

- a Nimbus-owned direct Fedora bootc image
- bootc-native machine config
- baked Nimbus guest control plane
- Nimbus release-owned version coupling

## Verification

Fast local checks:

```bash
bash scripts/verify-oci-layout-helper.sh
bash scripts/verify-publish-helper.sh
```

For release changes, also run the main Nimbus release-contract verifier from
the `nimbus/nimbus` repository:

```bash
bash scripts/verify-machine-os-release-ref-contract.sh \
  --machine-os-repo /Users/jack/src/github.com/nimbus/machine-os
```
