# verify.ps1 — Post 2 · Cumulative: 9 checks (7 from Post 1 + 2 new)
# Hyperscale Log Monitoring Masterclass · Microsoft Platform Edition
# Post 2 of 45 · post/02-serilog-appinsights
#
# Usage (Aspire): .\verify.ps1
# Usage (Compose): .\verify.ps1 -Mode DockerCompose

param(
    [ValidateSet("Aspire","DockerCompose")]
    [string]$Mode = "Aspire"
)

$pass=0; $fail=0; $errors=@()

function Get-AspireServicePort {
    param([string]$ServiceName)
    $pingPath = if ($ServiceName -eq 'user-service') { '/users/ping' } else { '/orders/ping' }
    $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1') -and $_.LocalPort -gt 1024 } |
        Select-Object -ExpandProperty LocalPort -Unique
    foreach ($port in $ports) {
        $body = curl.exe -s "http://localhost:${port}${pingPath}" 2>$null
        if ($body -match $ServiceName) { return $port }
    }
    return $null
}

function Get-OtelCollectorName {
    if ($Mode -eq 'DockerCompose') { return 'otel-collector' }
    foreach ($name in (docker ps --format '{{.Names}}' 2>$null | Where-Object { $_ -match '^otel-collector' })) {
        if ((docker logs $name 2>&1 | Select-String 'LogRecord' | Measure-Object).Count -gt 0) {
            return $name
        }
    }
    return (docker ps --filter 'name=otel-collector' --format '{{.Names}}' 2>$null | Select-Object -First 1)
}

function Check-Condition {
    param([string]$Description,[scriptblock]$Test,[string]$FailHint)
    Write-Host -NoNewline "  Checking: $Description ... "
    try {
        $result = & $Test
        if ($result) { Write-Host "PASS" -ForegroundColor Green; $script:pass++ }
        else {
            Write-Host "FAIL" -ForegroundColor Red
            if ($FailHint) { Write-Host "    Hint: $FailHint" -ForegroundColor Yellow }
            $script:fail++; $script:errors += $Description
        }
    } catch {
        Write-Host "FAIL (error: $_)" -ForegroundColor Red
        $script:fail++; $script:errors += $Description
    }
}

Write-Host ""
Write-Host "========================================================"
Write-Host " Hyperscale Log Monitoring — Post 2 Verification"
Write-Host " Mode: $Mode · Windows 11 + Docker Desktop"
Write-Host "========================================================"
Write-Host '-- Post 1 checks (all must still pass) -----------------'

if ($Mode -eq "Aspire") {
    Check-Condition "Aspire Dashboard reachable at localhost:15888" {
        try {
            $status = (Invoke-WebRequest -Uri http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode
            $status -in 200, 302
        }
        catch { $false }
    } "Ensure AppHost is running: dotnet run --project src/AppHost --launch-profile https"

    Check-Condition "user-service /health returns 200" {
        try {
            $port = Get-AspireServicePort 'user-service'
            if (-not $port) { return $false }
            (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$port/health") -eq "200"
        } catch { $false }
    } "Check user-service is Running in Aspire Dashboard"

    Check-Condition "user-service /alive returns 200" {
        try {
            $port = Get-AspireServicePort 'user-service'
            if (-not $port) { return $false }
            (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$port/alive") -eq "200"
        } catch { $false }
    } "Check user-service /alive endpoint"

    Check-Condition "order-service /health returns 200" {
        try {
            $port = Get-AspireServicePort 'order-service'
            if (-not $port) { return $false }
            (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$port/health") -eq "200"
        } catch { $false }
    } "Check order-service is Running in Aspire Dashboard"

    Check-Condition "order-service /alive returns 200" {
        try {
            $port = Get-AspireServicePort 'order-service'
            if (-not $port) { return $false }
            (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$port/alive") -eq "200"
        } catch { $false }
    }
} else {
    Check-Condition "user-service /health returns 200" {
        (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/health) -eq "200"
    }
    Check-Condition "order-service /health returns 200" {
        (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8081/health) -eq "200"
    }
    Check-Condition "otel-collector reachable" {
        (curl.exe -s -o NUL -w "%{http_code}" http://localhost:55679/debug/pipelinez) -eq "200"
    }
}

Check-Condition "OTel Collector received at least 1 LogRecord" {
    $collector = Get-OtelCollectorName
    if ($Mode -eq "Aspire") {
        try {
            $port = Get-AspireServicePort 'user-service'
            if ($port) {
                Invoke-RestMethod -Method Post "http://localhost:$port/users/login" | Out-Null
            }
        } catch {}
    } else {
        curl.exe -s http://localhost:8080/users/ping | Out-Null
    }
    Start-Sleep -Seconds 6
    (docker logs $collector 2>&1 | Select-String "LogRecord" | Measure-Object).Count -gt 0
} "Check OTEL_EXPORTER_OTLP_ENDPOINT environment variable"

Check-Condition "LogRecord contains service.name=user-service" {
    $collector = Get-OtelCollectorName
    (docker logs $collector 2>&1 | Select-String "user-service" | Measure-Object).Count -gt 0
}

Write-Host '-- Post 2 checks (new this post) -----------------------'

Check-Condition -Description "Serilog MachineName enricher present in LogRecord" -Test {
    $collector = Get-OtelCollectorName
    $logs = docker logs $collector 2>&1
    ($logs | Select-String "MachineName" | Measure-Object).Count -gt 0
} -FailHint "Check Serilog.Enrichers.Environment and WithMachineName in ServiceDefaults Extensions.cs"

Check-Condition -Description "AppInsights ExcludedTypes=Exception configured in user-service" -Test {
    # ExcludedTypes prevents exception telemetry from being sampled away.
    # This check reads appsettings.json directly - no runtime dependency.
    $config = Get-Content src/UserService/appsettings.json -ErrorAction SilentlyContinue | ConvertFrom-Json
    $excluded = $config.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes
    $excluded -eq "Exception"
} -FailHint "Set AdaptiveSamplingSettings.ExcludedTypes to Exception in user-service appsettings.json"

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================================"
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host " All $total checks passed. Post 2 complete." -ForegroundColor Green
    Write-Host ""
    Write-Host " Next: run the Manual Exploration steps in README.md"
    Write-Host " to confirm Serilog enrichers appear as queryable columns"
    Write-Host " and ExcludedTypes protects exception telemetry."
} else {
    Write-Host " $fail of $total checks FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    Write-Host " See docs\troubleshooting.md for diagnosis steps."
    exit 1
}
Write-Host "========================================================"
Write-Host ""
