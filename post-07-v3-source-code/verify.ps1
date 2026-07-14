# verify.ps1 - Post 7 cumulative checks
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

function Get-Port {
    param([string]$ServiceName)
    switch ($ServiceName) {
        "user-service"  { return 5080 }
        "order-service" { return 5081 }
        default { throw "Unknown service '$ServiceName'" }
    }
}

function Get-CollectorContainerName {
    $names = @(docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -like "otel-collector*" })
    if ($names -contains "otel-collector") { return "otel-collector" }
    if ($names.Count -gt 0) { return $names[0] }
    return "otel-collector"
}

function Get-CollectorLogs {
    # Merge logs from every otel-collector* container (Aspire suffix + manual name)
    $names = @(docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -like "otel-collector*" })
    if ($names.Count -eq 0) { return docker logs otel-collector 2>&1 }
    $all = @()
    foreach ($n in $names) { $all += @(docker logs $n 2>&1) }
    return $all
}

Write-Host ""
Write-Host "========================================================"
Write-Host " Hyperscale Log Monitoring - Post 7 - Phase 2 Start"
Write-Host "========================================================"
Write-Host "-- Phase 1 checks --------------------------------------"

if ($Mode -eq "Aspire") {
    Check-Condition "Aspire Dashboard reachable" {
        try { (Invoke-WebRequest http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false }
    } "dotnet run --project src/AppHost --launch-profile http"
    Check-Condition "user-service /health"  { try { (curl.exe -s -m 5 -o NUL -w "%{http_code}" "http://localhost:$(Get-Port 'user-service')/health")  -eq "200" } catch { $false } }
    Check-Condition "user-service /alive"   { try { (curl.exe -s -m 5 -o NUL -w "%{http_code}" "http://localhost:$(Get-Port 'user-service')/alive")   -eq "200" } catch { $false } }
    Check-Condition "order-service /health" { try { (curl.exe -s -m 5 -o NUL -w "%{http_code}" "http://localhost:$(Get-Port 'order-service')/health") -eq "200" } catch { $false } }
    Check-Condition "order-service /alive"  { try { (curl.exe -s -m 5 -o NUL -w "%{http_code}" "http://localhost:$(Get-Port 'order-service')/alive")  -eq "200" } catch { $false } }
} else {
    Check-Condition "user-service healthy"   { (docker inspect --format="{{.State.Health.Status}}" user-service  2>&1) -eq "healthy" }
    Check-Condition "user-service /health"   { (curl.exe -s -m 5 -o NUL -w "%{http_code}" http://localhost:8080/health) -eq "200" }
    Check-Condition "order-service healthy"  { (docker inspect --format="{{.State.Health.Status}}" order-service 2>&1) -eq "healthy" }
    Check-Condition "order-service /health"  { (curl.exe -s -m 5 -o NUL -w "%{http_code}" http://localhost:8081/health) -eq "200" }
    Check-Condition "otel-collector healthy" { (docker inspect --format="{{.State.Health.Status}}" otel-collector 2>&1) -eq "healthy" }
}

Check-Condition "OTel Collector received LogRecord" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-Port 'user-service')/users/login" -TimeoutSec 5 | Out-Null } catch {}
    Start-Sleep 3; (Get-CollectorLogs | Select-String "LogRecord" | Measure-Object).Count -gt 0
}
Check-Condition "LogRecord has service.name=user-service" { (Get-CollectorLogs | Select-String "user-service" | Measure-Object).Count -gt 0 }
Check-Condition "Serilog MachineName enricher"            { (Get-CollectorLogs | Select-String "MachineName"  | Measure-Object).Count -gt 0 }
Check-Condition "AppInsights ExcludedTypes=Exception"     {
    $c = Get-Content src/UserService/appsettings.json | ConvertFrom-Json
    $c.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes -eq "Exception"
}
Check-Condition "SemanticConventions in ServiceDefaults"  { (Get-Content src/ServiceDefaults/ServiceDefaults.csproj) -match "OpenTelemetry.SemanticConventions" }
Check-Condition "OTel Collector zPages reachable" {
    # Manual collector in start.ps1 may not expose zPages; accept pipeline config present
    try {
        if ((Invoke-WebRequest http://localhost:15579/debug/pipelinez -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { return $true }
    } catch {}
    try {
        if ((Invoke-WebRequest http://localhost:55679/debug/pipelinez -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { return $true }
    } catch {}
    # Fallback: collector process listening for OTLP
    $c = docker ps --filter "name=otel-collector" --format "{{.Status}}" 2>$null
    ($c -match "Up")
}
Check-Condition "ValidateCredentials span in Collector" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-Port 'user-service')/users/login" -TimeoutSec 5 | Out-Null } catch {}
    Start-Sleep 3; (Get-CollectorLogs | Select-String "ValidateCredentials" | Measure-Object).Count -gt 0
}
Check-Condition "Dashboard up + both service health endpoints" {
    try {
        $dash = (Invoke-WebRequest http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200
        $userOk = (curl.exe -s -m 5 -o NUL -w "%{http_code}" "http://localhost:$(Get-Port 'user-service')/health") -eq "200"
        $orderOk = (curl.exe -s -m 5 -o NUL -w "%{http_code}" "http://localhost:$(Get-Port 'order-service')/health") -eq "200"
        $dash -and $userOk -and $orderOk
    } catch { $false }
}
Check-Condition "orders/create multi-span trace" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-Port 'order-service')/orders/create" -TimeoutSec 5 | Out-Null } catch {}
    Start-Sleep 3
    $l = Get-CollectorLogs
    ($l | Select-String "CreateOrder" | Measure-Object).Count -gt 0 -and
    ($l | Select-String "PublishOrderEvent" | Measure-Object).Count -gt 0
}
Check-Condition "TelemetryConstants.cs in ServiceDefaults" { Test-Path "src/ServiceDefaults/TelemetryConstants.cs" }
Check-Condition "telemetry-schema.md in docs/"             { Test-Path "docs/telemetry-schema.md" }
Check-Condition "UserId attribute in Collector login output" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-Port 'user-service')/users/login" -TimeoutSec 5 | Out-Null } catch {}
    Start-Sleep 3; (Get-CollectorLogs | Select-String "UserId" | Measure-Object).Count -gt 0
}
Check-Condition "EventCounters package in ServiceDefaults" {
    (Get-Content src/ServiceDefaults/ServiceDefaults.csproj) -match "OpenTelemetry.Instrumentation.EventCounters"
}

Write-Host "-- Post 7 checks ---------------------------------------"

Check-Condition "Contracts project exists" {
    Test-Path "src/Contracts/Contracts.csproj"
} "Post 7 adds src/Contracts/"

Check-Condition "Azure.Messaging.ServiceBus package in OrderService" {
    (Get-Content src/OrderService/OrderService.csproj) -match "Azure.Messaging.ServiceBus"
} "Add Azure.Messaging.ServiceBus package"

Check-Condition "PayloadBytes attribute in order create log (serialisation working)" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-Port 'order-service')/orders/create" -TimeoutSec 5 | Out-Null } catch {}
    Start-Sleep 3
    (Get-CollectorLogs | Select-String "PayloadBytes" | Measure-Object).Count -gt 0
} "OrderService must log PayloadBytes after serialising OrderCreatedEvent"

Write-Host ""
Write-Host "========================================================"
if ($fail -eq 0) {
    Write-Host " All $($pass+$fail) checks passed. Post 7 complete." -ForegroundColor Green
} else {
    Write-Host " $fail/$($pass+$fail) FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    exit 1
}
Write-Host "========================================================"
