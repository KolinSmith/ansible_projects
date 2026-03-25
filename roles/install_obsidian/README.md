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
2. Re-run the role — the dpkg-query check will detect the version mismatch
   and reinstall
