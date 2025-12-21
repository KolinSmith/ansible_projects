# install_custom_motd

Ansible role to install a custom Message of the Day (MOTD) on Debian-based systems.

## Description

This role installs a clean, informative MOTD that displays system statistics on login. It's designed to work across Ubuntu, Debian, Raspbian, and other Debian-based distributions while being smart enough to skip Armbian systems (which already have an excellent built-in MOTD).

## Features

- ✅ **Multi-distro support** - Works on Ubuntu, Debian, Raspbian, and others
- ✅ **Armbian detection** - Automatically skips Armbian systems (preserves their great MOTD)
- ✅ **Safe installation** - Backs up existing MOTD before making changes
- ✅ **Colorized output** - Color-coded stats based on thresholds
- ✅ **Comprehensive stats** - Load, memory, CPU temp, disk usage, uptime, IPs
- ✅ **Customizable** - Control what's displayed via variables
- ✅ **Architecture-agnostic** - Detects temperature sensors on ARM and x86

## MOTD Sections

1. **Header** - ASCII art hostname (using figlet)
2. **System Info** - OS, kernel, hardware detection
3. **Performance Stats** - Load, uptime, memory, swap, CPU temp, disk usage
4. **Network** - LAN IP addresses
5. **Helpful Commands** - Customizable command shortcuts

## Requirements

- Debian-based Linux distribution
- Ansible 2.9+
- sudo/root privileges

## Role Variables

### Behavior Control

```yaml
motd_skip_armbian: true              # Don't touch Armbian systems (default: true)
motd_force_install: false            # Force install even on Armbian (default: false)
motd_backup_existing: true           # Backup existing MOTD (default: true)
```

### Display Settings

```yaml
motd_show_header: true               # Show ASCII art header
motd_show_sysinfo: true              # Show system information
motd_show_commands: true             # Show helpful commands

# Individual stats toggles
motd_show_load: true
motd_show_memory: true
motd_show_cpu_temp: true
motd_show_disk_usage: true
motd_show_uptime: true
motd_show_ip_addresses: true
motd_show_updates: false             # apt updates check (can be slow)
```

### Temperature Thresholds

```yaml
motd_cpu_temp_warning: 60            # Yellow warning threshold (°C)
motd_cpu_temp_critical: 80           # Red critical threshold (°C)
motd_disk_temp_warning: 50           # Disk temp warning (°C)
```

### Customization

```yaml
motd_header_font: 'standard'         # Figlet font for hostname

motd_helpful_commands:
  - { name: "Configuration", command: "sudo dpkg-reconfigure -plow unattended-upgrades" }
  - { name: "Monitoring", command: "htop" }
  - { name: "System logs", command: "journalctl -f" }
  - { name: "Disk usage", command: "ncdu /" }
```

## Dependencies

None. The role installs its own dependencies:
- `figlet` - ASCII art text
- `lsb-release` - Distribution information
- `lm-sensors` (optional) - Hardware monitoring
- `smartmontools` (optional) - Disk temperature

## Example Playbook

### Basic Usage

```yaml
- hosts: servers
  become: true
  roles:
    - role: install_custom_motd
```

### With Custom Settings

```yaml
- hosts: servers
  become: true
  roles:
    - role: install_custom_motd
      vars:
        motd_cpu_temp_warning: 70
        motd_cpu_temp_critical: 85
        motd_show_updates: true
        motd_helpful_commands:
          - { name: "Docker", command: "docker ps" }
          - { name: "Services", command: "systemctl status" }
          - { name: "Firewall", command: "ufw status" }
```

### Force Install on Armbian

```yaml
- hosts: armbian_server
  become: true
  roles:
    - role: install_custom_motd
      vars:
        motd_force_install: true  # Override Armbian detection
```

## How It Works

1. **Detection Phase**
   - Checks for Armbian MOTD files and `/etc/armbian-release`
   - Uses `is_armbian` fact from `check_if_pi` role if available
   - Skips installation if Armbian detected (unless `motd_force_install: true`)

2. **Backup Phase**
   - Creates backup at `/etc/update-motd.d.backup` (if doesn't exist)
   - Preserves original MOTD scripts

3. **Cleanup Phase**
   - Disables existing MOTD scripts (removes execute bit)
   - Removes Ubuntu's promotional MOTD scripts (motd-news, etc.)

4. **Installation Phase**
   - Deploys custom scripts to `/etc/update-motd.d/`:
     - `00-header` - ASCII header and system info
     - `10-sysinfo` - Performance statistics
     - `40-commands` - Helpful command list

5. **Testing Phase**
   - Runs `run-parts /etc/update-motd.d/` to validate

## Temperature Detection

The role automatically detects CPU temperature from various sources:

**ARM devices (Raspberry Pi, Orange Pi, etc.):**
- `/sys/class/thermal/thermal_zone0/temp`

**x86/x64 systems:**
- `sensors` command (Package temp, Tctl, Core temps)

Falls back gracefully if temperature sensors aren't available.

## Ubuntu MOTD Cleanup

Automatically disables Ubuntu's annoying MOTD scripts:
- `10-help-text` - Help link spam
- `50-motd-news` - Ubuntu news/ads
- `88-esm-announce` - ESM announcements
- `90-updates-available` - Update notifications
- `91-release-upgrade` - Upgrade prompts
- `95-hwe-eol` - HWE end-of-life warnings

## Compatibility

Tested on:
- Ubuntu 20.04, 22.04, 24.04
- Debian 11, 12
- Armbian (detection works, skips by default)
- Raspberry Pi OS (Raspbian)

Works on both ARM and x86 architectures.

## Integration with Existing Roles

Works well with:
- `check_if_pi` - Uses facts for hardware detection
- `import_dotfiles` - Complementary system customization
- `dev_server_provision` - Great addition to server provisioning

## Example Output

```
 _   _           _
| | | | ___  ___| |_ _ __   __ _ _ __ ___   ___
| |_| |/ _ \/ __| __| '_ \ / _` | '_ ` _ \ / _ \
|  _  | (_) \__ \ |_| | | | (_| | | | | | |  __/
|_| |_|\___/|___/\__|_| |_|\__,_|_| |_| |_|\___|

System: Ubuntu 22.04.3 LTS
Kernel: 5.15.0-91-generic (x86_64)
Hardware: HP EliteDesk 800 G4 DM

Performance:

 Load:         15% (0.61 on 4 cores)
 Uptime:       2 days, 5 hours
 Memory:       42% (3.2G / 7.6G)
 CPU temp:     52°C
 Disk (/):     18% (14G / 77G)

Network:
 LAN IP:       192.168.9.111 (eth0)

Helpful Commands:

 Configuration   : sudo dpkg-reconfigure -plow unattended-upgrades
 Monitoring      : htop
 System logs     : journalctl -f
 Disk usage      : ncdu /
```

## Restoration

To restore the original MOTD:

```bash
sudo rm /etc/update-motd.d/00-header
sudo rm /etc/update-motd.d/10-sysinfo
sudo rm /etc/update-motd.d/40-commands
sudo cp -r /etc/update-motd.d.backup/* /etc/update-motd.d/
```

## License

MIT

## Author

Created for homelab infrastructure management.
