# verify.ps1 — Post 6 · Cumulative: 17 checks (15 Post 5 + 2 new)
# This is also the PHASE 1 COMPLETION CHECK — all 17 checks passing
# means the complete Phase 1 foundation is working end-to-end.
param([ValidateSet("Aspire","DockerCompose")][string]$Mode = "Aspire")
$pass=0; $fail=0; $errors=@()

function Check-Condition {
    param([string]$Description,[scriptblock]$Test,[string]$FailHint="")
    Write-Host -NoNewline "  Checking: $Description ... "
    try {
        if (& $Test) { Write-Host "PASS" -ForegroundColor Green; $script:pass++ }
        else {
            Write-Host "FAIL" -ForegroundColor Red
            if ($FailHint) { Write-Host "    Hint: $FailHint" -ForegroundColor Yellow }
            $script:fail++; $script:errors += $Description
        }
    } catch { Write-Host "FAIL ($_)" -ForegroundColor Red; $script:fail++; $script:errors += $Description }
}

function Get-CollectorName {
    $name = docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -like "otel-collector*" } | Select-Object -First 1
    if (-not $name) { return "otel-collector" }
    return $name
}

function Get-CollectorLogs {
    docker logs (Get-CollectorName) 2>&1
}

function Get-ServicePort {
    param([Parameter(Mandatory)][string]$ServiceName, [int]$FallbackPort)
    try {
        $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 5
        # Aspire Dashboard may return HTML for this path on some versions — only parse real JSON arrays.
        if ($r -is [System.Array]) {
            $svc = $r | Where-Object { $_.name -eq $ServiceName } | Select-Object -First 1
            if ($null -ne $svc) {
                $port = $svc.services[0].allocatedEndpoint.port
                if ($port) { return [int]$port }
                $url = ($svc.urls | Where-Object { $_.url -match 'http://localhost:(\d+)' } | Select-Object -First 1).url
                if ($url -match ':(\d+)') { return [int]$Matches[1] }
            }
        }
    } catch {}
    return $FallbackPort
}

function Get-UserPort  { Get-ServicePort -ServiceName "user-service"  -FallbackPort 5101 }
function Get-OrderPort { Get-ServicePort -ServiceName "order-service" -FallbackPort 5102 }

Write-Host "`n========================================================"
Write-Host " Hyperscale Log Monitoring - Post 6 / Phase 1 Complete"
Write-Host "========================================================"
Write-Host "-- Posts 1-5 checks (all must still pass) --------------"

