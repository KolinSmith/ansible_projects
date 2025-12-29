# deploy_pihole

Ansible role to deploy and configure Pi-hole for DNS-based ad blocking.

## Description

This role intelligently detects whether Pi-hole should be deployed via Docker Compose or traditional installation, then deploys and configures accordingly.

**Supports two deployment methods:**
1. **Docker Compose** - If docker-compose.yml exists in `~/code_base/docker_projects/<hostname>/`
2. **Traditional Installation** - Direct installation on the system

## Requirements

### For Docker-based deployment:
- Docker and Docker Compose must be installed
- **IMPORTANT:** This role must run **AFTER** the role that deploys the Docker Compose setup (e.g., `deploy_docker_env` or similar)
- Pi-hole docker-compose.yml must exist at: `~/code_base/docker_projects/<hostname>/docker-compose.yml`
- Docker container must be named: `pihole-<hostname>` (lowercase)

### For traditional installation:
- Ubuntu/Debian-based system
- Internet connectivity for Pi-hole installer script

## Role Variables

**Required variables:**
- `ansible_user` - User account for deployment
- `username` - User for file ownership (legacy variable)

**Optional variables:**
- `pihole_webpassword` - Web interface password (hashed)
- `dns_server_private_ssh_key` - SSH key for gravity-sync

## Dependencies

**For Docker deployment:**
- Must run after Docker environment setup role
- Requires Docker and Docker Compose to be installed

**For traditional installation:**
- None

## How It Works

### Detection Logic

The role automatically detects the deployment method:

```yaml
1. Check if docker-compose.yml exists at:
   ~/code_base/docker_projects/<hostname>/docker-compose.yml

2. Check if Pi-hole container is running:
   docker ps --filter 'name=pihole-<hostname>'

3. If BOTH conditions are true → Docker deployment
   If NOT → Traditional installation
```

### Docker Deployment Path

When Docker-based Pi-hole is detected:
- ✅ Skips traditional installation steps
- ✅ Waits for container to be ready
- ✅ Configures whitelist domains via `docker exec`
- ✅ Configures blacklist domains via `docker exec`
- ✅ Custom DNS entries handled by mounted config file

### Traditional Deployment Path

When no Docker setup is detected:
- ✅ Creates pihole user and group
- ✅ Installs Pi-hole via official installer
- ✅ Configures setupVars.conf
- ✅ Adds whitelist/blacklist domains
- ✅ Configures custom DNS entries
- ✅ Sets up gravity-sync (if applicable)

## Configuration Applied

### Whitelist Domains
- dartsearch.net
- googleadservices.com
- www.dartsearch.net
- www.googleadservices.com
- clickserve.dartsearch.net
- ad.doubleclick.net
- ally.com
- protonmail.com
- loftliving.com
- claude.ai

### Blacklist Domains
- app-analytics-v2.snapchat.com
- metrics.icloud.com
- metrics.plex.tv
- analytics.plex.tv

### Custom DNS Entries (Traditional only)
- voyager.internal.homelab.gg
- pfsense.internal.homelab.gg
- discovery.internal.homelab.gg
- borg.internal.homelab.gg
- k3s-cluster.local

*Note: For Docker deployment, custom DNS entries are managed via the mounted `03-dns-overrides.conf` file in the docker-compose setup.*

## Example Playbook

### For Docker-based deployment:

```yaml
---
- hosts: dns_servers
  become: yes
  roles:
    # 1. Install Docker first (REQUIRED)
    - role: install_docker

    # 2. Deploy Docker Compose stack (REQUIRED - must come before deploy_pihole)
    - role: deploy_docker_env
      # This should deploy the docker-compose.yml to ~/code_base/docker_projects/<hostname>/

    # 3. Configure Pi-hole (detects Docker and configures accordingly)
    - role: deploy_pihole
```

### For traditional installation:

```yaml
---
- hosts: dns_servers
  become: yes
  roles:
    - role: deploy_pihole
      # Will auto-detect no Docker setup and install traditionally
```

## Task Files

- `tasks/main.yml` - Orchestrator that detects and routes to appropriate deployment
- `tasks/detect_pihole_type.yml` - Detection logic for Docker vs Traditional
- `tasks/configure_pihole_docker.yml` - Docker-specific configuration
- `tasks/install_pihole_traditional.yml` - Traditional installation (original code)

## Important Notes

1. **Order matters for Docker deployment:**
   ```
   deploy_docker_env (or similar) → THEN → deploy_pihole
   ```

2. **Container naming convention:**
   - Container must be named: `pihole-<hostname>` (lowercase)
   - Example: For host "DS9" → container name is "pihole-ds9"

3. **Docker Compose location:**
   - Must be at: `~/code_base/docker_projects/<hostname>/docker-compose.yml`
   - Hostname is converted to lowercase

4. **Idempotency:**
   - Docker configuration tasks check if domains are already whitelisted/blacklisted
   - Won't re-add existing entries

## Troubleshooting

### Docker deployment not detected
- Verify docker-compose.yml exists at correct path
- Check container is running: `docker ps | grep pihole`
- Ensure container name matches: `pihole-<hostname>` (lowercase)

### Traditional installation fails
- Check internet connectivity
- Verify system is Ubuntu/Debian-based
- Review Pi-hole installer logs

### Whitelist/blacklist not applied
- For Docker: Ensure container is fully started
- For Traditional: Check pihole command availability
- Run playbook with `-vvv` for verbose output

## License

MIT

## Author Information

Homelab automation project
