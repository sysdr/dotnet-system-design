# Post 1 — The Architecture of Scale: .NET Aspire & Your Windows Dev Sandbox

**Series:** Hyperscale Log Monitoring Masterclass · Post 1 of 45
**Branch:** `post/01-aspire-sandbox`
**Phase:** 1 — Foundations with .NET Aspire

> **No Azure subscription required.** Everything runs locally on Windows 11 with Docker Desktop and the .NET 8 SDK. All Azure services in this series use official free Microsoft local emulators.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Windows 11 | 22H2 or later | Windows Update |
| .NET SDK | 8.0.x (LTS) | https://dot.net |
| Docker Desktop | 4.x (latest) | https://www.docker.com/products/docker-desktop/ |
| PowerShell | 7.4.x (pwsh) | `winget install Microsoft.PowerShell` |
| Visual Studio Code | 1.9x | https://code.visualstudio.com |
| C# Dev Kit (VS Code extension) | latest | VS Code Extensions panel |

**Docker Desktop settings (required):**
Settings → Resources → Memory → set to at least 8 GB
Settings → General → Use the WSL 2 based engine ✓

**Verify your setup in PowerShell 7:**
```powershell
dotnet --version      # 8.0.xxx
docker --version      # Docker version 4.x
pwsh --version        # PowerShell 7.4.x
```

---

## Setup

**PowerShell 7 (primary):**
```powershell
git clone https://github.com/YOUR_ORG/hyperscale-log-monitoring.git
Set-Location hyperscale-log-monitoring
git checkout post/01-aspire-sandbox
dotnet run --project src/AppHost
# Aspire Dashboard opens at http://localhost:15888
```

**Docker Compose (secondary):**
```powershell
Copy-Item .env.example .env
docker compose up --build -d
```

---

## Verify

**PowerShell 7 (primary):**
```powershell
# Aspire mode (default):
.\verify.ps1

# Docker Compose mode:
.\verify.ps1 -Mode DockerCompose
```

**WSL2/bash (secondary):**
```bash
bash verify.sh        # Docker Compose mode
bash verify.sh aspire # Aspire mode
```

All 7 checks must show PASS. If any fail, see `docs\troubleshooting.md`.

---

## Manual Exploration

`verify.ps1` confirmed the plumbing is connected.
These steps confirm the concepts landed — that you understand what is flowing through the system, not just that the ports are open.

Run each block after `verify.ps1` passes.

---

### .NET Aspire Dashboard — structured log correlation across services

**Concept you are proving:** A single HTTP request generates structured log records with named attributes (UserId, IpAddress) as queryable columns, and a TraceId that links every record — across every service — produced by that one request.

**Tool:** Browser — open `http://localhost:15888` in Edge or Chrome.