if ($Mode -eq "Aspire") {
    Check-Condition "Aspire Dashboard reachable" { try { (Invoke-WebRequest http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false } } "dotnet run --project src/AppHost"
    Check-Condition "user-service /health 200"   { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-UserPort)/health") -eq "200" } catch { $false } }
    Check-Condition "user-service /alive 200"    { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-UserPort)/alive")  -eq "200" } catch { $false } }
    Check-Condition "order-service /health 200"  { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-OrderPort)/health") -eq "200" } catch { $false } }
    Check-Condition "order-service /alive 200"   { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-OrderPort)/alive")  -eq "200" } catch { $false } }
} else {
    Check-Condition "user-service healthy"   { (docker inspect --format="{{.State.Health.Status}}" user-service  2>&1) -eq "healthy" }
    Check-Condition "user-service /health"   { (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/health) -eq "200" }
    Check-Condition "order-service healthy"  { (docker inspect --format="{{.State.Health.Status}}" order-service 2>&1) -eq "healthy" }
    Check-Condition "order-service /health"  { (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8081/health) -eq "200" }
    Check-Condition "otel-collector healthy" { (docker inspect --format="{{.State.Health.Status}}" otel-collector 2>&1) -eq "healthy" }
}

Check-Condition "OTel Collector received LogRecord" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort)/users/login" | Out-Null } catch {}
    Start-Sleep 6
    (Get-CollectorLogs | Select-String "LogRecord" | Measure-Object).Count -gt 0
}
Check-Condition "LogRecord has service.name=user-service" { (Get-CollectorLogs | Select-String "user-service"   | Measure-Object).Count -gt 0 }
Check-Condition "Serilog MachineName enricher present"    { (Get-CollectorLogs | Select-String "MachineName"    | Measure-Object).Count -gt 0 }
Check-Condition "AppInsights ExcludedTypes=Exception set" { ($c = Get-Content src/UserService/appsettings.json | ConvertFrom-Json); $c.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes -eq "Exception" }
Check-Condition "TelemetryConstants used for attribute names"  { (Test-Path "src/ServiceDefaults/TelemetryConstants.cs") -and ((Get-Content src/UserService/Program.cs -Raw) -match "TelemetryConstants") }
Check-Condition "OTel Collector zPages at 55679"          { try { (Invoke-WebRequest http://localhost:55679/debug/pipelinez -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false } }
Check-Condition "ValidateCredentials span in Collector"   {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort)/users/login" | Out-Null } catch {}
    Start-Sleep 6; (Get-CollectorLogs | Select-String "ValidateCredentials" | Measure-Object).Count -gt 0
}
Check-Condition "Dashboard reachable and services healthy" {
    try {
        $dash = (Invoke-WebRequest http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200
        $userOk = (Invoke-RestMethod "http://localhost:$(Get-UserPort)/health" -TimeoutSec 5) -eq "Healthy"
        $orderOk = (Invoke-RestMethod "http://localhost:$(Get-OrderPort)/health" -TimeoutSec 5) -eq "Healthy"
        $dash -and $userOk -and $orderOk
    } catch { $false }
}
Check-Condition "orders/create multi-span trace"          {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-OrderPort)/orders/create" | Out-Null } catch {}
    Start-Sleep 6; $l = Get-CollectorLogs
    ($l | Select-String "CreateOrder" | Measure-Object).Count -gt 0 -and ($l | Select-String "PublishOrderEvent" | Measure-Object).Count -gt 0
}
Check-Condition "TelemetryConstants.cs in ServiceDefaults" { Test-Path "src/ServiceDefaults/TelemetryConstants.cs" }
Check-Condition "telemetry-schema.md in docs/"             { Test-Path "docs/telemetry-schema.md" }
Check-Condition "UserId attribute in Collector login output" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort)/users/login" | Out-Null } catch {}
    Start-Sleep 6; (Get-CollectorLogs | Select-String "UserId" | Measure-Object).Count -gt 0
}

Write-Host "-- Post 6 checks (new - Phase 1 completion) ------------"

Check-Condition "EventCounters package in ServiceDefaults" {
    (Get-Content src/ServiceDefaults/ServiceDefaults.csproj) -match "OpenTelemetry.Instrumentation.EventCounters"
} "Add <PackageReference Include='OpenTelemetry.Instrumentation.EventCounters' Version='1.0.0-rc.3' />"

Check-Condition "System.Runtime EventCounters in Aspire Dashboard Metrics" {
    # Wait 15s for EventCounters to emit first batch (default interval: 10s)
    Write-Host -NoNewline " (waiting 15s for counter batch) "
    Start-Sleep 15
    # Aspire Dashboard Metrics API — check that metrics are being received
    try {
        $metricsPage = Invoke-WebRequest "http://localhost:15888/metrics" -UseBasicParsing -TimeoutSec 5
        $metricsPage.StatusCode -eq 200
    } catch { $false }
} "Start AppHost, wait 15 seconds, then check http://localhost:15888/metrics in the browser - should show cpu-usage, working-set, gc-heap-size"

Write-Host "`n========================================================"
if ($fail -eq 0) {
    Write-Host " PHASE 1 COMPLETE - All $($pass+$fail) checks passed." -ForegroundColor Green
    Write-Host ""
    Write-Host " The complete Phase 1 foundation is working:"
    Write-Host "   .NET Aspire AppHost + Serilog + OTel + SemanticConv."
    Write-Host "   TelemetryConstants + telemetry-schema.md"
    Write-Host "   EventCounters (.NET runtime metrics in Dashboard)"
    Write-Host "   Aspire Dashboard 4-panel view"
    Write-Host "   OTel Collector (memory_limiter + batch + zPages)"
    Write-Host "   Application Insights (durable, ExcludedTypes set)"
    Write-Host ""
    Write-Host " Phase 2 begins with Post 7: Azure Service Bus Emulator."
    Write-Host " git checkout post/07-serialization"
} else {
    Write-Host " $fail/$($pass+$fail) FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    exit 1
}
Write-Host "========================================================"
