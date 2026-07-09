// src/UserService/Program.cs
// CUMULATIVE — Post 3 adds semantic convention attributes and a manual
// ActivitySource span on the login endpoint.
//
// Post 1: Minimal API + OTel + health checks
// Post 2: Serilog enrichers activated (via ServiceDefaults)
// Post 3: Semantic convention attributes + manual Activity span NEW

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Trace;
using ServiceDefaults;
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

var app = builder.Build();
app.MapDefaultEndpoints();

// POST 3: Use the shared ActivitySource from ServiceDefaults.
// Manual spans let you trace business-logic boundaries that HTTP instrumentation
// does not see — e.g., "ValidateCredentials" is not an HTTP call.
var activitySource = Extensions.ActivitySource;

app.MapPost("/users/login", (ILogger<Program> logger) =>
{
    var userId    = "user-" + Random.Shared.Next(1000, 9999);
    var ipAddress = $"192.168.1.{Random.Shared.Next(1, 254)}";

    // POST 3: Manual span for the credential validation step.
    // This span is a child of the HTTP request span — the parent is set
    // automatically because ASP.NET Core instrumentation set Activity.Current.
    using var activity = activitySource.StartActivity("ValidateCredentials");
    activity?.SetTag(TraceSemanticConventions.AttributeEnduserRole, "user");

    // POST 3: Semantic convention attributes on the log record.
    // TraceSemanticConventions.Attribute* are compile-time string constants.
    // They prevent the silent drift where one team writes "UserId" and another
    // writes "user_id" — the KQL filter breaks when attribute names differ.
    logger.LogInformation(
        "Login attempt. {UserId} {IpAddress} {EndUserRole}",
        userId,
        ipAddress,
        "user");

    return Results.Ok(new { UserId = userId, Status = "authenticated" });
});

app.MapGet("/users/ping", () => Results.Ok("pong"));

app.MapPut("/orders/{id}/cancel", (string id, ILogger<Program> logger) =>
{
    logger.LogWarning("Cancel attempted on order {OrderId} — validation failed", id);
    return Results.BadRequest(new { Error = "Order not found", OrderId = id });
});

app.Run();
