# Set-RamlWallpaper.ps1
# Generates a branded desktop background with live host + network info drawn
# top-right, then sets it as the wallpaper. Re-run on logon and on network
# change so the desktop always shows the machine's current state.
#
# This is the self-contained alternative to Sysinternals BGInfo: no download,
# lives in the template, survives a reset. BGInfo remains a fine choice if you
# prefer its refresh-on-demand tray behaviour (see the deployment sheet).
#
# One-time install (elevated), registers logon + network-change triggers:
#   .\Set-RamlWallpaper.ps1 -Install
# Manual refresh:
#   .\Set-RamlWallpaper.ps1

param([switch]$Install)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ── brand palette ────────────────────────────────────────────────────────
$cInk   = [System.Drawing.Color]::FromArgb(33, 31, 28)     # #211F1C background
$cCream = [System.Drawing.Color]::FromArgb(244, 239, 228)  # #F4EFE4 text
$cRed   = [System.Drawing.Color]::FromArgb(192, 71, 58)    # #C0473A accent
$cMuted = [System.Drawing.Color]::FromArgb(173, 168, 158)  # labels

if ($Install) {
    $self = $MyInvocation.MyCommand.Path
    $dest = "$env:ProgramData\raml\Set-RamlWallpaper.ps1"
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $self $dest -Force

    $action  = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest`""
    # logon trigger
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $action
    $tLogon = New-ScheduledTaskTrigger -AtLogOn
    # network-change trigger via event
    $class = Get-CimClass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
    $tNet = New-CimInstance -CimClass $class -ClientOnly
    $tNet.Subscription =
      "<QueryList><Query Id='0'><Select Path='Microsoft-Windows-NetworkProfile/Operational'>*[System[EventID=10000 or EventID=4004]]</Select></Query></QueryList>"
    $tNet.Enabled = $true
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Limited
    Register-ScheduledTask -TaskName 'raml-wallpaper' -Action $a `
        -Trigger $tLogon, $tNet -Settings $set -Principal $principal -Force | Out-Null
    Write-Host 'Installed. Wallpaper will refresh at logon and on network change.'
    # fall through and render once now
}

# ── live facts ───────────────────────────────────────────────────────────
$hostN = $env:COMPUTERNAME
$domain = (Get-CimInstance Win32_ComputerSystem).Domain
$fqdn = if ($domain -and $domain -ne 'WORKGROUP') { "$hostN.$domain" } else { $hostN }
$os   = (Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ',''

$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
         Sort-Object RouteMetric | Select-Object -First 1
if ($route) {
    $i = $route.ifIndex
    $gw = $route.NextHop
    $ipObj = Get-NetIPAddress -ifIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $ip = if ($ipObj) { "$($ipObj.IPAddress)/$($ipObj.PrefixLength)" } else { 'unconfigured' }
    $ifName = (Get-NetAdapter -ifIndex $i -ErrorAction SilentlyContinue).Name
    $mac = (Get-NetAdapter -ifIndex $i -ErrorAction SilentlyContinue).MacAddress
    $dns = ((Get-DnsClientServerAddress -ifIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join '  ')
} else {
    $ip='no default route'; $gw='none'; $ifName='none'; $mac='n/a'; $dns='none'
}
if (-not $dns) { $dns = 'none' }

$rows = @(
    @('host',    $hostN),
    @('os',      $os),
    @('domain',  $domain),
    @('',        ''),
    @('iface',   $ifName),
    @('addr',    $ip),
    @('gateway', $gw),
    @('dns',     $dns),
    @('mac',     $mac)
)

# ── canvas at primary screen resolution ──────────────────────────────────
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$w = $scr.Width; $h = $scr.Height
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'ClearTypeGridFit'
$g.Clear($cInk)

# faint centred watermark
$fWatermark = New-Object System.Drawing.Font 'Cormorant Garamond', 120, ([System.Drawing.FontStyle]::Bold)
$wmColor = [System.Drawing.Color]::FromArgb(18, 244, 239, 228)  # ~7% cream
$wmBrush = New-Object System.Drawing.SolidBrush $wmColor
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
$g.DrawString('raml.ch', $fWatermark, $wmBrush, ($w/2), ($h/2), $sf)

# ── info panel, top-right ────────────────────────────────────────────────
$fTitle = New-Object System.Drawing.Font 'Cormorant Garamond', 34, ([System.Drawing.FontStyle]::Bold)
$fHost  = New-Object System.Drawing.Font 'Montserrat', 15, ([System.Drawing.FontStyle]::Bold)
$fLabel = New-Object System.Drawing.Font 'Consolas', 12
$fValue = New-Object System.Drawing.Font 'Consolas', 12, ([System.Drawing.FontStyle]::Bold)

$bCream = New-Object System.Drawing.SolidBrush $cCream
$bRed   = New-Object System.Drawing.SolidBrush $cRed
$bMuted = New-Object System.Drawing.SolidBrush $cMuted

$panelW = 340
$x = $w - $panelW - 60
$y = 70

$g.DrawString('raml.ch', $fTitle, $bRed, $x, $y); $y += 58
$g.FillRectangle($bRed, $x, $y, $panelW, 2); $y += 16
$g.DrawString(([char]0x25C6) + " $fqdn", $fHost, $bCream, $x, $y); $y += 40

foreach ($row in $rows) {
    if ($row[0] -eq '') { $y += 12; continue }
    $g.DrawString($row[0], $fLabel, $bMuted, $x, $y)
    $valBrush = if ($row[0] -eq 'addr') { $bRed } else { $bCream }
    $g.DrawString([string]$row[1], $fValue, $valBrush, ($x + 92), $y)
    $y += 26
}

$g.DrawString((Get-Date -Format 'yyyy-MM-dd HH:mm'), $fLabel, $bMuted, $x, ($y + 10))

# ── save and apply ───────────────────────────────────────────────────────
$out = "$env:ProgramData\raml\wallpaper.png"
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$sig = @'
using System.Runtime.InteropServices;
public class Wp {
  [DllImport("user32.dll", CharSet=CharSet.Auto)]
  public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
if (-not ('Wp' -as [type])) { Add-Type $sig }
# 20 = SPI_SETDESKWALLPAPER, 0x1|0x2 = update + broadcast
[Wp]::SystemParametersInfo(20, 0, $out, 0x3) | Out-Null
