# BRC Analytics Playbook
# Run playbooks locally on TACC VMs with sudo caching
#
# Usage:
#   make bootstrap  - Initial system setup (Docker, Node.js, certbot)
#   make deploy     - Full deployment (clone, build, start)
#   make update     - Update existing deployment
#   make status     - Check service status

HOSTNAME = $(shell hostname --fqdn)
INVENTORY = inventory/hosts.yaml
ANSIBLE_PLAYBOOK = ansible-playbook -i $(INVENTORY)

.PHONY: sudo bootstrap deploy update status requirements cert-renew logs shell help

# Cache sudo credentials before running privileged playbooks
sudo:
	@echo "Caching sudo credentials..."
	@sudo -l > /dev/null

# Install Ansible Galaxy requirements
requirements:
	ansible-galaxy collection install -r requirements.yaml
	ansible-galaxy role install -r requirements.yaml

# Initial system setup: Docker, Node.js, certbot, service user
bootstrap: sudo
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --limit=$(HOSTNAME)

# Full deployment: clone repo, build catalog, obtain SSL cert, start services
deploy: sudo
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --limit=$(HOSTNAME)

# Update deployment: pull changes, rebuild, restart
update: sudo
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --limit=$(HOSTNAME)

# Check service status (no sudo required)
status:
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --limit=$(HOSTNAME)

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

# Syntax check playbooks
check:
	$(ANSIBLE_PLAYBOOK) playbook-bootstrap.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-deploy.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-update.yaml --syntax-check
	$(ANSIBLE_PLAYBOOK) playbook-status.yaml --syntax-check

help:
	@echo "BRC Analytics Playbook"
	@echo ""
	@echo "Targets:"
	@echo "  requirements  - Install Ansible Galaxy dependencies"
	@echo "  bootstrap     - Initial system setup (Docker, Node.js, certbot)"
	@echo "  deploy        - Full deployment (clone, build, SSL, start)"
	@echo "  update        - Update deployment (pull, rebuild, restart)"
	@echo "  status        - Check service status"
	@echo "  cert-renew    - Force SSL certificate renewal"
	@echo "  logs          - View container logs"
	@echo "  shell         - Shell into backend container"
	@echo "  vault-edit    - Edit encrypted vault file"
	@echo "  check         - Syntax check all playbooks"
	@echo ""
	@echo "Example workflow:"
	@echo "  1. make requirements  # First time only"
	@echo "  2. make bootstrap     # First time only"
	@echo "  3. make deploy        # Initial deployment"
	@echo "  4. make update        # Subsequent updates"
