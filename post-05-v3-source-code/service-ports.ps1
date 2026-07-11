# service-ports.ps1 - Discover Aspire service ports for manual exploration and verify.ps1.
# Falls back to HTTP probing when the dashboard resources API requires browser login.

$script:CachedUserPort = $null
$script:CachedOrderPort = $null

function Find-ServicePort {
    param([string]$ProbePath)
    $listeners = netstat -ano | Select-String "LISTENING" | Select-String "127.0.0.1"
    foreach ($line in $listeners) {
        if ($line -match "127\.0\.0\.1:(\d+)") {
            $port = [int]$Matches[1]
            if ($port -in 15888,18889,18890,4317,55679,11498,46575) { continue }
            if ((curl.exe -s -o NUL -w "%{http_code}" --connect-timeout 1 --max-time 1 "http://127.0.0.1:$port$ProbePath") -eq "200") {
                return $port
            }
        }
    }
    return $null
}

function Get-UserPort {
    param([ValidateSet("Aspire","DockerCompose")][string]$Mode = "Aspire")
    if ($Mode -eq "DockerCompose") { return 8080 }
    if ($script:CachedUserPort) { return $script:CachedUserPort }
    try {
        $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 2
        if ($r -isnot [string]) {
            $p = ($r | Where-Object { $_.name -eq "user-service" }).services[0].allocatedEndpoint.port
            if ($p) { $script:CachedUserPort = $p; return $p }
        }
    } catch {}
    $discovered = Find-ServicePort -ProbePath "/users/ping"
    if ($discovered) { $script:CachedUserPort = $discovered; return $discovered }
    throw "user-service port not found. Start AppHost: dotnet run --project src/AppHost"
}

function Get-OrderPort {
    param([ValidateSet("Aspire","DockerCompose")][string]$Mode = "Aspire")
    if ($Mode -eq "DockerCompose") { return 8081 }
    if ($script:CachedOrderPort) { return $script:CachedOrderPort }
    try {
        $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 2
        if ($r -isnot [string]) {
            $p = ($r | Where-Object { $_.name -eq "order-service" }).services[0].allocatedEndpoint.port
            if ($p) { $script:CachedOrderPort = $p; return $p }
        }
    } catch {}
    $discovered = Find-ServicePort -ProbePath "/orders/ping"
    if ($discovered) { $script:CachedOrderPort = $discovered; return $discovered }
    throw "order-service port not found. Start AppHost: dotnet run --project src/AppHost"
}
