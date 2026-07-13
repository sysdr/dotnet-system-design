# stop-app.ps1 — stop AppHost + services + otel-collector so you can restart clean
# Usage:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\stop-app.ps1

Write-Host ""
Write-Host "Stopping lesson processes..."

$names = @(
    "AppHost",
    "UserService",
    "OrderService",
    "Aspire.Dashboard",
    "dcpctrl",
    "dcp"
)

foreach ($name in $names) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host ("  Kill {0} PID={1}" -f $_.ProcessName, $_.Id)
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

# Free lesson ports if still held by leftover dotnet/aspire processes
# Do NOT kill Docker Desktop / com.docker.backend
$ports = @(5101, 5102, 15888, 18888, 18889, 4317, 4318, 55679)
foreach ($port in $ports) {
    foreach ($line in (netstat -ano | Select-String "LISTENING" | Select-String ":$port\s")) {
        if ($line.Line -match "\s+(\d+)\s*$") {
            $procId = [int]$Matches[1]
            try {
                $p = Get-Process -Id $procId -ErrorAction Stop
                if ($p.ProcessName -match "^(dotnet|dcp|dcpctrl|Aspire\.Dashboard|UserService|OrderService|AppHost)$") {
                    Write-Host ("  Kill {0} PID={1} (port {2})" -f $p.ProcessName, $procId, $port)
                    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }
}

Write-Host "Removing otel-collector containers..."
try {
    $ids = docker ps -aq --filter "name=otel-collector" 2>$null
    if ($ids) {
        $ids | ForEach-Object {
            Write-Host "  docker rm -f $_"
            docker rm -f $_ | Out-Null
        }
    } else {
        Write-Host "  none found"
    }
} catch {
    Write-Host "  Docker not available (skipped)"
}

Start-Sleep -Seconds 1
Write-Host ""
Write-Host "Stopped. Fresh start with:"
Write-Host "  dotnet run --project src/AppHost"
Write-Host ""
