# Provider Artifacts

Nimbus `machine-os` is a guest appliance lineage, not a promise that every host
provider consumes the same disk file. The repository should keep one production
bootc recipe while making provider artifact outputs explicit and testable.

## Current Supported Artifact

| Provider | Status | Artifact | Selector | Consumer |
| --- | --- | --- | --- | --- |
| macOS AppleHV / LibKrun | Supported | gzip-compressed raw disk | `disktype=applehv` | Nimbus macOS machine manager |

The supported release artifact remains `nimbus-machine-os.raw.gz` packaged into
an OCI image layout and published as `ghcr.io/nimbus/machine-os:<tag>`.

## Prepared Future Artifacts

| Provider | Status | Artifact | Selector | Consumer |
| --- | --- | --- | --- | --- |
| Windows WSL2 | Prepared, not supported | gzip-compressed rootfs Tar | `disktype=wsl` | Future `nimbus.exe` WSL2 provider using `wsl --import` |
| Windows Hyper-V | Deferred | VHDX-style disk | `disktype=hyperv` | Future Hyper-V provider, if promoted |

These artifacts are not release defaults and are not advertised as supported
outputs until host-side Windows work proves them end to end.

## WSL2 Contract

The WSL2 artifact is intentionally different from the macOS raw disk:

- WSL2 imports a root filesystem with `wsl --import <name> <dir> <tarball>
  --version 2`.
- WSL2 bootstrap is shell-command based, following Podman's WSL provider shape.
- WSL2 does not use Ignition or an AppleHV raw disk.
- WSL2 should reuse the same Nimbus guest control-plane content where possible:
  `/usr/local/bin/nimbus`, machine API units, container tooling, SELinux policy
  where applicable, and release provenance metadata.
- The Windows provider must prove distro import, shell bootstrap, nested
  systemd, SSH, named-pipe API forwarding, WSL networking, service lifecycle,
  and cleanup before the artifact is published as a supported release output.

## Repository Shape

Keep `image/` singular while the production guest recipe is shared. The name
identifies the bootc appliance recipe, not the number of provider artifacts.
Add provider-specific packaging outputs around that recipe when possible.

Introduce additional recipe directories only if a provider needs materially
different guest content. Examples of acceptable future splits would be:

- `image/` plus packaging scripts for raw, WSL rootfs, and VHDX outputs when the
  guest content is shared.
- `images/<provider>/` only after WSL2 or Hyper-V proves it cannot share the
  bootc guest recipe without making the supported macOS path harder to read or
  verify.

## Verification

Fast metadata checks:

```bash
bash scripts/verify-provider-artifact-contracts.sh
```

This helper proves that:

- current macOS artifacts remain `disktype=applehv` raw disk layouts;
- WSL prep artifacts use `disktype=wsl` and a rootfs Tar media type;
- Hyper-V prep artifacts use `disktype=hyperv` and a VHDX media type;
- future provider artifacts do not accidentally masquerade as the supported
  macOS AppleHV output.

It does not prove that Windows support works. Windows promotion requires the
host-side Windows plan to pass its lifecycle, transport, networking, and service
readiness gates.
