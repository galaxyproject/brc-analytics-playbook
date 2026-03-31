# Repository Guidelines

## Project Structure & Module Organization
This repository is an Ansible deployment playbook for BRC Analytics infrastructure. Top-level `playbook-*.yaml` files map to operational flows such as deploy, update, restart, status, bootstrap, and certificate renewal. Shared task fragments live in `tasks/`, Jinja templates in `templates/`, inventory in `inventory/hosts.yaml`, and environment-specific variables in `group_vars/`. Keep secrets in `group_vars/all/vault.yaml` via Ansible Vault, not in plaintext files.

## Build, Test, and Development Commands
Use the `Makefile` as the entry point for routine work:

- `make setup` creates `.venv`, installs Python dependencies, and installs Ansible collections.
- `make check` runs `ansible-playbook --syntax-check` against the main playbooks.
- `make deploy-dev`, `make deploy-prod`, `make update-dev`, `make update-prod` run the corresponding operational playbooks.
- `make status-dev` or `make restart-prod` handle inspection and service restarts.
- `make update-dev LOCAL=1` is the pattern for running locally on the VM with `ansible_connection=local`.

## Coding Style & Naming Conventions
Write YAML with two-space indentation and descriptive task names in sentence case, matching existing playbooks. Name new playbooks `playbook-<action>.yaml`; place reusable sequences in `tasks/<action>.yaml`. Keep variables in `snake_case` (for example `brc_repo_branch`, `health_check_url`) and prefer shared defaults in `group_vars/all/vars.yaml` with environment overrides in `group_vars/development/` or `group_vars/production/`.

## Testing Guidelines
There is no unit-test suite in this repository. Validation is primarily syntax and execution based:

- Run `make check` before opening a PR.
- For behavior changes, run the smallest relevant target such as `make status-dev` or the affected deploy/update target in a safe environment.
- If you add conditionals, templates, or inventory fields, verify both the changed path and any impacted environment override.

## Commit & Pull Request Guidelines
Recent commits use short, imperative summaries such as `switch to remote SSH execution by default` and `add SENTRY_DSN to backend env template`. Follow that style: one-line, lower-case subject, focused on the change. PRs should include a concise description, affected environments (`dev`, `prod`, or `jetstream`), any required vault or inventory updates, and relevant command output from `make check`. Include screenshots only if a change affects generated nginx or deployment-facing output that benefits from visual confirmation.

## Security & Configuration Tips
Do not commit `.vault-password.txt`, decrypted secrets, or generated certificates under `certs/`. Review `ansible.cfg` before adding privileged tasks: `become` is opt-in, so elevate only the tasks that require it.
