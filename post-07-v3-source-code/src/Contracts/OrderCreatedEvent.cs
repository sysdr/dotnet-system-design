// src/Contracts/OrderCreatedEvent.cs — POST 7
// Shared domain event. Published by OrderService, consumed by processors (Post 9+).
namespace Contracts;

public sealed record OrderCreatedEvent
{
    public required string OrderId      { get; init; }
    public required string TenantId     { get; init; }
    public required string CreatedAt    { get; init; }
    public int    EventVersion          { get; init; } = 1;
    public long   AmountCents           { get; init; }
    public string Currency              { get; init; } = "USD";
}
