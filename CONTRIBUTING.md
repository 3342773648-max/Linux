# Contributing to Kubernetes Cluster Bootstrap

Thank you for your interest in contributing to the Kubernetes Cluster
Bootstrap project! This repository automates Day 0/Day 1 Kubernetes cluster
delivery (Ubuntu 24.04 + kubeadm 1.36 + containerd 2.3 LTS + Calico v3.32)
with Ansible. This document outlines the contribution process.

## Prerequisites

- **ansible-core ≥ 2.21** (project-supported line) with a Python 3.10+
  interpreter. A venv at `/tmp/ansible-venv` is the documented lab setup.
- A Linux target environment for real acceptance. Two supported
  architectures exist:
  - **aarch64** — Lima arm64 (Apple Virtualization) dual-node lab.
  - **x86_64** — Lima QEMU TCG or native amd64 hosts; note the acceptance
    boundary in `SECURITY.md` (QEMU TCG proves lifecycle/idempotency, not
    hardware performance).
- `kubectl` / `kubeadm` / `kubelet` 1.36.x for version-parity assertions.
- No credentials are required to contribute docs, roles or tests: inventory
  examples use RFC 5737 documentation addresses, and real connections stay in
  gitignored `inventory/host_vars/<host>/local.yml`.

## Getting Started

1. Fork the repository and clone your fork.
2. Create a new branch for your changes:
   ```bash
   git checkout -b feat/your-feature-name
   ```
3. Make your changes, following the code conventions below.
4. Run the local gates before committing:
   ```bash
   # Markdown gates (docs/CI parity)
   python .github/scripts/check_markdown_links.py
   python .github/scripts/check_markdown_style.py
   python .github/scripts/scan_sensitive.py

   # Ansible gates
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
   ansible-playbook -i inventory/hosts.yml playbooks/reset.yml --syntax-check
   ansible-playbook -i inventory/hosts.yml playbooks/upgrade.yml --syntax-check
   ansible-inventory -i inventory/hosts.yml --graph
   ```
5. If you changed the scanner, run its regression suite:
   ```bash
   python -m unittest discover -s .github/scripts -p "test_*.py" -v
   ```
6. Commit and push; open a pull request against the `main` branch.

## Code Conventions

- **Roles and playbooks (Ansible/YAML)**: keep tasks declarative and
  idempotent. Every task must be safe to re-run with `changed=0` on a
  converged host. Use `creates`/`changed_when`/`when:` guards instead of
  unconditional operations.
- **Pinned versions only**: never introduce `latest`, `master` or
  unversioned external scripts/manifests. Component anchors live in
  `inventory/group_vars/all.yml`; changing an anchor requires a regression
  note.
- **Architecture support**: new roles must keep the `k8s_accepted_arches`
  preflight contract (`[x86_64, aarch64]`). Do not widen or relax the list to
  make an experiment pass.
- **Secrets discipline**: runtime-generated join material (tokens,
  certificate-keys, CA hashes) stays in `no_log` tasks; examples use RFC 5737
  placeholders; real host connections never enter tracked files.
- **Documentation**: user-facing changes update `README.md` (and the
  `CHANGELOG.md` "Unreleased" section when relevant). New security-relevant
  file types update both `.gitignore` and `docs/security-boundaries.md` §6.
- **Change records**: acceptance evidence is archived under
  `docs/changes/YYYY-MM-DD-<topic>.md` with the architecture, versions,
  sanitized logs, and the mock/real boundary stated.

## Pull Request Workflow

1. **Before submitting**: run all gates from "Getting Started" locally.
2. **PR description**: clearly describe the what, why, and how. Reference the
   relevant change record or `docs/` file when applicable.
3. **CI gates**: your PR must pass all checks before review:
   - Markdown links, markdown style, sensitive-field scan, scanner tests.
   - Ansible syntax-check for `site`/`reset`/`upgrade` and inventory parse.
4. **Review**: after CI passes, the PR will be reviewed. Address feedback
   promptly. Maintainers may request real-cluster acceptance evidence for
   changes that alter deployment behavior.

## Reporting Issues

When filing an issue, please include:

- Clear description of the problem.
- Steps to reproduce (playbook/role/task involved, if known).
- Expected behavior vs actual behavior.
- Sanitized logs or error output (no tokens, keys or real addresses).
- Environment details: host OS/arch, ansible-core version, target OS/arch,
  Kubernetes/containerd/Calico versions.

## Security Disclosure

For security vulnerabilities, please follow the process outlined in
[SECURITY.md](SECURITY.md). Do not file public issues for security
vulnerabilities.
