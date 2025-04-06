# Windows Machine Setup Script - Prepares system for Ansible using Scoop
# Run as Administrator

# Enable script execution
Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "-----------------------------------------" -ForegroundColor Cyan
Write-Host "Windows Machine Setup for Ansible" -ForegroundColor Cyan
Write-Host "-----------------------------------------" -ForegroundColor Cyan

# 1. Install Scoop if not already installed
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop package manager..." -ForegroundColor Yellow
    
    try {
        Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Host "Scoop installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error installing Scoop: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Scoop already installed" -ForegroundColor Green
}

# 2. Add necessary buckets
Write-Host "Adding required Scoop buckets..." -ForegroundColor Yellow
scoop bucket add extras
scoop bucket add versions

# 3. Install Python and Ansible with Scoop
Write-Host "Installing Python and Ansible..." -ForegroundColor Yellow

# Python
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    scoop install python
} else {
    Write-Host "Python already installed" -ForegroundColor Green
}

# Ansible
scoop install ansible

# Verify installations
if (Get-Command ansible -ErrorAction SilentlyContinue) {
    $ansibleVersion = (ansible --version) | Select-Object -First 1
    Write-Host "Ansible installed successfully: $ansibleVersion" -ForegroundColor Green
} else {
    Write-Host "Ansible installation failed" -ForegroundColor Red
    exit 1
}

# 4. Install pywinrm separately for Windows support
Write-Host "Installing pywinrm for Windows support..." -ForegroundColor Yellow
pip install pywinrm

# 5. Run the Ansible playbook
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