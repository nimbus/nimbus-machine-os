# Direct Fedora Bootc Proof

This directory is the original direct Fedora bootc proof lane. Its direction
has been promoted into the primary recipe in `images/`.

Purpose:

- build a direct Fedora bootc based Nimbus machine image now
- emit the same macOS OCI disk-artifact shape as the default candidate
- prove or falsify a bootc-native, Ignition-free Nimbus machine contract before
  any promotion

Default inputs, refreshed 2026-05-13:

- Fedora bootc base:
  `quay.io/fedora/fedora-bootc@sha256:187d480948fe37a4cc55211b8a594adfc4f85a7d17ac1991331bf98272eb8f94`
- bootc-image-builder:
  `quay.io/centos-bootc/bootc-image-builder@sha256:754fc17718f977313885379e2c779066aba7d15af88fe04b486baec74759f574`
- bootc-image-builder output:
  `--type raw --rootfs ext4`

Build:

```bash
sudo bash proofs/direct-fedora-bootc/build.sh \
  --nimbus-binary /absolute/path/to/nimbus-linux-arm64 \
  --nimbus-version vX.Y.Z \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir /tmp/nimbus-machine-os-fedora-bootc-proof
```

Package the proof output with the shared OCI wrapper:

```bash
bash scripts/package-oci.sh \
  --build-output-dir /tmp/nimbus-machine-os-fedora-bootc-proof \
  --image-reference docker://ghcr.io/nimbus/machine-os:fedora-bootc-proof \
  --layout-dir /tmp/nimbus-machine-os-fedora-bootc-proof/oci-layout \
  --arch arm64 \
  --disk-type applehv
```

Promotion rule:

The primary `images/` recipe can become the final macOS default only after it
passes the full macOS machine parity gate through a bootc-native provisioning
channel rather than Ignition. The proof must cover SSH/user contract, baked or
bootc-updated `/usr/local/bin/nimbus`, SELinux, virtiofs, forwarded machine
API, service lifecycle, bootc switch/upgrade/rollback, and recreate. SELinux
proof includes the baked `container_runtime_t` service domain,
`container_var_run_t` machine API socket label, narrow `nimbus-machine-api`
CIL module, Fedora-base bootupd compatibility policy, boot-state restorecon
service, and a real guest AVC gate capture before promotion.
