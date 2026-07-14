# Architecture Notes — Post 2

## Decision: ConfigureSerilog() runs before ConfigureOpenTelemetry()
The OTel ILogger bridge captures records enriched by Serilog only if Serilog is
registered first. The OTel bridge wraps whatever ILogger provider is already
registered. Reversing the order means OTel captures un-enriched records —
MachineName and ThreadId will be absent from every record in the pipeline.

## Decision: ExcludedTypes = "Exception" is set unconditionally
No valid production scenario justifies sampling exceptions. The App Insights
storage overhead for exception telemetry is negligible. The cost of missing
exceptions at a 10% sampling rate is Incident 2 from the lead magnet PDF.
The setting is in appsettings.json (not code) so it is visible to non-engineers
performing configuration audits.

## Decision: Application Insights connection string uses localhost:4318 for local dev
The Azure Monitor OTel Distro expects a valid Azure Monitor ingestion endpoint.
For local development, the IngestionEndpoint points to the OTel Collector's HTTP
receiver at localhost:4318. Data flows through the Collector to stdout, where
verify.ps1 can confirm it arrived. In production (Post 36), replace with the
real connection string from az monitor app-insights component show.

## Post 2 component inventory
| Component | Technology | New in Post |
|---|---|---|
| Serilog | Serilog.AspNetCore 8.0.3 | Post 2 |
| MachineName enricher | Serilog.Enrichers.Environment 3.0.1 | Post 2 |
| ThreadId enricher | Serilog.Enrichers.Thread 4.0.0 | Post 2 |
| App Insights OTel Distro | Azure.Monitor.OpenTelemetry.AspNetCore 1.3.0 | Post 2 (activated) |
