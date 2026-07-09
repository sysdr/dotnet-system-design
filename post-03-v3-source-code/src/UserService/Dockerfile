# Stage 1: build — full .NET 8 SDK (~800 MB), not shipped to production
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project files first — Docker caches this layer separately.
# If only .cs files change, the restore layer is reused (faster Windows rebuilds).
COPY ["UserService/UserService.csproj",           "UserService/"]
COPY ["ServiceDefaults/ServiceDefaults.csproj",   "ServiceDefaults/"]
RUN dotnet restore "UserService/UserService.csproj"

# Copy source and publish
COPY UserService/      UserService/
COPY ServiceDefaults/  ServiceDefaults/
WORKDIR "/src/UserService"
RUN dotnet publish -c Release -o /app/publish

# Stage 2: runtime — jammy base includes curl for Docker healthchecks
FROM mcr.microsoft.com/dotnet/aspnet:8.0-jammy AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -f http://localhost:8080/health || exit 1
ENTRYPOINT ["dotnet", "UserService.dll"]
