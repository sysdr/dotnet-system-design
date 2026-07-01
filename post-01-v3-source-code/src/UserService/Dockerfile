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

# Stage 2: runtime — ASP.NET Core only (~220 MB), no SDK, no compiler
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "UserService.dll"]
