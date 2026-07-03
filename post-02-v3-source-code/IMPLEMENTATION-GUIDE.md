## Implementation Guide: Structured Logging with Serilog & the Application Insights SDK

**Series:** Hyperscale Log Monitoring Masterclass · Post 2 of 45  
**Project:** `post-02-v3-source-code`

This guide covers every way to run the project, how to inspect output, and how to confirm success. No Azure subscription is required — everything runs locally with .NET 8, Docker Desktop, and optional .NET Aspire.

---

## Prerequisites

| Tool | Verify |
|------|--------|
| .NET 8 SDK | `dotnet --version` → `8.0.xxx` |
| Docker Desktop | `docker --version` (running) |
| PowerShell 7 | `pwsh --version` (for `verify.ps1` on Windows) |
| Aspire workload | `dotnet workload list` — install if AppHost fails: `dotnet workload install aspire` |

---

## Stop Everything (before a fresh start)

### Windows (PowerShell)

```powershell
Get-Process -Name "AppHost","Aspire.Dashboard","UserService","OrderService","dcpctrl" -ErrorAction SilentlyContinue | Stop-Process -Force
docker compose down --remove-orphans
```

### Bash / WSL / macOS / Linux

```bash
bash cleanup.sh
# optional: also remove unused images
bash cleanup.sh --prune-images
```

`cleanup.sh` stops Docker Compose, removes project containers (`otel-collector`, `user-service`, `order-service`), prunes stopped containers/networks/dangling images, and deletes local `bin/` / `obj/` folders.

---

## Option A — .NET Aspire AppHost (recommended)

Primary orchestration path. Aspire assigns dynamic ports, wires OTLP env vars, and hosts the dashboard.

### Start

```powershell
cd post-02-v3-source-code
dotnet run --project src/AppHost --launch-profile https
```

Wait for:

```
Distributed application started.
Login to the dashboard at http://localhost:15888/login?t=<token>
```

### Aspire Dashboard

| Item | Value |
|------|-------|
| URL | `http://localhost:15888` |
| Login | Copy the **full URL** from the console (`?t=<token>`). Token changes every start. |
| Resources | `user-service`, `order-service`, `otel-collector` |

### Service endpoints (dynamic ports)

Aspire assigns ports per session. Probe with:

```powershell
# Find user-service port
Get-NetTCPConnection -State Listen | ForEach-Object {
  $p = $_.LocalPort
  $b = curl.exe -s "http://localhost:$p/users/ping" 2>$null
  if ($b -match 'user-service') { "user-service → http://localhost:$p" }
}
```

Or open the Aspire Dashboard → **Resources** → click each service for its URL.

### Stop

Press `Ctrl+C` in the AppHost terminal, then run `bash cleanup.sh` or the PowerShell stop commands above.

---

## Option B — Docker Compose

Fixed ports; useful for CI or running without the Aspire SDK.

### Start

```powershell
cd post-02-v3-source-code
docker compose up --build -d
```

### Fixed endpoints

| Service | URL |
|---------|-----|
| user-service | `http://localhost:8080` |
| order-service | `http://localhost:8081` |
| OTel Collector zPages | `http://localhost:55679/debug/pipelinez` |
| OTLP gRPC | `localhost:4317` |
| OTLP HTTP | `localhost:4318` |

### Stop

```powershell
docker compose down --remove-orphans
# or
bash cleanup.sh
```

---

## Option C — Manual API exploration

After either Option A or B is running, exercise the APIs:

```powershell
# user-service
curl.exe http://localhost:8080/users/ping          # Docker Compose
curl.exe -X POST http://localhost:8080/users/login
curl.exe -X POST http://localhost:8080/users/logout

# order-service
curl.exe http://localhost:8081/orders/ping
curl.exe -X POST http://localhost:8081/orders/create
curl.exe -X POST http://localhost:8081/orders/123/cancel
```

For Aspire, replace `8080` / `8081` with the dynamic ports from the dashboard.

Health probes (used by `verify.ps1`):

```powershell
curl.exe http://localhost:8080/health   # readiness
curl.exe http://localhost:8080/alive    # liveness
```

---

## Verification scripts

Automated acceptance checks (9 for Aspire, 7 for Docker Compose).

### Windows (preferred)

```powershell
pwsh -ExecutionPolicy Bypass -File .\verify.ps1                  # Aspire mode (default)
pwsh -ExecutionPolicy Bypass -File .\verify.ps1 -Mode DockerCompose
```

### Bash / WSL

```bash
bash verify.sh aspire    # when AppHost is running
bash verify.sh compose   # when Docker Compose is running
```

---

## How to see output

### 1. Aspire Dashboard (`http://localhost:15888`)

