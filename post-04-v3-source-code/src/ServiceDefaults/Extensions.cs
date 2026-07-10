// src/ServiceDefaults/Extensions.cs
// CUMULATIVE — Post 3 adds explicit OTLP/gRPC configuration and the
// ActivitySource factory method. Posts 1–2 components unchanged.
//
// Post 1: ConfigureOpenTelemetry() + AddDefaultHealthChecks() + UseOtlpExporter()
// Post 2: ConfigureSerilog() + UseAzureMonitor() activated
// Post 3: AddHyperscaleActivitySource() NEW + explicit OTLP gRPC configuration

using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using Serilog;
using System.Diagnostics;

namespace ServiceDefaults;

public static class Extensions
{
    // POST 3: The shared ActivitySource used by all services for manual spans.
    // Registered as a singleton — one instance per service process.
    // Usage in service: activitySource.StartActivity("ProcessOrder")
    public const string ActivitySourceName = "HyperscaleLogMonitoring";
    public static readonly ActivitySource ActivitySource = new(ActivitySourceName, "1.0.0");

    public static IHostApplicationBuilder AddServiceDefaults(
        this IHostApplicationBuilder builder)
    {
        builder.ConfigureSerilog();
        builder.ConfigureOpenTelemetry();
        builder.AddDefaultHealthChecks();
        return builder;
    }

    public static IHostApplicationBuilder ConfigureSerilog(
        this IHostApplicationBuilder builder)
    {
        builder.Services.AddSerilog((services, config) =>
        {
            config
                .ReadFrom.Configuration(builder.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                .Enrich.WithMachineName()
                .Enrich.WithThreadId();
        });
        return builder;
    }

    public static IHostApplicationBuilder ConfigureOpenTelemetry(
        this IHostApplicationBuilder builder)
    {
        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;
        });

        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics =>
            {
                metrics.AddAspNetCoreInstrumentation()
                       .AddHttpClientInstrumentation()
                       .AddRuntimeInstrumentation();
            })
            .WithTracing(tracing =>
            {
                tracing.AddAspNetCoreInstrumentation()
                       .AddHttpClientInstrumentation()
                       // POST 3: Register the shared ActivitySource so the OTel SDK
                       // captures manual spans created with Extensions.ActivitySource.
                       .AddSource(ActivitySourceName);
            });

        builder.AddOpenTelemetryExporters();
        return builder;
    }

    private static IHostApplicationBuilder AddOpenTelemetryExporters(
        this IHostApplicationBuilder builder)
    {
        // POST 3: Explicit OTLP/gRPC configuration.
        // The Aspire AppHost sets OTEL_EXPORTER_OTLP_ENDPOINT automatically.
        // Outside Aspire (Docker Compose, standalone), set it in .env or appsettings.
        //
        // OTLP/gRPC (port 4317): persistent connections, HTTP/2, best throughput.
        // Always use gRPC in production. Only use HTTP (port 4318) for debugging
        // with tools like curl that cannot speak gRPC.
        var otlpEndpoint = builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            builder.Services.AddOpenTelemetry()
                .UseOtlpExporter(OtlpExportProtocol.Grpc, new Uri(otlpEndpoint));
        }

        // Application Insights — activated in Post 2
        var aiConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
        if (!string.IsNullOrWhiteSpace(aiConnectionString))
        {
            builder.Services.AddOpenTelemetry()
                .UseAzureMonitor(o => o.ConnectionString = aiConnectionString);
        }

        return builder;
    }

    public static IHostApplicationBuilder AddDefaultHealthChecks(
        this IHostApplicationBuilder builder)
    {
        builder.Services.AddHealthChecks()
            .AddCheck("self", () => HealthCheckResult.Healthy(), ["live"]);
        return builder;
    }

    public static WebApplication MapDefaultEndpoints(this WebApplication app)
    {
        app.MapHealthChecks("/health");
        app.MapHealthChecks("/alive", new HealthCheckOptions
        {
            Predicate = r => r.Tags.Contains("live")
        });
        return app;
    }
}
