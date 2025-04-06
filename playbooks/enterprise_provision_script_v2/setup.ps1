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
    Write-Host "Installing Python 3.10..." -ForegroundColor Yellow
    # Using Python 3.10 instead of 3.11 to avoid compatibility issues
    $pythonUrl = "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe"
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
    $pythonVersion = python --version
    Write-Host "Python already installed: $pythonVersion" -ForegroundColor Green
}

# 2. Install Ansible and dependencies with compatibility fix
Write-Host "Installing Ansible and dependencies..." -ForegroundColor Yellow
python -m pip install --upgrade pip

# Install required packages
python -m pip install pywinrm

# Install Ansible with temporary fix for os.get_blocking issue
$tempScript = @"
import os

# Add the missing function if it doesn't exist
if not hasattr(os, 'get_blocking'):
    os.get_blocking = lambda fd: False

# Continue with normal execution
import pip
pip.main(['install', 'ansible'])
"@

Write-Host "Applying compatibility fix and installing Ansible..." -ForegroundColor Yellow
$tempFile = "$env:TEMP\install_ansible.py"
$tempScript | Out-File -FilePath $tempFile
python $tempFile
Remove-Item $tempFile

# 3. Verify ansible installation
$ansibleVersion = python -m pip show ansible
if ($?) {
    $version = ($ansibleVersion | Select-String "Version:").ToString().Split(":")[1].Trim()
    Write-Host "Ansible installed successfully (version $version)" -ForegroundColor Green
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
try:
    ansible_path = os.path.dirname(ansible.__file__)
    scripts_path = os.path.join(os.path.dirname(os.path.dirname(ansible_path)), 'Scripts')
    playbook_path = os.path.join(scripts_path, 'ansible-playbook.exe')
    if os.path.exists(playbook_path):
        print(playbook_path)
except Exception as e:
    print("")
"@

$pythonResult = python -c $findAnsibleScript
# FIX: Only test path if result is not empty
if ($? -and -not [string]::IsNullOrWhiteSpace($pythonResult) -and (Test-Path $pythonResult)) {
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
        try {
            $resolved = Resolve-Path $location -ErrorAction SilentlyContinue
            if ($resolved) {
                $ansiblePlaybookPath = $resolved[0].Path
                break
            }
        } catch {
            # Continue to next location if error
            continue
        }
    }
}

# 5. Create patched playbook wrapper if needed
if ($ansiblePlaybookPath) {
    # Create a patched wrapper script for ansible-playbook
    $wrapperScript = @"
import os

# Add the missing function if it doesn't exist
if not hasattr(os, 'get_blocking'):
    os.get_blocking = lambda fd: False

# Continue with normal execution
import sys
from ansible.cli.playbook import PlaybookCLI

if __name__ == '__main__':
    cli = PlaybookCLI(sys.argv)
    exit_code = cli.run()
    sys.exit(exit_code)
"@

    $wrapperPath = "$env:TEMP\ansible_wrapper.py"
    $wrapperScript | Out-File -FilePath $wrapperPath

    # 6. Run the playbook through our wrapper
    Write-Host "Found ansible-playbook at: $ansiblePlaybookPath" -ForegroundColor Green
    
    # Add to PATH for this session
    $ansibleDir = [System.IO.Path]::GetDirectoryName($ansiblePlaybookPath)
    $env:Path = "$ansibleDir;$env:Path"
    
    # Verify the playbook file exists
    $playbookPath = Join-Path $PWD "main.yml"
    if (Test-Path $playbookPath) {
        Write-Host "Starting Ansible playbook execution (with compatibility fix)..." -ForegroundColor Cyan
        Write-Host "-----------------------------------------" -ForegroundColor Cyan
        
        # Run the playbook through our wrapper
        try {
            python $wrapperPath $playbookPath -v
            if ($?) {
                Write-Host "-----------------------------------------" -ForegroundColor Cyan
                Write-Host "Ansible playbook completed successfully!" -ForegroundColor Green
            } else {
                Write-Host "-----------------------------------------" -ForegroundColor Cyan
                Write-Host "Ansible playbook encountered errors." -ForegroundColor Red
            }
        } catch {
            Write-Host "-----------------------------------------" -ForegroundColor Cyan
            Write-Host "Error running Ansible playbook: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Cannot find main.yml playbook in the current directory." -ForegroundColor Red
        Write-Host "Playbook should be located at: $playbookPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "Could not find ansible-playbook executable." -ForegroundColor Red
    Write-Host "Trying alternative method via Python module..." -ForegroundColor Yellow
    
    # Create a patched version of the main runner
    $patchedRunner = @"
import os

# Add the missing function if it doesn't exist
if not hasattr(os, 'get_blocking'):
    os.get_blocking = lambda fd: False

# Continue with normal execution
import sys
from ansible.cli.playbook import PlaybookCLI

if __name__ == '__main__':
    args = ['ansible-playbook'] + sys.argv[1:]
    cli = PlaybookCLI(args)
    exit_code = cli.run()
    sys.exit(exit_code)
"@

    $runnerPath = "$env:TEMP\run_ansible.py"
    $patchedRunner | Out-File -FilePath $runnerPath
    
    # Try to run via our patched Python script
    try {
        $playbookPath = Join-Path $PWD "main.yml" 
        if (Test-Path $playbookPath) {
            python $runnerPath $playbookPath -v
            if ($?) {
                Write-Host "Ansible playbook completed successfully!" -ForegroundColor Green
            } else {
                Write-Host "Ansible playbook encountered errors." -ForegroundColor Red
            }
        } else {
            Write-Host "Cannot find main.yml playbook in the current directory." -ForegroundColor Red
        }
    } catch {
        Write-Host "Error running Ansible via Python module: $_" -ForegroundColor Red
    }
}

# Clean up temp files
Remove-Item "$env:TEMP\ansible_wrapper.py" -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\run_ansible.py" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Setup complete! You may need to restart your terminal if any changes were made to PATH." -ForegroundColor Green