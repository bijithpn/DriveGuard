<#
.SYNOPSIS
  Build the DriveGuard release app and install it for the current user (Windows).
.DESCRIPTION
  Installs to %LOCALAPPDATA%\Programs\DriveGuard and adds Start Menu + Desktop shortcuts.
  Missing Git / Visual Studio C++ build tools are installed with winget, and a missing
  Flutter SDK is cloned to ~\flutter. Installing the C++ tools and enabling Developer Mode
  need an Administrator PowerShell (only the first time, and only if they're missing).
  Run:  powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
.PARAMETER NoLaunch  Do not start the app afterwards.
#>
param([switch]$NoLaunch)

$ErrorActionPreference = 'Stop'
function Log($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }
function Run([string]$Exe, [string[]]$CmdArgs) {
  & $Exe @CmdArgs
  if ($LASTEXITCODE -ne 0) { Die "$Exe $($CmdArgs -join ' ') failed (exit code $LASTEXITCODE)" }
}

Set-Location (Split-Path -Parent $PSScriptRoot)

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

# Git (only if missing)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  if (-not $hasWinget) { Die 'Git not found and winget is unavailable. Install Git for Windows and re-run.' }
  Log 'Installing Git via winget...'
  winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements
  Refresh-Path
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'Git installed but not on PATH yet. Open a new terminal and re-run.' }
}

# Visual Studio C++ toolchain (only if missing; needs Administrator)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVC = (Test-Path $vswhere) -and [bool](& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
if (-not $hasVC) {
  if (-not $hasWinget) { Die 'Visual Studio C++ tools missing and winget is unavailable. Install "Desktop development with C++" and re-run.' }
  if (-not $isAdmin) { Die 'Visual Studio C++ tools are missing. Re-run this script from an Administrator PowerShell to install them.' }
  Log 'Installing Visual Studio Build Tools (C++ workload) - this takes a while...'
  winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent --accept-package-agreements --accept-source-agreements `
    --override '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
  Refresh-Path
}

# Developer Mode (Flutter plugins need symlinks); only changed when running as Administrator
$devKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devOn = (Get-ItemProperty $devKey -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense -eq 1
if (-not $devOn) {
  if ($isAdmin) {
    Log 'Enabling Developer Mode (needed for plugin symlinks)...'
    New-Item -Path $devKey -Force | Out-Null
    Set-ItemProperty -Path $devKey -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord
  } else {
    Write-Host 'WARN: Developer Mode is off. If "flutter pub get" reports a symlink error, re-run as Administrator.' -ForegroundColor Yellow
  }
}

# Flutter SDK: use the existing one, else clone stable into ~\flutter
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  $fl = Join-Path $env:USERPROFILE 'flutter'
  if (-not (Test-Path (Join-Path $fl 'bin\flutter.bat'))) {
    Log 'Flutter not found; downloading the stable SDK to ~\flutter ...'
    Run 'git' @('clone','--depth','1','-b','stable','https://github.com/flutter/flutter.git',$fl)
  }
  $env:Path = "$fl\bin;$env:Path"
}
Run 'flutter' @('config','--enable-windows-desktop')

Log 'Fetching dependencies...'
Run 'flutter' @('pub','get')

Log 'Building release app (this can take several minutes)...'
Run 'flutter' @('build','windows','--release')

$BuildDir = Get-ChildItem -Directory -Path 'build\windows\*\runner\Release' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $BuildDir -or -not (Test-Path (Join-Path $BuildDir.FullName 'driveguard.exe'))) {
  Die 'Build finished but driveguard.exe was not found.'
}

$Dest = Join-Path $env:LOCALAPPDATA 'Programs\DriveGuard'
if (Get-Process -Name driveguard -ErrorAction SilentlyContinue) {
  Log 'Closing the running copy...'
  Stop-Process -Name driveguard -Force
  Start-Sleep -Seconds 1
}

Log "Installing to $Dest ..."
if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $BuildDir.FullName '*') -Destination $Dest

$exe = Join-Path $Dest 'driveguard.exe'
$shell = New-Object -ComObject WScript.Shell
foreach ($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
  $lnk = $shell.CreateShortcut((Join-Path $dir 'DriveGuard.lnk'))
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $Dest
  $lnk.IconLocation = $exe
  $lnk.Save()
}

Log "Installed: $Dest"
if (-not $NoLaunch) { Start-Process $exe }
Log 'Done.'
