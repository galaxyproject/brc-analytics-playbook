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

### Per-site Next apps (`frontend_out_dir`)

The app repo is mid-migration to one standalone Next app per site under `sites/`, and the two deploy branches are on opposite sides of it:

- **`main`** (the dev environments) has the split. Builds run `next build sites/<site>`, so the static export lands in `sites/brc-analytics/out` or `sites/ga2/out`, and the npm scripts are named `build-<env>:<site>`.
- **`production`** (the prod environments) is still pre-split. The root Next app is intact, both sites build with a plain `next build`, and the export lands in a repo-root `out/`.

So the export dir is per environment, not global. The staging step is `mv <export dir> releases/<sha>-<ts>`, which fails with `mv: cannot stat 'out'` after an otherwise-successful build if it's pointed at the wrong one:

```yaml
- name: brc-dev            # tracks main -- split
  frontend_out_dir: sites/brc-analytics/out
- name: ga2-prod           # tracks production -- pre-split
  frontend_out_dir: out
  catalog_source_dir: catalog/ga2/source/   # defaults to catalog/source/
```

The build script name is coupled to the same thing, via `brc_build_script` (defaulting to the prod/pre-split `build:prod`, overridden to `build-dev:brc` in `group_vars/development`) or a per-env `build_script`. **When the next release promotes `main` to `production`, the prod `frontend_out_dir` values and `brc_build_script` have to flip in the same change**, or the first prod deploy afterwards fails on `Missing script`.

Frontend change detection deliberately watches the union of both layouts (`app/`, `pages/`, `public/`, `next.config.mjs` *and* `sites/`, `packages/`, plus `site-config/`, `catalog/`, `scripts/`, `package.json`, `tsconfig.json`). An unmatched pathspec is not an error, it is silently empty, and the task's `failed_when: false` turns that into "no frontend changes" -- so a stale path doesn't fail a deploy, it quietly stops doing one while every run still reports success. Keep the union honest in both directions when the app repo moves things.

### Organism Images (ga2 / GenomeArk)

The ga2 catalog points every assembly at `/organism_image/<species>.jpg`, but the app repo gitignores `public/organism_image/` — those ~360MB of JPEGs live in a public Jetstream bucket instead. A fresh checkout has none of them, so without this step the site renders with every organism image broken.

An environment opts in from inventory:

```yaml
- name: ga2-dev
  organism_images: ga2   # names the mirror dir under organism_images_dir
```

Bootstrap creates and SELinux-labels `/opt/brc-analytics-images/<set>/`; deploy and update mirror the bucket into it (skipping files already present at the same size, so a no-op run is one listing request); host nginx serves that directory at `/organism_image/`.

They stay outside the per-env release trees on purpose. Anything under `public/` is copied into `out/` and staged as an immutable release, so fetching them at build time would cost `releases_keep` copies — roughly 1.4GB per environment — and re-download the set on every deploy. Bucket coordinates live in `group_vars/all/vars.yaml` (`organism_images_endpoint`, `organism_images_bucket`, `organism_images_prefix`).

### SRA Mirror (Logan / kmindex search)

The Logan search joins its kmindex hits against a local mirror of SRA run metadata -- a DuckDB file built externally from the public NCBI parquet. It is not in either repo and nothing in this playbook builds or fetches it: the file is put on the host by hand, and the playbook only wires it up.

An environment opts in from inventory:

```yaml
- name: brc-dev
  galaxy_api_key: "{{ vault_galaxy_api_key_dev }}"   # service account, enables submission
  sra_mirror_host_path: /opt/brc-analytics-data/sra-mirror.duckdb
```

Bootstrap creates the parent directory owned by the service user. Deploy and update assert the file is a regular file, bind mount it read-only into the backend container under `brc_sra_mirror_container_dir`, and derive `SRA_MIRROR_PATH` from the same two variables so the env var and the mount cannot drift apart. Leave `sra_mirror_host_path` unset and none of that is emitted -- the backend then falls back to its own defaults and the join is simply off, which is the state of every environment except dev.

The assert exists because Docker will happily create an empty *directory* at a bind-mount source that does not exist. The backend requires a file, so it would log at INFO, disable the SRA tools, and serve an inert page while leaving a bogus directory behind. Failing the run is better.

Putting a mirror in place, or replacing one with a rebuild:

```bash
# 1. Copy it up. You SSH as your own login, and the directory is owned by the
#    service user, so stage it in your home dir and move it into place.
scp sra-mirror.duckdb brc-analytics-dev.tacc.utexas.edu:~/
sudo install -o brc-admin -g brc-admin -m 0644 \
  ~/sra-mirror.duckdb /opt/brc-analytics-data/sra-mirror.duckdb

# 2. Recreate the backend so it picks up the new file. Run it from the backend
#    directory and do NOT pass -f: Compose only auto-loads the generated
#    docker-compose.override.yml under default file discovery, and that
#    override is what carries both the mirror mount and the 127.0.0.1 port
#    binding. Naming the base file explicitly silently drops both.
cd /opt/brc-analytics-brc-dev/backend
sudo -u brc-admin docker compose -p brc-analytics-brc-dev up -d --force-recreate backend
```

Step 2 is not optional and is easy to get wrong. A bind mount resolves to an inode when the container is created, so a container that is already running keeps reading the *old* file after you replace it -- the mirror looks updated on the host while the API still serves what it started with. Two things that look like they would fix this do not: `make restart` runs `docker compose restart`, which restarts the process without recreating the container (mounts survive), and it is also still single-environment, pointed at `brc_backend_dir` rather than any `/opt/brc-analytics-<env>` project. And `make update-brc-dev` only recreates the backend when the app source, `api/.env`, or the compose override changed -- swapping a data file changes none of those, so it is a no-op here. A full `make deploy-brc-dev` does a `down`/`up` and works, but rebuilds everything to achieve a container recreate.

Confirm the mirror is actually live:

```bash
cd /opt/brc-analytics-brc-dev/backend
sudo -u brc-admin docker compose -p brc-analytics-brc-dev exec backend ls -l /sra/
sudo -u brc-admin docker compose -p brc-analytics-brc-dev logs backend | grep -i "sra mirror"
```

An "SRA mirror service disabled" line means `SRA_MIRROR_PATH` is empty or the path inside the container is not a file.

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
