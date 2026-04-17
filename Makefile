# BRC Analytics Playbook
#
# Run playbooks locally on TACC VMs with sudo caching
#
# Usage:
#   make setup      - First time: create venv and install Ansible
#   make bootstrap  - Initial system setup (Docker, Node.js, certbot)
#   make deploy     - Full deployment (clone, build, start)
#   make update     - Update existing deployment
#   make status     - Check service status

HOSTNAME = $(shell hostname --fqdn)
INVENTORY = inventory/hosts.yaml
VENV = .venv
ANSIBLE_PLAYBOOK = $(VENV)/bin/ansible-playbook -i $(INVENTORY)
ANSIBLE_GALAXY = $(VENV)/bin/ansible-galaxy
PIP = $(VENV)/bin/pip

JETSTREAM_HOST = brc-backend.novalocal

EXTRA_ARGS += -e ansible_connection=local

# Wrap a command with sudo keepalive so long-running playbooks don't lose credentials
define with-sudo
	@sudo -v
	@bash -c '(while sudo -v; do sleep 55; done) & PID=$$!; trap "kill $$PID 2>/dev/null" EXIT; $(1)'
endef

.PHONY: setup bootstrap deploy update update-staging update-beta rebuild auto-update status restart
.PHONY: requirements check vault-edit vault-create cert-renew cert-generate logs shell help

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

bootstrap:
	$(call with-sudo,$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS))

# --- Deploy (full, from scratch) ---

deploy:
	$(call with-sudo,$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS))

# --- Update (pull, rebuild, restart) ---

update:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS)

update-staging:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME) -e env_filter=staging $(EXTRA_ARGS)

update-beta:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME) -e env_filter=beta $(EXTRA_ARGS)

rebuild:
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME) -e force_rebuild=true $(EXTRA_ARGS)

auto-update:
	$(call with-sudo,$(ANSIBLE_PLAYBOOK) playbook-auto-update.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS))

# --- Status ---

status:
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS)

# --- Restart ---

restart:
	$(ANSIBLE_PLAYBOOK) playbook-restart.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS)

# --- SSL ---

cert-renew:
	$(call with-sudo,$(ANSIBLE_PLAYBOOK) playbook-cert-renew.yaml --limit=$(HOSTNAME) $(EXTRA_ARGS))

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
	$(ANSIBLE_PLAYBOOK) playbook-auto-update.yaml --syntax-check

# --- Help ---

help:
	@echo "BRC Analytics Playbook"
	@echo ""
	@echo "Targets:"
	@echo "  setup         - First time: create .venv and install Ansible"
	@echo "  bootstrap     - Initial system setup (Docker, Node.js, certbot)"
	@echo "  deploy        - Full deployment (clone, build, SSL, start)"
	@echo "  update        - Update deployment (pull, rebuild if needed, restart)"
	@echo "  update-staging- Update only staging env (multi-env hosts)"
	@echo "  update-beta   - Update only beta env (multi-env hosts)"
	@echo "  rebuild       - Force full rebuild and restart"
	@echo "  auto-update   - Install/refresh auto-update systemd timer"
	@echo "  status        - Check service status"
	@echo "  restart       - Restart services"
	@echo "  cert-renew    - Force SSL certificate renewal"
	@echo "  logs          - View container logs"
	@echo "  shell         - Shell into backend container"
	@echo "  vault-edit    - Edit encrypted vault file"
	@echo "  check         - Syntax check all playbooks"
	@echo ""
	@echo "First-time setup:"
	@echo "  sudo dnf install -y git python3 make"
	@echo "  git clone https://github.com/galaxyproject/brc-analytics-playbook.git"
	@echo "  cd brc-analytics-playbook"
	@echo "  make setup"
	@echo "  make bootstrap"
	@echo "  make deploy"
	@echo ""
	@echo "Subsequent updates:"
	@echo "  make update"
	@echo ""
	@echo "Branch deployment:"
	@echo "  Dev VM deploys 'main' branch"
	@echo "  Prod VM deploys 'production' branch"
