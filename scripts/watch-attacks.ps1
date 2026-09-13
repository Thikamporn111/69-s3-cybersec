<#
  watch-attacks.ps1 -- who connected to the lab, when, and how.

  Reads the Nginx JSON access log (security/nginx.conf logs in JSON on purpose)
  and sorts every request into three buckets:

    [ATTACK]     password guessing, scanners, SQL injection, path traversal,
                 XSS probes, forged X-Forwarded-For, flooding (HTTP 429).
    [SUSPICIOUS] failed logins, poking at sensitive files, non-browser tools,
                 403/405/400 responses.
    [VIEW]       ordinary, successful requests -- someone just looking.

  It prints each event live, pops a Windows alert on an attack (and on a view
  if you pass -AlertOnView), and writes a dated report plus a CSV under
  security/reports/.

  IT DOES NOT, AND MUST NOT, STRIKE BACK. Attacking the source of an attack is
  a crime under Thailand's Computer Crime Act even when you were hit first, and
  the source is usually a spoofed address or a hijacked third party -- you would
  be attacking a victim. The lawful, effective response is here: detect, record,
  alert, and (once the stack faces a real network) block. See SECURITY.md.

  USAGE (run from the project root, or from anywhere):
    # Look at the last hour and write a report:
    powershell -ExecutionPolicy Bypass -File .\scripts\watch-attacks.ps1 -Since 1h

    # Watch live and alert as things happen (Ctrl+C to stop):
    powershell -ExecutionPolicy Bypass -File .\scripts\watch-attacks.ps1 -Follow

    # Also alert when someone merely views a page, not only on attacks:
    powershell -ExecutionPolicy Bypass -File .\scripts\watch-attacks.ps1 -Follow -AlertOnView

    # Analyse a log you saved earlier instead of asking Docker:
    powershell -ExecutionPolicy Bypass -File .\scripts\watch-attacks.ps1 -LogFile .\saved.log

  Works in Windows PowerShell 5.1 and PowerShell 7.
#>

[CmdletBinding()]
param(
    [string] $Since = '1h',                 # how far back to read (docker --since): 30m, 2h, or a date
    [switch] $Follow,                        # keep watching live
    [string] $LogFile,                       # read this file instead of Docker
    [switch] $Stdin,                         # read log lines from the pipeline (used by tests)
    [int]    $BruteForceThreshold = 5,       # this many failed-auth/flood hits from one IP => brute force
    [string] $ReportDir,                     # where reports go; default security/reports
    [switch] $AlertOnView,                   # also pop an alert for plain views
    [switch] $NoToast                        # never pop a Windows alert (console + file only)
)

$ErrorActionPreference = 'Stop'

# --- locate things -----------------------------------------------------------
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\security or ...\scripts
$projectRoot = Split-Path -Parent $scriptDir
if (-not $ReportDir) { $ReportDir = Join-Path $scriptDir 'reports' }
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

$runStamp  = (Get-Date).ToString('yyyyMMdd-HHmmss')
$csvPath   = Join-Path $ReportDir "events-$runStamp.csv"
$reportPath= Join-Path $ReportDir "report-$runStamp.md"
$alertLog  = Join-Path $ReportDir 'alerts.log'

# --- detection patterns ------------------------------------------------------
# -match is case-insensitive, so these catch upper/lower variants.
$rxTraversal = '\.\./|\.\.%2f|%2e%2e|/etc/passwd|/etc/shadow|boot\.ini|win\.ini'
$rxSqli      = "union\s+select|select\s+.+\s+from|insert\s+into|drop\s+table|update\s+.+\s+set|'\s*or\s*'?1|\s+or\s+1=1|\bsleep\(|pg_sleep|benchmark\(|xp_cmdshell|information_schema|';|--\s|/\*"
$rxXss       = '<script|%3cscript|onerror\s*=|onload\s*=|javascript:|<svg|<img\s'
$rxSensitive = '/\.env|/\.git|/\.aws|/\.ssh|id_rsa|/wp-login|/wp-admin|/phpmyadmin|\.php(\?|/|$)|/vendor/|/\.svn|/backup|/config\.|/\.DS_Store'
$rxScanner   = 'sqlmap|nikto|masscan|zgrab|acunetix|nessus|wpscan|gobuster|dirbuster|ffuf|feroxbuster|nmap'
$rxTool      = 'curl|wget|python-requests|python-urllib|go-http-client|libwww|httpie|postman|insomnia|java/|okhttp'
$rxAuthPath  = '^/(admin/(login|register-admin|forgot-password|reset-password)|admin/auth/|api/auth/)'

# --- state -------------------------------------------------------------------
$events     = New-Object System.Collections.ArrayList
$alertedIps = New-Object System.Collections.Generic.HashSet[string]

