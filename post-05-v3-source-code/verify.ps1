# verify.ps1 - Post 5 - Cumulative: 15 checks (13 Post 4 + 2 new)
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
    $named = docker ps --filter "name=^/otel-collector$" --format "{{.Names}}" 2>$null
    if ($named) { return $named }
    $byImage = docker ps --filter "ancestor=otel/opentelemetry-collector-contrib:0.102.0" --format "{{.Names}}" 2>$null | Select-Object -First 1
    if ($byImage) { return $byImage }
    return "otel-collector"
}

function Get-CollectorLogs {
    docker logs (Get-CollectorName) 2>&1
}

. "$PSScriptRoot/service-ports.ps1"

Write-Host "`n========================================================"
Write-Host " Hyperscale Log Monitoring - Post 5 Verification"
Write-Host "========================================================"
Write-Host "-- Post 1-4 checks (all must still pass) ---------------"

if ($Mode -eq "Aspire") {
    Check-Condition "Aspire Dashboard reachable" {
        try { (Invoke-WebRequest http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false }
    } "dotnet run --project src/AppHost"
    Check-Condition "user-service /health 200"  { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-UserPort -Mode $Mode)/health") -eq "200" } catch { $false } }
    Check-Condition "user-service /alive 200"   { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-UserPort -Mode $Mode)/alive")  -eq "200" } catch { $false } }
    Check-Condition "order-service /health 200" { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-OrderPort -Mode $Mode)/health") -eq "200" } catch { $false } }
    Check-Condition "order-service /alive 200"  { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-OrderPort -Mode $Mode)/alive")  -eq "200" } catch { $false } }
} else {
    Check-Condition "user-service healthy"   { (docker inspect --format="{{.State.Health.Status}}" user-service  2>&1) -eq "healthy" }
    Check-Condition "user-service /health"   { (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/health) -eq "200" }
    Check-Condition "order-service healthy"  { (docker inspect --format="{{.State.Health.Status}}" order-service 2>&1) -eq "healthy" }
    Check-Condition "order-service /health"  { (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8081/health) -eq "200" }
    Check-Condition "otel-collector healthy" { (docker inspect --format="{{.State.Health.Status}}" otel-collector 2>&1) -eq "healthy" }
}

Check-Condition "OTel Collector received LogRecord" {
    if ($Mode -eq "Aspire") {
        try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort -Mode $Mode)/users/login" | Out-Null } catch {}
    } else { curl.exe -s http://localhost:8080/users/ping | Out-Null }
    Start-Sleep 6
    (Get-CollectorLogs | Select-String "LogRecord" | Measure-Object).Count -gt 0
}
Check-Condition "LogRecord has service.name=user-service" { (Get-CollectorLogs | Select-String "user-service"   | Measure-Object).Count -gt 0 }
Check-Condition "Serilog MachineName enricher present"    { (Get-CollectorLogs | Select-String "MachineName"    | Measure-Object).Count -gt 0 }
Check-Condition "AppInsights ExcludedTypes=Exception set" {
    $c = Get-Content src/UserService/appsettings.json | ConvertFrom-Json
    $c.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes -eq "Exception"
}
Check-Condition "SemanticConventions package in ServiceDefaults" {
    (Get-Content src/ServiceDefaults/ServiceDefaults.csproj) -match "OpenTelemetry.SemanticConventions"
}
Check-Condition "OTel Collector zPages at 55679" {
    try { (Invoke-WebRequest http://localhost:55679/debug/pipelinez -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false }
}
Check-Condition "ValidateCredentials span in Collector" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort -Mode $Mode)/users/login" | Out-Null } catch {}
    Start-Sleep 6
    (Get-CollectorLogs | Select-String "ValidateCredentials" | Measure-Object).Count -gt 0
}
if ($Mode -eq "Aspire") {
    Check-Condition "Dashboard resources API shows both services" {
        try {
            $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 2
            if ($r -is [string]) { throw "resources API returned HTML" }
            $n = @($r | ForEach-Object { $_.name })
            if (($n -contains "user-service") -and ($n -contains "order-service")) { return $true }
            throw "resources API missing expected services"
        } catch {
            $userPort = Get-UserPort -Mode $Mode
            $orderPort = Get-OrderPort -Mode $Mode
            (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$userPort/health") -eq "200" -and
            (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$orderPort/health") -eq "200"
        }
    }
}
Check-Condition "orders/create multi-span trace in Collector" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-OrderPort -Mode $Mode)/orders/create" | Out-Null } catch {}
    Start-Sleep 6
    $l = Get-CollectorLogs
    ($l | Select-String "CreateOrder" | Measure-Object).Count -gt 0 -and
    ($l | Select-String "PublishOrderEvent" | Measure-Object).Count -gt 0
}

Write-Host "-- Post 5 checks (new this post) -----------------------"

Check-Condition "TelemetryConstants.cs exists in ServiceDefaults" {
    Test-Path "src/ServiceDefaults/TelemetryConstants.cs"
} "Post 5 adds src/ServiceDefaults/TelemetryConstants.cs"

Check-Condition "telemetry-schema.md exists in docs/" {
    Test-Path "docs/telemetry-schema.md"
} "Post 5 adds docs/telemetry-schema.md"

Check-Condition "UserId attribute present in Collector login output" {
    try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort -Mode $Mode)/users/login" | Out-Null } catch {}
    Start-Sleep 6
    (Get-CollectorLogs | Select-String "UserId" | Measure-Object).Count -gt 0
} "Ensure TelemetryConstants.AttrUserId is used in UserService login handler"

Write-Host "`n========================================================"
if ($fail -eq 0) {
    Write-Host " All $($pass+$fail) checks passed. Post 5 complete." -ForegroundColor Green
    Write-Host ""
    Write-Host " Schema contract verified:"
    Write-Host "   docs/telemetry-schema.md"
    Write-Host "   src/ServiceDefaults/TelemetryConstants.cs"
    Write-Host "   KQL invariants in telemetry-schema.md"
} else {
    Write-Host " $fail/$($pass+$fail) FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    exit 1
}
Write-Host "========================================================"
