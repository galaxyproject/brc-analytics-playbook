# BRC Analytics Playbook

Ansible playbook for deploying BRC Analytics backend services to TACC VMs.

## Overview

This playbook deploys the BRC Analytics backend (nginx, FastAPI, Redis) to:
- **Production**: `brc-analytics-prod.tacc.utexas.edu` → https://platform.brc-analytics.org
- **Development**: `brc-analytics-dev.tacc.utexas.edu` → https://platform-dev.brc-analytics.org

## Architecture

The playbook is designed for **local execution** on each VM. Since SSH access requires VPN + MFA, you:
1. SSH into the VM manually
2. Run the playbook locally with `ansible_connection: local`
3. Use `--limit=$(hostname --fqdn)` to target only the current host

### Branch Deployment

- **Development VM** deploys the `main` branch
- **Production VM** deploys the `production` branch

## Prerequisites

- SSH access to the TACC VMs (requires VPN)
- Python 3.8+ on the VM
- sudo privileges

## Quick Start

### First Time Setup (on the VM)

```bash
# Install git, python, make if not present
sudo dnf install -y git python3 python3-pip make

# Clone this playbook repository
git clone https://github.com/galaxyproject/brc-analytics-playbook.git
cd brc-analytics-playbook

# Set up Python venv and install Ansible
make setup

# Create vault password file (store securely!)
echo "your-vault-password" > .vault-password.txt
chmod 600 .vault-password.txt

# Bootstrap the system (install Docker, Node.js, etc.)
make bootstrap

# Deploy the application
make deploy
```

### Subsequent Updates

```bash
cd brc-analytics-playbook
git pull
make update
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make setup` | First time: create .venv and install Ansible |
| `make bootstrap` | Initial system setup (Docker, Node.js, certbot) |
| `make deploy` | Full deployment (clone, build, SSL, start) |
| `make update` | Update deployment (pull, rebuild, restart) |
| `make status` | Check service status |
| `make restart` | Restart services (no rebuild) |
| `make cert-renew` | Force SSL certificate renewal |
| `make logs` | View container logs |
| `make shell` | Shell into backend container |
| `make vault-edit` | Edit encrypted secrets |
| `make check` | Syntax check all playbooks |
| `make help` | Show help message |

## Directory Structure

```
brc-analytics-playbook/
├── Makefile                    # Entry point for all operations
├── ansible.cfg                 # Ansible configuration
├── requirements.txt            # Python dependencies
├── requirements.yaml           # Ansible Galaxy collections
├── .vault-password.txt         # Vault password (gitignored)
├── inventory/
│   └── hosts.yaml             # Host definitions
├── group_vars/
│   ├── all/
│   │   ├── vars.yaml          # Shared variables
│   │   └── vault.yaml         # Shared secrets (encrypted)
│   ├── production/
│   │   └── vars.yaml          # Production config
│   └── development/
│       └── vars.yaml          # Development config
├── playbook-bootstrap.yaml    # Initial setup
├── playbook-deploy.yaml       # Full deployment
├── playbook-update.yaml       # Update existing
├── playbook-restart.yaml      # Restart services
├── playbook-status.yaml       # Status checks
├── playbook-cert-renew.yaml   # Certificate renewal
└── templates/
    ├── docker-compose.override.yml.j2
    ├── nginx-ssl.conf.j2
    └── api.env.j2
```

## Playbooks

### bootstrap

Run once on a fresh VM to install:
- Docker and docker-compose plugin
- Node.js v20 (for catalog builds)
- Certbot (for SSL)
- Service user (`brc-analytics`)
- Deployment directory (`/opt/brc-analytics`)

### deploy

Full deployment:
1. Clone the BRC Analytics repository
2. Install npm dependencies
3. Build catalog data (`npm run build-brc-db`)
4. Set up SSL certificate (from vault, self-signed, or Let's Encrypt)
5. Configure nginx with SSL
6. Build and start Docker containers
7. Set up automatic certificate renewal (Let's Encrypt mode)

### update

Update existing deployment:
1. Pull latest changes from repository
2. Rebuild catalog if source files changed
3. Update npm dependencies if package-lock changed
4. Rebuild Docker images
5. Restart services
6. Verify health check

### restart

Quick restart without pulling changes or rebuilding:
1. Restart Docker containers
2. Verify health check

### status

Check service status:
- Docker service health
- Container status
- API health endpoint
- SSL certificate expiry
- Disk usage

## Configuration

### Environment-Specific Variables

Edit `group_vars/production/vars.yaml` or `group_vars/development/vars.yaml` to customize:

```yaml
brc_environment: production
brc_repo_branch: production  # main for dev, production for prod
brc_domain: platform.brc-analytics.org
api_log_level: WARNING  # INFO, DEBUG, etc.
ssl_mode: vault  # vault, self_signed, or letsencrypt
```

### SSL Certificate Modes

The playbook supports three SSL modes via `ssl_mode`:

- **vault**: Deploy certificates from Ansible Vault (recommended for production)
- **self_signed**: Generate self-signed certificates (for testing)
- **letsencrypt**: Obtain certificates via Let's Encrypt HTTP-01 challenge

For vault mode, generate certificates locally using DNS-01 challenge:
```bash
make cert-generate DOMAIN=platform.brc-analytics.org
```

Then add the output to your vault file and set `ssl_mode: vault`.

### Secrets (Ansible Vault)

Sensitive values are stored encrypted in `group_vars/*/vault.yaml`.

To edit secrets:
```bash
make vault-edit
```

To create new vault file:
```bash
ansible-vault create group_vars/production/vault.yaml
```

## Troubleshooting

### Check container logs
```bash
make logs
# Or for a specific service:
cd /opt/brc-analytics/backend && docker compose logs backend
```

### Restart services
```bash
make restart
```

### Rebuild and restart
```bash
make update
# Or manually:
cd /opt/brc-analytics/backend && docker compose up -d --build --force-recreate
```

### Check SSL certificate
```bash
openssl x509 -in /etc/letsencrypt/live/platform.brc-analytics.org/fullchain.pem -noout -dates
```

### Manual certificate renewal
```bash
make cert-renew
```

## Service URLs

- **Production**: https://platform.brc-analytics.org
- **Development**: https://platform-dev.brc-analytics.org

### API Endpoints

- Health: `/api/v1/health`
- Documentation: `/api/docs`
- Version: `/api/v1/version`