# Popups use Windows-only APIs. $env:OS is 'Windows_NT' on every Windows
# (both Windows PowerShell 5.1 and PowerShell 7) and unset elsewhere.
$script:OnWindows = ($env:OS -eq 'Windows_NT')

# --- helpers -----------------------------------------------------------------
function Convert-ToLocal {
    param([string] $IsoTime)
    try { return ([datetimeoffset]::Parse($IsoTime)).LocalDateTime }
    catch { return $null }
}

function Show-Alert {
    param([string] $Title, [string] $Message, [string] $Level)

    # An alert must NEVER crash the monitor, so the whole body is guarded. The
    # worst case is a missed popup, never a stopped watch.
    try {
        # Durable record first -- there is always a trail in alerts.log even if
        # every popup method below is unavailable (e.g. a headless session).
        $line = ('{0}  [{1}]  {2} :: {3}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Title, $Message)
        Add-Content -LiteralPath $script:alertLog -Value $line -ErrorAction SilentlyContinue

        # A beep draws the eye even if no popup library is available. Harmless
        # if the platform has no console beep.
        try { if ($Level -eq 'ATTACK') { [console]::Beep(900, 250) } } catch { }

        if ($script:NoToast -or -not $script:OnWindows) { return }

        # 1) BurntToast module, if installed -> a proper non-blocking Windows
        #    toast. Install once with:  Install-Module BurntToast -Scope CurrentUser
        try {
            if (Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue) {
                Import-Module BurntToast -ErrorAction Stop
                New-BurntToastNotification -Text $Title, $Message -ErrorAction Stop
                return
            }
        } catch { }

        # 2) No module: a COM message box that closes itself after a few seconds.
        #    Present on every Windows, needs nothing installed, and does not drag
        #    in System.Drawing (which is Windows-only and would break elsewhere).
        #    48 = warning icon. The timeout keeps a live watch from stalling.
        try {
            $sh = New-Object -ComObject WScript.Shell
            [void]$sh.Popup(("{0}`n{1}" -f $Title, $Message), 4, 'watch-attacks', 48)
        } catch { }
    } catch { }
}

function Get-Classification {
    param($e)
    $uri = [string]$e.uri
    $ua  = [string]$e.ua
    $status = 0; [void][int]::TryParse([string]$e.status, [ref]$status)

    # Decode %20/%27/... so a URL-encoded payload ("%27%20UNION%20SELECT") is
    # matched, not just a raw one. Match against both forms to be safe.
    $dec = $uri
    try { $dec = [uri]::UnescapeDataString($uri) } catch { }
    $probe = "$uri`n$dec"

    $tags = New-Object System.Collections.Generic.List[string]
    if ($probe -match $rxTraversal) { $tags.Add('Path traversal') }
    if ($probe -match $rxSqli)      { $tags.Add('SQL injection') }
    if ($probe -match $rxXss)       { $tags.Add('XSS probe') }
    if ($probe -match $rxSensitive) { $tags.Add('Sensitive-file probe') }
    if ($ua  -match $rxScanner)   { $tags.Add('Attack scanner') }
    elseif ($ua -match $rxTool)   { $tags.Add('Automated tool') }

    $xff = [string]$e.xff
    if ($xff -and $xff -ne '-' -and $xff -ne '' -and $xff -ne [string]$e.ip) { $tags.Add('X-Forwarded-For spoof') }

    $onAuth = $uri -match $rxAuthPath
    switch ($status) {
        429 { $tags.Add('Flood / rate-limited (429)') }
        403 { $tags.Add('Blocked (403)') }
        401 { $tags.Add('Failed login (401)') }
        400 { $tags.Add('Bad request (400)') }
        405 { $tags.Add('Method blocked (405)') }
    }

    # Level: an attack payload or scanner is always an attack; a 429 flood is an
    # attack; tool use / single failures / probes are suspicious; the rest is a
    # view. Per-IP brute-force escalation happens later, after aggregation.
    $attackTags = @('Path traversal','SQL injection','XSS probe','Attack scanner','Flood / rate-limited (429)')
    $level = 'VIEW'
    foreach ($t in $tags) { if ($attackTags -contains $t) { $level = 'ATTACK'; break } }
    if ($level -eq 'VIEW') {
        if ($tags.Count -gt 0) { $level = 'SUSPICIOUS' }
    }

    # Count this event toward brute-force if it is a failed/near-auth hit.
    $authFail = ($status -eq 429) -or ($onAuth -and ($status -eq 401 -or $status -eq 403 -or $status -eq 400))

    [pscustomobject]@{ Level = $level; Tags = $tags; AuthFail = $authFail; OnAuth = $onAuth }
}

function Process-Line {
    param([string] $raw)
    if ($null -eq $raw) { return }

    # Strip ANSI colour FIRST (docker colours the "service |" label, so the
    # escape codes sit in front of it), then the "service |" prefix itself.
    # [char]27 rather than `e so this also runs on Windows PowerShell 5.1.
    $esc = [char]27
    $line = $raw -replace ("$esc" + '\[[0-9;]*m'), ''
    $line = $line -replace '^\s*[\w.-]+\s*\|\s*', ''
    $line = $line.Trim()
    if (-not $line.StartsWith('{')) { return }   # error_log / other noise

    try { $e = $line | ConvertFrom-Json -ErrorAction Stop } catch { return }
    if (-not $e.ip) { return }

    $c = Get-Classification $e
    $local = Convert-ToLocal $e.time
    $when  = if ($local) { $local.ToString('yyyy-MM-dd HH:mm:ss') } else { [string]$e.time }

    $rec = [pscustomobject]@{
        Time = $when; Local = $local; IP = [string]$e.ip; XFF = [string]$e.xff
        Method = [string]$e.method; URI = [string]$e.uri; Status = [int]$e.status
        UA = [string]$e.ua; Level = $c.Level; Tags = ($c.Tags -join '; ')
        AuthFail = $c.AuthFail; OnAuth = $c.OnAuth
    }
    [void]$events.Add($rec)

    # Live console line.
    $colour = switch ($rec.Level) { 'ATTACK' {'Red'} 'SUSPICIOUS' {'Yellow'} default {'DarkGray'} }
    $mark   = switch ($rec.Level) { 'ATTACK' {'[ATTACK]    '} 'SUSPICIOUS' {'[SUSPICIOUS]'} default {'[VIEW]      '} }
    $tagtxt = if ($rec.Tags) { " <- $($rec.Tags)" } else { '' }
    Write-Host ('{0} {1}  {2,-6} {3} {4}{5}' -f $mark, $rec.Time, $rec.Method, $rec.Status, $rec.URI, $tagtxt) -ForegroundColor $colour

    # Alerts: every attack (once per IP), optionally every view.
    if ($rec.Level -eq 'ATTACK' -and -not $alertedIps.Contains($rec.IP)) {
        [void]$alertedIps.Add($rec.IP)
        Show-Alert -Level 'ATTACK' -Title "Attack from $($rec.IP)" `
                   -Message ("{0} {1} ({2}) at {3}" -f $rec.Method, $rec.URI, $rec.Tags, $rec.Time)
    }
    elseif ($AlertOnView -and $rec.Level -eq 'VIEW') {
        Show-Alert -Level 'VIEW' -Title "Viewer $($rec.IP)" `
                   -Message ("{0} {1} at {2}" -f $rec.Method, $rec.URI, $rec.Time)
    }
}

# --- report writer -----------------------------------------------------------
function Write-Report {
    if ($events.Count -eq 0) {
        Write-Host 'No requests found in that window.' -ForegroundColor DarkGray
        return
    }

    # CSV of everything.
    $events | Select-Object Time, IP, XFF, Method, URI, Status, Level, Tags |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    # Group by IP and escalate brute force. @() forces an array so .Count is
    # the number of groups even when there is only one IP (a lone GroupInfo's
    # .Count is its member count, which would otherwise mislead every total).
    $byIp = @($events | Group-Object IP)
    $ipCards = @(foreach ($g in $byIp) {
        $rows   = @($g.Group)
        $fails  = @($rows | Where-Object { $_.AuthFail }).Count
        $isBrute = $fails -ge $BruteForceThreshold
        $level = 'VIEW'
        if (@($rows | Where-Object { $_.Level -eq 'ATTACK' }).Count -gt 0) { $level = 'ATTACK' }
        elseif ($isBrute) { $level = 'ATTACK' }
        elseif (@($rows | Where-Object { $_.Level -eq 'SUSPICIOUS' }).Count -gt 0) { $level = 'SUSPICIOUS' }

        $tagCounts = @($rows | Where-Object { $_.Tags } | ForEach-Object { $_.Tags -split '; ' } |
                     Group-Object | Sort-Object Count -Descending |
                     ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count })
        $topPaths = @($rows | Group-Object { '{0} {1}' -f $_.Method, $_.URI } |
                    Sort-Object Count -Descending | Select-Object -First 5 |
                    ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count })

        [pscustomobject]@{
            IP = $g.Name
            XFF = ($rows | Where-Object { $_.XFF -and $_.XFF -ne '-' } | Select-Object -First 1 -ExpandProperty XFF)
            Level = $level; Count = $rows.Count; Fails = $fails; IsBrute = $isBrute
            First = ($rows | Sort-Object Local | Select-Object -First 1 -ExpandProperty Time)
            Last  = ($rows | Sort-Object Local | Select-Object -Last 1 -ExpandProperty Time)
            TagCounts = $tagCounts; TopPaths = $topPaths
        }
    })

    $rank = @{ 'ATTACK' = 0; 'SUSPICIOUS' = 1; 'VIEW' = 2 }
    $ipCards = @($ipCards | Sort-Object @{ E = { $rank[$_.Level] } }, @{ E = 'Count'; Descending = $true })

    $nAtk  = @($ipCards | Where-Object { $_.Level -eq 'ATTACK' }).Count
    $nSus  = @($ipCards | Where-Object { $_.Level -eq 'SUSPICIOUS' }).Count
    $nView = @($ipCards | Where-Object { $_.Level -eq 'VIEW' }).Count

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Security report -- 69-s3-cybersec')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Generated: {0} (your local time)' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('Requests examined: {0} from {1} address(es)' -f $events.Count, $byIp.Count))
    [void]$sb.AppendLine(('Verdict: {0} attacking, {1} suspicious, {2} just viewing' -f $nAtk, $nSus, $nView))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> All times are your computer''s local time. On this localhost-only lab every')
    [void]$sb.AppendLine('> address is 127.0.0.1, so "who" is whoever is on this machine; the `XFF` column')
    [void]$sb.AppendLine('> and real client IPs only become meaningful once the stack faces a network.')
    [void]$sb.AppendLine('')

    foreach ($section in @(
        @{ L='ATTACK';     H='## [ATTACK] Treated as an attack' },
        @{ L='SUSPICIOUS'; H='## [SUSPICIOUS] Worth a look' },
        @{ L='VIEW';       H='## [VIEW] Just looked around' }
    )) {
        $cards = @($ipCards | Where-Object { $_.Level -eq $section.L })
        if ($cards.Count -eq 0) { continue }
        [void]$sb.AppendLine($section.H)
        [void]$sb.AppendLine('')
        foreach ($c in $cards) {
            $who = "### $($c.IP)"
            if ($c.XFF) { $who += "  (claimed X-Forwarded-For: $($c.XFF))" }
            [void]$sb.AppendLine($who)
            [void]$sb.AppendLine(('- When: {0}  ->  {1}' -f $c.First, $c.Last))
            [void]$sb.AppendLine(('- Requests: {0}' -f $c.Count))
            if ($c.IsBrute) { [void]$sb.AppendLine(('- **Brute force: {0} failed/blocked auth attempts**' -f $c.Fails)) }
            if ($c.TagCounts) { [void]$sb.AppendLine(('- How: {0}' -f ($c.TagCounts -join ', '))) }
            if ($c.TopPaths)  { [void]$sb.AppendLine(('- Top requests: {0}' -f ($c.TopPaths -join ', '))) }
            [void]$sb.AppendLine('')
        }
    }

    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine(('Full per-request log: `{0}`' -f (Split-Path -Leaf $csvPath)))
    Set-Content -LiteralPath $reportPath -Value $sb.ToString() -Encoding UTF8

    Write-Host ''
    Write-Host ('Summary: {0} attacking, {1} suspicious, {2} viewing.' -f $nAtk, $nSus, $nView) -ForegroundColor Cyan
    Write-Host ('Report: {0}' -f $reportPath) -ForegroundColor Cyan
    Write-Host ('CSV:    {0}' -f $csvPath) -ForegroundColor Cyan
    if ($nAtk -gt 0) {
        Show-Alert -Level 'ATTACK' -Title 'Security report ready' -Message ("{0} attacking IP(s) found. See {1}" -f $nAtk, (Split-Path -Leaf $reportPath))
    }
}

# --- input sources -----------------------------------------------------------
Write-Host ("watch-attacks: {0} mode, reports -> {1}" -f ($(if ($Follow) {'live'} else {'one-shot'})), $ReportDir) -ForegroundColor Cyan
if (-not $Follow) { Write-Host 'Reading... (one-shot; add -Follow to watch live)' -ForegroundColor DarkGray }

try {
    if ($Stdin) {
        $input | ForEach-Object { Process-Line $_ }
    }
    elseif ($LogFile) {
        if (-not (Test-Path -LiteralPath $LogFile)) { throw "LogFile not found: $LogFile" }
        if ($Follow) { Get-Content -LiteralPath $LogFile -Wait | ForEach-Object { Process-Line $_ } }
        else         { Get-Content -LiteralPath $LogFile       | ForEach-Object { Process-Line $_ } }
    }
    else {
        Push-Location $projectRoot
        try {
            $dockerArgs = @('compose','logs','proxy','--since', $Since)
            if ($Follow) { $dockerArgs += '-f' }
            & docker $dockerArgs 2>$null | ForEach-Object { Process-Line $_ }
        } finally { Pop-Location }
    }
}
finally {
    # Always write the report, even on Ctrl+C in live mode.
    Write-Report
}
