# Setup-WindowsForAnsible.ps1
# This script configures a Windows machine to be managed by Ansible via SSH
# Run as Administrator

param (
    [Parameter()]
    [switch]$SetPowershellAsDefault = $true
)

# ====== PASTE YOUR PUBLIC KEY BELOW THIS LINE ======
$PublicKeyString = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAGkgiD7guFU6pc7GwchfPknc+r2UuvQcL7mA7TzWRX8v1EaozCabWkuQY3rbW1uIWXZqil9BImRED5G6pCnREuY1ADZm/Nd4BnsA0FOsZv00NkKTAO6ide2Hljm5uQek+wCE6WqwJwgusfdmsidNF9yZRFVsiwP9bf3hgUcamx6B1hbkg== dax@Voyager"
# ====== PASTE YOUR PUBLIC KEY ABOVE THIS LINE ======

function Write-Status {
    param (
        [string]$Message
    )
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

# Ensure script is running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Exiting..." -ForegroundColor Red
    exit 1
}

# 1. Check and install OpenSSH Server
Write-Status "Checking if OpenSSH Server is installed..."
$sshServerInstalled = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*' | Select-Object -ExpandProperty State

if ($sshServerInstalled -ne "Installed") {
    Write-Status "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
} else {
    Write-Host "OpenSSH Server is already installed." -ForegroundColor Green
}

# 2. Check and install OpenSSH Client (useful to have)
Write-Status "Checking if OpenSSH Client is installed..."
$sshClientInstalled = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*' | Select-Object -ExpandProperty State

if ($sshClientInstalled -ne "Installed") {
    Write-Status "Installing OpenSSH Client..."
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
} else {
    Write-Host "OpenSSH Client is already installed." -ForegroundColor Green
}

# 3. Start and configure SSH service
Write-Status "Starting SSH service..."
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "SSH service started and set to automatic startup." -ForegroundColor Green

# 4. Configure firewall rule
Write-Status "Configuring firewall rule..."
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    Write-Output "Creating Firewall Rule 'OpenSSH-Server-In-TCP'..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' already exists."
}

# 5. Set PowerShell as the default SSH shell
if ($SetPowershellAsDefault) {
    Write-Status "Setting PowerShell as the default SSH shell..."
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
    Write-Host "PowerShell is now the default SSH shell." -ForegroundColor Green
}

# 6. Configure passwordless authentication for Administrator
Write-Status "Setting up passwordless authentication for Administrator..."

# Configure SSH server for public key authentication
$sshdConfigPath = "$env:ProgramData\ssh\sshd_config"
$sshdConfig = Get-Content $sshdConfigPath

# Backup the original config
Copy-Item $sshdConfigPath "$sshdConfigPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Update the sshd_config file
$sshdConfig = $sshdConfig -replace '#PubkeyAuthentication yes', 'PubkeyAuthentication yes'
$sshdConfig = $sshdConfig -replace '#PasswordAuthentication yes', 'PasswordAuthentication no'
$sshdConfig = $sshdConfig -replace 'StrictModes yes', 'StrictModes no'

# Comment out the administrators_authorized_keys line
$sshdConfig = $sshdConfig -replace '^Match Group administrators', '# Match Group administrators'
$sshdConfig = $sshdConfig -replace '^\s*AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys', '#    AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'

# Save updated configuration
$sshdConfig | Set-Content $sshdConfigPath

# Set up SSH directory for Administrator
$adminProfile = "C:\Users\Administrator"
$sshFolder = Join-Path $adminProfile ".ssh"

# Ensure the .ssh folder exists
if (-not (Test-Path $sshFolder)) {
    Write-Status "Creating .ssh directory for Administrator..."
    New-Item -Path $sshFolder -ItemType Directory -Force | Out-Null
}

# Take ownership of the .ssh folder
Write-Status "Taking ownership of .ssh directory..."
takeown.exe /F $sshFolder /R /D Y | Out-Null

# Grant full permissions to Administrator
Write-Status "Granting full permissions to Administrator for .ssh directory..."
icacls $sshFolder /inheritance:r /grant:r "Administrator:(F)" /grant:r "SYSTEM:(F)" /T | Out-Null

# Create the authorized_keys file
Write-Status "Creating authorized_keys file for Administrator..."
$authorizedKeysPath = Join-Path $sshFolder "authorized_keys"
$PublicKeyString | Out-File -FilePath $authorizedKeysPath -Encoding utf8 -Force

# Grant full permissions to the authorized_keys file
Write-Status "Granting full permissions to Administrator for authorized_keys file..."
icacls $authorizedKeysPath /inheritance:r /grant:r "Administrator:(F)" /grant:r "SYSTEM:(F)" | Out-Null

Write-Host "Added public key to $authorizedKeysPath for Administrator" -ForegroundColor Green

# 7. Restart the SSH service to apply changes
Write-Status "Restarting SSH service to apply changes..."
Restart-Service sshd
Write-Host "SSH service restarted." -ForegroundColor Green

# 8. Print helpful information for Ansible connection
Write-Status "Windows machine is now ready for Ansible connection"
Write-Host ""
Write-Host "SYSTEM INFORMATION:" -ForegroundColor Cyan
try {
    Write-Host "  IP Address: $(Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5)" 
} catch {
    Write-Host "  IP Address: [Could not determine - check ipconfig]"
}
Write-Host "  Username: Administrator"
Write-Host "  Hostname: $($env:COMPUTERNAME)"
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Create an inventory file on your Ansible controller with the following content:" -ForegroundColor Yellow
Write-Host "     [win]" 
try {
    Write-Host "     $(Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5) # or use $($env:COMPUTERNAME)" 
} catch {
    Write-Host "     YOUR_IP_ADDRESS # or use $($env:COMPUTERNAME)"
}
Write-Host ""
Write-Host "     [win:vars]"
Write-Host "     ansible_user=Administrator"
Write-Host "     ansible_connection=ssh"
Write-Host "     ansible_shell_type=powershell"
Write-Host "     ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
Write-Host "     ansible_ssh_retries=3"
Write-Host "     ansible_become_method=runas"
Write-Host ""
Write-Host "  2. Test the connection with: ansible win -i inventory -m win_ping" -ForegroundColor Yellow
Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green