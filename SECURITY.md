# Security Policy

This repository delivers Day 0/Day 1 Kubernetes cluster bootstrap automation
(Ansible playbooks for kubeadm + containerd + Calico on Ubuntu 24.04). It is
an infrastructure-as-code project: the security surface is the **delivery
pipeline and the credentials it handles**, not a long-running service.

## Supported Versions

The project is pre-1.0. Security fixes are applied only to the latest release
line. Older commits are not maintained.

| Version | Supported          |
|---------|--------------------|
| latest  | :white_check_mark: |
| < latest| :x:                |

## Reporting a Vulnerability

The maintainers treat security reports as the highest-priority work.
**Do not open public GitHub issues for security problems.**

Report vulnerabilities by one of the following private channels:

1. **GitHub Security Advisory** (preferred): use
   `Security` -> `Report a vulnerability` on the repository. This keeps the
   conversation private and allows the maintainers to request CVE IDs through
   GitHub.
2. **Encrypted email**: send a PGP-encrypted report to
   `security@bootstrap.local`. The current public key fingerprint is published
   in the release notes of the most recent release.

Please include the following information so we can reproduce and triage the
report quickly:

- Affected version (git tag or commit SHA).
- Component (Ansible role, playbook, CI workflow, inventory example, script).
- Target architecture (x86_64 and/or aarch64) and how it was exercised.
- Step-by-step reproduction, including any required cluster state.
- Observed impact and any proof of concept.
- Suggested fix or mitigation, if any.

### Disclosure timeline

| Stage                         | Target       |
|-------------------------------|--------------|
| Acknowledgement of receipt    | 1 business day |
| Initial triage and severity   | 5 business days |
| Fix or mitigation published   | 30 calendar days for high/critical severity, 90 calendar days otherwise |
| Public disclosure             | After a fix is released, or after 90 days if no fix path is agreed, whichever comes first |

Reporters are credited in the change record unless they request otherwise.

## Credential handling (what this repository never contains)

The repository is designed so that **no real credential or node address can
legitimately be committed**. The following invariants are enforced by
`.gitignore` and the CI sensitive-field scanner
(`.github/scripts/scan_sensitive.py`):

- **No real SSH credentials.** Inventory examples use RFC 5737 documentation
  addresses (`192.0.2.x`); real connections live only in gitignored
  `inventory/host_vars/<host>/local.yml` (directory form). Plaintext
  `ansible_password` is a forbidden pattern.
- **No kubeconfig / certificates / keys.** `*.kubeconfig`, `**/admin.conf`,
  `**/pki/`, `*.crt`, `*.key`, `*.csr`, `*.pem` are excluded from Git.
- **Join credentials are ephemeral and generated on the cluster.** Bootstrap
  tokens (default TTL 24h), certificate-keys and
  `discovery-token-ca-cert-hash` values are produced at runtime by
  `kubeadm`, delivered over a secure channel, and rotated/deleted after use.
  The playbooks use `no_log` on the tasks that handle them.
- **Placeholders never become values.** Documentation examples must keep
  `<BOOTSTRAP_TOKEN>`, `sha256:<CA_CERT_HASH>` and similar placeholders
  verbatim; the scanner rejects their literal expansion.

> `.gitignore` is a **mis-commit mitigation, not secret isolation** (`git add -f`
> can still commit a plaintext file). The real gate is the CI scanner and
> human review of the allowlist (`docs/security-boundaries.md` §7).

## Supply-chain controls (software and images)

The bootstrap path pins every component and verifies its origin:

- **Kubernetes tools** are pinned to the acceptance anchor (`kubeadm`,
  `kubelet`, `kubectl` 1.36.x) and installed from the official
  `pkgs.k8s.io` apt repository with signature verification enabled.
- **containerd** is pinned to the 2.3 LTS line from the official Docker apt
  repository (deb822, `signed_by` keyring), then `dpkg-selections`-held.
- **Calico / CNI** manifests are fetched from the fixed `v3.32.x` release
  (never `master`/`latest`) and applied from a locally cached copy with
  `NO_PROXY` set; image pulls go through the documented proxy path.
- **Container images** are pinned by tag; `registry.k8s.io` official images
  are the default `image_repository`.
- **Remote scripts** are never executed via `curl | sh`; anything external is
  a pinned version with a verifiable source.

## CI and supply-chain controls

Enforced by `.github/workflows/ci.yml` (no write access on pull requests):

- **Docs gates**: markdown link check, markdown style check, sensitive-field
  scan (kubeadm token shapes, disabled repo-signing markers, plaintext
  passwords, private-key blocks, kubeconfig-embedded credentials, RFC 1918
  node addresses), and scanner regression tests.
- **Ansible gates**: `ansible-playbook --syntax-check` for `site`, `reset`
  and `upgrade`, plus `ansible-inventory --graph` parse.
- **Allowlist self-protection**: `.github/scan-allowlist.txt` entries must be
  exact full-line regexes with a non-empty reason; wildcard exclusions are
  rejected, and the allowlist itself is a PR-review target.

## Architecture acceptance boundary

B0 declares x86_64 as the first supported path; B2 acceptance has been
executed on **both** architectures:

- **aarch64** (Lima arm64, Apple Virtualization) and **x86_64** (Lima QEMU
  TCG, Ubuntu 24.04 amd64) both completed the full matrix: first deploy,
  `verify-cluster.sh` all green, second-run idempotency `changed=0`,
  `reset.yml`, rebuild, re-verify, re-idempotency.
- The `k8s_accepted_arches` preflight assertion (`[x86_64, aarch64]`) fails a
  node outside the supported list before any cluster component is installed.
- **Boundary caveat**: the x86_64 regression ran under QEMU TCG software
  emulation. It proves the deployment lifecycle and idempotency on amd64, not
  x86_64 hardware performance or behavior. Do not cite it as a hardware
  compatibility or performance guarantee. See
  `docs/changes/2026-08-15-b2-x8664-regression.md`.

## Threat model boundaries

The following are explicit, documented design decisions (`docs/security-boundaries.md`):

- **No firewall/SELinux/AppArmor disablement.** Security features are never
  disabled to "fix" cluster networking; necessary ports are opened instead
  (6443, 2379-2380, 10250, 10257/10259, NodePort range, SSH from management
  sources only).
- **No disabled repository signature verification.** Repo-signing flags are
  never disabled; the literal examples in the security baseline are
  allowlist-exempt and flagged as dangerous examples.
- **Host key verification.** First connection registers the host key via
  fingerprint comparison; `StrictHostKeyChecking=no` auto-accept is forbidden.
- **Log and evidence sanitization.** Execution logs and acceptance evidence
  are desensitized (tokens, keys, real node addresses) before any archival;
  `artifacts/` and `logs/` are gitignored.

## Security-conscious contribution checklist

Before opening a pull request that touches security-sensitive code, confirm:

- [ ] No real SSH credentials, node addresses or kubeconfig data are
      introduced; examples stay on RFC 5737 placeholders.
- [ ] No kubeadm token, certificate hash or certificate-key is written as a
      literal value; runtime-generated join material stays behind `no_log`.
- [ ] No new disabled-repo-signature markers or remote-script-execute patterns
      unless they are allowlist-exempt dangerous examples with a reason.
- [ ] New sensitive file types are added to both `.gitignore` and
      `docs/security-boundaries.md` §6.
- [ ] Playbook changes pass `ansible-playbook --syntax-check` for the
      affected playbook(s).
- [ ] New artifacts/evidence are sanitized before archival.
