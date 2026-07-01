using ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();

var app = builder.Build();
app.MapDefaultEndpoints();

app.MapGet("/orders/ping", (ILogger<Program> logger) =>
{
    logger.LogInformation("Order service ping. Version={ServiceVersion}", "1.0.0");
    return Results.Ok(new { service = "order-service", status = "ok", ts = DateTime.UtcNow });
});

app.MapPost("/orders/create", (ILogger<Program> logger) =>
{
    var orderId = Guid.NewGuid().ToString()[..8];
    // OrderId, CustomerId, Amount become queryable columns in the Aspire Dashboard.
    // Post 24 uses Amount to flag unusually large orders as a Sentinel security signal.
    logger.LogInformation(
        "Order created. OrderId={OrderId} CustomerId={CustomerId} Amount={Amount} Currency={Currency}",
        orderId,
        Random.Shared.Next(100, 999),
        Math.Round(Random.Shared.NextDouble() * 500 + 10, 2),
        "USD");
    return Results.Created($"/orders/{orderId}", new { orderId });
});

app.MapPut("/orders/{orderId}/cancel", (string orderId, ILogger<Program> logger) =>
{
    logger.LogWarning(
        "Order cancellation. OrderId={OrderId} Reason={Reason}",
        orderId, "customer_request");
    return Results.Ok(new { orderId, status = "cancelled" });
});

app.Run();
