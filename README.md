# ansible_projects

Ansible roles and playbooks for the homelab. Targets Voyager (dev server, Ubuntu 24.04) and other hosts.

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `playbooks/dev_server_provision/dev_server_provision.yml` | Full Voyager provisioning — run after a fresh OS install |

## Roles

| Role | Purpose |
|------|---------|
| `install_obsidian` | Installs Obsidian headlessly via Xvfb; runs Obsidian Sync as a systemd service |
| `install_obsidian_vault` | Clones `~/wiki/` from GitHub, sets up nightly 4 AM git sync cron |
| `install_claude_code` | Installs Node via NVM and Claude Code via npm; symlinks `~/.claude` |
| `import_dotfiles` | Clones and links dotfiles repo |
| `install_custom_motd` | Sets up the homelab MOTD on login |
| `deploy_docker_env` | Deploys Docker Compose environment for a given host |
| `geerlingguy.docker` | Installs Docker Engine |
| `artis3n.tailscale` | Installs and configures Tailscale |
| `install_pivpn` | Installs PiVPN (WireGuard) |

## Infrastructure

- **Voyager** (`192.168.9.2`) — Ubuntu 24.04 LTS, HP EliteDesk 800 G4 DM, dev machine, always-on
- **Borg** (`192.168.9.7`) — Unraid server, primary homelab Docker host
- **Operator** (`192.168.9.10`) — Tor relay host
- **pfSense** (`192.168.3.1`) — Router/firewall

## Running the Dev Server Playbook

```bash
ansible-playbook playbooks/dev_server_provision/dev_server_provision.yml -l voyager -v
```

After running, complete the one-time Obsidian Sync login — see `roles/install_obsidian/README.md`.
