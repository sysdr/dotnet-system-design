# Troubleshooting — Post 2

## 1. MachineName not appearing in Aspire Dashboard Structured Logs

Cause: Serilog.Enrichers.Environment not installed, or .Enrich.WithMachineName() not called.
Fix:
  dotnet list src/ServiceDefaults/ServiceDefaults.csproj package | Select-String "Environment"
  # Expected: Serilog.Enrichers.Environment 3.0.1
  # If missing: dotnet add src/ServiceDefaults/ServiceDefaults.csproj package Serilog.Enrichers.Environment --version 3.0.1

## 2. verify.ps1 check 9 (ExcludedTypes) fails

Cause: ExcludedTypes key is missing from AdaptiveSamplingSettings in appsettings.json.
Fix:
  $config = Get-Content src/UserService/appsettings.json | ConvertFrom-Json
  $config.ApplicationInsights.AdaptiveSamplingSettings.ExcludedTypes
  # Expected: Exception
  # If null or missing: add "ExcludedTypes": "Exception" to AdaptiveSamplingSettings in appsettings.json

## 3. Serilog logs not appearing in Aspire Dashboard

Cause: ConfigureSerilog() is called AFTER ConfigureOpenTelemetry() in AddServiceDefaults().
Fix: In Extensions.cs, ensure ConfigureSerilog() is the FIRST call in AddServiceDefaults().

## 4. App Insights SDK throws on startup: Connection string not valid

Cause: Connection string format is incorrect — missing semicolon separators.
Expected format:
  InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=http://localhost:4318/
Fix: Check for missing semicolons in ApplicationInsights:ConnectionString in appsettings.json.

## 5. Order of enrichers matters for async code

Cause: WithThreadId() may show different thread IDs for async methods due to thread hopping.
This is expected behavior — not a bug. ThreadId tracks the actual OS thread that executed
the log call, which may differ from the thread that started the async method.
Fix: For stable per-request grouping, use TraceId (from FromLogContext) not ThreadId.
