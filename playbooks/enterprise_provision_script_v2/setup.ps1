# Windows 10 LTSC Configuration Script
# Run as Administrator

# Set execution policy to allow scripts
Set-ExecutionPolicy Bypass -Scope Process -Force

# Check for Python installation
$pythonInstalled = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonInstalled) {
    Write-Host "Python not found. Installing Python..." -ForegroundColor Yellow
    
    # Download Python installer
    $pythonUrl = "https://www.python.org/ftp/python/3.11.4/python-3.11.4-amd64.exe"
    $pythonInstaller = "$env:TEMP\python-installer.exe"
    Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller
    
    # Install Python (silently, include pip, add to PATH)
    Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_pip=1" -Wait
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "Python installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Python is already installed." -ForegroundColor Green
}

# Check for Ansible installation
$ansibleInstalled = Get-Command ansible -ErrorAction SilentlyContinue
if (-not $ansibleInstalled) {
    Write-Host "Ansible not found. Installing Ansible..." -ForegroundColor Yellow
    
    # Install Ansible and its dependencies
    pip install ansible pywinrm
    
    Write-Host "Ansible installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# Run the Ansible playbook
Write-Host "Running Ansible playbook to configure Windows 10 LTSC..." -ForegroundColor Cyan
ansible-playbook main.yml -v

Write-Host "Configuration complete! You may need to restart your computer for all changes to take effect." -ForegroundColor Green