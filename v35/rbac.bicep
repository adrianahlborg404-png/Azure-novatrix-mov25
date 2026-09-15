// =====================================================================
// v35 — Behörigheter och hanterad identitet
//
// Rolltilldelningar och managed identity ÄR Azure-resurser och kan
// därför byggas i Bicep. Användarna och grupperna de pekar på skapas
// först med entra.sh — kör det innan den här mallen.
//
// Omfattning: resursgruppen. Allt inom den ärver behörigheten, och
// inget utanför den påverkas.
// =====================================================================

@description('Plats för den hanterade identiteten.')
param location string = resourceGroup().location

@description('Objekt-ID för gruppen Novatrix-Drift. Skrivs ut av entra.sh.')
param driftGruppObjectId string

@description('Objekt-ID för gruppen Novatrix-Utveckling. Skrivs ut av entra.sh.')
param utvecklingGruppObjectId string

// ---------------------------------------------------------------------
// Inbyggda roller — ID:n är desamma i alla Azure-prenumerationer
// Kontrollera med: az role definition list --name "Reader" --query [].name -o tsv
// ---------------------------------------------------------------------

var rollReader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var rollVirtualMachineContributor = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
var rollNetworkContributor = '4d97b98b-1d4f-4787-a291-c67834d212e7'

// ---------------------------------------------------------------------
// Hanterad identitet för applikationen
// Inga rättigheter än — de tilldelas i v37 mot lagringen.
// ---------------------------------------------------------------------

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'ID-Novatrix-App'
  location: location
}

// ---------------------------------------------------------------------
// Rolltilldelningar
//
// Namnet på en rolltilldelning måste vara ett GUID. guid() genererar ett
// som är stabilt: samma indata ger alltid samma GUID, så mallen kan köras
// om utan att skapa dubbletter.
//
// principalType: 'Group' talar om för Azure att den inte ska vänta in
// replikering av ett användarobjekt — utan den kan utrullningen fallera
// direkt efter att gruppen skapats.
// ---------------------------------------------------------------------

// Anna Drift, via gruppen Novatrix-Drift:
// behöver starta, stoppa och skala den virtuella maskinen
resource driftVmContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, driftGruppObjectId, rollVirtualMachineContributor)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rollVirtualMachineContributor)
    principalId: driftGruppObjectId
    principalType: 'Group'
    description: 'Drift behöver hantera VM:en. Owner valdes bort — den tillåter ändring av behörigheter.'
  }
}

// ...och konfigurera brandväggsregler. NSG är en egen resurstyp,
// därför krävs Network Contributor utöver VM-rollen.
resource driftNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, driftGruppObjectId, rollNetworkContributor)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rollNetworkContributor)
    principalId: driftGruppObjectId
    principalType: 'Group'
    description: 'NSG är en separat resurs och kräver egen roll.'
  }
}

// Erik Dev, via gruppen Novatrix-Utveckling:
// ska kunna felsöka men inte ändra
resource utvecklingReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, utvecklingGruppObjectId, rollReader)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', rollReader)
    principalId: utvecklingGruppObjectId
    principalType: 'Group'
    description: 'Utveckling ser IP-adresser och inställningar, men läser bara metadata.'
  }
}

// ---------------------------------------------------------------------
// Utdata — behövs i v37 när identiteten ska kopplas till lagringen
// ---------------------------------------------------------------------

output identitetNamn string = appIdentity.name
output identitetResourceId string = appIdentity.id
output identitetPrincipalId string = appIdentity.properties.principalId
output identitetClientId string = appIdentity.properties.clientId
