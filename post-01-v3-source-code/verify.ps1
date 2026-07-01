# verify.ps1 — Post 1 acceptance criteria
# Hyperscale Log Monitoring Masterclass · Microsoft Platform Edition
# Post 1 of 45 · post/01-aspire-sandbox
#
# PRIMARY verification for Windows users. Requires PowerShell 7 (pwsh.exe).
# Windows PowerShell 5.1 (powershell.exe) is NOT supported.
#
# Usage (auto-detect):     .\verify.ps1
# Usage (Aspire mode):     .\verify.ps1 -Mode Aspire
# Usage (Compose mode):    .\verify.ps1 -Mode DockerCompose
#
# Auto mode picks Docker Compose when user-service, order-service, and
# otel-collector containers are running; otherwise Aspire if the dashboard
# is reachable on localhost:15888.
#
# CUMULATIVE: checks from prior posts are preserved as the series grows.
# Post 1 has no prior posts — all 7 checks below are new.

param(
    [ValidateSet("Aspire", "DockerCompose", "Auto")]
    [string]$Mode = "Auto"
)

function Resolve-VerificationMode {
    $dockerContainers = @("user-service", "order-service", "otel-collector")
    $dockerRunning = $true
    foreach ($name in $dockerContainers) {
        $status = docker inspect --format="{{.State.Status}}" $name 2>$null
        if ($status -ne "running") {
            $dockerRunning = $false
            break
        }
    }
    if ($dockerRunning) { return "DockerCompose" }

    try {
        $r = Invoke-WebRequest -Uri "http://localhost:15888" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { return "Aspire" }
    } catch { }

    return "Aspire"
}

if ($Mode -eq "Auto") {
    $Mode = Resolve-VerificationMode
}

$pass   = 0
$fail   = 0
$errors = @()

function Check-Condition {
    param(
        [string]      $Description,
        [scriptblock] $Test,
        [string]      $FailHint
    )
    Write-Host -NoNewline "  Checking: $Description ... "
    try {
        $result = & $Test
        if ($result) {
            Write-Host "PASS" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "FAIL" -ForegroundColor Red
            if ($FailHint) { Write-Host "    Hint: $FailHint" -ForegroundColor Yellow }
            $script:fail++
            $script:errors += $Description
        }
    } catch {
        Write-Host "FAIL (error: $_)" -ForegroundColor Red
        $script:fail++
        $script:errors += $Description
    }
}

Write-Host ""
Write-Host "========================================================"
Write-Host " Hyperscale Log Monitoring — Post 1 Verification"
Write-Host " Mode: $Mode · Platform: Windows 11 + Docker Desktop"
Write-Host "========================================================"
Write-Host ""
Write-Host "-- Post 1: .NET Aspire + OTel Collector ----------------"

if ($Mode -eq "Aspire") {
    # ── Aspire mode: Dashboard reachable ────────────────────────
    Check-Condition ".NET Aspire Dashboard reachable at localhost:15888" {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:15888" -UseBasicParsing -TimeoutSec 5
            $r.StatusCode -eq 200
        } catch { $false }
    } "Ensure AppHost is running: dotnet run --project src/AppHost"

    Check-Condition "user-service /health returns 200 (Aspire dynamic port)" {
        # Aspire assigns dynamic ports — find the actual port via the Dashboard API
        try {
            $resources = Invoke-RestMethod "http://localhost:15888/api/v1/resources" -TimeoutSec 5
            $us = $resources | Where-Object { $_.name -eq "user-service" }
            if (-not $us) { return $false }
            $port = $us.services[0].allocatedEndpoint.port
            $code = curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$port/health"
            $code -eq "200"
        } catch { $false }
    } "Open http://localhost:15888 and check user-service is Running"

    Check-Condition "order-service /health returns 200 (Aspire dynamic port)" {
        try {
            $resources = Invoke-RestMethod "http://localhost:15888/api/v1/resources" -TimeoutSec 5
            $os = $resources | Where-Object { $_.name -eq "order-service" }
            if (-not $os) { return $false }
            $port = $os.services[0].allocatedEndpoint.port
            $code = curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$port/health"
            $code -eq "200"
        } catch { $false }
    } "Open http://localhost:15888 and check order-service is Running"

} else {
    # ── Docker Compose mode ──────────────────────────────────────
    Check-Condition "user-service container is healthy" {
        $s = docker inspect --format="{{.State.Health.Status}}" user-service 2>&1
        $s -eq "healthy"
    } "Run: docker logs user-service"

    Check-Condition "order-service container is healthy" {
        $s = docker inspect --format="{{.State.Health.Status}}" order-service 2>&1
        $s -eq "healthy"
    } "Run: docker logs order-service"

    Check-Condition "user-service /health returns 200" {
        $code = curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/health
        $code -eq "200"
    } "Check port mapping: docker compose ps"
}

# ── Checks that apply in both modes ─────────────────────────────

Check-Condition "otel-collector container is healthy" {
    $s = docker inspect --format="{{.State.Health.Status}}" otel-collector 2>&1
    $s -eq "healthy"
} "Run: docker logs otel-collector | Select-Object -Last 20"

Check-Condition "OTel Collector received at least 1 LogRecord" {
    # Trigger a log event in whichever mode we're running
    if ($Mode -eq "Aspire") {
        try {
            $resources = Invoke-RestMethod "http://localhost:15888/api/v1/resources" -TimeoutSec 5
            $us = $resources | Where-Object { $_.name -eq "user-service" }
            $port = $us.services[0].allocatedEndpoint.port
            Invoke-RestMethod -Method Post -Uri "http://localhost:$port/users/login" | Out-Null
        } catch { }
    } else {
        curl.exe -s http://localhost:8080/users/ping | Out-Null
    }
    Start-Sleep -Seconds 6  # wait for batch processor 5s timeout
    $count = (docker logs otel-collector 2>&1 | Select-String "LogRecord" | Measure-Object).Count
    $count -gt 0
} "Check OTEL_EXPORTER_OTLP_ENDPOINT env var — must point to otel-collector:4317"

Check-Condition "LogRecord contains service.name = user-service" {
    $logs = docker logs otel-collector 2>&1
    ($logs | Select-String "user-service").Count -gt 0
} "Verify ServiceDefaults.Extensions.cs has .AddService(serviceName) call"

Check-Condition "zPages debug UI reachable at localhost:55679" {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:55679/debug/pipelinez" `
             -UseBasicParsing -TimeoutSec 5
        $r.StatusCode -eq 200
    } catch { $false }
} "Run: docker compose restart otel-collector"

# ── Summary ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================================"
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host " All $total checks passed. Post 1 complete." -ForegroundColor Green
    Write-Host ""
    Write-Host " Next: run the Manual Exploration steps in README.md"
    Write-Host " to confirm the concepts landed, not just the ports."
} else {
    Write-Host " $fail of $total checks FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host " See docs\troubleshooting.md for diagnosis steps."
    exit 1
}
Write-Host "========================================================"
Write-Host ""
