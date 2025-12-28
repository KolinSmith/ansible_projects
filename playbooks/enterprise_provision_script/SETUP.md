# Enterprise Windows Provisioning Setup

This playbook provisions a Windows 10 LTSC machine with Scoop package management, WSL Ubuntu configuration, and custom Windows Terminal settings.

## Quick Start (Fresh Windows 10 LTSC Install)

### Step 1: Bootstrap Windows (Run in PowerShell as Administrator)

```powershell
# Download and run the bootstrap script
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/AlexNabokikh/windows-playbook/master/setup.ps1"
$file = "$env:temp\setup.ps1"

(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
powershell.exe -ExecutionPolicy ByPass -File $file -Verbose
```

**Or use the local setup.ps1:**

```powershell
# If you have this repo locally
cd C:\path\to\ansible_projects\playbooks\enterprise_provision_script
powershell.exe -ExecutionPolicy ByPass -File setup.ps1 -Verbose
```

This script:
- Sets PowerShell execution policy to RemoteSigned
- Installs Chocolatey (not used by default, but available)
- Installs OpenSSH Server
- Configures SSH service and firewall

### Step 2: Install Ansible in WSL Ubuntu

After WSL is installed and configured (or do this manually first):

```bash
# In WSL Ubuntu terminal
sudo apt update
sudo apt install -y ansible

# Install required Ansible collections
ansible-galaxy install -r requirements.yml
```

### Step 3: Configure Vault Secrets

The playbook needs SSH keys from Ansible Vault. Ensure your `group_vars/all/vault.yml` contains:

- `voyager_private_ssh_key` - Your ed25519 private key
- `voyager_public_ssh_key` - Your ed25519 public key

### Step 4: Run the Playbook

```bash
# Run full provisioning
ansible-playbook main.yml

# Or run specific tags only
ansible-playbook main.yml --tags "scoop,wsl_configure,windows_terminal"
```

## What Gets Installed

### Windows Applications (via Scoop)

**Core Utilities:**
- 7zip, aria2, git, dark (dark mode toggle)

**Browsers:**
- Brave, LibreWolf, Firefox

**Productivity:**
- PowerToys, Nextcloud, Windows Terminal, Notepad++, Everything, VSCode

**Media:**
- VLC, Spotify

**Development:**
- Python, Terraform, Kubernetes CLI

**Security:**
- VeraCrypt

See `default.config.yml` for the full list.

### WSL Ubuntu Configuration

- **oh-my-zsh** + **Powerlevel10k** theme
- **tmuxinator** for tmux session management
- **Dotfiles** deployment from your GitHub repository
- **SSH keys** deployment
- Git configuration

### Windows Terminal

- Custom color schemes (SleepyHollow default)
- Custom keybindings (Ctrl+C/V for copy/paste)
- Ubuntu WSL as default profile
- Cascadia Code font

### Windows Settings

- Explorer configuration (show file extensions, etc.)
- Taskbar cleanup (remove search, chat, etc.)
- Start menu cleanup (disable suggestions)
- Bloatware removal
- High performance power plan
- Optional Windows updates

## Available Tags

Run specific portions of the playbook:

```bash
# Package installation only
ansible-playbook main.yml --tags "scoop"

# WSL configuration only
ansible-playbook main.yml --tags "wsl_configure"

# Windows Terminal settings only
ansible-playbook main.yml --tags "windows_terminal"

# Windows UI cleanup
ansible-playbook main.yml --tags "debloat,explorer,taskbar,start_menu"

# Full system
ansible-playbook main.yml --tags "all"
```

Available tags:
- `hostname` - Set custom hostname
- `updates` - Install Windows updates
- `debloat` - Remove bloatware
- `scoop` - Install Scoop packages
- `windows_features` - Enable Windows features (Hyper-V, etc.)
- `wsl` - Install WSL2 + Ubuntu
- `wsl_configure` - Configure WSL Ubuntu (oh-my-zsh, tmuxinator, dotfiles)
- `fonts` - Install Nerd Fonts
- `windows_terminal` - Deploy Windows Terminal settings
- `explorer` - Configure Windows Explorer
- `taskbar` - Configure Taskbar
- `start_menu` - Configure Start Menu
- `sounds` - Set sound scheme
- `mouse` - Disable mouse acceleration
- `power` - Set power plan
- `remote_desktop` - Configure RDP
- `desktop` - Configure desktop icons
- `defrag` - Defragment volumes

## Customization

### Override Default Configuration

Create a `config.yml` file (ignored by git) to override defaults:

```yaml
configure_hostname: true
custom_hostname: Enterprise

scoop_installed_packages:
  - 7zip
  - git
  - vscode
  # Add more packages

install_oh_my_zsh: true
install_tmuxinator: true
deploy_dotfiles: true
dotfiles_repo: "git@github.com:YourUsername/dotfiles.git"

configure_windows_terminal: true
```

### Skip Specific Tasks

Set configuration options to `false` in `config.yml`:

```yaml
remove_bloatware: false
install_windows_updates: false
configure_wsl: false
```

## Troubleshooting

### Ansible Can't Connect

Ensure OpenSSH Server is running:

```powershell
Get-Service sshd
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```

### WSL Commands Fail

Ensure WSL2 is installed and Ubuntu is available:

```powershell
wsl --list --verbose
wsl --set-default-version 2
```

### Scoop Packages Fail to Install

Update Scoop and retry:

```powershell
scoop update
scoop update *
```

### Permission Errors

Run Ansible from WSL as your Windows user (not root).

## Manual Steps

Some things still require manual installation:

1. **Elgato Control Center** (if you have Elgato equipment)
2. **Macrium Reflect** (backup software)
3. **Games** (Steam, EA App, etc.)
4. **Specialized tools** (ASTAP, Haveno, etc.)

## Architecture

This playbook runs **locally** on the Windows machine:
- Playbook runs via Ansible in WSL
- Connects to `127.0.0.1` via SSH
- Uses PowerShell commands via `ansible.builtin.raw` for Windows tasks
- Uses `wsl` commands for WSL configuration

## Credits

Based on [AlexNabokikh/windows-playbook](https://github.com/AlexNabokikh/windows-playbook)

Modified by Kolin Smith for personal use with Scoop package management and WSL development environment.
