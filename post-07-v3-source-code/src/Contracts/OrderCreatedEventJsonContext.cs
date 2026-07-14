// src/Contracts/OrderCreatedEventJsonContext.cs — POST 7
// System.Text.Json source generator — AOT-safe, compile-time serialisation.
// Usage: BinaryData.FromObjectAsJson(evt, OrderCreatedEventJsonContext.Default.Options)
using System.Text.Json.Serialization;

namespace Contracts;

[JsonSerializable(typeof(OrderCreatedEvent))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy   = JsonKnownNamingPolicy.CamelCase,
    WriteIndented          = false,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
public partial class OrderCreatedEventJsonContext : JsonSerializerContext { }
