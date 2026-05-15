# Release Contract

`nimbus/machine-os` is released as part of the main Nimbus release graph. The
machine image must contain the matching Linux arm64 `nimbus` binary, so the
image build starts in the `nimbus/nimbus` release workflow and publication
finishes in the `nimbus/machine-os` repository context.

## Why The Flow Is Split

The split gives Nimbus both properties it needs:

- the guest image is version-coupled to the host release binary
- GHCR package ownership, GitHub Release ownership, and attestations belong to
  `nimbus/machine-os`

The machine image build can overlap the slower platform release matrix, but the
external machine-os publish remains gated on all Nimbus release targets.

## Canonical Flow

1. A `v*` tag is pushed to `nimbus/nimbus`.
2. `nimbus/nimbus` verifies release contracts.
3. `nimbus/nimbus` builds the Linux arm64 release binary.
4. `nimbus/nimbus` checks out `nimbus/machine-os` at `MACHINE_OS_SOURCE_REF`.
5. `nimbus/nimbus` runs `scripts/build.sh` and `scripts/package-oci.sh` from
   this repository.
6. `nimbus/nimbus` uploads an internal staged machine-os artifact.
7. After every CLI/platform release target passes, `nimbus/nimbus` dispatches
   `.github/workflows/publish.yml` in `nimbus/machine-os`.
8. `nimbus/machine-os` downloads and verifies the staged artifact.
9. `nimbus/machine-os` publishes `ghcr.io/nimbus/machine-os:<tag>` with its own
   workflow token.
10. `nimbus/machine-os` creates or updates the GitHub Release, uploads release
   assets, and creates attestations.
11. The final `nimbus/nimbus` release waits for the machine-os publish result.

## Token And Permission Boundaries

The release app is used for cross-repo operations:

- `nimbus/nimbus` needs to read `nimbus/machine-os` and dispatch its publish
  workflow.
- `nimbus/machine-os` needs to read the staged artifact from the source
  `nimbus/nimbus` workflow run.

GHCR publishing should use the `nimbus/machine-os` workflow's `github.token`
with `packages: write`, so the package is linked to the repository that owns
the image source labels and release evidence.

## Workflow Responsibilities

`nimbus/nimbus/.github/workflows/release.yml` owns:

- host release verification
- host CLI/platform binary builds
- Linux arm64 Nimbus binary artifact
- staged machine-os build artifact
- dispatch and wait logic for the machine-os publish workflow

`nimbus/machine-os/.github/workflows/ci.yml` owns:

- pull request and push validation
- deterministic helper checks
- optional tag/manual validation builds that do not publish external artifacts

`nimbus/machine-os/.github/workflows/publish.yml` owns:

- staged bundle hydration
- source revision validation
- GHCR publish
- release evidence assembly
- GitHub Release creation or update
- asset attestation

## Standalone Machine-OS Tags

Standalone `nimbus/machine-os` `v*` tags are validation lanes unless the
project creates an explicit independent machine-os maintenance policy. They may
download the latest Nimbus release binary for testing, but they do not publish
immutable production artifacts by default.

## Release Evidence

Each release should make these facts easy to verify:

- host Nimbus release tag
- embedded Linux `nimbus` binary hash
- machine-os source revision
- base image digest
- bootc-image-builder digest
- raw disk hash
- compressed raw disk hash
- OCI manifest digest
- SBOM hash
- checksum file
- GitHub attestation record

## Attestation Verification

The publish workflow is dispatched from `refs/heads/main` and checks out the
exact `machine_os_source_revision` input before publishing. Current GitHub
asset attestations therefore verify against `refs/heads/main` plus the recorded
source repository digest, not against `refs/tags/<version>`. The machine-os
GitHub Release tag still targets the same source commit.

Example for a downloaded release asset:

```bash
gh attestation verify build-summary.txt \
  --repo nimbus/machine-os \
  --source-ref refs/heads/main
```

A tag-based attestation source-ref check is expected to fail for this
workflow-dispatch model unless the release flow is intentionally changed to
pre-create and dispatch from machine-os release tags.

## Verification

From `nimbus/machine-os`:

```bash
bash scripts/verify-build-helper.sh
bash scripts/verify-oci-layout-helper.sh
bash scripts/verify-publish-helper.sh
```

From `nimbus/nimbus`:

```bash
bash scripts/verify-machine-os-release-ref-contract-helper.sh
bash scripts/verify-machine-os-release-ref-contract.sh \
  --machine-os-repo /Users/jack/src/github.com/nimbus/machine-os
```
