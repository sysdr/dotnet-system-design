// src/OrderService/Program.cs
// CUMULATIVE — Post 5: TelemetryConstants constants replace string literals.

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Logging;
using ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

var app = builder.Build();
app.MapDefaultEndpoints();

var activitySource = Extensions.ActivitySource;

app.MapGet("/orders/ping", () => Results.Ok("pong"));

app.MapPost("/orders/create", async (ILogger<Program> logger) =>
{
    var orderId  = $"order-{Random.Shared.Next(10000, 99999)}";
    var tenantId = $"tenant-{Random.Shared.Next(1, 10):D2}";

    using var createSpan = activitySource.StartActivity("CreateOrder");
    // POST 5: TelemetryConstants.AttrOrderId instead of "OrderId"
    // TelemetryConstants.AttrTenantId instead of "TenantId"
    createSpan?.SetTag(TelemetryConstants.AttrOrderId,  orderId);
    createSpan?.SetTag(TelemetryConstants.AttrTenantId, tenantId);

    logger.LogInformation(
        "Order creation started. {OrderId} {TenantId}",
        orderId, tenantId);

    await Task.Delay(Random.Shared.Next(20, 80));

    using var publishSpan = activitySource.StartActivity("PublishOrderEvent");
    // POST 5: TelemetryConstants.AttrEventType instead of "EventType"
    publishSpan?.SetTag(TelemetryConstants.AttrEventType, "OrderCreated");
    publishSpan?.SetTag(TelemetryConstants.AttrTenantId,   tenantId);

    logger.LogInformation(
        "OrderCreated event queued. {OrderId} {EventType}",
        orderId, TelemetryConstants.AttrEventType);

    await Task.Delay(Random.Shared.Next(5, 25));

    return Results.Created($"/orders/{orderId}",
        new { OrderId = orderId, TenantId = tenantId, Status = "created" });
});

app.MapDelete("/orders/{id}", (string id, ILogger<Program> logger) =>
{
    logger.LogWarning("Cancel requested. {OrderId}", id);
    logger.LogError("Cancel blocked — payment processed. {OrderId}", id);
    return Results.Conflict(new { Error = "Cannot cancel paid order" });
});

app.Run();
