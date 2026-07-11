# Telemetry Schema — Distributed Systems with .NET
# Hyperscale Log Monitoring System · Attribute Contract v1.0
#
# PURPOSE
# ────────────────────────────────────────────────────────────────────
# This document is the authoritative source for attribute names in all
# telemetry emitted by services in this system.
#
# RULES
# 1. Every attribute in this file MUST be present on its designated
#    record type. Missing attributes fail the verify.ps1 schema check.
# 2. Attribute names are IMMUTABLE once a service is in production.
#    Renaming an attribute breaks KQL queries, alert rules, and
#    Application Insights workbooks that depend on it.
# 3. Standard OTel attributes (http.request.method, http.route, etc.)
#    are governed by the semantic conventions spec and use the
#    TraceSemanticConventions.Attribute* compile-time constants.
#    Custom attributes (UserId, TenantId, OrderId) are defined here.
# 4. Every new attribute requires a PR that updates this file,
#    updates the service code, and passes all verify.ps1 checks.
# ────────────────────────────────────────────────────────────────────

## Standard OTel Attributes (compile-time constants — do not use strings)
# Use TraceSemanticConventions.Attribute* from OpenTelemetry.SemanticConventions

| Attribute name                | OTel constant                                   | Type   | Required on       |
|-------------------------------|-------------------------------------------------|--------|-------------------|
| http.request.method           | AttributeHttpRequestMethod                      | string | every HTTP span   |
| http.response.status_code     | AttributeHttpResponseStatusCode                 | int    | every HTTP span   |
| http.route                    | AttributeHttpRoute                              | string | every HTTP span   |
| enduser.role                  | AttributeEnduserRole                            | string | login spans       |
| server.address                | AttributeServerAddress                          | string | downstream spans  |


## Custom Business Attributes (define here — never use string literals in code)
# Use the constants defined in ServiceDefaults/TelemetryConstants.cs (Post 5)

| Attribute name | C# constant                        | Type   | Required on                    | Example value          |
|----------------|------------------------------------|--------|--------------------------------|------------------------|
| UserId         | TelemetryConstants.AttrUserId      | string | user-service login records     | "user-4821"            |
| IpAddress      | TelemetryConstants.AttrIpAddress   | string | user-service login records     | "192.168.1.42"         |
| TenantId       | TelemetryConstants.AttrTenantId    | string | all multi-tenant records       | "tenant-03"            |
| OrderId        | TelemetryConstants.AttrOrderId     | string | order-service create records   | "order-42178"          |
| EventType      | TelemetryConstants.AttrEventType   | string | domain event publish records   | "OrderCreated"         |
| EndUserRole    | TelemetryConstants.AttrEndUserRole | string | authentication spans           | "user"                 |


## KQL Invariants — queries that MUST return results in a healthy system
# Run these in Application Insights > Logs or Kusto Emulator to verify
# the schema contract is being met in production.

```kql
// Invariant 1: every login record has UserId as a named attribute
traces
| where timestamp > ago(1h)
| where message has "Login"
| where isnull(customDimensions.UserId)
// Expected: zero rows. Any row = schema violation.

// Invariant 2: every HTTP span has semantic convention attributes
requests
| where timestamp > ago(1h)
| where isnull(customDimensions["http.request.method"])
// Expected: zero rows. Any row = OTel instrumentation misconfigured.

// Invariant 3: order records always carry TenantId
traces
| where timestamp > ago(1h)
| where message has "Order"
| where isnull(customDimensions.TenantId)
// Expected: zero rows. Any row = missing TenantId on order record.
```


## Change History

| Version | Date       | Change                                             | PR |
|---------|------------|----------------------------------------------------|----|
| 1.0     | Post 5     | Initial schema — UserId, IpAddress, TenantId, OrderId, EventType, EndUserRole | — |


## How to add a new attribute

1. Add the constant to `ServiceDefaults/TelemetryConstants.cs`
2. Use the constant in the relevant service's `Program.cs`
3. Add the attribute to the table above
4. Add a KQL Invariant query that fails if the attribute is missing
5. Add a verify.ps1 check that uses `docker logs otel-collector` to confirm
   the attribute appears in the Collector output
6. PR title format: `telemetry: add {AttrName} attribute to {service-name}`
