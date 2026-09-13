# Clear password-reset tokens from the lab database.
#
# Strapi Community Edition stores `reset_password_token` in plain text in both
# `up_users` and `admin_users`, and it sets no expiry. A token therefore stays a
# working one-shot account-takeover credential from the moment Forgot Password
# is called until someone uses it -- which could be months. Anyone who can read
# the database (pgAdmin, a copy of ./data/postgres, an unencrypted dump) can
# take over any account that has a token sitting in its row.
#
# There is no Strapi setting that fixes this. Clearing the tokens is the
# control. Run this after any forgot-password test, and on a schedule if the
# lab is left running.
#
#   .\scripts\purge-reset-tokens.ps1              # clears every token
#   .\scripts\purge-reset-tokens.ps1 -OlderThanMinutes 15
#   .\scripts\purge-reset-tokens.ps1 -WhatIf      # count only, change nothing

[CmdletBinding()]
param(
    # 0 clears every token. Any other value keeps tokens whose row was touched
    # within that many minutes, which approximates an expiry window: Strapi
    # bumps updated_at when it writes the token.
    [int] $OlderThanMinutes = 0,
    [switch] $WhatIf
)

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
if (-not $dbUser -or -not $dbName) {
    throw 'DATABASE_USER and DATABASE_DB must be set in .env'
}

function Invoke-Psql {
    param([Parameter(Mandatory)] [string] $Sql)
    $out = (& docker compose exec -T db psql -U $dbUser -d $dbName -tAc $Sql 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'psql call failed. Is the stack running? (docker compose ps)' }
    return $out.Trim()
}

if ($OlderThanMinutes -gt 0) {
    $age = "AND updated_at < now() - interval '$OlderThanMinutes minutes'"
    Write-Host "Clearing reset tokens older than $OlderThanMinutes minute(s)." -ForegroundColor Cyan
} else {
    $age = ''
    Write-Host 'Clearing every reset token.' -ForegroundColor Cyan
}

$total = 0
foreach ($table in @('up_users', 'admin_users')) {
    $where = "reset_password_token IS NOT NULL $age"
    $count = [int](Invoke-Psql "SELECT count(*) FROM $table WHERE $where;")

    if ($WhatIf) {
        Write-Host ("  {0,-14} {1} token(s) would be cleared" -f $table, $count)
    } else {
        if ($count -gt 0) {
            $null = Invoke-Psql "UPDATE $table SET reset_password_token = NULL WHERE $where;"
        }
        Write-Host ("  {0,-14} {1} token(s) cleared" -f $table, $count)
    }
    $total += $count
}

Write-Host ''
if ($WhatIf) {
    Write-Host "$total token(s) match. Nothing was changed." -ForegroundColor Yellow
} elseif ($total -eq 0) {
    Write-Host 'No live reset tokens were in the database.' -ForegroundColor Green
} else {
    Write-Host "$total token(s) cleared. Those reset links no longer work." -ForegroundColor Green
    Write-Host 'Anyone mid-reset has to call Forgot Password again.' -ForegroundColor DarkGray
}
