# install_obsidian Ansible Role Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `install_obsidian` Ansible role that installs Obsidian + Xvfb on Voyager as two systemd services, enabling Obsidian Sync to keep `~/wiki/` updated.

**Architecture:** Two systemd services — `xvfb.service` (virtual display) and `obsidian.service` (depends on xvfb). The role installs the Obsidian `.deb`, drops both unit files via templates, and enables the services. The existing `install_obsidian_vault` role handles vault cloning and git cron — no changes needed there.

**Tech Stack:** Ansible, Ubuntu 24.04 LTS (Noble), Xvfb, Obsidian `.deb` (Electron), systemd

**Spec:** `docs/superpowers/specs/2026-03-24-install-obsidian-headless-design.md`

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `roles/install_obsidian/defaults/main.yml` | Role variables with defaults |
| Create | `roles/install_obsidian/tasks/main.yml` | All install tasks |
| Create | `roles/install_obsidian/handlers/main.yml` | systemd daemon-reload handler |
| Create | `roles/install_obsidian/templates/xvfb.service.j2` | Xvfb systemd unit template |
| Create | `roles/install_obsidian/templates/obsidian.service.j2` | Obsidian systemd unit template |
| Create | `roles/install_obsidian/README.md` | Usage + first-time login instructions |
| Modify | `playbooks/dev_server_provision/dev_server_provision.yml` | Insert `install_obsidian` before `install_obsidian_vault` |

---

## Task 1: Role scaffold + defaults

**Files:**
- Create: `roles/install_obsidian/defaults/main.yml`

- [ ] **Step 1: Create the role directory structure**

```bash
mkdir -p roles/install_obsidian/{defaults,tasks,handlers,templates}
```

- [ ] **Step 2: Write defaults/main.yml**

```yaml
---
# install_obsidian role defaults

# Obsidian version to install — pinned for idempotency.
# To upgrade: bump this value and re-run the role.
obsidian_version: "1.8.7"

# User that owns and runs the Obsidian service
obsidian_user: "{{ ansible_user }}"

# Virtual display number used by Xvfb and Obsidian
obsidian_display: ":99"
```

- [ ] **Step 3: Verify syntax**

```bash
cd roles/install_obsidian && ansible-lint defaults/main.yml 2>/dev/null || echo "lint not available, skip"
```

- [ ] **Step 4: Commit**

```bash
git add roles/install_obsidian/defaults/main.yml
git commit -m "feat(install_obsidian): add role defaults"
```

---

## Task 2: systemd unit templates

**Files:**
- Create: `roles/install_obsidian/templates/xvfb.service.j2`
- Create: `roles/install_obsidian/templates/obsidian.service.j2`

- [ ] **Step 1: Write xvfb.service.j2**

```ini
[Unit]
Description=Virtual Framebuffer X Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb {{ obsidian_display }} -screen 0 1024x768x24
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Write obsidian.service.j2**

```ini
[Unit]
Description=Obsidian
After=xvfb.service
Requires=xvfb.service

[Service]
Type=simple
User={{ obsidian_user }}
Group={{ obsidian_user }}
Environment=DISPLAY={{ obsidian_display }}
Environment=HOME=/home/{{ obsidian_user }}
ExecStartPre=/bin/sleep 2
ExecStart=/opt/Obsidian/obsidian --no-sandbox
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Commit**

```bash
git add roles/install_obsidian/templates/
git commit -m "feat(install_obsidian): add xvfb and obsidian systemd unit templates"
```

---

## Task 3: Handler

**Files:**
- Create: `roles/install_obsidian/handlers/main.yml`

- [ ] **Step 1: Write handlers/main.yml**

```yaml
---
- name: Reload systemd daemon
  systemd:
    daemon_reload: true
  become: true
```

- [ ] **Step 2: Commit**

```bash
git add roles/install_obsidian/handlers/main.yml
git commit -m "feat(install_obsidian): add systemd daemon-reload handler"
```

---

## Task 4: Main tasks

**Files:**
- Create: `roles/install_obsidian/tasks/main.yml`

- [ ] **Step 1: Write tasks/main.yml**

