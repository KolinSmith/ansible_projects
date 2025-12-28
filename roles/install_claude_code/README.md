# install_claude_code

Ansible role to install Claude Code CLI via npm and configure the `.claude` directory as a symlink to dotfiles repo.

## Description

This role:
1. Installs NVM (Node Version Manager) if not present
2. Installs Node.js LTS via NVM
3. Installs Claude Code CLI via npm (`@anthropic-ai/claude-code`)
4. Creates a symlink from `~/.claude` to `~/code_base/dotfiles/.claude`
5. Works across all architectures (x86_64, ARM, etc.)

## Requirements

- The `dotfiles` repository must already be cloned to `~/code_base/dotfiles`
- The `.claude` folder must exist in the dotfiles repository
- Internet connection to download Claude Code installer

## Role Variables

This role uses the following Ansible built-in variables:
- `ansible_user` - The user to install Claude Code for

## Dependencies

**IMPORTANT:** This role depends on the dotfiles repository being present.

This role MUST be run AFTER:
- `provision_dev_server` role - Clones dotfiles repo to `~/code_base/dotfiles`
- `import_dotfiles` role - Copies individual dotfiles to home directory and sets up .zshrc

The role will fail if `~/code_base/dotfiles/.claude` does not exist.

## Example Playbook

```yaml
- name: provision dev server
  hosts: dev_servers
  become: true
  roles:
    - role: provision_dev_server
    - role: import_dotfiles
    - role: install_claude_code
```

## Claude Directory Structure

The `.claude` directory in the dotfiles repo contains:
- `CLAUDE.md` - Homelab environment context for Claude
- `progress-logs/` - Session history and progress tracking
- `plans/` - Implementation plans
- `settings.json` - Claude Code settings
- Other files excluded via `.gitignore`

## What Gets Symlinked

After this role runs:
```
~/.claude -> ~/code_base/dotfiles/.claude
```

This ensures all Claude Code configurations and progress logs are:
1. Stored in the dotfiles repository
2. Version controlled with git
3. Synced across all provisioned dev servers

## License

MIT

## Author

Homelab Infrastructure Team
