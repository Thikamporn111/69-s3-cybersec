# End-to-end check of the user auth flow: register, login, profile, forgot
# password, reset, login again.
#
# The reset token is read straight out of PostgreSQL into a variable, used, and
# then cleared. It is never printed and never written to a file, which is the
# whole point of using this script instead of pasting a token into api.rest:
# Strapi stores reset_password_token in plain text and never expires it, so a
# token left lying around stays a working account-takeover credential.
#
#   .\run-user-reset-test.ps1            # keeps the test user for inspection
#   .\run-user-reset-test.ps1 -Cleanup   # deletes the test user when done

[CmdletBinding()]
param(
    [switch] $Cleanup
)

$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

function Read-DotEnv {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath '.env') {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            # Trim a trailing CR so a CRLF .env does not append it to a password.
            $values[$Matches[1]] = $Matches[2].TrimEnd("`r")
        }
    }
    return $values
}

function Get-RequiredEnv {
    param([hashtable] $Values, [string] $Name)
    if (-not $Values[$Name] -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
        throw "$Name is not set in .env. Fill it with its own random value; this script no longer carries a fallback password."
    }
    return $Values[$Name]
}

function Invoke-JsonRequest {
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Body,
        [hashtable] $Headers
    )

    try {
        $request = @{
            UseBasicParsing = $true
            Method = $Method
            Uri = $Uri
            ContentType = 'application/json'
        }
        if ($Body) { $request.Body = ($Body | ConvertTo-Json -Compress) }
        if ($Headers) { $request.Headers = $Headers }
        $response = Invoke-WebRequest @request
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $response.Content }
    } catch {
        $response = $_.Exception.Response
        if (-not $response) { throw }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $reader.ReadToEnd() }
    }
}

function Assert-Success {
    param([string] $Name, $Result)
    Write-Host ("{0,-22} {1}" -f $Name, $Result.Status)
    if ($Result.Status -eq 429) {
        throw ("{0} was rate limited (429). The Nginx auth zone allows 10 credential requests a minute; wait a minute and run again." -f $Name)
    }
    if ($Result.Status -lt 200 -or $Result.Status -ge 300) {
        throw ("{0} failed: {1}" -f $Name, $Result.Body)
    }
}

function Invoke-Psql {
    param([Parameter(Mandatory)] [string] $Sql)
    $out = (& docker compose exec -T db psql -U $script:dbUser -d $script:dbName -tAc $Sql 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'psql call failed. Is the stack running?' }
    return $out.Trim()
}

$envValues = Read-DotEnv
$baseUrl = 'http://127.0.0.1:9093'
$password = Get-RequiredEnv $envValues 'REST_USER_PASSWORD'
$resetPassword = Get-RequiredEnv $envValues 'REST_RESET_PASSWORD'
$script:dbUser = Get-RequiredEnv $envValues 'DATABASE_USER'
$script:dbName = Get-RequiredEnv $envValues 'DATABASE_DB'

$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$username = "resttest-$stamp"
$email = "$username@cybersec.local"
$safeEmail = $email.Replace("'", "''")

Write-Host "Testing user auth with $email" -ForegroundColor Cyan

try {
    $register = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/register" -Body @{ username = $username; email = $email; password = $password }
    Assert-Success 'Register' $register

    $login = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/local" -Body @{ identifier = $email; password = $password }
    Assert-Success 'Login' $login
    $jwt = ($login.Body | ConvertFrom-Json).jwt

    $profile = Invoke-JsonRequest -Method GET -Uri "$baseUrl/api/users/me" -Headers @{ Authorization = "Bearer $jwt" }
    Assert-Success 'Profile' $profile

    $forgot = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/forgot-password" -Body @{ email = $email }
    Assert-Success 'Forgot Password' $forgot

    $token = Invoke-Psql "SELECT reset_password_token FROM up_users WHERE email = '$safeEmail';"
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'Could not read the reset token from PostgreSQL.'
    }

    $reset = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/reset-password" -Body @{ code = $token; password = $resetPassword; passwordConfirmation = $resetPassword }
    Assert-Success 'Reset Password' $reset

    $loginAfterReset = Invoke-JsonRequest -Method POST -Uri "$baseUrl/api/auth/local" -Body @{ identifier = $email; password = $resetPassword }
    Assert-Success 'Login after reset' $loginAfterReset
} finally {
    # Always clear the token, including on failure. Strapi nulls it on a
    # successful reset, but a run that stopped halfway would otherwise leave a
    # live token in the table.
    $token = $null
    try {
        $null = Invoke-Psql "UPDATE up_users SET reset_password_token = NULL WHERE email = '$safeEmail' AND reset_password_token IS NOT NULL;"
        Write-Host ("{0,-22} cleared" -f 'Reset token') -ForegroundColor DarkGray
    } catch {
        Write-Warning 'Could not clear reset_password_token. Run scripts\purge-reset-tokens.ps1.'
    }

    if ($Cleanup) {
        try {
            $null = Invoke-Psql "DELETE FROM up_users WHERE email = '$safeEmail';"
            Write-Host ("{0,-22} deleted" -f 'Test user') -ForegroundColor DarkGray
        } catch {
            Write-Warning "Could not delete the test user $email."
        }
    }
}

Write-Host ''
Write-Host 'User reset flow completed successfully.' -ForegroundColor Green
Write-Host 'The token was read from PostgreSQL, used once, and cleared. It was never printed.' -ForegroundColor DarkGray
if (-not $Cleanup) {
    Write-Host "Test user $email is still in up_users so you can inspect it in pgAdmin." -ForegroundColor DarkGray
    Write-Host 'Run with -Cleanup to delete it, or delete the resttest-* rows when you are done.' -ForegroundColor DarkGray
}
