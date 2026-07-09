# stop.ps1 — Tear down a local Aspire AppHost session and free its ports.
# Run this before restarting when you see "address already in use" on 8080/8081/4317/55679/15888.

$ports = @(15888, 18889, 18890, 4317, 55679, 8080, 8081, 5000, 5001)

Write-Host "Stopping Aspire AppHost / Dashboard processes..."
Get-Process AppHost, Aspire.Dashboard -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "Stopping orphaned dotnet service processes..."
Get-CimInstance Win32_Process -Filter "Name='dotnet.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'UserService|OrderService|AppHost' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host "Removing otel-collector containers..."
docker ps -aq --filter "name=otel-collector" 2>$null | ForEach-Object { docker rm -f $_ 2>$null | Out-Null }

Write-Host "Freeing ports: $($ports -join ', ')"
foreach ($port in $ports) {
    $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
    }
}

Start-Sleep -Seconds 2

$stillBound = @()
foreach ($port in $ports) {
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        $stillBound += $port
    }
}

if ($stillBound.Count -gt 0) {
    Write-Host "WARNING: ports still in use: $($stillBound -join ', ')" -ForegroundColor Yellow
    Write-Host "Close the owning app manually or reboot if needed."
    exit 1
}

Write-Host "All Aspire ports are free. Run: dotnet run --project src/AppHost --launch-profile http" -ForegroundColor Green
