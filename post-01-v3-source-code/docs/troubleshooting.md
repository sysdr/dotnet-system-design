# Troubleshooting — Post 1
## Windows 11 + Docker Desktop + .NET Aspire

---

## 1. `dotnet run --project src/AppHost` fails: SDK not found

**Symptom:** `error NETSDK1045: The current .NET SDK does not support targeting .NET 8.0`

**Cause:** Running inside an old PowerShell 5.1 session that found a different SDK, or .NET 8 SDK is not installed.

**Fix:**
```powershell
# Check which SDK is being used
dotnet --version    # must show 8.0.xxx

# If it shows 6.x or 7.x, install .NET 8:
winget install Microsoft.DotNet.SDK.8

# Close and reopen PowerShell 7, then retry
dotnet run --project src/AppHost
```

---

## 2. Aspire Dashboard does not open automatically at localhost:15888

**Symptom:** `dotnet run --project src/AppHost` starts but no browser tab opens.

**Cause A:** VS Code's integrated terminal suppresses automatic browser launch.

**Fix A:** Run in Windows Terminal (not VS Code terminal). Or manually open `http://localhost:15888` in Edge or Chrome.

**Cause B:** Port 15888 is in use by another process.

**Fix B:**
```powershell
netstat -ano | Select-String ":15888"
# Note the PID in the last column, then:
Stop-Process -Id <PID> -Force
# Restart AppHost
```

---

## 3. `verify.ps1` check fails: "Aspire Dashboard reachable"

**Symptom:** Check reports FAIL even though the AppHost terminal shows services starting.

**Cause:** Aspire takes 15–20 seconds to initialise all resources. `verify.ps1` runs before Aspire is fully ready.

**Fix:** Wait 30 seconds after the AppHost terminal shows `Application started` for all services, then rerun `verify.ps1`.

---

## 4. OTel Collector receives zero LogRecords (verify check 6 fails)

**Symptom:** `verify.ps1` reports "OTel Collector received at least 1 LogRecord — FAIL"

**Cause:** In Docker Compose mode, the `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable is missing or wrong.

**Fix:**
```powershell
# Check what the container sees
docker inspect user-service | Select-String "OTEL_EXPORTER"
# Expected: "OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317"
# If missing: ensure .env was copied from .env.example
Copy-Item .env.example .env
docker compose down
docker compose up -d
```

---

## 5. PowerShell 5.1 errors when running verify.ps1

**Symptom:** `verify.ps1` throws `param: The term 'param' is not recognized` or similar.

**Cause:** Running in Windows PowerShell 5.1 (`powershell.exe`) instead of PowerShell 7 (`pwsh.exe`).

**Fix:**
```powershell
# Check which shell you are in
$PSVersionTable.PSVersion   # Major must be 7

# Install PowerShell 7 if needed
winget install --id Microsoft.PowerShell --source winget

# Then run explicitly with pwsh
pwsh -File .\verify.ps1
```
