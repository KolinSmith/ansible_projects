# DMZ Custom MOTD Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the `install_custom_motd` Ansible role to the DMZ server, fixing the inventory IP and `is_ubuntu` detection gap along the way.

**Architecture:** Four file changes: inventory IP update, role `is_ubuntu` fix, wiring the role into the DMZ provision playbook, and a new one-off playbook for immediate application to the live server. No new roles or dependencies introduced.

**Tech Stack:** Ansible, Jinja2 templates, Ubuntu 22.04 (DMZ host), Tailscale (transport for post-provision connections)

---

## Files Changed

| File | Action | What changes |
|------|--------|-------------|
| `hosts` | Modify line 44 | `dmz_post_provision` `ansible_host` → `100.86.4.29` |
| `roles/install_custom_motd/tasks/main.yml` | Modify line 131 | `is_ubuntu \| default(false)` → `ansible_distribution == 'Ubuntu'` |
| `playbooks/dmz_server_provision/dmz_server_provision.yml` | Modify | Add `install_custom_motd` role to `dmz_pre_provision` play |
| `playbooks/install_motd_dmz/install_motd_dmz.yml` | Create | Minimal one-off playbook targeting `dmz_post_provision` |

---

### Task 1: Update dmz_post_provision inventory IP

**Files:**
- Modify: `hosts:44`

- [ ] **Step 1: Edit the inventory**

In `hosts`, line 44, change:
```ini
dmz_post_provision ansible_host=129.146.141.62
```
to:
```ini
dmz_post_provision ansible_host=100.86.4.29
```

Leave `dmz_pre_provision` (line 31) untouched — it must stay on the public IP because Tailscale is not installed until during pre-provision.

- [ ] **Step 2: Verify the change looks right**

```bash
grep -n "ansible_host" /home/dax/code_base/ansible_projects/hosts | grep dmz
```

Expected output:
```
31:dmz_pre_provision ansible_host=129.146.141.62
44:dmz_post_provision ansible_host=100.86.4.29
```

- [ ] **Step 3: Commit**

```bash
git add hosts
git commit -m "fix: update dmz_post_provision to Tailscale IP"
```

---

### Task 2: Fix is_ubuntu detection in install_custom_motd role

**Files:**
- Modify: `roles/install_custom_motd/tasks/main.yml:131`

- [ ] **Step 1: Edit the task**

In `roles/install_custom_motd/tasks/main.yml`, line 131, change:
```yaml
  when: is_ubuntu | default(false)
```
to:
```yaml
  when: ansible_distribution == 'Ubuntu'
```

The full task block for context (lines 119–131) should now read:
```yaml
- name: Disable Ubuntu's MOTD news/spam
  file:
    path: "{{ item }}"
    mode: '0644'
  loop:
    - /etc/update-motd.d/10-help-text
    - /etc/update-motd.d/50-motd-news
    - /etc/update-motd.d/88-esm-announce
    - /etc/update-motd.d/90-updates-available
    - /etc/update-motd.d/91-release-upgrade
    - /etc/update-motd.d/95-hwe-eol
  failed_when: false
  when: ansible_distribution == 'Ubuntu'
```

- [ ] **Step 2: Verify**

```bash
grep -n "ansible_distribution\|is_ubuntu" /home/dax/code_base/ansible_projects/roles/install_custom_motd/tasks/main.yml
```

Expected: only `ansible_distribution == 'Ubuntu'` appears, no remaining `is_ubuntu` references.

- [ ] **Step 3: Commit**

```bash
git add roles/install_custom_motd/tasks/main.yml
git commit -m "fix: use ansible_distribution fact instead of is_ubuntu in motd role"
```

---

### Task 3: Add install_custom_motd to DMZ provision playbook

**Files:**
- Modify: `playbooks/dmz_server_provision/dmz_server_provision.yml`

- [ ] **Step 1: Add the role**

In `playbooks/dmz_server_provision/dmz_server_provision.yml`, add `install_custom_motd` to the `dmz_pre_provision` play's roles list, after `install_rsyslog_client` and before `setup_oracle_vps`:

```yaml
---
- name: dmz server pre provision
  hosts: dmz_pre_provision
  gather_facts: true
  become: true
  vars_files:
    - vars/dmz_server_provision_vars.yml
  roles:
    - role: bootstrap_python
    - role: check_if_raspberry_pi
    - role: geerlingguy.docker
    - role: deploy_docker_env
      vars:
        deploy_docker_services_for: dmz
    - role: import_dotfiles
    - role: install_rsyslog_client
    - role: install_custom_motd
    - role: setup_oracle_vps

- name: post server post provision
  hosts: post_provision_servers
  gather_facts: true
  become: true
  vars_files:
    - vars/dev_server_provision_vars.yml
  roles:
    # - role: check_if_raspberry_pi
    - role: remove_default_user
      default_user: "{{ dmz_username }}"
    - role: oracle_vps_cpu_burn
```

