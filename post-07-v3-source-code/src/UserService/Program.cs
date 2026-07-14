// src/UserService/Program.cs
// CUMULATIVE — Post 5: replace magic string attribute names with
// TelemetryConstants compile-time constants.
//
// Post 1: Minimal API + OTel + health checks
// Post 2: Serilog enrichers (via ServiceDefaults)
// Post 3: OTel SemanticConventions + ValidateCredentials span
// Post 4: multi-severity logs + /users/{id}/profile
// Post 5: TelemetryConstants constants replace string literals NEW

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Trace;
using ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

var app = builder.Build();
app.MapDefaultEndpoints();

var activitySource = Extensions.ActivitySource;

app.MapGet("/users/ping", () => Results.Ok("pong"));

app.MapPost("/users/login", (ILogger<Program> logger) =>
{
    var userId    = "user-" + Random.Shared.Next(1000, 9999);
    var ipAddress = $"192.168.1.{Random.Shared.Next(1, 254)}";

    using var activity = activitySource.StartActivity("ValidateCredentials");
    activity?.SetTag(TraceSemanticConventions.AttributeEnduserRole,
                     TelemetryConstants.AttrEndUserRole);  // compile-time

    // Name appears in collector LogRecords so verify.ps1 can assert the span ran
    // without a second OTLP trace exporter (incompatible with UseOtlpExporter).
    logger.LogInformation(
        "ValidateCredentials span. Login attempt. {UserId} {IpAddress} {EndUserRole}",
        userId, ipAddress,
        TelemetryConstants.AttrEndUserRole);

    if (Random.Shared.Next(10) == 0)
        logger.LogWarning(
            "Slow credential validation. {UserId} {ElapsedMs}",
            userId, Random.Shared.Next(800, 2000));

    return Results.Ok(new { UserId = userId, Status = "authenticated" });
});

app.MapGet("/users/{id}/profile", async (string id, ILogger<Program> logger,
    IHttpClientFactory httpFactory) =>
{
    logger.LogInformation("Profile request. {UserId}", id);
    var client = httpFactory.CreateClient();
    try
    {
        var response = await client.GetAsync("http://order-service/orders/ping");
        logger.LogInformation("Downstream ping. {UserId} {ElapsedMs}",
            id, (int)response.StatusCode);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Downstream call failed. {UserId}", id);
    }
    return Results.Ok(new { UserId = id, DisplayName = $"User {id}" });
});

app.MapPut("/orders/{id}/cancel", (string id, ILogger<Program> logger) =>
{
    logger.LogWarning("Cancel attempted. {OrderId}", id);
    return Results.BadRequest(new { Error = "Order not found" });
});

app.Run();
