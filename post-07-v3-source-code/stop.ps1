# stop.ps1 - Stop Post 7 AppHost stack cleanly so a restart binds ports again.
# Usage:
#   .\stop.ps1
#   .\stop.ps1 -AlsoDockerCompose   # also runs: docker compose down

param(
    [switch]$AlsoDockerCompose
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Stopping Hyperscale Log Monitoring (Post 7)"
Write-Host "========================================================"
Write-Host ""

function Stop-ByName {
    param([string[]]$Names)
    foreach ($name in $Names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  Stopping process: $($_.ProcessName) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stop-ByPort {
    param([int[]]$Ports)
    foreach ($port in $Ports) {
        $conns = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)
        $processIds = @($conns | Select-Object -ExpandProperty OwningProcess -Unique)
        foreach ($processId in $processIds) {
            if ($null -eq $processId -or $processId -eq 0) { continue }
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($null -ne $proc) {
                Write-Host "  Freeing port $port - $($proc.ProcessName) (PID $processId)"
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Write-Host "-- Aspire processes --------------------------------"
Stop-ByName @(
    "AppHost",
    "Aspire.Dashboard",
    "dcp",
    "dcpctrl",
    "UserService",
    "OrderService"
)

Write-Host ""
Write-Host "-- Ports -----------------------------------------------"
Stop-ByPort @(
    15888,
    18889,
    18890,
    18891,
    5080,
    5081,
    4317,
    4318,
    15579,
    55679,
    8080,
    8081
)

Write-Host ""
Write-Host "-- Docker containers -----------------------------------"
$collectorIds = @(docker ps -aq --filter "name=otel" 2>$null)
if ($collectorIds.Count -gt 0 -and $collectorIds[0]) {
    foreach ($id in $collectorIds) {
        Write-Host "  Removing container $id"
        docker rm -f $id 2>$null | Out-Null
    }
}
else {
    Write-Host "  No otel containers running"
}

if ($AlsoDockerCompose) {
    Write-Host ""
    Write-Host "-- docker compose down ---------------------------------"
    if (Test-Path "docker-compose.yml") {
        docker compose down 2>&1 | ForEach-Object { Write-Host "  $_" }
    }
}

Start-Sleep -Seconds 1

Write-Host ""
Write-Host "-- Verify ports free -----------------------------------"
$stillBusy = @()
foreach ($port in @(15888, 18891, 5080, 5081, 4317)) {
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($busy) {
        $stillBusy += $port
        Write-Host "  STILL IN USE: $port" -ForegroundColor Yellow
    }
    else {
        Write-Host "  free: $port" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "========================================================"
if ($stillBusy.Count -eq 0) {
    Write-Host " Stack stopped. Restart with:" -ForegroundColor Green
    Write-Host "   .\start.ps1"
    Write-Host "   # or:  dotnet run --project src/AppHost --launch-profile http"
}
else {
    Write-Host " Some ports still busy: $($stillBusy -join ', ')" -ForegroundColor Yellow
    Write-Host " Close any leftover terminal running AppHost, then re-run .\stop.ps1"
}
Write-Host "========================================================"
Write-Host ""
