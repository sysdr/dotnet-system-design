// src/UserService/Program.cs
// CUMULATIVE — Post 4 adds multi-severity log records for Dashboard demo
// and a /users/{id}/profile endpoint that generates a dependency call.
//
// Post 1: /users/login + /users/ping
// Post 2: Serilog enrichers (via ServiceDefaults)
// Post 3: ValidateCredentials ActivitySource span + semantic conventions
// Post 4: multi-severity logs + /users/{id}/profile endpoint NEW

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Trace;
using ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

var app = builder.Build();
app.MapDefaultEndpoints();

var activitySource = Extensions.ActivitySource;

app.MapGet("/", () => Results.Ok(new
{
    service = "user-service",
    status = "running",
    endpoints = new[]
    {
        "GET  /users/ping",
        "POST /users/login",
        "GET  /users/{id}/profile",
        "GET  /health",
        "GET  /alive"
    }
}));

app.MapGet("/users/ping", () => Results.Ok("pong"));

app.MapPost("/users/login", (ILogger<Program> logger) =>
{
    var userId    = "user-" + Random.Shared.Next(1000, 9999);
    var ipAddress = $"192.168.1.{Random.Shared.Next(1, 254)}";

    using var activity = activitySource.StartActivity("ValidateCredentials");
    activity?.SetTag(TraceSemanticConventions.AttributeEnduserRole, "user");

    // POST 4: Log at multiple severity levels to demonstrate Dashboard filtering.
    // The Structured Logs panel has a Severity filter — these three records
    // let you switch between Information, Warning, and Error views.
    logger.LogDebug(
        "Credential lookup started. {UserId}", userId);

    logger.LogInformation(
        "Login attempt. {UserId} {IpAddress} {EndUserRole}",
        userId, ipAddress, "user");

    // Simulate occasional slow logins — visible in Traces waterfall duration
    if (Random.Shared.Next(10) == 0)
    {
        logger.LogWarning(
            "Slow credential validation. {UserId} {ElapsedMs}",
            userId, Random.Shared.Next(800, 2000));
    }

    return Results.Ok(new { UserId = userId, Status = "authenticated" });
});

// POST 4: New endpoint that generates a downstream HTTP call.
// In the Dashboard Traces view, this shows a second span (HttpClient)
// under the main HTTP request span — demonstrating automatic HttpClient
// instrumentation without any code changes.
app.MapGet("/users/{id}/profile", async (string id, ILogger<Program> logger,
    [FromServices] IHttpClientFactory httpFactory) =>
{
    logger.LogInformation("Profile request. {UserId}", id);

    // This HTTP call is automatically traced by OpenTelemetry.Instrumentation.Http.
    // In the Aspire Dashboard, you will see it as a child dependency span
    // under the /users/{id}/profile request span.
    var client = httpFactory.CreateClient();
    try
    {
        // Calls the ping endpoint on order-service via service discovery
        // (AppHost wires the service discovery automatically)
        var response = await client.GetAsync("http://order-service/orders/ping");
        logger.LogInformation(
            "Downstream order-service ping. {UserId} {StatusCode}",
            id, (int)response.StatusCode);
    }
    catch (Exception ex)
    {
        logger.LogError(ex,
            "Downstream order-service call failed. {UserId}", id);
    }

    return Results.Ok(new
    {
        UserId = id,
        DisplayName = $"User {id}",
        Email = $"{id}@example.com"
    });
});

app.MapPut("/orders/{id}/cancel", (string id, ILogger<Program> logger) =>
{
    logger.LogWarning("Cancel attempted on order {OrderId} — validation failed", id);
    return Results.BadRequest(new { Error = "Order not found", OrderId = id });
});

app.Run();