- [ ] **Step 2: Verify**

```bash
grep -n "install_custom_motd\|install_rsyslog_client\|setup_oracle_vps" \
  /home/dax/code_base/ansible_projects/playbooks/dmz_server_provision/dmz_server_provision.yml
```

Expected output shows `install_custom_motd` between `install_rsyslog_client` and `setup_oracle_vps`.

- [ ] **Step 3: Commit**

```bash
git add playbooks/dmz_server_provision/dmz_server_provision.yml
git commit -m "feat: add install_custom_motd to DMZ provision playbook"
```

---

### Task 4: Create one-off playbook for immediate DMZ deployment

**Files:**
- Create: `playbooks/install_motd_dmz/install_motd_dmz.yml`

- [ ] **Step 1: Create the directory and playbook**

```bash
mkdir -p /home/dax/code_base/ansible_projects/playbooks/install_motd_dmz
```

Create `playbooks/install_motd_dmz/install_motd_dmz.yml` with this content:

```yaml
---
- name: Install custom MOTD on DMZ server
  hosts: dmz_post_provision
  gather_facts: true
  become: true
  roles:
    - role: install_custom_motd
```

No `vars_files` needed — all required variables come from `group_vars/all/` (loaded automatically by Ansible) and role defaults.

- [ ] **Step 2: Verify the file was created**

```bash
cat /home/dax/code_base/ansible_projects/playbooks/install_motd_dmz/install_motd_dmz.yml
```

- [ ] **Step 3: Commit**

```bash
git add playbooks/install_motd_dmz/install_motd_dmz.yml
git commit -m "feat: add one-off playbook to deploy MOTD to DMZ server"
```

---

### Task 5: Dry-run against DMZ server

**Files:** none (validation only)

- [ ] **Step 1: Run in check mode**

```bash
cd /home/dax/code_base/ansible_projects
ansible-playbook playbooks/install_motd_dmz/install_motd_dmz.yml \
  --vault-id ~/code_base/dotfiles/.ansible_password \
  --check -v
```

Expected: Ansible connects to `100.86.4.29` as the vault-resolved username, runs tasks in check mode. Look for:
- No connection errors
- `install dependencies` task shows `figlet` and `lsb-release` would be installed
- `Disable Ubuntu's MOTD news/spam` task shows `changed` (not skipped) — this confirms the `ansible_distribution` fix is working
- No fatal errors

If you see `SKIPPING` on the "Disable Ubuntu's MOTD news/spam" task, the `ansible_distribution` fix did not apply correctly — go back to Task 2.

---

### Task 6: Apply to live DMZ server and verify

**Files:** none (execution + verification)

- [ ] **Step 1: Run for real**

```bash
cd /home/dax/code_base/ansible_projects
ansible-playbook playbooks/install_motd_dmz/install_motd_dmz.yml \
  --vault-id ~/code_base/dotfiles/.ansible_password -v
```

Expected: all tasks complete without fatal errors. Look for `changed` on:
- Install dependencies (figlet, lsb-release)
- Disable existing MOTD scripts
- Deploy 00-header, 10-sysinfo, 40-commands
- Disable Ubuntu's MOTD news/spam scripts

- [ ] **Step 2: Verify MOTD on the live server**

```bash
ssh ubuntu@100.86.4.29
```

On login you should see:
- Figlet hostname banner in green
- System info (OS, kernel, IP, load, memory, uptime)
- Helpful commands section
- No Ubuntu spam (no "N packages can be updated", no motd.ubuntu.com news)

---

### Task 7: Open PR

- [ ] **Step 1: Push the branch**

```bash
git push --set-upstream origin feat/dmz-custom-motd
```

- [ ] **Step 2: Open PR**

```bash
gh pr create \
  --title "feat: deploy custom MOTD to DMZ server" \
  --body "$(cat <<'EOF'
## Summary
- Updates `dmz_post_provision` inventory IP to Tailscale address (100.86.4.29) for post-provision Ansible runs
- Fixes `is_ubuntu` detection in `install_custom_motd` role — replaces variable dependency with `ansible_distribution` gathered fact, making the Ubuntu spam-disabling task work on any Ubuntu host
- Wires `install_custom_motd` into the DMZ provision playbook for future fresh provisions
- Adds one-off playbook `playbooks/install_motd_dmz/install_motd_dmz.yml` for re-running MOTD deployment against the live DMZ server

## Test plan
- [ ] Dry-run passes (`--check`) with no connection errors and "Disable Ubuntu MOTD spam" task not skipped
- [ ] Live run completes with no fatal errors
- [ ] SSH login to DMZ shows custom figlet MOTD with sysinfo
- [ ] No Ubuntu spam scripts visible on login

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
