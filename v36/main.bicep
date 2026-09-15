// =====================================================================
// v36 — Nätverk och säkerhet
// Segmenterat virtuellt nätverk med publikt och privat subnät, en NSG
// per subnät, och webbservern byggd direkt i snet-public.
//
// Mallen är kumulativ: den innehåller även servern från v34. Skälet är
// detsamma som i portalen — en VM går inte att flytta mellan virtuella
// nätverk, så nätverket byggs först och servern sist.
// =====================================================================

@description('Plats för alla resurser.')
param location string = resourceGroup().location

@description('Namn på den virtuella maskinen.')
param vmName string = 'VM-Novatrix-Web-02'

@description('Administratörskonto på servern.')
param adminUsername string = 'azureuser'

@description('Publik SSH-nyckel — innehållet i din .pub-fil.')
param adminPublicKey string

@description('Din publika IP i CIDR-form, t.ex. 31.208.29.95/32.')
param sshSourceAddressPrefix string

@description('VM-storlek.')
param vmSize string = 'Standard_B2ats_v2'

// Adressplanen från uppgift 3
var vnetPrefix = '10.20.0.0/16'
var publicSubnetPrefix = '10.20.1.0/24'
var privateSubnetPrefix = '10.20.2.0/24'

// ---------------------------------------------------------------------
// NSG för det publika subnätet
//
// Ingen egen blockeringsregel behövs: Azure har en inbyggd sistaregel,
// DenyAllInBound på 65500, som nekar allt ingen tidigare regel tillåtit.
// ---------------------------------------------------------------------

resource nsgPublic 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-public'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Besökare måste nå formuläret.'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Förberett för certifikat.'
        }
      }
      {
        name: 'Allow-SSH-Admin'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: sshSourceAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Administration av servern. Endast min adress — standard är annars hela internet.'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------
// NSG för det privata subnätet
//
// Utgående trafik lämnas öppen: servern behöver hämta uppdateringar
// med apt och ska prata med Azure Storage i v37.
// ---------------------------------------------------------------------

resource nsgPrivate 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'NSG-private'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-from-public-subnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: publicSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Webbservern ska nå lagringen i v37. Bara denna källa, bara denna port.'
        }
      }
      {
        name: 'Deny-internet-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Redundant mot sistaregeln, men gör avsikten tydlig i regellistan.'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Virtuellt nätverk
//
// NSG:erna kopplas här, på subnätsnivå — inte på nätverkskortet.
// Ett enda lager på nätverkssidan är lättare att felsöka än två
// uppsättningar regler som båda måste släppa igenom samma trafik.
// ---------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'Vnet-Novatrix'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetPrefix ]
    }
    subnets: [
      {
        name: 'snet-public'
        properties: {
          addressPrefix: publicSubnetPrefix
          networkSecurityGroup: {
            id: nsgPublic.id
          }
        }
      }
      {
        name: 'snet-private'
        properties: {
          addressPrefix: privateSubnetPrefix
          networkSecurityGroup: {
            id: nsgPrivate.id
          }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Webbservern, byggd direkt i snet-public
// ---------------------------------------------------------------------

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: '${vmName}-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: '${toLower(vmName)}-nic'
  location: location
  properties: {
    // Medvetet ingen networkSecurityGroup här — skyddet sitter på subnätet
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: loadFileAsBase64('cloud-init.yaml')
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------
// Utdata
// ---------------------------------------------------------------------

output publikIp string = publicIp.properties.ipAddress
output privatIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output webbadress string = 'http://${publicIp.properties.ipAddress}'
output privatSubnetId string = vnet.properties.subnets[1].id
