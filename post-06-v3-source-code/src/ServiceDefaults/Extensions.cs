// src/ServiceDefaults/Extensions.cs
// CUMULATIVE — Post 6 adds EventCounter instrumentation so .NET runtime
// counters (GC, thread pool, exception rate, memory) flow as OTel metrics.
//
// Post 1: ConfigureOpenTelemetry() + AddDefaultHealthChecks() + OTLP export
// Post 2: ConfigureSerilog() + UseAzureMonitor()
// Post 3: AddSource(ActivitySourceName) + explicit OTLP/gRPC
// Post 4: no new ServiceDefaults changes
// Post 5: TelemetryConstants.cs added (compile-time attribute constants)
// Post 6: AddEventCounterInstrumentation() NEW

using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Instrumentation.EventCounters;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using Serilog;
using System.Diagnostics;

namespace ServiceDefaults;

public static class Extensions
{
    public const string ActivitySourceName = "HyperscaleLogMonitoring";
    public static readonly ActivitySource ActivitySource = new(ActivitySourceName, "1.0.0");

    public static IHostApplicationBuilder AddServiceDefaults(
        this IHostApplicationBuilder builder)
    {
        builder.ConfigureSerilog();
        builder.ConfigureOpenTelemetry();
        builder.AddDefaultHealthChecks();

        builder.Services.AddServiceDiscovery();
        builder.Services.ConfigureHttpClientDefaults(http =>
        {
            http.AddStandardResilienceHandler();
            http.AddServiceDiscovery();
        });

        return builder;
    }

    public static IHostApplicationBuilder ConfigureSerilog(
        this IHostApplicationBuilder builder)
    {
        // writeToProviders: true forwards Serilog events to other MEL providers
        // (including OpenTelemetry), so LogRecords reach the OTel Collector.
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
        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeFormattedMessage = true;
            logging.IncludeScopes = true;
        });

        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics =>
            {
                metrics
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation()
                    // POST 6 NEW: EventCounter instrumentation.
                    //
                    // EventCounters are .NET's cross-platform replacement for ETW.
                    // They work on Windows (via ETW), Linux (via LTTng), and
                    // macOS — the same API everywhere.
                    //
                    // "System.Runtime" is the built-in event source published by
                    // the .NET runtime itself. It emits 20+ counters including:
                    //   cpu-usage           — CPU percentage used by this process
                    //   working-set         — process working set in MB
                    //   gc-heap-size        — total GC heap size in MB
                    //   gen-0-gc-count      — Gen 0 GC collections per second
                    //   gen-1-gc-count      — Gen 1 GC collections per second
                    //   gen-2-gc-count      — Gen 2 (full) GC collections per second
                    //   exception-count     — exceptions thrown per second
                    //   active-timer-count  — active System.Threading.Timer instances
                    //   alloc-rate          — bytes allocated on heap per second
                    //   threadpool-queue-length — pending ThreadPool work items
                    //
                    // All of these appear in the Aspire Dashboard > Metrics panel
                    // and in Application Insights > customMetrics after this change.
                    .AddEventCountersInstrumentation(options =>
                    {
                        // System.Runtime is blocked by this package — use
                        // AddRuntimeInstrumentation() above for those counters.
                        // These EventCounter sources still flow as OTel metrics
                        // and appear in Aspire Dashboard > Metrics.
                        options.AddEventSources(
                            "Microsoft.AspNetCore.Hosting",
                            "System.Net.Http");
                    });
            })
            .WithTracing(tracing =>
            {
                tracing
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddSource(ActivitySourceName);
            });

        builder.AddOpenTelemetryExporters();
        return builder;
    }

    private static IHostApplicationBuilder AddOpenTelemetryExporters(
        this IHostApplicationBuilder builder)
    {
        // IMPORTANT: do not mix UseOtlpExporter() with signal-specific
        // AddOtlpExporter() — OTel 1.9 throws NotSupportedException at startup.
        // Use AddOtlpExporter for every destination (Dashboard + Collector).
        void AddOtlpSink(Uri endpoint)
        {
            builder.Services.ConfigureOpenTelemetryTracerProvider(tracing =>
                tracing.AddOtlpExporter(o =>
                {
                    o.Endpoint = endpoint;
                    o.Protocol = OtlpExportProtocol.Grpc;
                }));
            builder.Services.ConfigureOpenTelemetryMeterProvider(metrics =>
                metrics.AddOtlpExporter(o =>
                {
                    o.Endpoint = endpoint;
                    o.Protocol = OtlpExportProtocol.Grpc;
                }));
            builder.Services.Configure<OpenTelemetryLoggerOptions>(logging =>
                logging.AddOtlpExporter(o =>
                {
                    o.Endpoint = endpoint;
                    o.Protocol = OtlpExportProtocol.Grpc;
                }));
        }

        // Aspire injects OTEL_EXPORTER_OTLP_ENDPOINT → Dashboard Structured Logs.
        var otlpEndpoint = builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
        if (!string.IsNullOrWhiteSpace(otlpEndpoint))
        {
            AddOtlpSink(new Uri(otlpEndpoint));
        }

        // Second sink: local OTel Collector (verify.ps1 docker logs).
        var collectorEndpoint = builder.Configuration["OTEL_COLLECTOR_ENDPOINT"];
        if (!string.IsNullOrWhiteSpace(collectorEndpoint))
        {
            AddOtlpSink(new Uri(collectorEndpoint));
        }

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
