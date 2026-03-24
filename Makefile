# BRC Analytics Playbook
#
# Default: remote execution over SSH (requires VPN to TACC).
# For local execution on a VM: make <target> LOCAL=1
#
# Usage:
#   make setup          - First time: create venv and install Ansible
#   make deploy-dev     - Full deploy to dev
#   make deploy-prod    - Full deploy to prod
#   make update-dev     - Update dev
#   make update-prod    - Update prod
#   make status-dev     - Check dev service status
#   make status-prod    - Check prod service status

INVENTORY = inventory/hosts.yaml
VENV = .venv
ANSIBLE_PLAYBOOK = $(VENV)/bin/ansible-playbook -i $(INVENTORY)
ANSIBLE_GALAXY = $(VENV)/bin/ansible-galaxy
PIP = $(VENV)/bin/pip

DEV_HOST = brc-analytics-dev.tacc.utexas.edu
PROD_HOST = brc-analytics-prod.tacc.utexas.edu
JETSTREAM_HOST = brc-backend.novalocal

# For on-box execution: make <target> LOCAL=1
ifdef LOCAL
EXTRA_ARGS += -e ansible_connection=local
endif

.PHONY: setup requirements check vault-edit vault-create cert-generate help
.PHONY: bootstrap-dev bootstrap-prod deploy-dev deploy-prod update-dev update-prod
.PHONY: update-staging update-beta status-dev status-prod status-jetstream
.PHONY: restart-dev restart-prod cert-renew-dev cert-renew-prod
.PHONY: logs shell

# --- Setup ---

setup:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt
	$(ANSIBLE_GALAXY) collection install -r requirements.yaml
	@echo ""
	@echo "Setup complete!"

requirements: $(VENV)
	$(ANSIBLE_GALAXY) collection install -r requirements.yaml

$(VENV):
	@echo "Run 'make setup' first to create the virtual environment"
	@exit 1

# --- Bootstrap (first time on a VM) ---

bootstrap-dev:
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --limit=$(DEV_HOST) $(EXTRA_ARGS)

bootstrap-prod:
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --limit=$(PROD_HOST) $(EXTRA_ARGS)

# --- Deploy (full, from scratch) ---

deploy-dev:
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --limit=$(DEV_HOST) $(EXTRA_ARGS)

deploy-prod:
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --limit=$(PROD_HOST) $(EXTRA_ARGS)

deploy-jetstream:
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --limit=$(JETSTREAM_HOST) $(EXTRA_ARGS)

# --- Update (pull, rebuild, restart) ---

update-dev:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(DEV_HOST) $(EXTRA_ARGS)

update-prod:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(PROD_HOST) $(EXTRA_ARGS)

update-jetstream:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(JETSTREAM_HOST) $(EXTRA_ARGS)

update-staging:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(JETSTREAM_HOST) -e env_filter=staging $(EXTRA_ARGS)

update-beta:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(JETSTREAM_HOST) -e env_filter=beta $(EXTRA_ARGS)

# --- Status ---

status-dev:
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --limit=$(DEV_HOST) $(EXTRA_ARGS)

status-prod:
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --limit=$(PROD_HOST) $(EXTRA_ARGS)

status-jetstream:
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --limit=$(JETSTREAM_HOST) $(EXTRA_ARGS)

# --- Restart ---

restart-dev:
	$(ANSIBLE_PLAYBOOK) playbook-restart.yaml --limit=$(DEV_HOST) $(EXTRA_ARGS)

restart-prod:
	$(ANSIBLE_PLAYBOOK) playbook-restart.yaml --limit=$(PROD_HOST) $(EXTRA_ARGS)

# --- SSL ---

cert-renew-dev:
	$(ANSIBLE_PLAYBOOK) playbook-cert-renew.yaml --limit=$(DEV_HOST) $(EXTRA_ARGS)

cert-renew-prod:
	$(ANSIBLE_PLAYBOOK) playbook-cert-renew.yaml --limit=$(PROD_HOST) $(EXTRA_ARGS)

cert-generate:
ifndef DOMAIN
	$(error DOMAIN is required. Usage: make cert-generate DOMAIN=api.brc-analytics.org)
endif
	@echo "Generating certificate for $(DOMAIN) using DNS-01 challenge..."
	certbot certonly --dns-route53 -d $(DOMAIN) --config-dir ./certs --work-dir ./certs --logs-dir ./certs
	@echo ""
	@echo "Certificate generated! Add these to your vault file:"
	@echo ""
	@echo "vault_ssl_fullchain: |"
	@cat ./certs/live/$(DOMAIN)/fullchain.pem | sed 's/^/  /'
	@echo ""
	@echo "vault_ssl_privkey: |"
	@cat ./certs/live/$(DOMAIN)/privkey.pem | sed 's/^/  /'
	@echo ""
	@echo "Then run: ansible-vault encrypt group_vars/<env>/vault.yaml"

# --- Vault ---

vault-edit:
	$(VENV)/bin/ansible-vault edit group_vars/all/vault.yaml

vault-create:
	$(VENV)/bin/ansible-vault create group_vars/all/vault.yaml

# --- Local utilities (run on the VM itself) ---

logs:
	cd /opt/brc-analytics/backend && docker compose logs -f

shell:
	cd /opt/brc-analytics/backend && docker compose exec backend /bin/bash

# --- Validation ---

check:
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-restart.yaml --syntax-check

# --- Help ---

help:
	@echo "BRC Analytics Playbook"
	@echo ""
	@echo "Remote execution (default, requires VPN):"
	@echo "  make deploy-dev       - Full deploy to dev"
	@echo "  make deploy-prod      - Full deploy to prod"
	@echo "  make deploy-jetstream - Full deploy to Jetstream"
	@echo "  make update-dev       - Update dev"
	@echo "  make update-prod      - Update prod"
	@echo "  make update-jetstream - Update Jetstream (all envs)"
	@echo "  make update-staging   - Update Jetstream staging only"
	@echo "  make update-beta      - Update Jetstream beta only"
	@echo "  make status-dev       - Check dev service status"
	@echo "  make status-prod      - Check prod service status"
	@echo "  make restart-dev      - Restart dev services"
	@echo "  make restart-prod     - Restart prod services"
	@echo ""
	@echo "Local execution (on the VM itself):"
	@echo "  make update-dev LOCAL=1"
	@echo ""
	@echo "Setup & utilities:"
	@echo "  make setup            - Create .venv and install Ansible"
	@echo "  make vault-edit       - Edit encrypted vault file"
	@echo "  make check            - Syntax check all playbooks"
	@echo "  make logs             - View container logs (on VM)"
	@echo "  make shell            - Shell into backend (on VM)"
