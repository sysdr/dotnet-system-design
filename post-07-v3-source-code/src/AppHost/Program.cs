// src/AppHost/Program.cs
// OTel Collector runs via start.ps1 (`docker run` on :4317) so Resource Saver
// Docker outages do not block the .NET services. Services export to that port
// through OTEL_COLLECTOR_ENDPOINT for verify.ps1.

var builder = DistributedApplication.CreateBuilder(args);

var userService = builder.AddProject<Projects.UserService>("user-service")
    .WithExternalHttpEndpoints()
    .WithEnvironment("OTEL_COLLECTOR_ENDPOINT", "http://127.0.0.1:4317");

var orderService = builder.AddProject<Projects.OrderService>("order-service")
    .WithExternalHttpEndpoints()
    .WithEnvironment("OTEL_COLLECTOR_ENDPOINT", "http://127.0.0.1:4317");

builder.Build().Run();
