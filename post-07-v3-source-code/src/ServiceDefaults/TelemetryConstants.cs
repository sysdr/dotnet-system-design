// src/ServiceDefaults/TelemetryConstants.cs
// POST 5: Compile-time constants for custom business attributes.
//
// PURPOSE: Prevent the silent attribute-name drift that breaks KQL queries.
// Instead of: logger.LogInformation("Login. {UserId}", id)  ← "UserId" string
// Use:        logger.LogInformation("Login. {AttrUserId}", id) and reference
//             TelemetryConstants.AttrUserId wherever the name is checked.
//
// When a constant name changes, every reference fails to compile — the same
// protection that TraceSemanticConventions.Attribute* provides for OTel
// standard attributes, applied to our custom business attributes.
//
// IMPORTANT: The string values in these constants are the actual attribute
// names that appear in Application Insights customDimensions and KQL queries.
// Do not change them without a migration plan — existing KQL queries,
// alert rules, and workbooks depend on these exact strings.

namespace ServiceDefaults;

/// <summary>
/// Custom business attribute names for this system's telemetry schema.
/// See docs/telemetry-schema.md for the full attribute contract.
/// </summary>
public static class TelemetryConstants
{
    // ── Identity attributes ──────────────────────────────────────────────
    // Used on authentication-related log records and spans.

    /// <summary>The authenticated user's internal identifier.</summary>
    /// <example>"user-4821"</example>
    public const string AttrUserId = "UserId";

    /// <summary>The client IP address for the request.</summary>
    /// <example>"192.168.1.42"</example>
    public const string AttrIpAddress = "IpAddress";

    /// <summary>The user's role within the system.</summary>
    /// <example>"user", "admin", "readonly"</example>
    public const string AttrEndUserRole = "EndUserRole";

    // ── Tenancy attributes ───────────────────────────────────────────────
    // Required on all records that are scoped to a specific tenant.
    // Used as the Service Bus message property for SQL filter routing (Post 25).

    /// <summary>
    /// The tenant identifier. Required on all multi-tenant records.
    /// Used as Service Bus message property for subscription routing.
    /// KQL invariant: no order record may lack this attribute.
    /// </summary>
    /// <example>"tenant-03"</example>
    public const string AttrTenantId = "TenantId";

    // ── Order domain attributes ──────────────────────────────────────────
    // Used on records related to the order creation and cancellation flows.

    /// <summary>The order's unique identifier.</summary>
    /// <example>"order-42178"</example>
    public const string AttrOrderId = "OrderId";

    /// <summary>The domain event type for event-sourcing records.</summary>
    /// <example>"OrderCreated", "OrderCancelled", "PaymentProcessed"</example>
    public const string AttrEventType = "EventType";

    // ── Observability attributes ─────────────────────────────────────────
    // Used on records related to the telemetry pipeline itself.

    /// <summary>Elapsed time in milliseconds — for slow-operation warnings.</summary>
    /// <example>850</example>
    public const string AttrElapsedMs = "ElapsedMs";
}
