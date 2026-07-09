# verify.ps1 - Post 3 - Cumulative: 11 checks (9 Post 2 + 2 new)
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

function Get-UserPort {
    $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 5
    ($r | Where-Object { $_.name -eq "user-service" }).services[0].allocatedEndpoint.port
}
function Get-OrderPort {
    $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 5
    ($r | Where-Object { $_.name -eq "order-service" }).services[0].allocatedEndpoint.port
}

Write-Host "`n========================================================"
Write-Host " Hyperscale Log Monitoring - Post 3 Verification"
Write-Host "========================================================"
Write-Host "-- Post 1-2 checks (all must still pass) ---------------"

if ($Mode -eq "Aspire") {
    Check-Condition "Aspire Dashboard reachable" { try { (Invoke-WebRequest http://localhost:15888 -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false } } "dotnet run --project src/AppHost"
    Check-Condition "user-service /health 200"   { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-UserPort)/health") -eq "200" } catch { $false } }
    Check-Condition "user-service /alive 200"    { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-UserPort)/alive") -eq "200" } catch { $false } }
    Check-Condition "order-service /health 200"  { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-OrderPort)/health") -eq "200" } catch { $false } }
    Check-Condition "order-service /alive 200"   { try { (curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$(Get-OrderPort)/alive") -eq "200" } catch { $false } }
} else {
    Check-Condition "user-service healthy"   { (docker inspect --format="{{.State.Health.Status}}" user-service 2>&1) -eq "healthy" }
    Check-Condition "user-service /health"   { (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/health) -eq "200" }
    Check-Condition "order-service healthy"  { (docker inspect --format="{{.State.Health.Status}}" order-service 2>&1) -eq "healthy" }
    Check-Condition "order-service /health"  { (curl.exe -s -o NUL -w "%{http_code}" http://localhost:8081/health) -eq "200" }
    Check-Condition "otel-collector healthy" { (docker inspect --format="{{.State.Health.Status}}" otel-collector 2>&1) -eq "healthy" }
}
Check-Condition "OTel Collector received LogRecord" {
    if ($Mode -eq "Aspire") { try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort)/users/login" | Out-Null } catch {} } else { curl.exe -s -X POST http://localhost:8080/users/login | Out-Null }
    Start-Sleep 6
    (docker logs otel-collector 2>&1 | Select-String "LogRecord" | Measure-Object).Count -gt 0
}
Check-Condition "LogRecord has service.name=user-service" { (docker logs otel-collector 2>&1 | Select-String "user-service" | Measure-Object).Count -gt 0 }
Check-Condition "Serilog MachineName enricher present"    { (docker logs otel-collector 2>&1 | Select-String "MachineName" | Measure-Object).Count -gt 0 }
Check-Condition "AppInsights ExcludedTypes=Exception set" {
    $c = Get-Content src/UserService/appsettings.json | ConvertFrom-Json
    $c.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes -eq "Exception"
}

Write-Host "-- Post 3 checks (new this post) -----------------------"

Check-Condition "OpenTelemetry.SemanticConventions package in ServiceDefaults" {
    (Get-Content src/ServiceDefaults/ServiceDefaults.csproj) -match "OpenTelemetry.SemanticConventions"
} -FailHint 'Add PackageReference for OpenTelemetry.SemanticConventions in ServiceDefaults.csproj'

Check-Condition "OTel Collector zPages responding at localhost:55679" {
    try { (Invoke-WebRequest http://localhost:55679/debug/pipelinez -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch { $false }
} "Enable zpages extension in otel-collector-config.yaml; expose port 55679 in docker-compose.yml"

Check-Condition "ValidateCredentials manual span in Collector output" {
    if ($Mode -eq "Aspire") { try { Invoke-RestMethod -Method Post "http://localhost:$(Get-UserPort)/users/login" | Out-Null } catch {} } else { curl.exe -s -X POST http://localhost:8080/users/login | Out-Null }
    Start-Sleep 6
    (docker logs otel-collector 2>&1 | Select-String "ValidateCredentials" | Measure-Object).Count -gt 0
} -FailHint 'Check Extensions.ActivitySource is added to WithTracing and UserService creates the span'

Write-Host "`n========================================================"
if ($fail -eq 0) {
    Write-Host " All $($pass+$fail) checks passed. Post 3 complete." -ForegroundColor Green
    Write-Host " Next: open http://localhost:55679/debug/pipelinez"
} else {
    Write-Host " $fail/$($pass+$fail) FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    exit 1
}
Write-Host "========================================================"
