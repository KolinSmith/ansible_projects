# deploy_docker_env

Ansible role to deploy Docker environments from Ansible Vault secrets.

## Description

This role:
1. Clones/pulls the docker_projects repository from GitHub
2. Deploys `.env` files with secrets from Ansible Vault
3. Creates `.env.example` files for documentation

## Requirements

- Docker must be installed (use `geerlingguy.docker` role first)
- Ansible Vault must contain docker secrets
- Git must be installed

## Role Variables

**Required:**
- `deploy_docker_services_for` - Which server's services to deploy
  - Values: `voyager`, `operator`, `dmz`, `intranet_monitor`, etc.
  - **MUST** be passed when calling the role
  - Each server gets ONLY its own .env file

**Optional (defined in group_vars/all/docker_vars.yml):**
- `docker_projects_repo` - GitHub repo URL for docker_projects
- `docker_projects_base_path` - Where to clone docker_projects (default: `/home/{{ ansible_user }}/docker_projects`)
- `docker_projects_branch` - Branch to checkout (default: `main`)
- All docker secret variables (from vault)

## Dependencies

- Vault variables must be defined in `group_vars/all/vault.yml`:
  - `vault_docker_duckdns_token`
  - `vault_docker_cf_api_key`
  - `vault_docker_capture_api_secret`
  - `vault_docker_superuser_password`
  - `vault_docker_duckdns_domain`
  - `vault_docker_search_domain`
  - `vault_docker_superuser_email`

## Example Usage

### In a Playbook

```yaml
- hosts: servers
  roles:
    - role: geerlingguy.docker
    - role: deploy_docker_env
      vars:
        deploy_docker_services_for: voyager  # or 'dmz'
```

### Standalone

```bash
# Deploy voyager services
ansible-playbook deploy.yml -e "deploy_docker_services_for=voyager"

# Deploy DMZ services
ansible-playbook deploy.yml -e "deploy_docker_services_for=dmz"
```

## What Gets Deployed

Each server gets ONLY its own `.env` file:

**When `deploy_docker_services_for: voyager`:**
- `voyager/.env` only

**When `deploy_docker_services_for: operator`:**
- `operator/.env` only

**When `deploy_docker_services_for: dmz`:**
- `dmz/.env` only

**When `deploy_docker_services_for: intranet_monitor`:**
- `intranet_monitor/.env` only

## File Permissions

- `.env` files: `0600` (owner read/write only - contains secrets)
- `.env.example` files: `0644` (readable by all - no secrets)

## Backups

Existing `.env` files are automatically backed up to `.env.backup-YYYYMMDD-HHMMSS` before replacement.

## Author

Kolin Smith
