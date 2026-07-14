// src/OrderService/Program.cs
// CUMULATIVE — Post 7: send OrderCreatedEvent to Service Bus via BinaryData.
//
// Post 1: Minimal API + OTel + health checks
// Post 2: Serilog enrichers (via ServiceDefaults)
// Post 3: OTel SemanticConventions + ValidateCredentials span
// Post 4: multi-span /orders/create + HttpClient dependency span
// Post 5: TelemetryConstants constants
// Post 7: OrderCreatedEvent published to Service Bus "orders" queue NEW

using Azure.Messaging.ServiceBus;
using Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ServiceDefaults;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

// POST 7: Register ServiceBusClient as a singleton.
// Connection string comes from appsettings.json or environment variable.
// In Aspire AppHost, it is injected automatically via WithReference().
// In docker-compose, it is set in the environment block.
//
// WHY singleton: ServiceBusClient manages TCP connections and AMQP sessions.
// Creating a new client per request is expensive and causes connection pool
// exhaustion under load. One client per service process, many senders/receivers.
var sbConnectionString = builder.Configuration["ConnectionStrings:servicebus"]
                      ?? builder.Configuration["ServiceBus:ConnectionString"];

ServiceBusClient? serviceBusClient = null;
if (!string.IsNullOrWhiteSpace(sbConnectionString))
{
    serviceBusClient = new ServiceBusClient(sbConnectionString);
    builder.Services.AddSingleton(serviceBusClient);
    builder.Services.AddSingleton(_ => serviceBusClient.CreateSender("orders"));
}

var app = builder.Build();
app.MapDefaultEndpoints();

var activitySource = Extensions.ActivitySource;

app.MapGet("/orders/ping", () => Results.Ok("pong"));

app.MapPost("/orders/create", async (
    ILogger<Program> logger,
    IServiceProvider sp) =>
{
    var sender = sp.GetService<ServiceBusSender>();
    var orderId  = $"order-{Random.Shared.Next(10000, 99999)}";
    var tenantId = $"tenant-{Random.Shared.Next(1, 10):D2}";

    using var createSpan = activitySource.StartActivity("CreateOrder");
    createSpan?.SetTag(TelemetryConstants.AttrOrderId,  orderId);
    createSpan?.SetTag(TelemetryConstants.AttrTenantId, tenantId);

    logger.LogInformation(
        "CreateOrder span. Order creation started. {OrderId} {TenantId}",
        orderId, tenantId);

    await Task.Delay(Random.Shared.Next(20, 80));

    // POST 7: Build the domain event and serialise it to the wire.
    var orderEvent = new OrderCreatedEvent
    {
        OrderId    = orderId,
        TenantId   = tenantId,
        CreatedAt  = DateTimeOffset.UtcNow.ToString("O"),
        AmountCents= Random.Shared.Next(500, 50000),
        Currency   = "USD",
    };

    using var publishSpan = activitySource.StartActivity("PublishOrderEvent");
    publishSpan?.SetTag(TelemetryConstants.AttrEventType, "OrderCreated");
    publishSpan?.SetTag(TelemetryConstants.AttrTenantId,   tenantId);

    // Always serialise so PayloadBytes is measurable even without Service Bus.
    var body = BinaryData.FromObjectAsJson(
        orderEvent,
        OrderCreatedEventJsonContext.Default.Options);

    if (sender is not null)
    {
        // POST 7: BinaryData.FromObjectAsJson<T> with source-generated context.
        // This is the preferred Azure SDK pattern:
        //   - Source generator context → AOT-safe, no reflection
        //   - BinaryData → Azure SDK's universal message body type
        //   - ContentType header → helps subscribers skip deserialisation
        var message = new ServiceBusMessage(body)
        {
            ContentType            = "application/json",
            Subject                = "OrderCreated",
            // TenantId as application property — used for SQL filter routing (Post 25)
            ApplicationProperties  = { [TelemetryConstants.AttrTenantId] = tenantId },
            // MessageId prevents duplicate processing if the publisher retries
            MessageId              = orderId,
        };

        await sender.SendMessageAsync(message);

        logger.LogInformation(
            "PublishOrderEvent OrderCreated event sent. {OrderId} {TenantId} {PayloadBytes}",
            orderId, tenantId, body.ToMemory().Length);
    }
    else
    {
        // Service Bus not configured — still log PayloadBytes so wire-size
        // checks (verify.ps1 / Explore it) work without the emulator.
        logger.LogInformation(
            "PublishOrderEvent OrderCreated event serialised (Service Bus not configured). {OrderId} {TenantId} {PayloadBytes}",
            orderId, tenantId, body.ToMemory().Length);
    }

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
