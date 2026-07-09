// infra/main.bicep — Post 1 of 45
// No Azure resources are deployed in Post 1 — everything runs locally.
// Phase 7 (Posts 36–40) adds AKS, Service Bus, Event Hubs, and ACR here.
// Run `az deployment group create --template-file infra/main.bicep` in Post 36.

targetScope = 'resourceGroup'

@description('Environment name — used as a suffix on all resource names')
param environmentName string = 'dev'

@description('Azure region')
param location string = resourceGroup().location

// Post 36 adds:
//   module aks './modules/aks.bicep' = { ... }
//   module serviceBus './modules/servicebus.bicep' = { ... }
//   module eventHubs './modules/eventhubs.bicep' = { ... }
//   module storage './modules/storage.bicep' = { ... }

output environmentName string = environmentName
output location string = location
