// src/ServiceDefaults/Extensions.cs
// CUMULATIVE — Post 3 adds explicit OTLP/gRPC configuration and the
// ActivitySource factory method. Posts 1–2 components unchanged.
//
// Post 1: ConfigureOpenTelemetry() + AddDefaultHealthChecks() + UseOtlpExporter()
// Post 2: ConfigureSerilog() + UseAzureMonitor() activated
// Post 3: ActivitySource NEW + explicit OTLP gRPC configuration

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
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using System.Diagnostics;

namespace ServiceDefaults;

public static class Extensions
{
    // POST 3: The shared ActivitySource used by all services for manual spans.
    public const string ActivitySourceName = "HyperscaleLogMonitoring";
    public static readonly ActivitySource ActivitySource = new(ActivitySourceName, "1.0.0");

    public static IHostApplicationBuilder AddServiceDefaults(
        this IHostApplicationBuilder builder)
    {
        builder.ConfigureOpenTelemetry();
        builder.ConfigureSerilog();
        builder.AddDefaultHealthChecks();
        return builder;
    }

    public static IHostApplicationBuilder ConfigureSerilog(
        this IHostApplicationBuilder builder)
    {
        if (builder is WebApplicationBuilder webBuilder)
        {
            // writeToProviders: true forwards Serilog output to other ILogger
            // providers (including OpenTelemetry) so LogRecords reach the collector.
            webBuilder.Host.UseSerilog((context, services, configuration) =>
            {
                configuration
                    .ReadFrom.Configuration(context.Configuration)
                    .ReadFrom.Services(services)
                    .Enrich.FromLogContext()
                    .Enrich.WithMachineName()
                    .Enrich.WithThreadId();
            }, writeToProviders: true);
        }

        return builder;
    }

    public static IHostApplicationBuilder ConfigureOpenTelemetry(
        this IHostApplicationBuilder builder)
    {
        var machineName = Environment.MachineName;

        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.SetResourceBuilder(ResourceBuilder
                .CreateDefault()
                .AddAttributes(new Dictionary<string, object>
                {
                    ["MachineName"] = machineName
                }));
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;
        });

        builder.Services.AddOpenTelemetry()
            .ConfigureResource(r => r.AddAttributes(new Dictionary<string, object>
            {
                ["MachineName"] = machineName
            }))
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
                       .AddSource(ActivitySourceName);
            });

        builder.AddOpenTelemetryExporters();
        return builder;
    }

    private static IHostApplicationBuilder AddOpenTelemetryExporters(
        this IHostApplicationBuilder builder)
    {
        var otlpEndpoint = builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            builder.Services.AddOpenTelemetry()
                .UseOtlpExporter(OtlpExportProtocol.Grpc, new Uri(otlpEndpoint));
        }

        var aiConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
        if (!string.IsNullOrWhiteSpace(aiConnectionString)
            && !aiConnectionString.Contains("localhost", StringComparison.OrdinalIgnoreCase))
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
