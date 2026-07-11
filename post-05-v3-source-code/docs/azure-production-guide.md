# Azure Production Guide — Post 2

## Activating real Application Insights (requires Azure subscription)

### Step 1: Provision Application Insights resource
az group create --name rg-hyperscale --location eastus
az monitor app-insights component create \
    --app hyperscale-ai \
    --resource-group rg-hyperscale \
    --location eastus \
    --kind web

### Step 2: Retrieve the connection string
az monitor app-insights component show \
    --app hyperscale-ai \
    --resource-group rg-hyperscale \
    --query connectionString \
    --output tsv
# Output format:
# InstrumentationKey=<guid>;IngestionEndpoint=https://eastus.in.applicationinsights.azure.com/;...

### Step 3: Update appsettings.json (or use environment variable)
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=<guid>;IngestionEndpoint=https://eastus.in.applicationinsights.azure.com/;..."
  }
}

# OR use environment variable (recommended for production — no secret in appsettings.json):
$env:APPLICATIONINSIGHTS_CONNECTION_STRING = "InstrumentationKey=..."
dotnet run --project src/AppHost

### Step 4: Verify data in Azure Portal
# Navigate to Application Insights resource > Logs
# Run the KQL query from kql-library.kql [POST-02]:
# traces | where timestamp > ago(1h) | where customDimensions has "UserId" | take 10

## Zero code changes required
The C# code in ServiceDefaults/Extensions.cs reads the connection string from config.
Only the connection string value changes — no code edits.