```yaml
---
# Install Obsidian headlessly on Ubuntu using Xvfb as a virtual display.
# Two systemd services are created: xvfb.service and obsidian.service.
# After this role runs, complete first-time Obsidian Sync login via:
#   ssh -X dax@voyager && /opt/Obsidian/obsidian --no-sandbox

- name: Install Xvfb and Electron runtime dependencies
  apt:
    name:
      - xvfb
      - libgbm1
      - libasound2t64
    state: present
    update_cache: true
  become: true

- name: Check installed Obsidian version
  command: dpkg-query --showformat='${Version}' --show obsidian
  register: obsidian_installed_version
  failed_when: false
  changed_when: false

- name: Download Obsidian {{ obsidian_version }} .deb
  get_url:
    url: "https://github.com/obsidianmd/obsidian-releases/releases/download/v{{ obsidian_version }}/obsidian_{{ obsidian_version }}_amd64.deb"
    dest: "/tmp/obsidian_{{ obsidian_version }}_amd64.deb"
    mode: '0644'
  when: obsidian_installed_version.rc != 0 or obsidian_installed_version.stdout != obsidian_version

- name: Install Obsidian .deb (resolves Electron dependencies via apt)
  apt:
    deb: "/tmp/obsidian_{{ obsidian_version }}_amd64.deb"
    state: present
  become: true
  when: obsidian_installed_version.rc != 0 or obsidian_installed_version.stdout != obsidian_version

- name: Deploy xvfb.service unit
  template:
    src: xvfb.service.j2
    dest: /etc/systemd/system/xvfb.service
    owner: root
    group: root
    mode: '0644'
  become: true
  notify: Reload systemd daemon

- name: Deploy obsidian.service unit
  template:
    src: obsidian.service.j2
    dest: /etc/systemd/system/obsidian.service
    owner: root
    group: root
    mode: '0644'
  become: true
  notify: Reload systemd daemon

- name: Flush handlers (daemon-reload before enabling services)
  meta: flush_handlers

- name: Enable and start xvfb.service
  systemd:
    name: xvfb
    enabled: true
    state: started
  become: true

- name: Enable and start obsidian.service
  systemd:
    name: obsidian
    enabled: true
    state: started
  become: true

- name: Display post-install instructions
  debug:
    msg:
      - "=== Obsidian installed and services started ==="
      - ""
      - "obsidian.service will restart repeatedly until Obsidian Sync is configured."
      - "This is expected. Complete the one-time login:"
      - ""
      - "  1. sudo systemctl stop obsidian"
      - "  2. From MacBook: ssh -X {{ obsidian_user }}@voyager"
      - "  3. /opt/Obsidian/obsidian --no-sandbox"
      - "  4. Log into Obsidian Sync, open ~/wiki/ as vault"
      - "  5. sudo systemctl start obsidian"
      - ""
      - "See roles/install_obsidian/README.md for full details."
```

