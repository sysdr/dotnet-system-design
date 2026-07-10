// src/OrderService/Program.cs
// CUMULATIVE — Post 4 adds /orders/create endpoint with a multi-span trace
// so the Aspire Dashboard Traces view shows a meaningful waterfall.
//
// Post 1: health checks + /orders/ping
// Post 2: Serilog enrichers (via ServiceDefaults)
// Post 3: OTel semantic conventions (via ServiceDefaults)
// Post 4: multi-span /orders/create endpoint NEW

using Microsoft.AspNetCore.Builder;
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
    service = "order-service",
    status = "running",
    endpoints = new[]
    {
        "GET    /orders/ping",
        "POST   /orders/create",
        "DELETE /orders/{id}",
        "GET    /health",
        "GET    /alive"
    }
}));

app.MapGet("/orders/ping", () => Results.Ok("pong"));

// POST 4: Multi-span endpoint for the Aspire Dashboard Traces deep dive.
// This endpoint deliberately creates a 3-level span hierarchy so the
// trace waterfall in the Dashboard shows parent → child → grandchild.
//
// Span hierarchy:
//   [HTTP span — auto, created by ASP.NET Core instrumentation]
//     └── [CreateOrder — manual ActivitySource span]
//           └── [PublishOrderEvent — manual child span]
//
// In the Aspire Dashboard > Traces, click any operation ID to see
// all three spans with their timing and attributes.
app.MapPost("/orders/create", async (ILogger<Program> logger) =>
{
    var orderId  = $"order-{Random.Shared.Next(10000, 99999)}";
    var tenantId = $"tenant-{Random.Shared.Next(1, 10):D2}";

    // Span 1: the business operation — validate and persist the order
    using var createSpan = activitySource.StartActivity("CreateOrder");
    createSpan?.SetTag("orderId",  orderId);
    createSpan?.SetTag("tenantId", tenantId);
    createSpan?.SetTag(TraceSemanticConventions.AttributeEnduserRole, "user");

    logger.LogInformation(
        "Order creation started. {OrderId} {TenantId}",
        orderId, tenantId);

    // Simulate processing time — visible as span duration in the waterfall
    await Task.Delay(Random.Shared.Next(20, 80));

    // Span 2 (child of Span 1): publishing the domain event
    // In the Dashboard waterfall, this appears indented under CreateOrder.
    using var publishSpan = activitySource.StartActivity("PublishOrderEvent");
    publishSpan?.SetTag("eventType", "OrderCreated");
    publishSpan?.SetTag("tenantId",  tenantId);

    logger.LogInformation(
        "OrderCreated event queued. {OrderId} {EventType}",
        orderId, "OrderCreated");

    await Task.Delay(Random.Shared.Next(5, 25));

    logger.LogInformation(
        "Order creation complete. {OrderId} {TenantId}",
        orderId, tenantId);

    return Results.Created($"/orders/{orderId}",
        new { OrderId = orderId, TenantId = tenantId, Status = "created" });
});

// POST 4: Endpoint that deliberately logs at Warning and Error levels
// so the Dashboard Structured Logs severity filter can be demonstrated.
app.MapDelete("/orders/{id}", (string id, ILogger<Program> logger) =>
{
    logger.LogWarning(
        "Order cancellation requested. {OrderId} — requires manual review",
        id);
    logger.LogError(
        "Order {OrderId} cannot be cancelled — payment already processed",
        id);
    return Results.Conflict(new { Error = "Cannot cancel paid order", OrderId = id });
});

app.Run();
