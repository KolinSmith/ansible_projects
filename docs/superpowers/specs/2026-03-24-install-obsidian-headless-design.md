# Design: install_obsidian Ansible Role (Headless Obsidian on Voyager)

**Date:** 2026-03-24
**Status:** Approved
**Branch:** feature/install-obsidian-headless

---

## Goal

Run Obsidian headlessly on Voyager (Ubuntu 24.04 LTS, headless) so that Obsidian Sync keeps `~/wiki/` up to date. The existing nightly git cron in `install_obsidian_vault` then pushes any synced changes to GitHub.

---

## Context

- Voyager is always-on and headless — no display server
- User pays for Obsidian Sync; iPhone and MacBook are the primary editing devices
- `~/wiki/` is the vault path, managed by the existing `install_obsidian_vault` role
- MacBook is not reliably on every day, so it cannot be the git sync source
- Obsidian is an Electron app — requires a display to run; solved via Xvfb (virtual framebuffer)
- Obsidian was previously installed at `/opt/Obsidian/` (apparmor profile confirms this path)

---

## Architecture

Two systemd services:

```
xvfb.service  ──depends──▶  obsidian.service
(virtual display :99)        (Obsidian app, DISPLAY=:99)
```

Sync flow after setup:
```
iPhone/MacBook ──Obsidian Sync──▶ Voyager ~/wiki/ ──nightly cron──▶ GitHub
```

---

## Role Structure

New role: `install_obsidian`

```
roles/install_obsidian/
├── defaults/main.yml          # obsidian_version, obsidian_user, obsidian_display
├── tasks/main.yml             # install deps, download .deb, install, drop services, enable
├── handlers/main.yml          # systemctl daemon-reload (triggered by service file changes)
├── templates/
│   ├── xvfb.service.j2        # virtual framebuffer systemd unit
│   └── obsidian.service.j2    # Obsidian systemd unit
└── README.md                  # includes first-time login instructions
```

---

## Playbook Order

In `dev_server_provision.yml`, `install_obsidian` is inserted immediately before `install_obsidian_vault` (currently line 27). Final order around the obsidian roles:

```yaml
- role: check_if_pi
- role: remove_default_user
- role: orangepi_disable_ramlog
- role: install_obsidian        # NEW — installs Obsidian + Xvfb + systemd services
- role: install_obsidian_vault  # EXISTING — clones vault repo, sets up nightly git cron
- role: import_dotfiles
```

---

## defaults/main.yml

| Variable | Default | Description |
|----------|---------|-------------|
| `obsidian_version` | `1.8.7` | Pinned version. Update manually when upgrading. |
| `obsidian_user` | `{{ ansible_user }}` | User that runs the Obsidian service |
| `obsidian_display` | `:99` | Virtual display number |

Version is pinned (not `latest`) to ensure idempotency. Re-running the role will not reinstall unless the version variable is changed. To upgrade, bump `obsidian_version` in defaults and re-run.

The `.deb` download URL is constructed as:
```
https://github.com/obsidianmd/obsidian-releases/releases/download/v{{ obsidian_version }}/obsidian_{{ obsidian_version }}_amd64.deb
```

---

## Package Dependencies

The tasks install:
- `xvfb` — virtual framebuffer
- `libgbm1` — GPU buffer manager (required by Electron, not in .deb deps)
- `libasound2t64` — audio library (Ubuntu 24.04 renamed package)

All other Electron dependencies (`libgtk-3-0`, `libnss3`, etc.) are declared in the Obsidian `.deb`'s own `Depends:` field and resolved automatically by `apt` when installing the `.deb`. The manually listed packages above are only those not covered by the `.deb`'s own dependency tree.

---

## systemd Units

### xvfb.service

Runs as root. Uses the raw `Xvfb` binary directly — NOT `xvfb-run` (which is a convenience wrapper for short-lived processes and must not be used in a systemd unit).

```ini
[Unit]
Description=Virtual Framebuffer X Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :99 -screen 0 1024x768x24
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### obsidian.service

Runs as `obsidian_user` (dax). Requires `HOME` to be set explicitly — Electron will misbehave without a writable home directory for `~/.config/obsidian/`.

`ExecStartPre` sleeps 2 seconds to allow Xvfb to be ready before Obsidian connects to the display (known race condition between Xvfb start and Electron display connection). If `obsidian.service` shows repeated restarts immediately after boot, increase the sleep value.

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

---

## handlers/main.yml

One handler: `Reload systemd daemon`, triggered by any change to the service unit files.

```yaml
- name: Reload systemd daemon
  systemd:
    daemon_reload: true
  become: true
```

---

## Tasks Sequence

1. Install packages: `xvfb`, `libgbm1`, `libasound2t64`
2. Download Obsidian `.deb` from pinned GitHub release URL to `/tmp/`
3. Install `.deb` via `apt` (`deb` state) — resolves all declared Electron deps automatically
4. Template `xvfb.service.j2` → `/etc/systemd/system/xvfb.service` (notifies handler)
5. Template `obsidian.service.j2` → `/etc/systemd/system/obsidian.service` (notifies handler)
6. Handler fires: `systemctl daemon-reload`
7. Enable and start `xvfb.service`
8. Enable and start `obsidian.service`

---

## First-Time Login (One-Time Manual Step)

After the role runs, `obsidian.service` will start but immediately enter a crash loop — this is expected. Obsidian has no Sync config or vault selected yet, so it crashes on startup. The service will keep restarting (`Restart=always`) until Sync is configured.

To configure Obsidian Sync via X forwarding (requires XQuartz on MacBook):

```bash
# 1. Stop the service
sudo systemctl stop obsidian

# 2. From MacBook — SSH with X forwarding
ssh -X dax@voyager

# 3. Launch Obsidian on the forwarded display
/opt/Obsidian/obsidian --no-sandbox

# 4. Obsidian window appears on MacBook:
#    - Log into Obsidian Sync
#    - Open ~/wiki/ as vault
#    - Wait for initial sync to complete

# 5. Close Obsidian, start the service
sudo systemctl start obsidian

# 6. Verify it's running cleanly
sudo systemctl status obsidian
```

After this one-time step, `obsidian.service` will run permanently and Obsidian Sync will keep `~/wiki/` updated.

This procedure is documented in the role README.

---

## Out of Scope

- Obsidian Sync credentials/login (manual one-time step via X forwarding)
- VNC or any other display access method
- Any changes to `install_obsidian_vault` role
- Automatic Obsidian version upgrades (bump `obsidian_version` manually and re-run)
