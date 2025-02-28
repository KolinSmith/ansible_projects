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

# Find Python Scripts directory
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCommand) {
    $pythonPath = Split-Path -Parent $pythonCommand.Source
    $pythonScriptsPath = Join-Path $pythonPath "Scripts"
    Write-Host "Python Scripts path: $pythonScriptsPath" -ForegroundColor Cyan
} else {
    Write-Host "Unable to determine Python path. Using default..." -ForegroundColor Yellow
    $pythonScriptsPath = "$env:LOCALAPPDATA\Programs\Python\Python311\Scripts"
    if (-not (Test-Path $pythonScriptsPath)) {
        $pythonScriptsPath = "C:\Program Files\Python311\Scripts"
    }
}

# Add Python Scripts to PATH if not already there
if ($env:Path -notlike "*$pythonScriptsPath*") {
    Write-Host "Adding Python Scripts to PATH..." -ForegroundColor Yellow
    $env:Path = $env:Path + ";" + $pythonScriptsPath
    [System.Environment]::SetEnvironmentVariable("Path", $env:Path, "User")
}

# Check for Ansible installation
$ansibleInstalled = Get-Command ansible -ErrorAction SilentlyContinue
if (-not $ansibleInstalled) {
    Write-Host "Ansible not found. Installing Ansible..." -ForegroundColor Yellow
    
    # Install Ansible and its dependencies
    & "$pythonScriptsPath\pip" install ansible pywinrm
    
    Write-Host "Ansible installed successfully!" -ForegroundColor Green
} else {
    Write-Host "Ansible is already installed." -ForegroundColor Green
}

# Check if ansible-playbook is available
$ansiblePlaybookPath = Join-Path $pythonScriptsPath "ansible-playbook.exe"
if (Test-Path $ansiblePlaybookPath) {
    Write-Host "Found ansible-playbook at: $ansiblePlaybookPath" -ForegroundColor Green
    
    # Run the Ansible playbook using full path
    Write-Host "Running Ansible playbook to configure Windows 10 LTSC..." -ForegroundColor Cyan
    & $ansiblePlaybookPath main.yml -v
} else {
    Write-Host "ansible-playbook not found at expected location." -ForegroundColor Red
    Write-Host "Searching for ansible-playbook in system..." -ForegroundColor Yellow
    
    $ansiblePlaybookFiles = Get-ChildItem -Path "$env:ProgramFiles" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "ansible-playbook.exe" }
    if (-not $ansiblePlaybookFiles) {
        $ansiblePlaybookFiles = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "ansible-playbook.exe" }
    }
    
    if ($ansiblePlaybookFiles) {
        $ansiblePlaybookPath = $ansiblePlaybookFiles[0].FullName
        Write-Host "Found ansible-playbook at: $ansiblePlaybookPath" -ForegroundColor Green
        
        # Run the Ansible playbook using found path
        Write-Host "Running Ansible playbook to configure Windows 10 LTSC..." -ForegroundColor Cyan
        & $ansiblePlaybookPath main.yml -v
    } else {
        Write-Host "Unable to find ansible-playbook. Please run the playbook manually after restarting your terminal:" -ForegroundColor Red
        Write-Host "1. Close and reopen PowerShell as Administrator" -ForegroundColor Yellow
        Write-Host "2. Run: ansible-playbook main.yml -v" -ForegroundColor Yellow
    }
}

Write-Host "Configuration complete! You may need to restart your computer for all changes to take effect." -ForegroundColor Green