# Azure Production Guide — Post 1
## How to swap local setup for real Azure resources

> **No Azure subscription is required for Posts 1–45.** This guide documents the production migration for teams ready to deploy.

---

## Post 1 components and their production equivalents

| Local (Post 1) | Production Azure | What changes |
|---|---|---|
| .NET Aspire Dashboard (localhost:15888) | Azure Monitor + Application Insights | Add connection string in appsettings.json |
| OTel Collector stdout | Azure Monitor workspace | Add OTel exporter in otel-collector-config.yaml |

---

## Step 1: Deploy Azure resources with Bicep

```powershell
# Create a resource group
az group create --name rg-hyperscale --location eastus

# Deploy Post 1 infra (adds Application Insights workspace)
az deployment group create \
    --resource-group rg-hyperscale \
    --template-file infra/main.bicep \
    --parameters environmentName=prod
```

*Note: `infra/main.bicep` currently has only placeholder output. The Application Insights resource is added in Post 2's Bicep file.*

---

## Step 2: Get Application Insights connection string

```powershell
az monitor app-insights component show \
    --app hyperscale-log-monitoring \
    --resource-group rg-hyperscale \
    --query connectionString \
    --output tsv
```

Copy the output into `src/UserService/appsettings.json` and `src/OrderService/appsettings.json`:

```json
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=<key>;IngestionEndpoint=https://eastus.in.applicationinsights.azure.com/"
  }
}
```

**That is the only change.** The `AddServiceDefaults()` call in ServiceDefaults already wires `UseAzureMonitor()` — it was waiting for a non-empty connection string.

---

## Verification after migration

```powershell
# Restart the AppHost
dotnet run --project src/AppHost

# Trigger a login
Invoke-RestMethod -Method Post -Uri "http://localhost:<dynamic-port>/users/login"

# Within 30 seconds, query Application Insights in the Azure Portal:
# Logs → Tables → traces | where customDimensions.UserId != "" | take 5
```

The same KQL query works in Azure Monitor, Application Insights, and Azure Data Explorer — the query language introduced in Post 18 is transferable across all three.
