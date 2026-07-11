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
using Microsoft.Extensions.Configuration;
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
        builder.Services.AddHttpClient();
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
        }, writeToProviders: true);
        return builder;
    }

    public static IHostApplicationBuilder ConfigureOpenTelemetry(
        this IHostApplicationBuilder builder)
    {
        var dashboardEndpoint = builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
        var collectorEndpoint = builder.Configuration["OTEL_COLLECTOR_ENDPOINT"];
        var exportToDashboard = !string.IsNullOrWhiteSpace(dashboardEndpoint);
        var exportToCollector = !string.IsNullOrWhiteSpace(collectorEndpoint);
        Uri? collectorUri = exportToCollector ? new Uri(collectorEndpoint!) : null;

        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;

            if (exportToDashboard)
            {
                logging.AddOtlpExporter(o => ConfigureDashboardExporter(o, builder.Configuration));
            }

            if (collectorUri is not null)
            {
                logging.AddOtlpExporter(o => ConfigureCollectorExporter(o, collectorUri));
            }
        });

        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics =>
            {
                metrics.AddAspNetCoreInstrumentation()
                       .AddHttpClientInstrumentation()
                       .AddRuntimeInstrumentation();

                if (exportToDashboard)
                {
                    metrics.AddOtlpExporter(o => ConfigureDashboardExporter(o, builder.Configuration));
                }

                if (collectorUri is not null)
                {
                    metrics.AddOtlpExporter(o => ConfigureCollectorExporter(o, collectorUri));
                }
            })
            .WithTracing(tracing =>
            {
                tracing.AddAspNetCoreInstrumentation()
                       .AddHttpClientInstrumentation()
                       .AddSource(ActivitySourceName);

                if (exportToDashboard)
                {
                    tracing.AddOtlpExporter(o => ConfigureDashboardExporter(o, builder.Configuration));
                }

                if (collectorUri is not null)
                {
                    tracing.AddOtlpExporter(o => ConfigureCollectorExporter(o, collectorUri));
                }
            });

        var aiConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
        if (!string.IsNullOrWhiteSpace(aiConnectionString))
        {
            builder.Services.AddOpenTelemetry()
                .UseAzureMonitor(o => o.ConnectionString = aiConnectionString);
        }

        return builder;
    }

    private static void ConfigureDashboardExporter(
        OtlpExporterOptions options,
        IConfiguration configuration)
    {
        var endpoint = configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
        if (!string.IsNullOrWhiteSpace(endpoint))
        {
            options.Endpoint = new Uri(endpoint);
        }

        options.Protocol = OtlpExportProtocol.Grpc;

        var headers = configuration["OTEL_EXPORTER_OTLP_HEADERS"];
        if (!string.IsNullOrWhiteSpace(headers))
        {
            options.Headers = headers;
        }
    }

    private static void ConfigureCollectorExporter(
        OtlpExporterOptions options,
        Uri collectorUri)
    {
        // Secondary export for verify.ps1 collector checks in Aspire mode.
        options.Endpoint = collectorUri;
        options.Protocol = OtlpExportProtocol.Grpc;
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
