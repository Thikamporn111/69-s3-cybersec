# End-to-end check of api.rest Section 3 (Content section): for Student,
# Subject and Teacher run 1 Create, 2 List All, 3 List with ID, 4 Update, and
# verify each response body, not just the status code.
#
# A fresh throwaway user is registered and logged in for the Bearer token, so
# the REST_USER_* account in .env is left untouched. Record payloads come from
# REST_STUDENT_* / REST_SUBJECT_* / REST_TEACHER_* in .env; each code gets a
# per-run suffix because the code fields are unique.
#
#   .\run-content-test.ps1            # keeps the records for inspection
#   .\run-content-test.ps1 -Cleanup   # deletes the records and the test user

[CmdletBinding()]
param(
    [switch] $Cleanup
)

$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

function Read-DotEnv {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath '.env' -Encoding UTF8) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $values[$Matches[1]] = $Matches[2].TrimEnd("`r")
        }
    }
    return $values
}

function Get-RequiredEnv {
    param([hashtable] $Values, [string] $Name)
    if (-not $Values[$Name] -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
        throw "$Name is not set in .env. See .env.example."
    }
    return $Values[$Name]
}

function Invoke-JsonRequest {
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST', 'PUT')] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Body,
        [hashtable] $Headers
    )

    try {
        $request = @{
            UseBasicParsing = $true
            Method = $Method
            Uri = $Uri
            ContentType = 'application/json; charset=utf-8'
        }
        # Send UTF-8 bytes; Windows PowerShell would otherwise encode non-ASCII
        # names (e.g. Thai) with the ANSI code page.
        if ($Body) { $request.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress -Depth 5)) }
        if ($Headers) { $request.Headers = $Headers }
        $response = Invoke-WebRequest @request
        $content = [Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $content }
    } catch {
        $response = $_.Exception.Response
        if (-not $response) { throw }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $reader.ReadToEnd() }
    }
}

function Assert-Success {
    param([string] $Name, $Result, [scriptblock] $Check, [string] $Detail = '')
    if ($Result.Status -eq 429) {
        throw ("{0} was rate limited (429). Wait a minute and run again." -f $Name)
    }
    if ($Result.Status -eq 403) {
        throw ("{0} returned 403. Rebuild Strapi so its bootstrap grants the Authenticated role create/find/findOne/update (see README, Section 3)." -f $Name)
    }
    if ($Result.Status -lt 200 -or $Result.Status -ge 300) {
        throw ("{0} failed ({1}): {2}" -f $Name, $Result.Status, $Result.Body)
    }
    $json = $Result.Body | ConvertFrom-Json
    if ($Check -and -not (& $Check $json)) {
        throw ("{0} returned {1} but the body is wrong: {2}" -f $Name, $Result.Status, $Result.Body)
    }
    Write-Host ("  {0,-22} {1} {2}" -f $Name, $Result.Status, $Detail)
    return $json
}

function Invoke-Psql {
    param([Parameter(Mandatory)] [string] $Sql)
    $out = (& docker compose exec -T db psql -U $script:dbUser -d $script:dbName -tAc $Sql 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'psql call failed. Is the stack running?' }
    return $out.Trim()
}

$envValues = Read-DotEnv
$appHost = Get-RequiredEnv $envValues 'APP_HOST'
$appPort = Get-RequiredEnv $envValues 'APP_PORT'
$baseUrl = "http://${appHost}:$appPort"
$password = Get-RequiredEnv $envValues 'REST_USER_PASSWORD'
$script:dbUser = Get-RequiredEnv $envValues 'DATABASE_USER'
$script:dbName = Get-RequiredEnv $envValues 'DATABASE_DB'

$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$username = "contenttest-$stamp"
$email = "$username@cybersec.local"

