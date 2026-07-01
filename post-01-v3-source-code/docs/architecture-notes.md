# Architecture Notes — Post 1

## Decision: .NET Aspire AppHost as primary orchestration

**Chose:** .NET Aspire AppHost (`src/AppHost/Program.cs`)
**Secondary:** `docker-compose.yml`

Aspire's AppHost is C# code with the full .NET type system — typos in service names are compile errors, not runtime surprises. Aspire also sets `OTEL_EXPORTER_OTLP_ENDPOINT` automatically for every project it orchestrates, points it at its own built-in OTLP endpoint, and opens a browser dashboard with structured logs, metrics, and traces in one place. None of this requires any container — user-service and order-service run as native .NET processes, which makes startup faster and debugging easier on Windows.

Docker Compose is retained as the secondary option for CI/CD pipelines (GitHub Actions, Azure DevOps) where the .NET SDK may not be available, and for demonstrating the OTel Collector pipeline in isolation.

## Decision: IncludeScopes = true is mandatory in ServiceDefaults

`IncludeScopes = true` on the OTel logging builder propagates the ASP.NET Core `Activity` object into `ILogger`. The `Activity` carries `TraceId` and `SpanId`. Without this setting, every log record is emitted without trace context — the structured attributes (UserId, IpAddress) are present, but the cross-service linking mechanism is absent. The "Break it deliberately" step in the Manual Exploration section demonstrates this failure mode explicitly.

## Decision: ApplicationInsights:ConnectionString is empty in Post 1

The `Azure.Monitor.OpenTelemetry.AspNetCore` package is installed and wired in ServiceDefaults from Post 1. The connection string is left empty so the exporter is a no-op. Post 2 adds a local connection string that enables the exporter without requiring an Azure subscription. This pattern means zero code changes are required when activating Application Insights — only a config value changes.

## Post 1 component inventory

| Component | Technology | Port | mem_limit | Persistent |
|---|---|---|---|---|
| AppHost | .NET Aspire 8.3.0 | 15888 (Dashboard) | OS-managed | No |
| user-service | .NET 8 Minimal API | Dynamic (Aspire) | OS-managed | No |
| order-service | .NET 8 Minimal API | Dynamic (Aspire) | OS-managed | No |
| otel-collector | otel-contrib 0.102.0 | 4317, 55679 | 300m | No |
