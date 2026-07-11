FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["OrderService/OrderService.csproj",         "OrderService/"]
COPY ["ServiceDefaults/ServiceDefaults.csproj",   "ServiceDefaults/"]
RUN dotnet restore "OrderService/OrderService.csproj"
COPY OrderService/     OrderService/
COPY ServiceDefaults/  ServiceDefaults/
WORKDIR "/src/OrderService"
RUN dotnet restore "OrderService.csproj"
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "OrderService.dll"]
