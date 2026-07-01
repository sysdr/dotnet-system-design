// src/ServiceDefaults/Extensions.cs
// Shared wiring for every .NET service in the series.
// AddServiceDefaults() is the single call that gives every service:
//   - Production-grade OTel (logs, metrics, traces)
//   - Health check endpoints (/health and /alive)
//   - Service discovery (for inter-service calls in later posts)
//
// CUMULATIVE FILE: Post 2 adds AddAzureMonitor() inside ConfigureOpenTelemetry().
// Post 21 adds AddMicrosoftIdentityWebApiAuthentication().
// Services reference this project and gain all wiring automatically.

using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

namespace ServiceDefaults;

public static class Extensions
{
    /// <summary>
    /// Registers OTel telemetry, health checks, and service discovery.
    /// Call this once in Program.cs: builder.AddServiceDefaults()
    /// </summary>
    public static IHostApplicationBuilder AddServiceDefaults(
        this IHostApplicationBuilder builder)
    {
        builder.ConfigureOpenTelemetry();
        builder.AddDefaultHealthChecks();
        return builder;
    }

    public static IHostApplicationBuilder ConfigureOpenTelemetry(
        this IHostApplicationBuilder builder)
    {
        builder.Logging.AddOpenTelemetry(logging =>
        {
            // Stores the human-readable formatted string in LogRecord.Body.
            // Without this, Body is empty and only structured attributes survive.
            logging.IncludeFormattedMessage = true;

            // Propagates ASP.NET Core Activity context (TraceId, SpanId) into
            // every ILogger call made within an HTTP request scope.
            // This is the single line that makes cross-service log correlation work.
            // Remove it → TraceId disappears from every log record.
            logging.IncludeScopes = true;
        });

        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics =>
            {
                metrics.AddAspNetCoreInstrumentation()  // HTTP request metrics
                       .AddHttpClientInstrumentation()  // outbound HTTP metrics
                       .AddRuntimeInstrumentation();    // GC, thread pool, memory
            })
            .WithTracing(tracing =>
            {
                tracing.AddAspNetCoreInstrumentation()
                       .AddHttpClientInstrumentation();
            });

        builder.AddOpenTelemetryExporters();
        return builder;
    }

    private static IHostApplicationBuilder AddOpenTelemetryExporters(
        this IHostApplicationBuilder builder)
    {
        // Primary export path: OTLP → .NET Aspire Dashboard.
        // Aspire sets OTEL_EXPORTER_OTLP_ENDPOINT automatically for every
        // project it orchestrates. UseOtlpExporter() reads that environment variable.
        // If the variable is not set (e.g., running outside Aspire with docker-compose),
        // this call is a no-op — no exception, no missing data warning.
        var useOtlpExporter = !string.IsNullOrWhiteSpace(
            builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"]);

        if (useOtlpExporter)
        {
            builder.Services.AddOpenTelemetry().UseOtlpExporter();
        }

        // Azure Monitor / Application Insights export path.
        // Post 1: connection string is empty in appsettings.json → this block is skipped.
        // Post 2: a local connection string is added → App Insights receives all telemetry.
        // Production: replace with real Azure Monitor connection string → zero code change.
        //
        // Azure Monitor connection string format:
        //   "InstrumentationKey=00000000-0000-0000-0000-000000000000;
        //    IngestionEndpoint=https://eastus.in.applicationinsights.azure.com/;"
        var appInsightsConnectionString = builder.Configuration[
            "ApplicationInsights:ConnectionString"];

        if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
        {
            builder.Services.AddOpenTelemetry()
                .UseAzureMonitor(options =>
                {
                    options.ConnectionString = appInsightsConnectionString;
                });
        }

        return builder;
    }

    public static IHostApplicationBuilder AddDefaultHealthChecks(
        this IHostApplicationBuilder builder)
    {
        builder.Services.AddHealthChecks()
            // "self" tag: liveness check — is the .NET process alive?
            // Used by the /alive endpoint. Kubernetes liveness probe maps here.
            .AddCheck("self", () => HealthCheckResult.Healthy(), ["live"]);

        // Additional readiness checks (database connectivity, downstream services)
        // are added to this collection in Posts 9 and 12.
        return builder;
    }

    /// <summary>
    /// Maps /health (all checks) and /alive (liveness only) endpoints.
    /// Call this on WebApplication after Build(): app.MapDefaultEndpoints()
    /// </summary>
    public static WebApplication MapDefaultEndpoints(this WebApplication app)
    {
        // /health — full readiness check. Returns 200 when ALL health checks pass.
        // Kubernetes readiness probe and Azure Load Balancer health probe map here.
        app.MapHealthChecks("/health");

        // /alive — liveness only. Returns 200 if the process is running.
        // Separate from readiness: a service can be alive but not ready
        // (e.g., still connecting to Service Bus on startup).
        app.MapHealthChecks("/alive", new HealthCheckOptions
        {
            Predicate = r => r.Tags.Contains("live")
        });

        return app;
    }
}
