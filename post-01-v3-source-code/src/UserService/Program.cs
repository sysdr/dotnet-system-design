using ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);

// One line. OTel, health checks, service discovery — all wired via ServiceDefaults.
// AddServiceDefaults() reads OTEL_EXPORTER_OTLP_ENDPOINT from the environment,
// which Aspire sets automatically. Running outside Aspire? Set it manually:
//   $env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317"
builder.AddServiceDefaults();

var app = builder.Build();

// Maps /health (readiness) and /alive (liveness) — used by verify.ps1 checks 2 & 3
app.MapDefaultEndpoints();

// ── Endpoints ──────────────────────────────────────────────────────────────
//
// The {Token} syntax is critical. UserId={UserId} stores UserId as a named
// attribute on the LogRecord — not embedded in the Body string.
// In the Aspire Dashboard: click "Structured Logs" → UserId is a filterable column.
// In Application Insights (Post 2): KQL `where UserId == "4821"` works.
// With string interpolation ($"UserId={userId}") neither query is possible.

app.MapGet("/users/ping", (ILogger<Program> logger) =>
{
    logger.LogInformation("User service ping. Version={ServiceVersion}", "1.0.0");
    return Results.Ok(new { service = "user-service", status = "ok", ts = DateTime.UtcNow });
});

app.MapPost("/users/login", (ILogger<Program> logger) =>
{
    logger.LogInformation(
        "Login attempt. UserId={UserId} IpAddress={IpAddress}",
        Random.Shared.Next(1000, 9999),
        "192.168.1.1");
    return Results.Ok(new { authenticated = true });
});

app.MapPost("/users/logout", (ILogger<Program> logger) =>
{
    logger.LogInformation(
        "User logout. UserId={UserId} SessionDurationSeconds={SessionDurationSeconds}",
        Random.Shared.Next(1000, 9999),
        Random.Shared.Next(60, 3600));
    return Results.Ok(new { loggedOut = true });
});

app.Run();
