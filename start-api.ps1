$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

Write-Host 'Starting Docker Desktop...' -ForegroundColor Cyan
& docker desktop start --timeout 120

Write-Host 'Waiting for Docker Engine...' -ForegroundColor Cyan
$dockerReady = $false
for ($attempt = 1; $attempt -le 60; $attempt++) {
    $null = & docker info 2>$null
    if ($LASTEXITCODE -eq 0) {
        $dockerReady = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $dockerReady) {
    throw 'Docker Engine did not become ready. Open Docker Desktop and check its status.'
}

Write-Host 'Starting the API stack...' -ForegroundColor Cyan
& docker compose up -d --build
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Compose could not start the project.'
}

$services = @(
    @{ Name = 'Strapi API'; Url = 'http://localhost:9093/admin' },
    @{ Name = 'pgAdmin'; Url = 'http://localhost:8083' }
)

Write-Host 'Waiting for web services...' -ForegroundColor Cyan
$deadline = (Get-Date).AddMinutes(2)
foreach ($service in $services) {
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $service.Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    }

    if ($ready) {
        Write-Host ("{0}: {1}" -f $service.Name, $service.Url) -ForegroundColor Green
        Start-Process $service.Url
    } else {
        Write-Warning ("{0} did not respond yet: {1}" -f $service.Name, $service.Url)
    }
}

Write-Host ''
Write-Host 'API is running.' -ForegroundColor Green
Write-Host 'REST requests: open api.rest in VS Code.' -ForegroundColor Yellow
Write-Host 'Press Enter to close this window.' -ForegroundColor DarkGray
[void](Read-Host)
