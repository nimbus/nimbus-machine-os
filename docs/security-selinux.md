# Security And SELinux

The machine image is part of the local Nimbus trust boundary. It runs the guest
machine API, starts service containers, and handles bootc lifecycle operations.

## Current SELinux Shape

The image installs a narrow SELinux policy stance:

- `nimbus.service` runs with
  `SELinuxContext=system_u:system_r:container_runtime_t:s0`
- `nimbus.socket` listens on `/run/nimbus/nimbus.sock`
- the socket is relabeled `container_var_run_t`
- `nimbus-machine-api.cil` allows the host-forwarded SSH session to connect to
  the machine API socket
- `nimbus-bootupd-fedora-base.cil` covers the observed Fedora bootupd userdb
  path in the current base image
- `nimbus-boot-restorecon.service` relabels `/boot/bootupd-state.json` before
  Fedora's bootloader update service runs

This policy is deliberately narrow. Do not broaden it without real AVC
evidence and a written reason.

## Promotion Gate

Default promotion requires a real guest audit capture:

```bash
bash scripts/check-selinux-avcs.sh --audit-log <path>
```

The helper fails on any AVC denial. It classifies known categories only to make
triage faster; a classified AVC is still a failure unless the image policy is
updated and reviewed.

Deterministic helper tests such as `scripts/verify-selinux-avc-gate.sh` prove
the parser behavior. They do not prove runtime SELinux safety.

## Runtime Boundary

The host reaches the guest through a forwarded machine API path. The policy is
designed around that narrow path rather than broad SSH access to arbitrary
container runtime surfaces.

The guest machine API owns:

- readiness reporting
- service lifecycle commands
- bootc status/switch/upgrade/rollback commands
- machine config application

The host owns:

- image selection
- disk materialization
- VM launch
- machine config bundle generation
- diagnostics and recreate when the guest cannot answer

## Base Image Compatibility

Fedora bootc base image behavior can change. When updating the base digest,
capture and review:

- package inventory changes
- bootupd behavior changes
- systemd unit changes that affect Nimbus services
- new or removed AVCs
- bootc status and rollback behavior

The Fedora bootupd compatibility module should remain specific to observed
base-image behavior. It is not a general permission bucket.

## Release Evidence

Security-sensitive release evidence includes:

- digest-pinned Fedora bootc base image
- digest-pinned bootc-image-builder image
- embedded Nimbus binary hash
- SBOM
- checksums
- GitHub attestations
- `selinux_expectation` in `build-summary.txt`
- real guest AVC capture for default promotion

## Triage Rules

- New AVC denial: blocker until reviewed.
- Missing SBOM or checksum asset: release blocker.
- Missing source revision or Nimbus version metadata: release blocker.
- GHCR package source label not pointing at `nimbus/machine-os`: release
  blocker.
- Runtime proof without real guest evidence: useful for helper validation, not
  enough for default promotion.
