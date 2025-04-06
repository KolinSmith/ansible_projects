# Windows Machine Setup Script - Prepares Ansible via Cygwin
# Run as Administrator

# Enable script execution
Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "-----------------------------------------" -ForegroundColor Cyan
Write-Host "Windows Machine Setup for Ansible via Cygwin" -ForegroundColor Cyan
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

# 2. Install Cygwin via Scoop
Write-Host "Installing Cygwin..." -ForegroundColor Yellow
scoop install cygwin

# 3. Install Ansible within Cygwin
Write-Host "Installing Ansible within Cygwin..." -ForegroundColor Yellow
$cygwinSetup = "$env:USERPROFILE\scoop\apps\cygwin\current\cygwin-setup.exe"

# Using -qnBP for quiet install with Ansible package
& $cygwinSetup -qnBP ansible
if ($LASTEXITCODE -eq 0) {
    Write-Host "Ansible installed successfully in Cygwin!" -ForegroundColor Green
} else {
    Write-Host "Error installing Ansible in Cygwin (exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# 4. Create a batch file wrapper to run Ansible from Windows
$batchWrapper = @"
@echo off
REM Ansible Playbook Wrapper
REM Usage: ansible-playbook-cygwin.bat playbook.yml [options]

if "%~1"=="" (
    echo Error: No playbook specified
    echo Usage: ansible-playbook-cygwin.bat playbook.yml [options]
    exit /b 1
)

REM Get the full path to the playbook
set PLAYBOOK=%~f1
shift

REM Prepare the arguments string
set ARGS=
:arg_loop
if "%~1"=="" goto arg_done
set ARGS=%ARGS% %1
shift
goto arg_loop
:arg_done

REM Run ansible-playbook in Cygwin
"%USERPROFILE%\scoop\apps\cygwin\current\bin\bash.exe" --login -c "cd `$(cygpath '%CD%') && ansible-playbook `$(cygpath '%PLAYBOOK%')%ARGS%"
exit /b %ERRORLEVEL%
"@

$wrapperPath = Join-Path $PWD "ansible-playbook-cygwin.bat"
$batchWrapper | Out-File -FilePath $wrapperPath -Encoding ascii

# 5. Run the Ansible playbook via Cygwin
$playbookPath = Join-Path $PWD "main.yml"
if (Test-Path $playbookPath) {
    Write-Host "Starting Ansible playbook execution via Cygwin..." -ForegroundColor Cyan
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    try {
        & $wrapperPath $playbookPath -v
        
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
Write-Host "Setup complete! You can now run Ansible using the ansible-playbook-cygwin.bat wrapper." -ForegroundColor Green