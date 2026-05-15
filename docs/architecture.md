# Machine-OS Architecture

`nimbus/machine-os` builds the Linux guest appliance currently used by Nimbus on macOS.
It is a direct Fedora bootc image with Nimbus guest services and container
tooling pre-installed. Future Windows support should add provider-specific
artifacts from this appliance lineage instead of reusing the macOS raw disk
as-is.

## Design Position

The repository keeps Podman compatibility at the artifact boundary, not at the
repo or build-system boundary.

- The published artifact is a raw disk wrapped in an OCI layout that the host
  selector can consume using the same `disktype=applehv` convention used by
  Podman machine images.
- The image recipe is Nimbus-owned and bootc-native. It does not rebuild a
  Fedora CoreOS image and does not use Ignition as the normal provisioning
  channel.
- The matching Linux arm64 `nimbus` binary from the host release is baked into
  the image and is treated as image content.

## Build Flow

```text
digest-pinned Fedora bootc base
  -> image/Containerfile plus image/build-common.sh
  -> bootc container image with /usr/local/bin/nimbus
  -> digest-pinned bootc-image-builder raw disk conversion
  -> nimbus-machine-os.raw.gz plus build summary and SBOM
  -> scripts/package-oci.sh creates an OCI layout with disktype=applehv
  -> scripts/publish.sh publishes ghcr.io/nimbus/machine-os:<tag>
```

The checked-in production recipe lives under `image/`. All workflow, script, and cross-repo verifier references should move with that directory if it is ever renamed again.

`image/` is singular on purpose: it names the production bootc appliance recipe,
not the number of release artifacts. If future Windows support can reuse the
same guest content, add provider-specific artifact packaging around the recipe
instead of renaming the tree back to `images/`. Introduce additional recipe
directories only if a Windows provider truly needs different guest content.

## Provider Artifact Model

The supported artifact today is macOS AppleHV/LibKrun: a raw disk wrapped in
OCI and selected with `disktype=applehv`.

The reviewed Windows plan reserves two different future shapes:

- WSL2: a rootfs Tar artifact imported with `wsl --import`, then configured by
  WSL-specific shell bootstrap and nested systemd setup.
- Hyper-V: a VHDX-style artifact, deferred until Hyper-V is promoted as a
  supported provider.

The current AppleHV raw disk should not be described as Windows-ready. A
Windows artifact becomes supported only after the Windows host provider can
consume it and prove machine lifecycle, API forwarding, networking, and service
readiness end to end.

## Guest Responsibilities

The guest owns the Linux-side machine contract:

- boot to multi-user systemd target
- mount the host-provided machine config through virtiofs
- apply machine config with `nimbus machine guest-config apply`
- expose the socket-activated machine API with `nimbus machine api`
- run standard Linux containers through Podman, crun, conmon, netavark, and
  aardvark-dns
- support bootc status, switch, upgrade, and rollback through the machine API
- keep mutable state under persistent `/etc` and `/var`

## Host Responsibilities

The macOS host owns the outer control plane:

- choose and pin the desired machine image digest
- materialize the `disktype=applehv` raw disk layer from the OCI artifact
- launch the VM through the macOS provider
- generate and attach the machine-config bundle
- forward the machine API socket through SSH
- monitor readiness, diagnostics, repair, and recreate flows

The host does not normally scp a replacement `nimbus` binary into a bootc
guest. If the baked binary is wrong, the image is wrong and must be fixed by a
new machine image release.

## Provisioning Contract

The bootc-native provisioning contract uses:

- sysusers for the `nimbus` administrative user
- tmpfiles for persistent directories and runtime sockets
- baked systemd units for sshd, machine config, socket activation, and boot
  restorecon behavior
- virtiofs for host-provided machine config
- the Nimbus guest config command for SSH keys, trust material, volumes, and
  ready-state inputs

Ignition is not a requirement or preferred mechanism for this bootc path.

## Relationship To Podman

`containers/podman-machine-os` remains an important upstream reference for how
Podman machines consume and reason about VM disk artifacts. Nimbus follows the
parts that matter for host compatibility:

- publish a disk artifact through OCI/GHCR
- annotate the provider disk type
- keep the artifact selectable by OS and architecture
- preserve Podman-compatible runtime behavior inside the guest

Nimbus does not inherit Podman's current FCOS/WSL/COSA project structure as the
right shape for this repository.

## Enterprise Evidence

Every promoted image should be explainable from release evidence:

- exact Nimbus release tag and Linux guest binary hash
- exact machine-os source revision
- Fedora bootc base image digest
- bootc-image-builder digest and rootfs choice
- package inventory
- systemd unit inventory
- SELinux policy expectation
- SBOM, checksums, and attestations
- published tag and digest reference

The image digest is the contract operators should trust; tags are a discovery
aid.