# Section, route, table, payload, and the field Update changes.
$sections = @(
    @{
        Title = '3.1 Student'; Route = 'students'; Table = 'students'; Field = 'firstname'
        Data = @{
            studentCode = "$(Get-RequiredEnv $envValues 'REST_STUDENT_CODE')-$stamp"
            firstname = Get-RequiredEnv $envValues 'REST_STUDENT_FIRSTNAME'
            lastname = Get-RequiredEnv $envValues 'REST_STUDENT_LASTNAME'
            email = Get-RequiredEnv $envValues 'REST_STUDENT_EMAIL'
        }
    },
    @{
        Title = '3.2 Subject'; Route = 'subjects'; Table = 'subjects'; Field = 'name'
        Data = @{
            code = "$(Get-RequiredEnv $envValues 'REST_SUBJECT_CODE')-$stamp"
            name = Get-RequiredEnv $envValues 'REST_SUBJECT_NAME'
            credit = [int](Get-RequiredEnv $envValues 'REST_SUBJECT_CREDIT')
        }
    },
    @{
        Title = '3.3 Teacher'; Route = 'teachers'; Table = 'teachers'; Field = 'firstname'
        Data = @{
            teacherCode = "$(Get-RequiredEnv $envValues 'REST_TEACHER_CODE')-$stamp"
            firstname = Get-RequiredEnv $envValues 'REST_TEACHER_FIRSTNAME'
            lastname = Get-RequiredEnv $envValues 'REST_TEACHER_LASTNAME'
            email = Get-RequiredEnv $envValues 'REST_TEACHER_EMAIL'
        }
    }
)

Write-Host "Testing Section 3 as $email" -ForegroundColor Cyan
$created = @()

try {
    $register = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/register" -Body @{ username = $username; email = $email; password = $password }
    $null = Assert-Success '2.1 User Register' $register
    $login = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/login" -Body @{ identifier = $email; password = $password }
    $jwt = (Assert-Success '2.2 User Login' $login { param($j) $j.jwt }).jwt
    $auth = @{ Authorization = "Bearer $jwt" }

    foreach ($s in $sections) {
        $n = $s.Title.Substring(0, 3)
        Write-Host $s.Title -ForegroundColor Cyan

        $r = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/$($s.Route)" -Headers $auth -Body @{ data = $s.Data }
        $id = (Assert-Success "$n.1 Create" $r { param($j) $j.data.documentId }).data.documentId
        $created += @{ Table = $s.Table; Id = $id }

        $r = Invoke-JsonRequest -Method GET -Uri "$baseUrl/api/$($s.Route)" -Headers $auth
        $list = Assert-Success "$n.2 List All" $r { param($j) @($j.data | Where-Object { $_.documentId -eq $id }).Count -eq 1 }
        Write-Host ("  {0,-22} {1} record(s), new one included" -f '', @($list.data).Count) -ForegroundColor DarkGray

        $r = Invoke-JsonRequest -Method GET -Uri "$baseUrl/api/$($s.Route)/$id" -Headers $auth
        $null = Assert-Success "$n.3 List with ID" $r { param($j) $j.data.documentId -eq $id } "documentId=$id"

        $updated = $s.Data.Clone()
        $updated[$s.Field] = "$($s.Data[$s.Field]) (updated)"
        $r = Invoke-JsonRequest -Method PUT -Uri "$baseUrl/api/$($s.Route)/$id" -Headers $auth -Body @{ data = $updated }
        $null = Assert-Success "$n.4 Update" $r { param($j) $j.data.($s.Field) -eq $updated[$s.Field] } "$($s.Field)=$($updated[$s.Field])"
    }
} finally {
    $jwt = $null
    if ($Cleanup) {
        try {
            # The API deliberately exposes no delete route, so clean up in SQL.
            foreach ($c in $created) {
                $null = Invoke-Psql "DELETE FROM $($c.Table) WHERE document_id = '$($c.Id)';"
            }
            $null = Invoke-Psql "DELETE FROM up_users WHERE email = '$email';"
            Write-Host ("  {0,-22} deleted" -f 'Test records + user') -ForegroundColor DarkGray
        } catch {
            Write-Warning "Cleanup failed. Remove $username and its records by hand."
        }
    }
}

Write-Host ''
Write-Host 'Section 3 passed: 12/12 requests.' -ForegroundColor Green
if (-not $Cleanup) {
    Write-Host "Records and user $email are kept for inspection in pgAdmin. Run with -Cleanup to remove them." -ForegroundColor DarkGray
}
