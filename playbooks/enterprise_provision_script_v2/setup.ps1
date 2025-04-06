# Windows Machine Setup Script - Prepares system for Ansible playbook
# Run as Administrator

# Enable script execution
Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "-----------------------------------------" -ForegroundColor Cyan
Write-Host "Windows Machine Setup for Ansible" -ForegroundColor Cyan
Write-Host "-----------------------------------------" -ForegroundColor Cyan

# 1. Check and install Python
$pythonInstalled = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonInstalled) {
    Write-Host "Installing Python 3.11..." -ForegroundColor Yellow
    $pythonUrl = "https://www.python.org/ftp/python/3.11.4/python-3.11.4-amd64.exe"
    $pythonInstaller = "$env:TEMP\python-installer.exe"
    Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller
    Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_pip=1" -Wait
    
    # Force refresh path
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Verify installation
    $pythonInstalled = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonInstalled) {
        Write-Host "Python installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Python installation failed. Please install manually." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Python already installed" -ForegroundColor Green
}

# 2. Install Ansible and dependencies
Write-Host "Installing Ansible and dependencies..." -ForegroundColor Yellow
python -m pip install --upgrade pip
python -m pip install ansible pywinrm

# 3. Verify ansible installation
$ansibleVersion = python -m pip show ansible
if ($?) {
    Write-Host "Ansible installed successfully" -ForegroundColor Green
} else {
    Write-Host "Ansible installation failed" -ForegroundColor Red
    exit 1
}

# 4. Find ansible-playbook executable (looking in multiple locations)
Write-Host "Locating ansible-playbook executable..." -ForegroundColor Yellow

$ansiblePlaybookPath = $null

# Method 1: Use Python to find it (most reliable)
$findAnsibleScript = @"
import os, sys, ansible
ansible_path = os.path.dirname(ansible.__file__)
scripts_path = os.path.join(os.path.dirname(os.path.dirname(ansible_path)), 'Scripts')
playbook_path = os.path.join(scripts_path, 'ansible-playbook.exe')
if os.path.exists(playbook_path):
    print(playbook_path)
"@

$pythonResult = python -c $findAnsibleScript
if ($? -and (Test-Path $pythonResult)) {
    $ansiblePlaybookPath = $pythonResult
} 

# Method 2: Check common locations if Method 1 failed
if (-not $ansiblePlaybookPath) {
    $possibleLocations = @(
        (Join-Path ([System.IO.Path]::GetDirectoryName((Get-Command python).Source)) "Scripts\ansible-playbook.exe"),
        (Join-Path $env:USERPROFILE "AppData\Roaming\Python\Python*\Scripts\ansible-playbook.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python*\Scripts\ansible-playbook.exe"),
        (Join-Path $env:ProgramFiles "Python*\Scripts\ansible-playbook.exe")
    )

    foreach ($location in $possibleLocations) {
        $resolved = Resolve-Path $location -ErrorAction SilentlyContinue
        if ($resolved) {
            $ansiblePlaybookPath = $resolved[0].Path
            break
        }
    }
}

# 5. Add ansible-playbook to path if found
if ($ansiblePlaybookPath) {
    Write-Host "Found ansible-playbook at: $ansiblePlaybookPath" -ForegroundColor Green
    
    # Add to PATH for this session
    $ansibleDir = [System.IO.Path]::GetDirectoryName($ansiblePlaybookPath)
    $env:Path = "$ansibleDir;$env:Path"
    
    Write-Host "Ready to run Ansible playbook!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To run the playbook, close this window and run:" -ForegroundColor White
    Write-Host "ansible-playbook main.yml -v" -ForegroundColor Yellow
} else {
    Write-Host "Could not find ansible-playbook executable." -ForegroundColor Red
    Write-Host "Please try restarting your PowerShell session and running:" -ForegroundColor Yellow
    Write-Host "ansible-playbook main.yml -v" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete! You may need to restart your terminal or computer for all changes to take effect." -ForegroundColor Green