1. Click **user-service** in the Resources panel on the left sidebar.
   *Observe:* The resource detail shows CPU usage, memory, environment variables (`OTEL_SERVICE_NAME=user-service`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://...`), and an endpoint URL such as `http://localhost:58341`.
   *What it means:* Aspire assigned a dynamic port to avoid conflicts with IIS Express or other local services — and tracked that assignment automatically. No `docker-compose.yml` port line needed.

2. Click **Structured Logs** in the left sidebar. Then trigger a login from PowerShell 7:
   ```powershell
   # Find the dynamic port Aspire assigned to user-service
   $resources = Invoke-RestMethod http://localhost:15888/api/v1/resources
   $port = ($resources | Where-Object { $_.name -eq "user-service" }).services[0].allocatedEndpoint.port
   Invoke-RestMethod -Method Post -Uri "http://localhost:$port/users/login"
   ```
   *Observe:* A new row appears within 2 seconds with these distinct columns: Timestamp, Level, Message, service.name, TraceId, SpanId, UserId, IpAddress.
   *What it means:* `UserId` and `IpAddress` are not embedded in the Message string — they are separate named attributes. You can now filter `where UserId == "4821"` without parsing any text. This is the architectural shift from a log file to a log database.

3. Click the **TraceId** value (the blue link) in that row.
   *Observe:* The Structured Logs view filters to show only records with that exact TraceId. If order-service had been called in the same request chain, its records would appear here too.
   *What it means:* One TraceId threads through every service boundary that a single HTTP request crosses. This is the mechanism that reduces cross-service incident correlation from hours to minutes.

4. Click **Traces** in the left sidebar. Find the trace entry for your login request.
   *Observe:* A timeline shows the HTTP request as a root span with duration in milliseconds.
   *What it means:* The same TraceId in Structured Logs also appears in Traces — they are two views of the same record. One click connects a slow trace to its log records.

**Now break it deliberately:**

```powershell
# 1. Open src/ServiceDefaults/Extensions.cs in VS Code
code src/ServiceDefaults/Extensions.cs

# 2. Comment out line: logging.IncludeScopes = true;
#    Change to:        // logging.IncludeScopes = true;

# 3. Stop and restart the AppHost
#    Press Ctrl+C in the AppHost terminal, then:
dotnet run --project src/AppHost

# 4. Trigger a login and check Structured Logs
$resources = Invoke-RestMethod http://localhost:15888/api/v1/resources
$port = ($resources | Where-Object { $_.name -eq "user-service" }).services[0].allocatedEndpoint.port
Invoke-RestMethod -Method Post -Uri "http://localhost:$port/users/login"
```

*Observe:* In the Aspire Dashboard Structured Logs, the TraceId column is empty on new records. Records still appear, but TraceId shows blank.

*Why:* `IncludeScopes = true` propagates the ASP.NET Core `Activity` (which carries TraceId and SpanId) from the HTTP middleware into every `ILogger` call. Without it, the logger runs without context. The record is emitted but the cross-service linking mechanism is broken.

*Restore:*
```powershell
# Uncomment logging.IncludeScopes = true in Extensions.cs
# Restart: dotnet run --project src/AppHost
.\verify.ps1   # confirm all 7 checks pass
```

---

### OTel Collector (open-source secondary track) — the decoupled pipeline model

**Concept you are proving:** The Collector receiver-processor-exporter pipeline decouples log emission from log destination. Changing where logs go requires only a config file change — the .NET service code is untouched.

**Tool:** Browser — open `http://localhost:55679/debug/pipelinez` in Edge or Chrome.

1. Open `http://localhost:55679/debug/pipelinez`.
   *Observe:* Three pipeline stage rows: `otlp` receiver (Accepted: N), `batch` processor (Accepted: N, Dropped: 0), `logging` exporter (Exported: N). All show "Running" status.
   *What it means:* The Collector is live and actively processing records through the declared pipeline. The counters are live — refresh the page to see them update.

2. Trigger five requests, wait for the batch flush, then refresh:
   ```powershell
   1..5 | ForEach-Object {
       Invoke-RestMethod -Method Post -Uri http://localhost:8080/users/login 2>$null
   }
   Start-Sleep -Seconds 6   # wait for the batch processor 5s timeout to fire
   # Then refresh http://localhost:55679/debug/pipelinez in the browser
   ```
   *Observe:* The receiver's Accepted counter increased by 5+. The exporter's Exported counter also increased. If you refreshed before 5 seconds, the processor shows Accepted but the exporter shows 0 — the batch is being held.
   *What it means:* The batch processor accumulated 5 records and flushed them in one write after `timeout: 5s`. This protects storage backends (Service Bus, ADX) from individual small writes at high request rates.

3. Read the exported records in PowerShell 7:
   ```powershell
   docker logs otel-collector 2>&1 | Select-String "service.name" | Select-Object -Last 3
   ```
   *Observe:* JSON objects appear, each containing `"service.name": "user-service"` and `"Body": "Login attempt. UserId=..."` as distinct named fields.
   *What it means:* The logging exporter serialised each record as JSON to stdout. In Post 9, the one word `logging` in `otel-collector-config.yaml` changes to `servicebus`. UserService and OrderService emit zero changed lines. Logs start flowing into Azure Service Bus instead.

**Now break it deliberately:**

```powershell
# 1. Open config/otel-collector-config.yaml
code config/otel-collector-config.yaml

# 2. Change the grpc endpoint port from 4317 to 4316:
#    endpoint: "0.0.0.0:4316"   (was 4317)

# 3. Restart only the Collector container
docker compose restart otel-collector
Start-Sleep -Seconds 10   # wait for restart

# 4. Trigger a request and wait
Invoke-RestMethod -Method Post -Uri http://localhost:8080/users/login 2>$null
Start-Sleep -Seconds 6

# 5. Count LogRecords received
docker logs otel-collector 2>&1 | Select-String "LogRecord" | Measure-Object
```

*Observe:* Count returns 0. If running Aspire, the Aspire Dashboard still shows the record — it uses a different OTLP path. Only the Collector receives nothing.

*Why:* The Collector listens on 4316 but docker-compose services still send to 4317. OTLP/gRPC fails silently — no error in the .NET service, just missing records at the Collector. This is the most common silent failure in OTel deployments.

*Restore:*
```powershell
# Change back to: endpoint: "0.0.0.0:4317"
docker compose restart otel-collector
.\verify.ps1   # confirm all 7 checks pass
```

---

## Memory budget

| Component | mem_limit | Typical use |
|-----------|-----------|-------------|
| Windows 11 + VS Code + Docker Desktop + browser | — | ~6.0 GB |
| user-service (Aspire: .NET process) | no container limit | ~80–120 MB |
| order-service (Aspire: .NET process) | no container limit | ~80–120 MB |
| otel-collector (Docker) | 300m | ~50–100 MB |
| **Total** | | **~7.0 GB** |

17.0 GB headroom remaining before the 24 GB cap.

---

## Stop

Aspire: `Ctrl+C` in the AppHost terminal — Aspire shuts down everything it started.
Docker Compose: `docker compose down` — no `-v` needed (no persistent volumes yet).

---

## What Post 2 adds

Post 2 wires the Application Insights OTel Distro to ServiceDefaults — adding a local export that persists records across restarts. Right now, `Ctrl+C` erases everything in the Aspire Dashboard. Post 2 fixes that with zero changes to UserService or OrderService.