- **Structured Logs** — filter by `UserId`, `service.name`, `MachineName`
- **Traces** — HTTP request spans across services
- **Metrics** — runtime, ASP.NET Core, HTTP client metrics

### 2. OTel Collector stdout (log pipeline demo)

Collector config: `config/otel-collector-config.yaml` — OTLP receiver → batch processor → logging exporter (stdout).

```powershell
# Docker Compose (fixed container name)
docker logs otel-collector 2>&1 | Select-String "LogRecord|MachineName|user-service"

# Aspire (dynamic container name)
docker ps --filter "name=otel-collector" --format "{{.Names}}"
docker logs <container-name> 2>&1 | Select-String "LogRecord"
```

Trigger log traffic first:

```powershell
curl.exe -X POST http://localhost:8080/users/login
```

### 3. Service console output

Serilog writes structured JSON-ish lines to stdout:

```
[12:00:00 INF] Login attempt. UserId=4821 IpAddress=192.168.1.1
```

Docker Compose:

```powershell
docker logs user-service --tail 20
docker logs order-service --tail 20
```

### 4. Collector zPages

Open `http://localhost:55679/debug/pipelinez` in a browser to inspect the collector pipeline.

---

## Success metrics

All items below must pass before considering Post 2 complete.

### Automated (`verify.ps1`)

| # | Check | Aspire | Docker Compose |
|---|-------|--------|----------------|
| 1 | Aspire Dashboard reachable at `localhost:15888` | PASS | — |
| 2 | user-service `/health` returns 200 | PASS | PASS |
| 3 | user-service `/alive` returns 200 | PASS | — |
| 4 | order-service `/health` returns 200 | PASS | PASS |
| 5 | order-service `/alive` returns 200 | PASS | — |
| 6 | OTel Collector received at least 1 `LogRecord` | PASS | PASS |
| 7 | `LogRecord` contains `service.name=user-service` | PASS | PASS |
| 8 | Serilog `MachineName` enricher present in `LogRecord` | PASS | PASS |
| 9 | AppInsights `ExcludedTypes=Exception` in user-service config | PASS | PASS |

**Target:** `All 9 checks passed` (Aspire) or `All 7 checks passed` (Docker Compose).

### Manual confirmation

- [ ] Aspire Dashboard **Structured Logs** shows `UserId` as a filterable column (not embedded in message body)
- [ ] `MachineName` appears on log records in collector stdout or dashboard
- [ ] `src/UserService/appsettings.json` has `AdaptiveSamplingSettings.ExcludedTypes` set to `"Exception"`
- [ ] Login/logout endpoints return `200` with JSON body
- [ ] No startup errors in AppHost or `docker logs user-service`

### Configuration landmarks

| File | What to verify |
|------|----------------|
| `src/ServiceDefaults/Extensions.cs` | `ConfigureSerilog()` with `WithMachineName()`; `UseOtlpExporter()`; `UseAzureMonitor()` skipped for localhost |
| `src/UserService/appsettings.json` | Serilog enrichers; `ApplicationInsights:ConnectionString` points to `http://localhost:4318/` for local dev |
| `src/AppHost/Program.cs` | `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://localhost:4317` on both services |
| `config/otel-collector-config.yaml` | logs pipeline: `otlp` → `batch` → `logging` |

---

## Troubleshooting

See `docs/troubleshooting.md` for common failures:

- MachineName missing → check `Serilog.Enrichers.Environment` package and `WithMachineName()`
- Collector checks fail → ensure Docker Desktop is running; run `bash cleanup.sh` then restart
- Aspire port conflicts → stop old AppHost processes before restarting
- `verify.ps1` parse errors → use `pwsh`, not Windows PowerShell 5

---

## Project layout (git check-in)

```
post-02-v3-source-code/
├── src/
│   ├── AppHost/           # Aspire orchestrator
│   ├── UserService/       # /users/* endpoints
│   ├── OrderService/      # /orders/* endpoints
│   └── ServiceDefaults/   # Serilog + OTel + health checks
├── config/
│   └── otel-collector-config.yaml
├── docs/
├── docker-compose.yml
├── verify.ps1
├── verify.sh
├── cleanup.sh
├── .gitignore
└── IMPLEMENTATION-GUIDE.md
```

**Not checked in:** `bin/`, `obj/`, `.env`, real Azure connection strings, Aspire login tokens.

---

## Production note

Local `InstrumentationKey=00000000-0000-0000-0000-000000000000` is a **placeholder** for offline development. For real Azure deployment, replace with a connection string from `az monitor app-insights component show` — see `docs/azure-production-guide.md`. Never commit production keys; use environment variables or Azure Key Vault.
