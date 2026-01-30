# BRC Analytics Playbook
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

.PHONY: setup sudo bootstrap deploy update update-staging update-beta status restart requirements cert-renew cert-generate logs shell help

# First-time setup: create venv, install Ansible, install Galaxy collections
setup:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt
	$(ANSIBLE_GALAXY) collection install -r requirements.yaml
	@echo ""
	@echo "Setup complete! Now run: make bootstrap"

# Cache sudo credentials before running privileged playbooks
sudo:
	@echo "Caching sudo credentials..."
	@sudo -l > /dev/null

# Install/update Ansible Galaxy requirements
requirements: $(VENV)
	$(ANSIBLE_GALAXY) collection install -r requirements.yaml

$(VENV):
	@echo "Run 'make setup' first to create the virtual environment"
	@exit 1

# Initial system setup: Docker, Node.js, certbot, service user
bootstrap: sudo
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --limit=$(HOSTNAME)

# Full deployment: clone repo, build catalog, obtain SSL cert, start services
deploy: sudo
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --limit=$(HOSTNAME)

# Update deployment: pull changes, rebuild, restart
update: sudo
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME)

# Update only staging environment (multi-env hosts)
update-staging: sudo
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME) -e env_filter=staging

# Update only beta environment (multi-env hosts)
update-beta: sudo
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME) -e env_filter=beta

# Check service status (no sudo required)
status:
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --limit=$(HOSTNAME)

# Restart services
restart: sudo
	$(ANSIBLE_PLAYBOOK) playbook-restart.yaml --limit=$(HOSTNAME)

# Force certificate renewal
cert-renew: sudo
	$(ANSIBLE_PLAYBOOK) playbook-cert-renew.yaml --limit=$(HOSTNAME)

# View container logs
logs:
	cd /opt/brc-analytics/backend && docker compose logs -f

# Shell into backend container
shell:
	cd /opt/brc-analytics/backend && docker compose exec backend /bin/bash

# Create/edit vault encrypted files
vault-edit:
	ansible-vault edit group_vars/all/vault.yaml

vault-create:
	ansible-vault create group_vars/all/vault.yaml

# Generate SSL certificate locally using DNS-01 challenge (requires AWS creds)
# Usage: make cert-generate DOMAIN=api.brc-analytics.org
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

# Syntax check playbooks
check:
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-restart.yaml --syntax-check

help:
	@echo "BRC Analytics Playbook"
	@echo ""
	@echo "Targets:"
	@echo "  setup         - First time: create .venv and install Ansible"
	@echo "  bootstrap     - Initial system setup (Docker, Node.js, certbot)"
	@echo "  deploy        - Full deployment (clone, build, SSL, start)"
	@echo "  update        - Update deployment (pull, rebuild, restart)"
	@echo "  update-staging- Update only staging env (multi-env hosts)"
	@echo "  update-beta   - Update only beta env (multi-env hosts)"
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
