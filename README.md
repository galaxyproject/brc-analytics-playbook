# BRC Analytics Playbook

Ansible playbook for deploying BRC Analytics backend services to TACC VMs.

## Overview

This playbook deploys the BRC Analytics backend (nginx, FastAPI, Redis) to:
- **Production**: `brc-analytics.tacc.utexas.edu`
- **Development**: `brc-analytics-dev.tacc.utexas.edu`

## Architecture

The playbook is designed for **local execution** on each VM. Since SSH access requires VPN + MFA, you:
1. SSH into the VM manually
2. Run the playbook locally with `ansible_connection: local`
3. Use `--limit=$(hostname --fqdn)` to target only the current host

## Prerequisites

- SSH access to the TACC VMs (requires VPN)
- Python 3.8+ on the VM
- sudo privileges

## Quick Start

### First Time Setup (on the VM)

```bash
# Clone this playbook repository
git clone https://github.com/galaxyproject/brc-analytics-playbook.git
cd brc-analytics-playbook

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Ansible
pip install -r requirements.txt

# Install Ansible Galaxy collections
make requirements

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
source venv/bin/activate
make update
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make bootstrap` | Initial system setup (Docker, Node.js, certbot) |
| `make deploy` | Full deployment (clone, build, SSL, start) |
| `make update` | Update deployment (pull, rebuild, restart) |
| `make status` | Check service status |
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
- Certbot (for Let's Encrypt SSL)
- Service user (`brc-analytics`)
- Deployment directory (`/opt/brc-analytics`)

### deploy

Full deployment:
1. Clone the BRC Analytics repository
2. Install npm dependencies
3. Build catalog data (`npm run build-brc-db`)
4. Obtain SSL certificate from Let's Encrypt
5. Configure nginx with SSL
6. Build and start Docker containers
7. Set up automatic certificate renewal

### update

Update existing deployment:
1. Pull latest changes from repository
2. Rebuild catalog if source files changed
3. Update npm dependencies if package-lock changed
4. Rebuild Docker images
5. Restart services
6. Verify health check

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
brc_repo_branch: main  # or a release tag
api_log_level: WARNING  # INFO, DEBUG, etc.
```

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
cd /opt/brc-analytics/backend && docker compose restart
```

### Rebuild and restart
```bash
cd /opt/brc-analytics/backend && docker compose up -d --build --force-recreate
```

### Check SSL certificate
```bash
certbot certificates
```

### Manual certificate renewal
```bash
make cert-renew
```

## Service URLs

- **Production**: https://brc-analytics.tacc.utexas.edu
- **Development**: https://brc-analytics-dev.tacc.utexas.edu

### API Endpoints

- Health: `/api/v1/health`
- Documentation: `/api/docs`
- Version: `/api/v1/version`
