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
#
# NOTE: must be saved as UTF-8 *with BOM* or PowerShell 5.1 mangles the block
# glyphs in the logo (reads the file as Windows-1252).

Clear-Host   # wipe the "Windows PowerShell / Copyright" header before drawing

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
        $dns     = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ' '
    } else {
        $ip = 'no default route'; $gw = 'none'; $ifName = 'none'; $mac = 'n/a'; $dns = 'none'
    }
    if (-not $dns) { $dns = 'none' }

    # NOTE: keep every element a single interpolated string. Using `+` to
    # concat (e.g. with [char]0x25C6) makes PowerShell parse the whole @(...)
    # as one expression, collapsing the array to a single element.
    $dia = [char]0x25C6
    $info = @(
        "$RED$B$dia$R  $CREAM$B$fqdn$R",
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

    $logoW = 54           # visible width of the logo block
    $gap   = '   '        # space between logo and the info block
    $cols  = try { $Host.UI.RawUI.WindowSize.Width } catch { 80 }
    if (-not $cols -or $cols -lt 1) { $cols = 80 }

    $nLogo = $logo.Count; $nInfo = $info.Count
    $total = [Math]::Max($nLogo, $nInfo)

    # side-by-side only if the widest info line still fits; else stack below.
    $maxInfo = 0
    foreach ($ln in $info) {
        $v = ($ln -replace "$([char]27)\[[0-9;]*m", '').Length
        if ($v -gt $maxInfo) { $maxInfo = $v }
    }

    Write-Host ''
    if ($cols -ge ($logoW + $gap.Length + $maxInfo)) {
        # logo left, info block immediately to its right (fixed gap)
        $blank = ' ' * $logoW
        $logoOff = [Math]::Floor(($total - $nLogo) / 2)   # center logo vs info
        $infoOff = [Math]::Floor(($total - $nInfo) / 2)
        for ($i = 0; $i -lt $total; $i++) {
            $li = $i - $logoOff
            $left = if ($li -ge 0 -and $li -lt $nLogo) { "$RED$($logo[$li])$R" } else { $blank }
            $ii = $i - $infoOff
            $right = if ($ii -ge 0 -and $ii -lt $nInfo) { $info[$ii] } else { '' }
            Write-Host ($left + $gap + $right)
        }
    } else {
        # narrow terminal: logo first, then the info block below it
        foreach ($ln in $logo) { Write-Host "$RED$ln$R" }
        Write-Host ''
        foreach ($ln in $info) { Write-Host $ln }
    }
    Write-Host ''
}

Show-RamlBanner
