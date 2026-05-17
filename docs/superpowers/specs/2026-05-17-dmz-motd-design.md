# Design: DMZ Custom MOTD Deployment

**Date:** 2026-05-17
**Branch:** feat/dmz-custom-motd

## Summary

Deploy the `install_custom_motd` Ansible role to the DMZ server (Oracle Cloud VPS). Fixes two pre-existing gaps — the inventory still references the public Oracle IP instead of the Tailscale IP for the post-provision group, and the `is_ubuntu` detection in the MOTD role relies on a variable that is never set for the DMZ host.

---

## Changes

### 1. Inventory (`hosts`)

Update `dmz_post_provision` `ansible_host` from `129.146.141.62` to `100.86.4.29` (Tailscale IP).

`dmz_pre_provision` is intentionally left on the public IP — Tailscale is not yet installed at that stage, so it cannot be the transport for pre-provision runs.

### 2. MOTD Role (`roles/install_custom_motd/tasks/main.yml`)

Replace:
```yaml
when: is_ubuntu | default(false)
```
with:
```yaml
when: ansible_distribution == 'Ubuntu'
```

`is_ubuntu` is only set when the `check_if_pi` role has already run. `ansible_distribution` is a standard gathered fact — always present, always correct, no role dependency required. This makes the Ubuntu MOTD spam-disabling task work correctly on any Ubuntu host without additional setup.

### 3. DMZ Provision Playbook (`playbooks/dmz_server_provision/dmz_server_provision.yml`)

Add `install_custom_motd` to the `dmz_pre_provision` play so future fresh provisions of the DMZ server include the custom MOTD automatically.

### 4. One-off Playbook (`playbooks/install_motd_dmz/install_motd_dmz.yml`)

A minimal playbook targeting `dmz_post_provision` with only the `install_custom_motd` role. Used to apply the MOTD to the already-provisioned live server immediately. Kept in the repo as a convenience for re-running the role against the DMZ without a full re-provision.

---

## Execution

After the PR is merged (or on the feature branch), run:

```bash
cd ~/code_base/ansible_projects
ansible-playbook playbooks/install_motd_dmz/install_motd_dmz.yml \
  --vault-id ~/code_base/dotfiles/.ansible_password
```

Expected result: custom MOTD (figlet hostname header + sysinfo + commands) visible on next SSH login to DMZ. Ubuntu spam scripts (`50-motd-news`, `90-updates-available`, etc.) disabled.

---

## Files Changed

| File | Change |
|------|--------|
| `hosts` | `dmz_post_provision` IP → Tailscale |
| `roles/install_custom_motd/tasks/main.yml` | `is_ubuntu` → `ansible_distribution` |
| `playbooks/dmz_server_provision/dmz_server_provision.yml` | Add `install_custom_motd` to pre-provision play |
| `playbooks/install_motd_dmz/install_motd_dmz.yml` | New one-off playbook (created) |
