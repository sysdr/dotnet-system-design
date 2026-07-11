// src/AppHost/Program.cs
// Post 1 of 45 — .NET Aspire AppHost
// This is the C# equivalent of docker-compose.yml.
// Every service, container, and connection is declared here with full type safety.
//
// CUMULATIVE FILE: each subsequent post adds resources here.
// By Post 45, this file orchestrates the entire 22-component system.

var builder = DistributedApplication.CreateBuilder(args);

// ── .NET services ──────────────────────────────────────────────────────────
//
// AddProject<T> registers a .NET project as an Aspire resource.
// Aspire automatically:
//   1. Assigns a dynamic local port (avoids IIS Express conflicts on Windows)
//   2. Sets OTEL_EXPORTER_OTLP_ENDPOINT pointing to its own built-in OTLP endpoint
//   3. Sets OTEL_SERVICE_NAME to the resource name ("user-service")
//   4. Shows the service in the Dashboard at http://localhost:15888
//
// WithExternalHttpEndpoints() makes the endpoint accessible from Windows browser.

var userService = builder.AddProject<Projects.UserService>("user-service")
    .WithExternalHttpEndpoints()
    // Secondary export for verify.ps1 collector checks. Do NOT override
    // OTEL_EXPORTER_OTLP_ENDPOINT — Aspire injects the dashboard OTLP endpoint.
    .WithEnvironment("OTEL_COLLECTOR_ENDPOINT", "http://localhost:4317");

var orderService = builder.AddProject<Projects.OrderService>("order-service")
    .WithExternalHttpEndpoints()
    .WithEnvironment("OTEL_COLLECTOR_ENDPOINT", "http://localhost:4317");

// ── Open-source secondary track: OTel Collector ────────────────────────────
//
// The Aspire Dashboard handles ALL telemetry for local development.
// This container demonstrates the Collector pipeline model in isolation:
//   otlp receiver → batch processor → logging exporter (stdout)
//
// In Post 9 this AddContainer() call changes to:
//   builder.AddAzureServiceBus("messaging")
// The .NET services (UserService, OrderService) change ZERO lines.
// Only the connection string in their environment changes.
//
// WithBindMount uses a relative path from the AppHost project directory.
// Forward slashes work on Windows with Docker Desktop WSL2 backend.

builder.AddContainer("otel-collector",
        "otel/opentelemetry-collector-contrib",
        "0.102.0")
    .WithBindMount("../../config/otel-collector-config.yaml",
        "/etc/otelcol-contrib/config.yaml",
        isReadOnly: true)
    .WithEndpoint(
        port: 4317,
        targetPort: 4317,
        name: "grpc",
        scheme: "http",
        isProxied: false,
        isExternal: false)
    .WithEndpoint(
        port: 55679,
        targetPort: 55679,
        name: "zpages",
        scheme: "http",
        isProxied: false,
        isExternal: true);

builder.Build().Run();
