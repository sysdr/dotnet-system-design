# Post 2 — Structured Logging with Serilog & the Application Insights SDK

**Series:** Hyperscale Log Monitoring Masterclass · Post 2 of 45
**Branch:** `post/02-serilog-appinsights`
**Phase:** 1 — Foundations with .NET Aspire

> **No Azure subscription required.** Everything runs locally on Windows 11 with Docker Desktop and the .NET 8 SDK. Application Insights is configured with a local connection string that routes through the OTel Collector for verification without an Azure subscription.

---

## What changed from Post 1

| File | Change |
|------|--------|
| `src/ServiceDefaults/ServiceDefaults.csproj` | Added Serilog.AspNetCore 8.0.3, Serilog.Enrichers.Environment 3.0.1, Serilog.Enrichers.Thread 4.0.0 |
| `src/ServiceDefaults/Extensions.cs` | Added `ConfigureSerilog()` with MachineName, ThreadId, FromLogContext enrichers; activated `UseAzureMonitor()` |
| `src/UserService/appsettings.json` | Added Serilog config section; activated Application Insights connection string with `ExcludedTypes: Exception` |
| `src/OrderService/appsettings.json` | Same as UserService |
| `verify.ps1` | 2 new checks: MachineName enricher present, ExcludedTypes configured (9 total) |

---

## Prerequisites

Same as Post 1. Confirm:

```powershell
dotnet --version   # 8.0.xxx
docker --version   # Docker version 4.x
pwsh --version     # PowerShell 7.4.x
```

---

## Setup

```powershell
git checkout post/02-serilog-appinsights
dotnet run --project src/AppHost
# Aspire Dashboard: http://localhost:15888
```

**Docker Compose (secondary):**
```powershell
Copy-Item .env.example .env
docker compose up --build -d
```

---

## Verify

```powershell
.\verify.ps1
```

All 9 checks must pass:

```
-- Post 1 checks (all must still pass) -----------------
  Aspire Dashboard reachable ... PASS
  user-service /health ... PASS
  user-service /alive ... PASS
  order-service /health ... PASS
  order-service /alive ... PASS
  OTel Collector received at least 1 LogRecord ... PASS
  LogRecord contains service.name=user-service ... PASS
-- Post 2 checks (new this post) -----------------------
  Serilog MachineName enricher present in LogRecord ... PASS
  AppInsights ExcludedTypes=Exception configured ... PASS
```

---

## Manual Exploration

`verify.ps1` confirmed 9 checks pass. These steps confirm the concepts landed — that Serilog enrichers produce queryable columns and you understand why `ExcludedTypes = "Exception"` is unconditional.

---

### Serilog enrichers — queryable columns in the Aspire Dashboard

**Concept you are proving:** Serilog's `WithMachineName()` and `WithThreadId()` enrichers add named attributes to every log record. Those attributes appear as filterable columns in the Aspire Dashboard — the difference between "search the log text" and "filter by a named field."

**Tool:** Browser — open `http://localhost:15888` in Edge or Chrome.

