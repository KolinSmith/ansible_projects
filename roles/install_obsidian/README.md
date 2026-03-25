# install_obsidian

Installs Obsidian headlessly on Ubuntu 24.04 using Xvfb as a virtual framebuffer.
Creates two systemd services (`xvfb.service` + `obsidian.service`) so Obsidian
runs permanently and Obsidian Sync keeps `~/wiki/` up to date.

## How It Works

Obsidian is an Electron app that normally requires a display. On a headless server
there's no display, so we run Xvfb (X Virtual Framebuffer) — a fake X11 display
that lives entirely in memory. Obsidian draws into that display and otherwise runs
normally, including Obsidian Sync. The virtual display is never rendered anywhere.

Two systemd services:

| Service | Runs as | Purpose |
|---------|---------|---------|
| `xvfb.service` | root | Starts Xvfb on virtual display `:99` |
| `obsidian.service` | ansible_user | Runs Obsidian with `DISPLAY=:99` |

`obsidian.service` depends on `xvfb.service` — if Xvfb dies, Obsidian is restarted
after it recovers. Both services are set to `Restart=always`.

## Requirements

- Ubuntu 24.04 LTS (Noble)
- Run before `install_obsidian_vault` role (which sets up the git sync cron)

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `obsidian_version` | `1.12.7` | Pinned Obsidian version. Bump to upgrade. |
| `obsidian_user` | `{{ ansible_user }}` | User that owns and runs the Obsidian service |
| `obsidian_display` | `:99` | Virtual display number for Xvfb |

## What It Does

1. Installs `xvfb`, `libgbm1`, `libasound2t64` (Electron runtime deps)
2. Downloads and installs `obsidian_<version>_amd64.deb` (version-pinned, idempotent)
3. Drops `/etc/systemd/system/xvfb.service` and `obsidian.service`
4. Enables and starts both services

## First-Time Login (Required after initial deploy)

After the role runs, `obsidian.service` will start but Obsidian has no Sync config
yet — it will sit idle or restart. You need to log into Obsidian Sync once using
X11 forwarding, which tunnels the Obsidian GUI from Voyager to your MacBook.

### Prerequisites

**On your MacBook**, install XQuartz (an X11 server for macOS):
```bash
brew install --cask xquartz
```
After installing, **open XQuartz** from Applications or Spotlight. You must see
the XQuartz icon in your dock/menu bar before proceeding — it needs to be running.

### Login Procedure

```bash
# 1. Stop the service on Voyager so it doesn't fight for the singleton lock
#    (run this in your normal Voyager terminal)
sudo systemctl stop obsidian

# 2. Open a NEW terminal on your MacBook and SSH with X forwarding:
ssh -X dax@voyager

# 3. Verify X forwarding is working — DISPLAY must be set:
echo $DISPLAY
# Expected: localhost:10.0 (or similar)
# If empty: XQuartz isn't running — open it on your Mac and try again

# 4. Launch Obsidian with GPU disabled (required for virtual display):
/opt/Obsidian/obsidian --no-sandbox --disable-gpu

# 5. The Obsidian window appears on your MacBook via XQuartz.
#    In the window:
#    a. Click "Sign in" → log into your Obsidian account
#    b. Go to Settings → Sync → connect to your remote vault
#    c. When prompted for a local vault location, choose ~/wiki/
#       (IMPORTANT: select ~/wiki/ directly, not a subdirectory)
#    d. Wait for the initial sync to complete (watch the sync indicator)
#    e. Close the Obsidian window

# 6. Back on Voyager, start the service:
sudo systemctl start obsidian

# 7. Verify it's stable:
sudo systemctl status obsidian
# Expected: active (running)
journalctl -u obsidian -n 10 --no-pager
# Expected: "App is up to date" or similar, no crash loop
```

After this one-time step, `obsidian.service` runs permanently. Obsidian Sync
keeps `~/wiki/` updated, and the nightly git cron (from `install_obsidian_vault`)
pushes changes to GitHub at 4 AM.

## Troubleshooting

**`obsidian.service` keeps restarting (crash loop):**
- Check logs: `journalctl -u obsidian -n 50 --no-pager`
- If `Unable to connect to main process`: stale singleton lock — clean up:
  ```bash
  sudo systemctl stop obsidian
  rm -f ~/.config/obsidian/Singleton*
  rm -rf /tmp/scoped_dir*
  sudo systemctl start obsidian
  ```
- If restarting immediately after boot, increase the `ExecStartPre` sleep in
  `templates/obsidian.service.j2` from `2` to `5` and re-run the role

**Obsidian auto-updated its asar but the installer is outdated:**
- Symptom: `Your Obsidian installer is out of date` in logs
- Fix: bump `obsidian_version` in `defaults/main.yml` to the latest release and
  re-run the role. Obsidian's auto-updater updates its app code (asar) but not
  the underlying Electron binary — the .deb must be kept in sync.

**`xvfb.service` fails to start:**
- Check: `journalctl -u xvfb -n 20 --no-pager`
- Ensure `xvfb` package is installed: `dpkg -l | grep xvfb`

**Obsidian window doesn't appear when doing `ssh -X`:**
- Make sure XQuartz is open on your Mac BEFORE SSH (check your dock)
- Try `ssh -Y` (trusted X11 forwarding) instead of `ssh -X`
- Run `echo $DISPLAY` inside the SSH session — must not be empty
- If DISPLAY is set but window still doesn't appear, restart XQuartz

**Vault synced into a subdirectory (e.g. `~/wiki/wiki/`) instead of `~/wiki/`:**
- This happens if you selected the wrong folder during the Obsidian login
- Fix: stop the service, edit `~/.config/obsidian/obsidian.json`, change the
  vault path to `/home/dax/wiki`, delete the erroneous subdirectory, start service

## Upgrading Obsidian

Obsidian auto-updates its app code (asar) but not the Electron runtime binary.
When the asar version diverges too far from the installer, Obsidian logs
`"Your Obsidian installer is out of date"` and stops working.

To upgrade:
1. Bump `obsidian_version` in `defaults/main.yml` to the new version
2. Re-run the role — the `dpkg-query` check detects the mismatch and reinstalls
3. The service restarts automatically with the new binary
