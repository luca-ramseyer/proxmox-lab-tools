# raml.ch branding installer for Windows 11 / PowerShell.
#
# One-liner (elevated PowerShell recommended so the wallpaper task registers):
#   irm https://raw.githubusercontent.com/luca-ramseyer/proxmox-lab-tools/main/branding/install.ps1 | iex
#
# Installs: PowerShell terminal banner (per-user, all hosts) + live branded
# wallpaper with logon/network-change auto-refresh.

$ErrorActionPreference = 'Stop'
$raw = 'https://raw.githubusercontent.com/luca-ramseyer/proxmox-lab-tools/main/branding'

Write-Host 'raml branding: installing Windows profile'

# ── terminal banner -> per-user, all hosts ───────────────────────────────
$profilePath = $PROFILE.CurrentUserAllHosts
New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
Invoke-WebRequest "$raw/Microsoft.PowerShell_profile.ps1" -OutFile $profilePath -UseBasicParsing
Write-Host "  [+] terminal banner -> $profilePath"

# ── live wallpaper + auto-refresh scheduled task ─────────────────────────
$wp = Join-Path $env:TEMP 'Set-RamlWallpaper.ps1'
Invoke-WebRequest "$raw/Set-RamlWallpaper.ps1" -OutFile $wp -UseBasicParsing

# task registration needs admin; render-only still works without it.
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wp -Install
    Write-Host '  [+] wallpaper installed (refreshes at logon + on network change)'
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wp
    Write-Host '  [!] not elevated: wallpaper set once, auto-refresh task NOT registered.'
    Write-Host '      Re-run from an admin PowerShell for logon/network auto-refresh.'
}

Write-Host 'done. banner shows on next PowerShell session.'
