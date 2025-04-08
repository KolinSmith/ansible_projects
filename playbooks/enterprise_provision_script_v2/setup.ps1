# Windows Machine Setup Script - Prepares system for Ansible using Chocolatey
# Run as Administrator

# Check for admin rights
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires administrator privileges. Please run as administrator." -ForegroundColor Red
    exit 1
}

# Enable script execution
Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "-----------------------------------------" -ForegroundColor Cyan
Write-Host "Windows Machine Setup for Ansible via Chocolatey" -ForegroundColor Cyan
Write-Host "-----------------------------------------" -ForegroundColor Cyan

# 1. Install Chocolatey if not already installed
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey package manager..." -ForegroundColor Yellow
    
    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Host "Chocolatey installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error installing Chocolatey: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Chocolatey already installed" -ForegroundColor Green
}

# 2. Install Ansible via Chocolatey
Write-Host "Installing Ansible via Chocolatey..." -ForegroundColor Yellow
choco install ansible -y

# 3. Refresh environment after installation
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 4. Verify Ansible installation
$ansiblePath = Get-Command ansible -ErrorAction SilentlyContinue
if ($ansiblePath) {
    $ansibleVersion = & ansible --version
    Write-Host "Ansible installed successfully!" -ForegroundColor Green
    Write-Host "Version: $($ansibleVersion[0])" -ForegroundColor Green
} else {
    Write-Host "Ansible installation may have failed. Please check your system." -ForegroundColor Red
    exit 1
}

# 5. Install pywinrm for Windows remote management
Write-Host "Installing pywinrm for Windows support..." -ForegroundColor Yellow
pip install pywinrm

# 6. Run the Ansible playbook
$playbookPath = Join-Path $PWD "main.yml"
if (Test-Path $playbookPath) {
    Write-Host "Starting Ansible playbook execution..." -ForegroundColor Cyan
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    try {
        ansible-playbook $playbookPath -v
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "-----------------------------------------" -ForegroundColor Cyan
            Write-Host "Ansible playbook completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "-----------------------------------------" -ForegroundColor Cyan
            Write-Host "Ansible playbook encountered errors (exit code: $LASTEXITCODE)" -ForegroundColor Red
        }
    } catch {
        Write-Host "-----------------------------------------" -ForegroundColor Cyan
        Write-Host "Error running Ansible playbook: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Cannot find main.yml playbook in the current directory." -ForegroundColor Red
    Write-Host "Playbook should be located at: $playbookPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green