- [ ] **Step 2: Check YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('roles/install_obsidian/tasks/main.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add roles/install_obsidian/tasks/main.yml
git commit -m "feat(install_obsidian): add main tasks"
```

---

## Task 5: README

**Files:**
- Create: `roles/install_obsidian/README.md`

- [ ] **Step 1: Write README.md**

```markdown
# install_obsidian

Installs Obsidian headlessly on Ubuntu 24.04 using Xvfb as a virtual framebuffer.
Creates two systemd services (`xvfb.service` + `obsidian.service`) so Obsidian
runs permanently and Obsidian Sync keeps `~/wiki/` up to date.

## Requirements

- Ubuntu 24.04 LTS (Noble)
- Run before `install_obsidian_vault` role

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `obsidian_version` | `1.8.7` | Pinned Obsidian version. Bump to upgrade. |
| `obsidian_user` | `{{ ansible_user }}` | User that owns and runs the Obsidian service |
| `obsidian_display` | `:99` | Virtual display number for Xvfb |

## What It Does

1. Installs `xvfb`, `libgbm1`, `libasound2t64`
2. Downloads and installs `obsidian_<version>_amd64.deb`
3. Drops `/etc/systemd/system/xvfb.service` and `obsidian.service`
4. Enables and starts both services

## First-Time Login (Required after initial deploy)

After the role runs, `obsidian.service` will restart repeatedly — this is
expected. Obsidian has no Sync config yet. Complete this one-time step:

**Requirements:** XQuartz installed on your MacBook (`brew install --cask xquartz`)

```bash
# 1. Stop the service on Voyager
sudo systemctl stop obsidian

# 2. From your MacBook — SSH with X forwarding
ssh -X dax@voyager

# 3. Launch Obsidian (window appears on your MacBook via XQuartz)
/opt/Obsidian/obsidian --no-sandbox

# 4. In the Obsidian window:
#    - Sign into Obsidian Sync
#    - Open ~/wiki/ as your vault
#    - Wait for initial sync to complete before closing

# 5. Back on Voyager — start the service
sudo systemctl start obsidian

# 6. Verify it's running cleanly
sudo systemctl status obsidian
```

After this, `obsidian.service` runs permanently. Obsidian Sync keeps `~/wiki/`
updated, and the nightly git cron (from `install_obsidian_vault`) pushes
changes to GitHub.

## Troubleshooting

**obsidian.service keeps restarting after login:**
- Check logs: `journalctl -u obsidian -n 50`
- If restarting immediately after boot, try increasing the `ExecStartPre` sleep
  in `templates/obsidian.service.j2` from `2` to `5` and re-run the role

**xvfb.service fails to start:**
- Check: `journalctl -u xvfb -n 20`
- Ensure `xvfb` package is installed: `dpkg -l | grep xvfb`

**Obsidian window doesn't appear over SSH -X:**
- Ensure XQuartz is running on your MacBook before SSH
- Try `ssh -Y` (trusted forwarding) if `-X` doesn't work
- Check `echo $DISPLAY` inside the SSH session — should be set (e.g. `localhost:10.0`)

## Upgrading Obsidian

1. Bump `obsidian_version` in `defaults/main.yml`
2. Re-run the role — the existing binary check will detect the version mismatch
   and reinstall
```

- [ ] **Step 2: Commit**

```bash
git add roles/install_obsidian/README.md
git commit -m "feat(install_obsidian): add README with first-time login instructions"
```

---

## Task 6: Update playbook

**Files:**
- Modify: `playbooks/dev_server_provision/dev_server_provision.yml`

- [ ] **Step 1: Insert `install_obsidian` before `install_obsidian_vault`**

Current lines 26-27:
```yaml
      - role: orangepi_disable_ramlog
      - role: install_obsidian_vault
```

Change to:
```yaml
      - role: orangepi_disable_ramlog
      - role: install_obsidian
      - role: install_obsidian_vault
```

- [ ] **Step 2: Verify YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('playbooks/dev_server_provision/dev_server_provision.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add playbooks/dev_server_provision/dev_server_provision.yml
git commit -m "feat: add install_obsidian role to dev_server_provision playbook"
```

---

## Task 7: Smoke test on Voyager

Run the role against Voyager directly to verify it works end-to-end.

- [ ] **Step 1: Check ansible inventory has Voyager**

```bash
cat hosts
```

Voyager is under `[dev_server]` (not `[post_provision_servers]`). The full playbook
targets `post_provision_servers`, so use ad-hoc `include_role` to run directly against Voyager.

- [ ] **Step 2: Run syntax check**

```bash
ansible-playbook playbooks/dev_server_provision/dev_server_provision.yml --syntax-check
```

Expected: `playbook: playbooks/dev_server_provision/dev_server_provision.yml` with no errors.

- [ ] **Step 3: Run the role in check mode (dry run) against Voyager**

```bash
ansible voyager -m include_role -a name=install_obsidian --check -v
```

Expected: tasks shown as `changed` (would install) with no errors.

- [ ] **Step 4: Run the role for real against Voyager**

```bash
ansible voyager -m include_role -a name=install_obsidian -v
```

- [ ] **Step 5: Verify services are running on Voyager**

```bash
ssh dax@voyager "systemctl status xvfb obsidian --no-pager"
```

Expected:
- `xvfb.service` — `active (running)`
- `obsidian.service` — `activating` or repeatedly restarting (crash loop is expected — waiting for Sync config)

- [ ] **Step 6: Commit any fixes discovered during smoke test**

---

## Task 8: Push branch and open PR

- [ ] **Step 1: Push branch**

```bash
git push -u origin feature/install-obsidian-headless
```

- [ ] **Step 2: Open PR**

```bash
gh pr create \
  --title "feat: install_obsidian role — headless Obsidian via Xvfb on Voyager" \
  --body "$(cat <<'EOF'
## Summary

- Adds new `install_obsidian` Ansible role that installs Obsidian + Xvfb on Voyager as two systemd services
- `xvfb.service` manages the virtual display (`:99`); `obsidian.service` runs Obsidian and depends on it
- Obsidian Sync keeps `~/wiki/` updated; the existing nightly git cron (install_obsidian_vault) pushes changes to GitHub
- Inserts `install_obsidian` before `install_obsidian_vault` in `dev_server_provision.yml`

## Services

| Service | Runs as | Purpose |
|---------|---------|---------|
| `xvfb.service` | root | Virtual framebuffer on display `:99` |
| `obsidian.service` | dax | Obsidian app, `DISPLAY=:99`, `Restart=always` |

## First-Time Setup Required

After deploy, one manual step: `ssh -X dax@voyager` + run Obsidian to log into Obsidian Sync.
See `roles/install_obsidian/README.md` for full instructions.

## Test plan

- [ ] `ansible-playbook --syntax-check` passes
- [ ] Role runs in `--check` mode with no errors
- [ ] `xvfb.service` shows `active (running)` on Voyager
- [ ] `obsidian.service` starts (crash loop expected pre-login)
- [ ] After first-time login: `obsidian.service` stays `active (running)`
- [ ] `~/wiki/` files update when notes are changed on iPhone/MacBook

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
