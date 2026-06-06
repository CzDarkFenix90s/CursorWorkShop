# MarketLab Windows start
# Diagnoses a broken local folder, restores repo files, installs deps, and starts dev.
#
# Run from anywhere:
#   pwsh -ExecutionPolicy Bypass -File .\scripts\windows-start.ps1
# or:
#   powershell -ExecutionPolicy Bypass -File .\scripts\windows-start.ps1

[CmdletBinding()]
param(
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot),
    [string]$RepoUrl = "https://github.com/CzDarkFenix90s/CursorWorkShop.git"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Test-ProjectRoot($path) {
    return (Test-Path (Join-Path $path "Taskfile.yml")) -and (Test-Path (Join-Path $path "mise.toml"))
}

function Activate-Mise {
    if (-not (Test-Command "mise")) {
        throw @"
mise is not installed.

Run setup first:
  pwsh -ExecutionPolicy Bypass -File .\scripts\windows-setup.ps1
"@
    }

    Write-Step "Activating mise"
    $activationScript = & mise activate pwsh 2>&1
    if ($LASTEXITCODE -ne 0) {
        $activationScript = & mise activate powershell 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "mise activate failed. Install PowerShell 7 (pwsh) or rerun windows-setup.ps1."
        }
    }
    $activationScript | Out-String | Invoke-Expression
}

Write-Step "Project directory: $ProjectDir"
Set-Location $ProjectDir

if (-not (Test-ProjectRoot $ProjectDir)) {
    Write-Step "Taskfile.yml not found. Trying to restore the repo..."

    if (Test-Path (Join-Path $ProjectDir ".git")) {
        Write-Step "Git repo detected. Fetching and resetting to origin/main"
        Invoke-NativeCommand -Command "git" -Arguments @("fetch", "origin")
        Invoke-NativeCommand -Command "git" -Arguments @("checkout", "main")
        Invoke-NativeCommand -Command "git" -Arguments @("reset", "--hard", "origin/main")
    } else {
        $parent = Split-Path -Parent $ProjectDir
        $folder = Split-Path -Leaf $ProjectDir
        $backup = "${ProjectDir}_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

        Write-Step "This folder is not a complete git clone."
        Write-Host "Backing up current folder to: $backup" -ForegroundColor Yellow
        if (Test-Path $ProjectDir) {
            Rename-Item -Path $ProjectDir -NewName (Split-Path -Leaf $backup)
        }

        Write-Step "Cloning fresh copy from $RepoUrl"
        Invoke-NativeCommand -Command "git" -Arguments @("clone", $RepoUrl, (Join-Path $parent $folder))
    }

    Set-Location $ProjectDir

    if (-not (Test-ProjectRoot $ProjectDir)) {
        throw "Taskfile.yml is still missing after restore. Check your internet connection and repo access."
    }
}

Write-Step "Project files look good (Taskfile.yml found)"

Activate-Mise

Write-Step "Trusting mise config and installing tools"
Invoke-NativeCommand -Command "mise" -Arguments @("trust")
Invoke-NativeCommand -Command "mise" -Arguments @("install")

if (-not (Test-Path (Join-Path $ProjectDir "node_modules"))) {
    Write-Step "Running task setup"
    Invoke-NativeCommand -Command "task" -Arguments @("setup")
} else {
    Write-Step "node_modules already present, skipping setup"
}

Write-Host ""
Write-Host "Starting dev server at http://localhost:3000" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

Invoke-NativeCommand -Command "task" -Arguments @("dev")
