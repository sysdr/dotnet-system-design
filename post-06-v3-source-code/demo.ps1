# demo.ps1 — one-shot demo helper for recording
# Prerequisite: AppHost already running (`dotnet run --project src/AppHost`)
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\demo.ps1
#
# Same traffic as the README terminal snippet:
#   POST /users/login  and  POST /orders/create
# Ports: Aspire resources API when it returns JSON, else launchSettings 5101/5102.

$ErrorActionPreference = "Stop"
$DashboardUrl = "http://localhost:15888"

function Test-HttpOk {
    param(
        [string]$Url,
        [switch]$AllowRedirect
    )
    try {
        $code = curl.exe -s -o NUL -w "%{http_code}" $Url
        if ($AllowRedirect) {
            return $code -match "^(200|301|302|303|307|308)$"
        }
        return $code -eq "200"
    } catch {
        return $false
    }
}

function Get-ServicePort {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [Parameter(Mandatory)][int]$FallbackPort
    )

    try {
        $r = Invoke-RestMethod "$DashboardUrl/api/v1/resources" -TimeoutSec 5
        if ($r -is [System.Array]) {
            $svc = $r | Where-Object { $_.name -eq $ServiceName } | Select-Object -First 1
            if ($null -ne $svc) {
                $port = $svc.services[0].allocatedEndpoint.port
                if ($port) { return [int]$port }

                $url = ($svc.urls | Where-Object { $_.url -match "http://localhost:(\d+)" } |
                    Select-Object -First 1).url
                if ($url -match ":(\d+)") { return [int]$Matches[1] }
            }
        }
    } catch {
        # API shape varies by Aspire version; fall through to launchSettings ports.
    }

    if (Test-HttpOk "http://localhost:$FallbackPort/health") {
        return $FallbackPort
    }

    throw "Could not find a live port for '$ServiceName'. Is AppHost running?"
}

Write-Host ""
Write-Host "========================================================"
Write-Host " Demo helper — Structured logging lesson"
Write-Host "========================================================"

if (-not (Test-HttpOk $DashboardUrl -AllowRedirect)) {
    Write-Host "FAIL: Aspire Dashboard not reachable at $DashboardUrl" -ForegroundColor Red
    Write-Host "Start it first:"
    Write-Host "  dotnet run --project src/AppHost"
    exit 1
}
Write-Host "Dashboard: $DashboardUrl" -ForegroundColor Green

$userPort  = Get-ServicePort -ServiceName "user-service"  -FallbackPort 5101
$orderPort = Get-ServicePort -ServiceName "order-service" -FallbackPort 5102
Write-Host "user-service  -> http://localhost:$userPort"
Write-Host "order-service -> http://localhost:$orderPort"

Write-Host ""
Write-Host "1) Trigger login (creates Structured Logs) ..."
$login = Invoke-RestMethod -Method Post -Uri "http://localhost:$userPort/users/login"
Write-Host ("   Login OK: UserId={0} Status={1}" -f $login.userId, $login.status) -ForegroundColor Green

Write-Host "2) Trigger order create (shared TraceId demo) ..."
try {
    $order = Invoke-RestMethod -Method Post -Uri "http://localhost:$orderPort/orders/create"
    Write-Host ("   Order OK: {0}" -f ($order | ConvertTo-Json -Compress)) -ForegroundColor Green
} catch {
    Write-Host "   Order create skipped/failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "3) Waiting 3s for OTLP export flush ..."
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "========================================================"
Write-Host " What to show in the browser now"
Write-Host "========================================================"
Write-Host "Open:     $DashboardUrl"
Write-Host "Click:    Structured Logs  (left sidebar)"
Write-Host "Resource: select user-service  (or clear Resource filter)"
Write-Host "Expand:   a 'Login attempt' row"
Write-Host "Look for: MachineName, ThreadId, TraceId, UserId"
Write-Host "Filter:   type MachineName in the filter bar"
Write-Host ""
Write-Host "If still empty: restart AppHost (Ctrl+C), then:"
Write-Host "  dotnet run --project src/AppHost"
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File .\demo.ps1"
Write-Host "========================================================"
Write-Host ""
