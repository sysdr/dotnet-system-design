# call-apis.ps1 - Working Post 7 API calls (Aspire 9 fixed ports).
# Root cause of the old discovery failure:
#   Invoke-RestMethod http://localhost:15888/api/v1/resources
# returns the Dashboard HTML login page (auth required), so
#   .services[0].allocatedEndpoint.port
# is null -> "Cannot index into a null array".
#
# Fix: use launchSettings ports (user=5080, order=5081).

param(
    [ValidateSet("login","create","all")]
    [string]$Action = "all"
)

$userPort  = 5080
$orderPort = 5081

Write-Host "user-service  -> http://localhost:$userPort"
Write-Host "order-service -> http://localhost:$orderPort"
Write-Host ""

if ($Action -eq "login" -or $Action -eq "all") {
    Write-Host "POST /users/login"
    Invoke-RestMethod -Method Post -Uri "http://localhost:$userPort/users/login" | ConvertTo-Json
    Write-Host ""
}

if ($Action -eq "create" -or $Action -eq "all") {
    Write-Host "POST /orders/create"
    Invoke-RestMethod -Method Post -Uri "http://localhost:$orderPort/orders/create" | ConvertTo-Json
    Write-Host ""
}
