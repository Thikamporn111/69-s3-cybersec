[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')

function Read-DotEnv {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath '.env') {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $values[$Matches[1]] = $Matches[2].TrimEnd("`r")
        }
    }
    return $values
}

$envValues = Read-DotEnv
$dbUser = $envValues['DATABASE_USER']
$dbName = $envValues['DATABASE_DB']
$baseUrl = 'http://127.0.0.1:9093'

$script:pass = 0
$script:fail = 0
$script:warn = 0

function Write-Result {
    param([string] $Name, [string] $Status, [string] $Detail)
    $statusText = '{0,-13}' -f ("[$Status]")
    $color = switch ($Status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Cyan' } }
    Write-Host ("  {0} {1,-48} {2}" -f $statusText, $Name, $Detail) -ForegroundColor $color
    switch ($Status) {
        'PASS' { $script:pass++ }
        'FAIL' { $script:fail++ }
        'WARN' { $script:warn++ }
    }
}

function Get-Status {
    param([string] $Method = 'GET', [string] $Uri, [hashtable] $Headers, [string] $Body)
    $argsList = @('-s', '-o', 'NUL', '-w', '%{http_code}', '-X', $Method)
    if ($Body) { $argsList += @('--data', $Body, '-H', 'Content-Type: application/json') }
    foreach ($k in $Headers.Keys) { $argsList += @('-H', "${k}: $($Headers[$k])") }
    $argsList += $Uri
    $code = & curl.exe @argsList
    if ($LASTEXITCODE -eq 0 -and $code -match '^\d+$') { return [int]$code }
    return 0
}

Write-Host ''
Write-Host '=== 1. Stack inventory ===' -ForegroundColor Cyan
try {
    $up = @()
    foreach ($l in (& docker compose ps --format '{{.Name}}|{{.Service}}|{{.State}}|{{.Status}}' 2>$null)) {
        $c = $l -split '\|'
        $name = $c[0]; $serv = $c[1]; $state = $c[2]
        $healthy = $c[3] -match 'healthy'
        if ($state -ne 'running' -or ($serv -eq 'strapi' -and -not $healthy)) {
            Write-Result "$name ($serv)" 'FAIL' 'not running or not healthy'
        } else {
            Write-Result "$name ($serv)" 'PASS' ($c[3])
        }
    }
} catch { Write-Result 'docker compose ps' 'FAIL' $_.Exception.Message }

Write-Host ''
Write-Host '=== 2. Host exposure ===' -ForegroundColor Cyan
$listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
$a = $listeners | Where-Object { $_.LocalPort -eq 9093 -and $_.LocalAddress -notmatch '^127\.0\.0\.1$|^::1$' }
$b = $listeners | Where-Object { $_.LocalPort -eq 8083 -and $_.LocalAddress -notmatch '^127\.0\.0\.1$|^::1$' }
if ($a) { Write-Result 'port 9093 binding' 'FAIL' 'bound beyond loopback' } else { Write-Result 'port 9093 binding' 'PASS' 'loopback only' }
if ($b) { Write-Result 'port 8083 binding' 'FAIL' 'bound beyond loopback' } else { Write-Result 'port 8083 binding' 'PASS' 'loopback only' }

Write-Host ''
Write-Host '=== 3. Container hardening ===' -ForegroundColor Cyan
foreach ($c in @('69-s3-strapi', '69-s3-proxy')) {
    $info = & docker inspect $c --format '{{.HostConfig.ReadonlyRootfs}}|{{.HostConfig.CapDrop}}|{{.HostConfig.Privileged}}|{{.Config.User}}' 2>$null
    if (-not $info) { Write-Result $c 'CHECK' 'inspect failed' ; continue }
    $f = $info -split '\|'
    $ok = $f[0] -eq 'True' -and $f[1] -match 'ALL' -and $f[2] -eq 'false'
    if ($ok) { Write-Result $c 'PASS' 'readonly + cap_drop ALL + unprivileged' }
    else { Write-Result $c 'FAIL' "readonly=$($f[0]) capdrop=$($f[1]) priv=$($f[2]) user=$($f[3])" }
}

Write-Host ''
Write-Host '=== 4. Proxy behaviour ===' -ForegroundColor Cyan
$h = Get-Status -Uri "$baseUrl/_health"
if ($h -eq 204 -or $h -eq 200) { Write-Result '_health' 'PASS' "status $h" } else { Write-Result '_health' 'FAIL' "status $h" }

$dot = Get-Status -Uri "$baseUrl/.git/config"
if ($dot -eq 403) { Write-Result 'dotfile deny' 'PASS' "status $dot" } else { Write-Result 'dotfile deny' 'FAIL' "status $dot (expected 403)" }

$sc = Get-Status -Headers @{ 'User-Agent' = 'sqlmap/1.7' } -Uri "$baseUrl/_health"
if ($sc -eq 403) { Write-Result 'scanner UA block' 'PASS' "status $sc" } else { Write-Result 'scanner UA block' 'FAIL' "status $sc (expected 403)" }

$ra = Get-Status -Method POST -Uri "$baseUrl/admin/register-admin" -Body '{}'
if ($ra -ge 200 -and $ra -lt 300) { Write-Result 'register-admin' 'FAIL' "status $ra (registration open)" } else { Write-Result 'register-admin' 'PASS' "status $ra (first admin exists)" }

$ctb = Get-Status -Uri "$baseUrl/content-type-builder/content-types"
if ($ctb -eq 401 -or $ctb -eq 404) { Write-Result 'content-type-builder' 'PASS' "status $ctb (auth-gated; re-check on upgrade)" } else { Write-Result 'content-type-builder' 'WARN' "status $ctb (verify against CVE-2026-22599 patch)" }

$corsHdr = (& curl.exe -s -o NUL -D - -X OPTIONS -H 'Origin: http://evil.example' -H 'Access-Control-Request-Method: GET' "$baseUrl/api/users" 2>$null | Out-String)
if ($corsHdr -match '(?im)^access-control-allow-origin:') { Write-Result 'CORS origin allowlist' 'FAIL' 'evil origin reflected' } else { Write-Result 'CORS origin allowlist' 'PASS' 'evil origin not echoed' }

$upHdr = (& curl.exe -s -o NUL -D - "$baseUrl/uploads/" 2>$null | Out-String)
if ($upHdr -match '(?im)^content-security-policy:\s*(.+)$') { $upCsp = $Matches[1] } else { $upCsp = '' }
if ($upCsp -match 'sandbox') { Write-Result 'uploads CSP' 'PASS' 'sandbox present' } else { Write-Result 'uploads CSP' 'WARN' "csp='$upCsp'" }

Write-Host ''
Write-Host '=== 5. Database hygiene ===' -ForegroundColor Cyan
try {
    foreach ($t in @('up_users', 'admin_users')) {
        $n = (& docker compose exec -T db psql -U $dbUser -d $dbName -tAc "SELECT count(*) FROM $t WHERE reset_password_token IS NOT NULL;" 2>$null | Out-String).Trim()
        if ($n -eq '0') { Write-Result "reset tokens in $t" 'PASS' 'none' }
        else { Write-Result "reset tokens in $t" 'FAIL' "$n sensitive token(s) present" }
    }
    $un = (& docker compose exec -T db psql -U $dbUser -d $dbName -tAc "SELECT count(*) FROM up_users;" 2>$null | Out-String).Trim()
    Write-Result 'user accounts' 'CHECK' "$un account(s) registered"
} catch { Write-Result 'database check' 'FAIL' $_.Exception.Message }

Write-Host ''
Write-Host '=== 6. Secret file exposure ===' -ForegroundColor Cyan
foreach ($f in @('.env', 'api.rest')) {
    $tracked = @(& git -c safe.directory=* ls-files $f)
    if ($tracked) { Write-Result "$f tracked in git" 'FAIL' 'secret committed' }
    else { Write-Result "$f tracked in git" 'PASS' 'not in repository' }
}
$acl = & icacls '.env'
if ($acl -match 'CodexSandboxUsers.*\(I\)\(M\)') {
    Write-Result '.env ACL' 'WARN' 'CodexSandboxUsers has Modify (sandbox accounts)'
} else {
    Write-Result '.env ACL' 'PASS' 'no sandbox-group Modify found'
}

Write-Host ''
Write-Host '=== 7. Backups ===' -ForegroundColor Cyan
$bk = Get-ChildItem -Path '.\backups' -Filter '*.sql.gz.enc' -ErrorAction SilentlyContinue
if (-not $bk) {
    Write-Result 'backups' 'FAIL' 'no encrypted backup found'
} else {
    $stale = $bk | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    if ($stale) { Write-Result 'backups' 'WARN' "newest is $($bk[0].LastWriteTime.ToString('yyyy-MM-dd')) ($($bk.Count) file(s))" }
    else { Write-Result 'backups' 'PASS' "$($bk.Count) file(s), newest $($bk[0].LastWriteTime.ToString('yyyy-MM-dd'))" }
}

Write-Host ''
Write-Host '=== 8. Recent proxy traffic ===' -ForegroundColor Cyan
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$log = (& docker logs 69-s3-proxy --since 24h 2>$null | Out-String)
$ErrorActionPreference = $prevEAP
function Count-Regex { param($Pattern) ([regex]::Matches(($log -join "`n"), $Pattern)).Count }
$n4 = Count-Regex '"status":"4\d\d"'
$n5 = Count-Regex '"status":"5\d\d"'
$n429 = Count-Regex '"status":"429"'
$ns = Count-Regex '(?i)sqlmap|nikto|nessus|gobuster|ffuf|feroxbuster|acunetix|wpscan'
Write-Result '24h 4xx/5xx' $(if (($n4 + $n5) -eq 0) { 'PASS' } else { 'WARN' }) "$n4 x 4xx, $n5 x 5xx"
Write-Result '24h rate-limit (429)' $(if ($n429 -eq 0) { 'PASS' } else { 'WARN' }) "$n429 hit(s)"
Write-Result '24h scanner UA' $(if ($ns -eq 0) { 'PASS' } else { 'WARN' }) "$ns hit(s)"

Write-Host ''
Write-Host ("Summary: {0} PASS, {1} WARN, {2} FAIL" -f $script:pass, $script:warn, $script:fail)
Write-Host ''
$exit = if ($script:fail -gt 0) { 1 } else { 0 }
Write-Host ("Audit finished. Exit code {0}. Manually review:`n - topics in Check/Warn`n - CVE status of @strapi/strapi at github.com/strapi/strapi/security/advisories`n - a real restore test on a scratch database" -f $exit)
exit $exit