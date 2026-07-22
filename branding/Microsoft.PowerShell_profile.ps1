# raml.ch terminal banner for Windows PowerShell
# Brand ASCII on the left, live host + network facts on the right.
#
# Install for all users (run elevated):
#   Copy-Item Microsoft.PowerShell_profile.ps1 $PSHOME\Profile.ps1
# Or per-user:
#   Copy-Item Microsoft.PowerShell_profile.ps1 $PROFILE.CurrentUserAllHosts
#
# Works in Windows Terminal and the Windows 11 console (ANSI enabled by
# default). Uses [char]27 escapes so it also runs under Windows PowerShell 5.1.

function Show-RamlBanner {
    $e = [char]27
    $RED   = "$e[38;2;192;71;58m"
    $INK   = "$e[38;2;173;168;158m"
    $CREAM = "$e[38;2;244;239;228m"
    $DIM   = "$e[38;2;120;116;108m"
    $B     = "$e[1m"; $R = "$e[0m"

    $logo = @(
        '██████╗  █████╗ ███╗   ███╗██╗         ██████╗██╗  ██╗',
        '██╔══██╗██╔══██╗████╗ ████║██║        ██╔════╝██║  ██║',
        '██████╔╝███████║██╔████╔██║██║        ██║     ███████║',
        '██╔══██╗██╔══██║██║╚██╔╝██║██║        ██║     ██╔══██║',
        '██║  ██║██║  ██║██║ ╚═╝ ██║███████╗██╗╚██████╗██║  ██║',
        '╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝ ╚═════╝╚═╝  ╚═╝'
    )

    # ── live facts ──────────────────────────────────────────────────────
    $hostN = $env:COMPUTERNAME
    $domain = (Get-CimInstance Win32_ComputerSystem).Domain
    $fqdn = if ($domain -and $domain -ne 'WORKGROUP') { "$hostN.$domain" } else { $hostN }
    $os   = (Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ',''

    # interface holding the default route
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        $ifIndex = $route.ifIndex
        $gw      = $route.NextHop
        $ipObj   = Get-NetIPAddress -ifIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                   Select-Object -First 1
        $ip      = if ($ipObj) { "$($ipObj.IPAddress)/$($ipObj.PrefixLength)" } else { 'unconfigured' }
        $ifName  = (Get-NetAdapter -ifIndex $ifIndex -ErrorAction SilentlyContinue).Name
        $mac     = (Get-NetAdapter -ifIndex $ifIndex -ErrorAction SilentlyContinue).MacAddress
        $dns     = (Get-DnsClientServerAddress -ifIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ' '
    } else {
        $ip = 'no default route'; $gw = 'none'; $ifName = 'none'; $mac = 'n/a'; $dns = 'none'
    }
    if (-not $dns) { $dns = 'none' }

    $info = @(
        "$RED$B" + [char]0x25C6 + "$R  $CREAM$B$fqdn$R",
        '',
        "${INK}host    $R$CREAM$hostN$R",
        "${INK}os      $R$CREAM$os$R",
        "${INK}domain  $R$CREAM$domain$R",
        '',
        "${INK}iface   $R$CREAM$ifName$R",
        "${INK}addr    $R$RED$B$ip$R",
        "${INK}gateway $R$CREAM$gw$R",
        "${INK}dns     $R$CREAM$dns$R",
        "${INK}mac     $R$DIM$mac$R"
    )

    $gap = '   '; $blank = ' ' * 54
    $total = [Math]::Max($logo.Count, $info.Count)
    Write-Host ''
    for ($i = 0; $i -lt $total; $i++) {
        $left = if ($i -lt $logo.Count) { "$RED$($logo[$i])$R" } else { $blank }
        $right = if ($i -lt $info.Count) { $info[$i] } else { '' }
        Write-Host ($left + $gap + $right)
    }
    Write-Host ''
}

Show-RamlBanner