1. Click **Structured Logs** in the left sidebar. Trigger traffic (either way works):

   **Option A — paste in terminal** (resolves Aspire ports, falls back to launchSettings 5101/5102):
   ```powershell
   $userPort = 5101; $orderPort = 5102
   try {
     $r = Invoke-RestMethod http://localhost:15888/api/v1/resources -TimeoutSec 5
     if ($r -is [System.Array]) {
       $up = ($r | Where-Object { $_.name -eq "user-service" }).services[0].allocatedEndpoint.port
       $op = ($r | Where-Object { $_.name -eq "order-service" }).services[0].allocatedEndpoint.port
       if ($up) { $userPort = [int]$up }
       if ($op) { $orderPort = [int]$op }
     }
   } catch {}
   Invoke-RestMethod -Method Post "http://localhost:$userPort/users/login"
   Invoke-RestMethod -Method Post "http://localhost:$orderPort/orders/create"
   ```

   **Option B — one-shot demo script** (same calls, guided output):
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\demo.ps1
   ```

   *Observe:* Expand any log row. Look for `MachineName`, `ThreadId`, `TraceId`, `UserId`, `IpAddress` as separate named fields.
   *What it means:* Every attribute is a queryable column — not embedded in the message body. `where MachineName == "dev-machine-01"` isolates logs from a specific pod. Impossible with plain string logging.

2. In the filter bar, type `MachineName` and look for autocomplete.
   *Observe:* The Dashboard offers `MachineName` as a filter option.
   *What it means:* First-class structured attribute. Not a substring match — an indexed field.

3. Find a record from `order-service` and confirm it has the same `TraceId` as a `user-service` record.
   *Observe:* Both services share a `TraceId` even though they are separate processes.
   *What it means:* `Enrich.FromLogContext()` propagates the OTel Activity through Serilog into the record. Without it, Serilog and OTel are disconnected — records have TraceId only if you set it manually.

**Now break it deliberately:**

```powershell
# 1. In src/ServiceDefaults/Extensions.cs, comment out:
#       .Enrich.WithMachineName()
# 2. Restart:
dotnet run --project src/AppHost
# 3. Trigger a login and check Structured Logs
```

*Observe:* New records have no `MachineName` attribute in the Aspire Dashboard.
*Why:* Enrichers run at record creation time. Not registered = never added. No error, just an informational gap.
*Restore:*
```powershell
# Uncomment .Enrich.WithMachineName() in Extensions.cs
# Restart and run:
.\verify.ps1   # check 8 (MachineName present) must pass
```

---

### Application Insights sampling — ExcludedTypes protects exceptions

**Concept you are proving:** Without `ExcludedTypes = "Exception"`, adaptive sampling discards exception records at the same rate as normal requests — silently. With the setting, every exception is retained regardless of the sampling rate.

**Tool:** PowerShell 7.

1. Verify the setting is present in user-service:
   ```powershell
   $config = Get-Content src/UserService/appsettings.json | ConvertFrom-Json
   $config.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes
   # Expected: Exception
   ```
   *Observe:* Returns `Exception`.
   *What it means:* The adaptive sampler will never discard `ExceptionTelemetry`. Every exception reaches the Application Insights backend.

2. Confirm order-service has the same setting:
   ```powershell
   $config = Get-Content src/OrderService/appsettings.json | ConvertFrom-Json
   $config.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes
   # Expected: Exception
   ```
   *Observe:* Also returns `Exception`.
   *What it means:* Both services are protected. A single service without the setting creates a blind spot.

3. Verify the OTel Collector receives warning/error records (which would be exceptions in production):
   ```powershell
   Invoke-RestMethod -Method Put -Uri "http://localhost:$port/orders/INVALID/cancel"
   Start-Sleep -Seconds 6
   docker logs otel-collector 2>&1 | Select-String "SeverityText" | Select-Object -Last 3
   ```
   *Observe:* Records with `"SeverityText": "Warning"` appear in the Collector logs.
   *What it means:* Higher-severity records are flowing. With `ExcludedTypes`, they will never be sampled away.

**Now break it deliberately:**

```powershell
# 1. In src/UserService/appsettings.json, remove "ExcludedTypes": "Exception"
#    from AdaptiveSamplingSettings
# 2. Run verify.ps1:
.\verify.ps1
```

*Observe:* Check 9 (`AppInsights ExcludedTypes=Exception configured`) fails. System still runs.
*Why:* The adaptive sampler now applies the same 10% rate to exceptions. At high traffic, 90% of exceptions are silently discarded. No SDK error, no service log warning.
*Restore:*
```powershell
# Add "ExcludedTypes": "Exception" back to appsettings.json
.\verify.ps1   # all 9 checks pass
```

---

## Memory budget

| Component | mem_limit | Typical |
|-----------|-----------|---------|
| Windows 11 + VS Code + Docker Desktop | — | ~6.0 GB |
| user-service (Serilog + OTel) | OS-managed | ~130 MB |
| order-service | OS-managed | ~130 MB |
| otel-collector | 300m | ~60 MB |
| **Total** | | **~7.1 GB** — 16.9 GB headroom |

---

## Stop

Aspire: `Ctrl+C` in the AppHost terminal.
Docker Compose: `docker compose down`

---

## What Post 3 adds

Post 3 introduces OpenTelemetry semantic conventions — the standardised attribute names that make the same KQL query work across every service in the system, regardless of which developer wrote the ILogger call.
