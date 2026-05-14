# Nimbus Machine OS Recipe

This directory owns the checked-in Linux guest-image recipe for the Nimbus
macOS machine.

It is intentionally bootc-native while preserving the Podman-compatible raw
disk artifact contract that the macOS host selector consumes:

- base image: digest-pinned `quay.io/fedora/fedora-bootc:44`
- build flow: `podman build` -> `podman save` -> digest-pinned
  `bootc-image-builder --type raw --rootfs ext4`
- guest workload model: standard Linux containers via `crun`, not nested
  guest-side microVMs
- first-boot bootstrap: baked Nimbus units plus the Nimbus machine-config
  channel, not Ignition
- host file sharing: virtiofs
- SELinux: `nimbus.service` runs in `container_runtime_t`, the machine API
  socket is relabeled `container_var_run_t`, and the image installs a narrow
  `nimbus-machine-api` CIL module for the host-forwarded socket path

This recipe is for Linux hosts and CI. macOS consumes the published artifact;
it does not build the guest image locally during normal development.

## Outputs

`images/build.sh` produces:

- `nimbus-machine-os.ociarchive`
- `nimbus-machine-os.raw.gz`
- `summary.txt`

The summary records:

- the staged `nimbus` binary path and sha256
- the optional embedded `nimbus_version` tag
- the direct Fedora bootc base digest
- the bootc-image-builder digest and rootfs choice
- the bootc-native provisioning contract and administrative user
- the SELinux policy/domain expectation plus package inventory
- the recipe file sha256 values
- the OCI archive and raw-disk artifact sha256 values

That summary is the canonical handoff into `scripts/package-oci.sh`, which
wraps the raw disk in the OCI layout consumed by the host machine manager.
The disk payload is still a raw disk image, but the published macOS provider
artifact is annotated as `disktype=applehv` to match Podman's machine image
selector contract.

## Build

Preferred wrapper:

```bash
sudo bash scripts/build.sh \
  --nimbus-binary /absolute/path/to/nimbus-linux-arm64 \
  --nimbus-version vX.Y.Z \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir /tmp/nimbus-machine-os
```

Direct recipe entrypoint:

```bash
sudo bash images/build.sh \
  --nimbus-binary /absolute/path/to/nimbus-linux-arm64 \
  --nimbus-version vX.Y.Z \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir /tmp/nimbus-machine-os
```

`--nimbus-version` and `--source-revision` are optional for local builds, but
CI and release lanes should pass them so downstream OCI metadata can declare
exactly which Nimbus release and machine-os revision the image embeds.

## Package And Publish

Package the raw disk into the OCI layout expected by the host manager:

```bash
bash scripts/package-oci.sh \
  --build-output-dir /tmp/nimbus-machine-os \
  --image-reference docker://ghcr.io/nimbus/nimbus-machine-os:vX.Y.Z \
  --layout-dir /tmp/nimbus-machine-os/oci-layout
```

Publish the packaged layout:

```bash
bash scripts/publish.sh \
  --layout-dir /tmp/nimbus-machine-os/oci-layout \
  --image-reference docker://ghcr.io/nimbus/nimbus-machine-os:vX.Y.Z \
  --additional-reference docker://ghcr.io/nimbus/nimbus-machine-os:stable \
  --release-dir /tmp/nimbus-machine-os/release
```

The packaged OCI artifact carries:

- `disktype=applehv`
- `org.opencontainers.image.source`
- `org.opencontainers.image.revision`
- `io.nimbus.machine.attestation.repository`
- `io.nimbus.machine.nimbus.version`

That keeps the host-side attestation and version checks machine-readable
instead of inferred from repo naming alone.

## CI Contract

The owning workflow is:

- `.github/workflows/build.yml`

Release shape:

- `nimbus/nimbus` `v*` releases call this workflow via `workflow_call`
  and pass the same tag as `nimbus_version`
- standalone `nimbus/nimbus-machine-os` `v*` tags must embed the same
  Nimbus version they publish
- non-release validation runs may float to Nimbus's latest published release,
  but they do not publish immutable artifacts

## Verification

Repo-owned verification entrypoints:

```bash
bash scripts/verify-recipe.sh
bash scripts/verify-build-helper.sh
bash scripts/verify-fedora-bootc-proof.sh
bash scripts/verify-oci-layout-helper.sh
bash scripts/verify-publish-helper.sh
```
