# machine-os Agent Notes

This repository owns the Nimbus macOS guest VM image. The current architecture
is a direct Fedora bootc appliance, not a Podman-machine-os-shaped FCOS build.

## Durable Rules

- Keep `main` as the only long-lived development branch unless a named
  enterprise maintenance line is created.
- Preserve the public artifact contract: a raw disk packaged as an OCI image
  with `disktype=applehv` for the macOS provider.
- Keep GHCR publishing, GitHub Release mutation, and attestations inside the
  `nimbus/machine-os` repository context.
- Do not reintroduce Ignition, FCOS-derived recipe structure, or host-side
  guest binary sync as normal bootc behavior.
- Keep the matching Linux arm64 `nimbus` release binary baked into the image at
  `/usr/local/bin/nimbus`.
- Record exact base image, builder image, Nimbus version, source revision,
  SBOM, checksums, and digest evidence for release artifacts.
- Preserve license and attribution obligations from the original
  Podman-machine-os-derived history.

## Verification

Before finishing repo-shape, workflow, script, or recipe work, run the focused
deterministic checks that match the touched files:

```bash
bash scripts/verify-recipe.sh
bash scripts/verify-build-helper.sh
bash scripts/verify-oci-layout-helper.sh
bash scripts/verify-publish-helper.sh
bash scripts/verify-selinux-avc-gate.sh
```

For release-contract changes, also run the main Nimbus verifier from the
`nimbus/nimbus` repository:

```bash
bash scripts/verify-machine-os-release-ref-contract.sh \
  --machine-os-repo /Users/jack/src/github.com/nimbus/machine-os
```

For image promotion, deterministic helper checks are not enough. Promotion
requires a real macOS guest audit capture checked by:

```bash
bash scripts/check-selinux-avcs.sh --audit-log <path>
```
