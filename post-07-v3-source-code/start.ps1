# start.ps1 - Ensure OTel Collector is up, then start AppHost
param([switch]$StopFirst)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if ($StopFirst) {
    & "$PSScriptRoot\stop.ps1"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Starting OTel Collector (docker :4317)"
Write-Host "========================================================"

docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker is not running. Start Docker Desktop, then re-run .\start.ps1" -ForegroundColor Red
    exit 1
}

$existing = docker ps -q --filter "name=^otel-collector$"
if (-not $existing) {
    docker rm -f otel-collector 2>$null | Out-Null
    docker run -d --name otel-collector `
        -p 4317:4317 -p 4318:4318 `
        -v "${PWD}/config/otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro" `
        otel/opentelemetry-collector-contrib:0.102.0 | Out-Null
    Start-Sleep -Seconds 2
}
Write-Host "  collector: $(docker ps --filter name=^otel-collector$ --format '{{.Status}}')"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Starting Hyperscale Log Monitoring (Post 7)"
Write-Host "========================================================"
Write-Host " Dashboard login URL prints below (http://localhost:15888/...)"
Write-Host " UserService  -> http://localhost:5080/health"
Write-Host " OrderService -> http://localhost:5081/health"
Write-Host "========================================================"
Write-Host ""

dotnet run --project src/AppHost --launch-profile http
