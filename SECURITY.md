# Security Policy

`nimbus/machine-os` publishes the guest VM image used by Nimbus on macOS. The
image includes a Linux arm64 `nimbus` control-plane binary, container tooling,
systemd units, SELinux policy, and bootc lifecycle support.

Nimbus is pre-launch, but machine image changes are treated as security
sensitive because they define the local VM trust boundary.

## Supported Versions

The supported machine image is the immutable digest pinned by the matching
`nimbus/nimbus` release. Tags are convenience labels; operators and release
docs should use the digest reference recorded in `machine-image-reference.txt`.

Older pre-launch tags may remain available as historical release records but
are not maintenance branches unless the project explicitly creates such a line.

## Reporting A Vulnerability

Report suspected vulnerabilities through GitHub private vulnerability
reporting or by contacting the Nimbus maintainers through the project security
channel. Include:

- affected image tag and digest reference
- Nimbus host release version
- host platform and architecture
- relevant release asset checksums or SBOM references
- reproduction steps or audit excerpts, if available

Do not post exploit details in public issues before a maintainer has triaged
the report.

## Security Gates

Release and promotion work should preserve these gates:

- digest-pinned Fedora bootc base image
- digest-pinned bootc-image-builder image
- exact embedded Nimbus version and source revision in build summaries
- SBOM and checksum release assets
- GitHub attestations for release assets
- OCI annotations that identify source repository, source revision,
  attestation repository, and embedded Nimbus version
- real macOS guest SELinux audit capture before default promotion

The deterministic helper checks prove script and parser behavior. They do not
replace real guest evidence for SELinux, boot, virtiofs, machine API, or bootc
lifecycle promotion.

## SELinux Policy Posture

The image keeps a narrow policy stance:

- `nimbus.service` runs as `container_runtime_t`
- `/run/nimbus/nimbus.sock` is relabeled `container_var_run_t`
- the host-forwarded SSH session can connect to the machine API socket through
  a narrow `nimbus-machine-api` CIL module
- the Fedora bootupd userdb compatibility module covers only the observed base
  image path and must not grow without recorded AVC evidence

Any new AVC denial is a release blocker until it is removed, proven harmless,
or covered by an explicitly reviewed policy change.
