// src/AppHost/Program.cs
// Post 1 of 45 — .NET Aspire AppHost
// This is the C# equivalent of docker-compose.yml.
// Every service, container, and connection is declared here with full type safety.
//
// CUMULATIVE FILE: each subsequent post adds resources here.
// By Post 45, this file orchestrates the entire 22-component system.

var builder = DistributedApplication.CreateBuilder(args);

// ── Open-source secondary track: OTel Collector ────────────────────────────
//
// Expose fixed host ports (isProxied: false) so:
//   - verify.ps1 can docker-logs the collector
//   - ApplicationInsights IngestionEndpoint=http://localhost:4318 works
//   - services can OTLP-export to http://127.0.0.1:4317
//
// WithBindMount uses a relative path from the AppHost project directory.
// Forward slashes work on Windows with Docker Desktop WSL2 backend.

_ = builder.AddContainer("otel-collector",
        "otel/opentelemetry-collector-contrib",
        "0.102.0")
    .WithBindMount("../../config/otel-collector-config.yaml",
        "/etc/otelcol-contrib/config.yaml",
        isReadOnly: true)
    .WithEndpoint(
        targetPort: 4317,
        port: 4317,
        name: "grpc",
        scheme: "http",
        isExternal: false,
        isProxied: false)
    .WithEndpoint(
        targetPort: 4318,
        port: 4318,
        name: "http",
        scheme: "http",
        isExternal: false,
        isProxied: false)
    .WithEndpoint(
        targetPort: 55679,
        port: 55679,
        name: "zpages",
        scheme: "http",
        isExternal: true,
        isProxied: false);

// ── .NET services ──────────────────────────────────────────────────────────
//
// Do NOT override OTEL_EXPORTER_OTLP_ENDPOINT — Aspire injects the Dashboard
// OTLP endpoint so Structured Logs / Traces / Metrics appear in the UI.
//
// OTEL_COLLECTOR_ENDPOINT is a second export target (ServiceDefaults) so
// verify.ps1 can still assert against collector docker logs.

var collectorEndpoint = "http://127.0.0.1:4317";

builder.AddProject<Projects.UserService>("user-service")
    .WithExternalHttpEndpoints()
    .WithEnvironment("OTEL_COLLECTOR_ENDPOINT", collectorEndpoint);

builder.AddProject<Projects.OrderService>("order-service")
    .WithExternalHttpEndpoints()
    .WithEnvironment("OTEL_COLLECTOR_ENDPOINT", collectorEndpoint);

builder.Build().Run();
