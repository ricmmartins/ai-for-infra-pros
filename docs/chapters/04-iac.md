# Chapter 4. Infrastructure as Code (IaC) and AI environments

> “You don’t scale AI with spreadsheets. You scale it with code.”

---

## Why IaC is essential for AI workloads

AI environments are fundamentally different from traditional application stacks.

They are:

- **Complex.** GPU compute, high-throughput networking, storage tiers, and fine-grained identity.
- **Costly.** Every GPU minute matters.
- **Dynamic.** Experiments, models, and scaling patterns change constantly.

Manual provisioning does not scale in this reality.  
It is slow, error-prone, and impossible to reproduce reliably.

That is why **Infrastructure as Code (IaC)** is not optional for AI. It is the foundation.

---

## Direct benefits

| Without IaC | With IaC |
|------------|---------|
| Click-ops and ad-hoc scripts | Versioned, declarative infrastructure |
| Configuration drift | Idempotent, repeatable deployments |
| Slow experimentation | Environments created in minutes |
| No audit trail | Reviewed, traceable changes |

IaC turns an AI environment into something **reproducible, auditable, and secure**.

---

## IaC fundamentals for AI

| Concept | Role in AI environments |
|-------|-------------------------|
| **Infrastructure as Code** | Infrastructure defined declaratively |
| **Idempotency** | Same code. Same result. Every time |
| **Reusability** | Modules reused across teams and projects |
| **Auditability** | Git history, reviews, and approvals |

### Core tools

✅ **Terraform**. Multi-cloud. Strong module ecosystem.  
✅ **Bicep**. Azure-native. Clean syntax. ARM-integrated.  
✅ **Azure CLI**. Fast iteration and glue automation.  
✅ **GitHub Actions**. CI/CD pipelines for infrastructure.

---

## Common components of an AI environment

- **Networking.** VNets, subnets, NSGs, private endpoints  
- **Compute.** GPU VMs, AKS with GPU node pools  
- **Storage.** Blob, Data Lake, ephemeral NVMe  
- **Identity.** Managed Identity, RBAC, Key Vault  
- **Observability.** Log Analytics, metrics, alerts  
- **AI services.** Azure ML, Azure OpenAI, Front Door, Purview  

---

## Example 1. Creating a GPU VM with Bicep (correct and deployable)

A virtual machine cannot exist in isolation.  
It needs networking, disks, and authentication.

This example is intentionally **minimal but complete**.

### What this example includes

- VNet and subnet  
- Network Security Group allowing SSH  
- Public IP and NIC  
- Ubuntu 22.04 GPU-capable VM  
- SSH key authentication  

---

### `main.bicep`

```bicep
param vmName string = 'vm-gpu'
param location string = resourceGroup().location
param vmSize string = 'Standard_NC6'
param adminUsername string = 'azureuser'
param sshPublicKey string

var vnetName = '${vmName}-vnet'
var subnetName = '${vmName}-subnet'
var nsgName = '${vmName}-nsg'
var nicName = '${vmName}-nic'
var pipName = '${vmName}-pip'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.10.0.0/16']
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.10.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: pip.id
          }
          privateIPAllocationMethod: 'Dynamic'
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
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
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
```

---

### Deploy

```bash
az group create --name rg-ai --location eastus2

az deployment group create   --resource-group rg-ai   --template-file main.bicep   --parameters sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"
```

After deployment:

- Connect via SSH  
- Install NVIDIA drivers  
- Validate with `nvidia-smi`  

---

## Example 2. AKS cluster with GPU node pool (Terraform)

Terraform is ideal for **composable, multi-environment platforms**, especially when AKS is the control plane.

```hcl
resource "azurerm_kubernetes_cluster" "aks_ai" {
  name                = "aks-ai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  default_node_pool {
    name       = "system"
    vm_size    = "Standard_DS2_v2"
    node_count = 1
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "ai"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_ai.id
  vm_size               = "Standard_NC6"
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = 5
}
```

💡 Inline resources are great for learning. Use **modules** in production.

---

## Automating IaC with GitHub Actions

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: azure/login@v1
      - uses: azure/arm-deploy@v1
        with:
          template: ./infra/main.bicep
```

💡 Combine with protected branches, reviewers, and environment approvals.

---

## Recommended patterns

- Separate modules for **network**, **compute**, **storage**, and **observability**
- Parameterize region, SKU, and scale limits
- Automate inference rollouts  
  New model → Storage update → AKS rollout → Endpoint refresh

---

## Pro insight

> “If you can destroy and recreate your entire AI environment safely, you control it.”

---

## Security and governance with IaC

- Managed Identity instead of secrets  
- Key Vault injected via policy  
- Private networking by default  
- Azure Policy to enforce SKU, region, and tagging  

---

## Hands-on recap

```bash
az group create --name rg-ai-test --location eastus

az deployment group create   --resource-group rg-ai-test   --template-file main.bicep
```

Validate:

- SSH access  
- GPU visibility  
- Cost and quota alignment  

---

## Advanced curiosity

You can estimate **average request size** using **TPM (Tokens per Minute)** and **QPS (Queries per Second)**.  
This becomes critical to avoid throttling and over-provisioning.

👉 See **Chapter 8** for deep dives on TPM, RPM, PTUs, and performance modeling.

---

## References

- Azure Bicep documentation  
  https://learn.microsoft.com/azure/azure-resource-manager/bicep/

- Terraform on Azure  
  https://learn.microsoft.com/azure/developer/terraform/

- GitHub Actions for Azure  
  https://learn.microsoft.com/azure/developer/github/
