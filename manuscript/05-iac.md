# Chapter 5 — Infrastructure as Code for AI

*"If you can't destroy and rebuild your entire AI environment from a single command, you don't own it — it owns you."*

---

## The $4,000 Typo

It started as a win. You manually provisioned a GPU cluster in East US 2 for an ML experiment — an AKS cluster with a Standard_NC6s_v3 node pool, accelerated networking, the right NVIDIA drivers, proper taints. It took most of a day, but it worked. The training job ran, the team was happy, and you moved on.

Three weeks later, the same team needs the identical setup in West US 3. No problem, you think. You open the Azure portal and start clicking. You reference a Slack thread for the VM SKU, a wiki page for the network config, and your own memory for everything else. Two days later, it's "done."

Except it isn't. Someone fat-fingered the VM SKU. Instead of `Standard_NC6s_v3` (a GPU-equipped VM at around $3.80/hr), the node pool is running `Standard_D16s_v5` — a general-purpose CPU VM with no GPU at all. The training job launches, finds no CUDA device, falls back to CPU, and grinds along at a fraction of the expected speed. Nobody notices for three days because the job doesn't fail — it just runs slowly. By the time someone checks, the cluster has burned through $4,000 in compute on a VM that can't do the one thing it was provisioned for.

That was the last time I provisioned AI infrastructure by hand. The lesson wasn't that people make typos. The lesson was that AI infrastructure is too expensive, too complex, and too important to live in anyone's head. It needs to live in code.

---

## Why IaC Is Non-Negotiable for AI

Infrastructure as Code isn't a nice-to-have for AI workloads. It's a survival mechanism. Traditional web applications are forgiving — a misconfigured App Service might cost you an extra $50/month. A misconfigured GPU cluster costs you thousands per day.

### Complexity

AI environments have more moving parts than almost any other infrastructure pattern. You're managing GPU quotas that vary by region and subscription. You're dealing with driver versions that must match specific CUDA toolkits. You're configuring node pools with taints and tolerations so GPU workloads land on the right hardware. You're setting up accelerated networking, InfiniBand for multi-node training, ephemeral NVMe disks for checkpoint storage, and private endpoints for model registries. No human can hold all of that in their head reliably.

### Cost

A single NVIDIA A100 VM (`Standard_NC24ads_A100_v4`) runs approximately $3.67/hr. A four-node training cluster costs about $14.68/hr — over $350/day. At those rates, every minute of misconfiguration is money on fire. IaC lets you provision exactly what you need, when you need it, and tear it down the moment you're done. That discipline is the difference between a manageable GPU bill and a budget-busting surprise.

### Reproducibility

Machine learning experiments must be repeatable. If a model achieves breakthrough accuracy on a Tuesday, the team needs to know they can recreate the exact same infrastructure on a Wednesday. Same VM SKU, same driver version, same network topology, same storage configuration. IaC makes this trivial — you run the same code and get the same environment, every time.

### Compliance and Auditability

Regulated industries need to know who changed what, when, and why. When your infrastructure is defined in code and stored in Git, you get that audit trail for free. Every change is a pull request. Every pull request has a reviewer. Every deployment is traceable to a commit hash. Try getting that from a portal session.

**Infra ↔ AI Translation**: When an ML engineer says "I need the same environment as last week's experiment," they're asking for infrastructure reproducibility. When a compliance officer says "show me what changed," they're asking for an audit trail. IaC answers both questions with the same artifact: a versioned configuration file.

---

## The IaC Landscape for AI

Not every tool is right for every job. The AI infrastructure space has four primary approaches, each with distinct strengths.

**Decision Matrix: Choosing Your IaC Tool**

| Criteria | Terraform | Bicep | Azure CLI | Pulumi |
|----------|-----------|-------|-----------|--------|
| **Paradigm** | Declarative | Declarative | Imperative | Declarative (code) |
| **Multi-cloud** | Yes | ❌ Azure only | ❌ Azure only | Yes |
| **State management** | Remote state file | None (ARM handles it) | None | Remote state file |
| **Language** | HCL | Bicep DSL | Bash/PowerShell | Python, TypeScript, Go, C# |
| **Learning curve** | Moderate | Low (Azure users) | Low | Moderate–High |
| **Module ecosystem** | Massive (Registry) | Growing (modules) | N/A | Growing |
| **AI/GPU support** | Excellent | Excellent | Good | Good |
| **Best for** | Multi-cloud platforms | Azure-native teams | Quick automation | Developer-first teams |

### Terraform

Terraform is the industry standard for multi-cloud infrastructure. Its provider ecosystem covers Azure, AWS, GCP, Kubernetes, Helm, and hundreds of SaaS services. State management (who owns what) is explicit, which is both a strength and a responsibility. For organizations running AI workloads across multiple clouds — training on Azure GPUs, serving on AWS endpoints — Terraform is the natural choice.

### Bicep

Bicep is Azure's first-party IaC language. It compiles to ARM templates, requires no state file (Azure Resource Manager tracks state natively), and has first-class support for every Azure resource type on day one of GA. If your AI infrastructure is 100% Azure, Bicep gives you the cleanest syntax and the tightest integration. No state file means no state locking headaches, no storage account to manage, and no risk of state corruption.

### Azure CLI

The Azure CLI is imperative — you tell it exactly what to do, step by step. It's excellent for quick automation, ad-hoc scripting, and glue code between declarative tools. It's not the right choice for managing complex, stateful infrastructure, but it's invaluable for tasks like checking GPU quota, registering preview features, or running one-off deployments during development.

### When to Use Each

Use **Terraform** when you need multi-cloud support, have a platform engineering team, or are managing infrastructure at scale across multiple environments. Use **Bicep** when you're Azure-native and want the simplest path to production-grade infrastructure with the least operational overhead. Use **Azure CLI** for automation glue, prototyping, and operations tasks. Use **Pulumi** when your team prefers to write infrastructure in the same language as their application code.

**Pro Tip**: Many production teams use more than one tool. A common pattern is Terraform or Bicep for infrastructure provisioning, Azure CLI scripts for operational tasks (quota checks, feature registration), and GitHub Actions to orchestrate all of it.

---

## Terraform for AI Infrastructure

Terraform's strength is its explicitness. Every resource, every dependency, every configuration value is visible in the code. For AI infrastructure — where a single wrong SKU can cost thousands — that explicitness is a feature, not a burden.

### Provider Configuration

Start with the provider block. The `azurerm` provider version `~> 4.0` is the current major release. Pin it to avoid surprises.

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

### Variables

Parameterize everything that changes between environments. GPU SKUs, regions, node counts — none of these should be hardcoded.

```hcl
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus2"
}

variable "gpu_vm_size" {
  description = "VM SKU for GPU node pool"
  type        = string
  default     = "Standard_NC6s_v3"

  validation {
    condition     = can(regex("^Standard_N", var.gpu_vm_size))
    error_message = "GPU VM size must be an N-series SKU (e.g., Standard_NC6s_v3, Standard_NC24ads_A100_v4)."
  }
}

variable "gpu_max_nodes" {
  description = "Maximum number of GPU nodes for autoscaling"
  type        = number
  default     = 5
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}
```

**Pro Tip**: That `validation` block on `gpu_vm_size` is not decorative. It prevents the exact mistake from the opening story — someone accidentally specifying a D-series or E-series VM for a GPU workload. Catch it at `terraform plan`, not on your cloud bill.

### AKS Cluster with GPU Node Pool

This is a production-ready AKS configuration for AI workloads. It includes a system node pool for cluster services, a GPU node pool with autoscaling, proper taints to prevent non-GPU workloads from landing on expensive nodes, and labels for workload targeting.

```hcl
resource "azurerm_resource_group" "ai" {
  name     = "rg-ai-${var.environment}"
  location = var.location

  tags = {
    environment  = var.environment
    project      = "ai-platform"
    managed-by   = "terraform"
    cost-center  = "ml-engineering"
  }
}

resource "azurerm_kubernetes_cluster" "ai" {
  name                = "aks-ai-${var.environment}"
  location            = azurerm_resource_group.ai.location
  resource_group_name = azurerm_resource_group.ai.name
  dns_prefix          = "aks-ai-${var.environment}"
  kubernetes_version  = "1.30"

  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    node_count          = 2
    os_disk_size_gb     = 128
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  tags = azurerm_resource_group.ai.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.ai.id
  vm_size               = var.gpu_vm_size
  mode                  = "User"
  os_disk_size_gb       = 256
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = var.gpu_max_nodes

  node_taints = [
    "sku=gpu:NoSchedule"
  ]

  node_labels = {
    "hardware"    = "gpu"
    "gpu-type"    = "nvidia"
    "workload"    = "ai"
  }

  tags = azurerm_resource_group.ai.tags
}
```

**Production Gotcha**: The `sku=gpu:NoSchedule` taint is critical. Without it, Kubernetes will happily schedule your monitoring DaemonSets, log collectors, and other non-GPU workloads onto your $3.80/hr GPU nodes. The taint ensures only pods with a matching toleration land on GPU hardware. Every GPU pod in your cluster must include `tolerations: [{key: "sku", operator: "Equal", value: "gpu", effect: "NoSchedule"}]` in its spec.

### Outputs

Expose the values that downstream consumers need — kubectl configuration, cluster identity, and resource group name.

```hcl
output "kube_config" {
  value     = azurerm_kubernetes_cluster.ai.kube_config_raw
  sensitive = true
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.ai.name
}

output "cluster_identity" {
  value = azurerm_kubernetes_cluster.ai.identity[0].principal_id
}

output "resource_group_name" {
  value = azurerm_resource_group.ai.name
}
```

### Remote State in Azure Storage

Never store Terraform state locally for AI infrastructure. A corrupted or lost state file for a GPU cluster means Terraform can't track — or destroy — resources that cost real money every hour they run. Use Azure Storage with locking enabled.

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "ai-platform.terraform.tfstate"
  }
}
```

```bash
# Create the state storage (one-time setup)
az group create --name rg-terraform-state --location eastus2

az storage account create \
  --name stterraformstate \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --encryption-services blob

az storage container create \
  --name tfstate \
  --account-name stterraformstate
```

**Production Gotcha**: Terraform state for GPU resources is a blast radius concern. If two engineers run `terraform apply` simultaneously against the same state, you can end up with orphaned GPU nodes that nobody's state file knows about. Azure Storage provides native blob leasing for state locking, but you should also enforce single-writer discipline through CI/CD — only your pipeline should run `apply`, never a human directly.

---

## Bicep for AI Infrastructure

Bicep's advantage is simplicity. No state file to manage, no backend to configure, no locking to worry about. Azure Resource Manager handles all of it. For teams that are 100% Azure, Bicep removes an entire category of operational complexity.

### GPU VM with NVIDIA Driver Extension

This Bicep template provisions a GPU VM and automatically installs NVIDIA drivers via the VM extension. No SSH required for driver setup.

```bicep
@description('Name of the GPU virtual machine')
param vmName string = 'vm-gpu-ai'

@description('Azure region for deployment')
param location string = resourceGroup().location

@allowed([
  'Standard_NC6s_v3'
  'Standard_NC12s_v3'
  'Standard_NC24s_v3'
  'Standard_NC24ads_A100_v4'
  'Standard_NC48ads_A100_v4'
  'Standard_NC96ads_A100_v4'
])
@description('GPU VM size — must be an N-series SKU')
param vmSize string = 'Standard_NC6s_v3'

@description('Administrator username')
param adminUsername string = 'azureuser'

@secure()
@description('SSH public key for authentication')
param sshPublicKey string

var vnetName = '${vmName}-vnet'
var subnetName = '${vmName}-subnet'
var nsgName = '${vmName}-nsg'
var nicName = '${vmName}-nic'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
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

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
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

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
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
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
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
        diskSizeGB: 256
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
  tags: {
    environment: 'ai'
    'managed-by': 'bicep'
  }
}

resource nvidiaExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'NvidiaGpuDriverLinux'
  location: location
  properties: {
    publisher: 'Microsoft.HpcCompute'
    type: 'NvidiaGpuDriverLinux'
    typeHandlerVersion: '1.9'
    autoUpgradeMinorVersion: true
  }
}

output vmId string = vm.id
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
```

**Pro Tip**: The `@allowed` decorator on `vmSize` serves the same purpose as Terraform's `validation` block — it prevents non-GPU SKUs from being deployed. The NVIDIA driver extension (`Microsoft.HpcCompute/NvidiaGpuDriverLinux`) eliminates the need to SSH in and manually install drivers, which was one of the most error-prone steps in the old manual process.

### AKS Cluster with GPU Node Pool (Bicep)

```bicep
@description('Name of the AKS cluster')
param clusterName string = 'aks-ai'

@description('Azure region')
param location string = resourceGroup().location

@description('GPU VM size for the AI node pool')
param gpuVmSize string = 'Standard_NC6s_v3'

@description('Maximum GPU nodes for autoscaling')
param gpuMaxCount int = 5

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-06-02-preview' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: '1.30'
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        vmSize: 'Standard_D4s_v5'
        count: 2
        osDiskSizeGB: 128
        osType: 'Linux'
      }
      {
        name: 'gpu'
        mode: 'User'
        vmSize: gpuVmSize
        minCount: 0
        maxCount: gpuMaxCount
        enableAutoScaling: true
        osDiskSizeGB: 256
        osType: 'Linux'
        nodeTaints: [
          'sku=gpu:NoSchedule'
        ]
        nodeLabels: {
          hardware: 'gpu'
          'gpu-type': 'nvidia'
        }
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
    }
  }
  tags: {
    environment: 'ai'
    'managed-by': 'bicep'
    'cost-center': 'ml-engineering'
  }
}

output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
```

### Modules Pattern for Reusable AI Infrastructure

Production teams don't write monolithic Bicep files. They use modules — self-contained, parameterized building blocks that enforce standards across the organization.

```
infra/
├── main.bicep              # Orchestrator
├── modules/
│   ├── network.bicep       # VNet, subnets, NSGs, private endpoints
│   ├── aks.bicep            # AKS cluster with GPU node pool
│   ├── storage.bicep        # Storage account for models and data
│   ├── monitoring.bicep     # Log Analytics, alerts, dashboards
│   └── keyvault.bicep       # Key Vault for secrets and certificates
└── parameters/
    ├── dev.bicepparam
    ├── staging.bicepparam
    └── prod.bicepparam
```

The orchestrator file (`main.bicep`) wires the modules together:

```bicep
targetScope = 'resourceGroup'

param environment string
param location string = resourceGroup().location

module network 'modules/network.bicep' = {
  name: 'network-${environment}'
  params: {
    location: location
    environment: environment
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks-${environment}'
  params: {
    location: location
    subnetId: network.outputs.aksSubnetId
    environment: environment
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-${environment}'
  params: {
    location: location
    environment: environment
  }
}
```

This pattern means a new team can spin up a complete, compliant AI environment by creating a single parameter file. No reinventing the wheel. No forgetting the GPU taint. No skipping the monitoring setup.

---

## CI/CD Pipelines for AI Infrastructure

Infrastructure changes to AI environments should never be applied from a laptop. The stakes are too high. A CI/CD pipeline gives you review gates, automated validation, and an audit trail for every change.

### GitHub Actions with OIDC Authentication

Modern CI/CD for Azure uses OpenID Connect (OIDC) — no client secrets stored in GitHub. The workflow exchanges a short-lived token with Microsoft Entra ID at runtime. This is the current best practice.

```yaml
name: "AI Infrastructure — Plan & Apply"

on:
  push:
    branches: [main]
    paths: ["infra/**"]
  pull_request:
    branches: [main]
    paths: ["infra/**"]

permissions:
  id-token: write
  contents: read
  pull-requests: write

env:
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  TF_VERSION: "1.9.0"

jobs:
  plan:
    name: "Terraform Plan"
    runs-on: ubuntu-latest
    environment: ai-infrastructure
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        working-directory: infra
        run: terraform init

      - name: Terraform Plan
        working-directory: infra
        run: terraform plan -out=tfplan -input=false

      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: infra/tfplan

  apply:
    name: "Terraform Apply"
    runs-on: ubuntu-latest
    needs: plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment:
      name: ai-infrastructure-prod
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: infra

      - name: Terraform Init
        working-directory: infra
        run: terraform init

      - name: Terraform Apply
        working-directory: infra
        run: terraform apply -auto-approve tfplan
```

### The Plan → Approve → Apply Pattern

This workflow implements a critical safety pattern for AI infrastructure:

1. **On pull request**: Terraform runs `plan` only. The plan output shows exactly what will change — new GPU nodes, modified network rules, destroyed resources. Reviewers can see the cost implications before anything happens.
2. **On merge to main**: The `apply` job runs, but only after passing through an **environment protection rule**. This is a GitHub-native approval gate where designated reviewers must explicitly approve the deployment.
3. **Artifact handoff**: The plan is saved as an artifact and consumed by the apply job. This ensures the exact plan that was reviewed is the plan that gets applied — no drift between review and execution.

**Production Gotcha**: Always pin your action versions. Use `actions/checkout@v4`, `hashicorp/setup-terraform@v3`, `azure/login@v2`, and `actions/upload-artifact@v4`. Using `@latest` or `@main` in production pipelines means a breaking upstream change can take down your infrastructure deployment at the worst possible time — like when you need to scale GPU nodes for a deadline.

### Environment Protection Rules

In GitHub, navigate to **Settings → Environments** and create an environment called `ai-infrastructure-prod`. Configure it with:

- **Required reviewers**: At least one infrastructure engineer must approve
- **Wait timer**: Optional delay (e.g., 5 minutes) for last-chance review
- **Deployment branches**: Restrict to `main` only — no feature branch deployments to production

This turns your CI/CD pipeline into a controlled deployment process rather than a fire-and-forget script.

---

## Governance and Guardrails

AI infrastructure without guardrails is a cost center waiting to explode. Governance ensures that every deployment meets organizational standards for naming, tagging, security, and cost control.

### Azure Policy for GPU Governance

Azure Policy can enforce rules at the subscription or management group level. For AI infrastructure, the most impactful policies prevent cost overruns and ensure compliance.

```json
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Compute/virtualMachines"
        },
        {
          "field": "Microsoft.Compute/virtualMachines/sku.name",
          "in": [
            "Standard_NC24ads_A100_v4",
            "Standard_NC48ads_A100_v4",
            "Standard_NC96ads_A100_v4",
            "Standard_ND96asr_v4",
            "Standard_ND96amsr_A100_v4"
          ]
        },
        {
          "field": "tags['cost-center']",
          "exists": "false"
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  },
  "parameters": {}
}
```

This policy denies the creation of high-end GPU VMs (A100, ND-series) unless they carry a `cost-center` tag. No tag, no GPU. It's a simple rule that prevents shadow GPU clusters from appearing on your bill.

### Naming Conventions for AI Resources

Consistent naming makes resources discoverable, filterable, and manageable at scale. Adopt a pattern that encodes purpose, environment, and region.

| Resource Type | Pattern | Example |
|---------------|---------|---------|
| Resource Group | `rg-{project}-{env}` | `rg-ai-platform-prod` |
| AKS Cluster | `aks-{project}-{env}` | `aks-ai-platform-prod` |
| GPU Node Pool | `gpu{workload}` | `gputraining` |
| Storage Account | `st{project}{env}{region}` | `staiprodeus2` |
| Key Vault | `kv-{project}-{env}` | `kv-ai-platform-prod` |
| Log Analytics | `log-{project}-{env}` | `log-ai-platform-prod` |

### Tagging Strategy

Every AI resource should carry a minimum set of tags. These tags drive cost reporting, access control, and lifecycle management.

```hcl
locals {
  required_tags = {
    environment  = var.environment          # dev, staging, prod
    project      = var.project_name         # ai-platform, ml-training
    team         = var.team_name            # ml-engineering, data-science
    cost-center  = var.cost_center          # finance tracking
    experiment   = var.experiment_id        # links infra to ML experiment
    managed-by   = "terraform"             # how this resource was created
    created-date = formatdate("YYYY-MM-DD", timestamp())
  }
}
```

**Infra ↔ AI Translation**: The `experiment` tag bridges the gap between infrastructure and ML workflows. When a data scientist asks "how much did experiment X cost?", you can answer with a single Azure Cost Management query filtered by that tag. Without it, you're manually correlating timestamps and resource groups.

### Module Registries

For organizations with multiple teams deploying AI infrastructure, a module registry prevents configuration sprawl. Terraform supports private registries (Terraform Cloud, Azure-hosted), and Bicep modules can be published to Azure Container Registry.

```bash
# Publish a Bicep module to Azure Container Registry
az bicep publish \
  --file modules/aks-gpu.bicep \
  --target br:myregistry.azurecr.io/bicep/modules/aks-gpu:v1.2.0
```

```bicep
// Consume a published module
module aksGpu 'br:myregistry.azurecr.io/bicep/modules/aks-gpu:v1.2.0' = {
  name: 'aks-gpu-deployment'
  params: {
    location: location
    environment: environment
    gpuVmSize: 'Standard_NC6s_v3'
  }
}
```

Teams consume approved, tested, version-pinned modules instead of writing their own. This ensures every GPU cluster in the organization gets the right taints, the right tags, the right monitoring, and the right security configuration.

---

## Hands-On: Deploy an AKS GPU Cluster with Terraform

This section walks through a complete, end-to-end deployment. Every command is production-valid. Every file is self-contained.

### Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.5 installed
- An Azure subscription with GPU quota in your target region
- A resource group for Terraform state (see the Remote State section above)

### Step 1 — Check GPU Quota

Before writing a single line of Terraform, verify you have GPU quota. Nothing is more frustrating than a perfect plan that fails at apply.

```bash
az vm list-usage --location eastus2 \
  --query "[?contains(name.value, 'StandardNCSv3Family')]" \
  --output table
```

If `CurrentValue` equals `Limit`, you need to request a quota increase before proceeding.

### Step 2 — Initialize Terraform

```bash
mkdir ai-gpu-cluster && cd ai-gpu-cluster
```

Create `main.tf` with the provider, resource group, AKS cluster, and GPU node pool configurations from the Terraform section above. Then initialize:

```bash
terraform init
```

You should see `Terraform has been successfully initialized!` along with the provider version being downloaded.

### Step 3 — Plan

```bash
terraform plan -out=tfplan
```

Review the plan output carefully. You should see:

- 1 resource group
- 1 AKS cluster with a system node pool
- 1 GPU node pool with autoscaling (0–5 nodes), `sku=gpu:NoSchedule` taint

Verify the VM SKU in the plan output. This is your last chance to catch a wrong SKU before real money starts flowing.

### Step 4 — Apply

```bash
terraform apply tfplan
```

AKS provisioning typically takes 5–10 minutes. The GPU node pool may take an additional 2–3 minutes if it scales up from zero.

### Step 5 — Verify

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group rg-ai-dev \
  --name aks-ai-dev

# Verify node pools
kubectl get nodes -L hardware

# Verify GPU taint
kubectl describe node <gpu-node-name> | grep Taints

# Verify GPU availability
kubectl get nodes -l hardware=gpu \
  -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'
```

You should see the GPU taint `sku=gpu:NoSchedule` on GPU nodes, and the `nvidia.com/gpu` resource available in the node's allocatable resources.

### Step 6 — Clean Up

When the experiment is done, tear it all down. This is one of IaC's superpowers — destruction is as controlled and repeatable as creation.

```bash
terraform destroy
```

Type `yes` when prompted. Terraform will remove all resources in reverse dependency order. No orphaned NICs, no forgotten disks, no surprise bills next month.

**Pro Tip**: For ephemeral training environments, consider running `terraform destroy` on a schedule. A GitHub Actions workflow triggered by `schedule` (cron) can destroy dev GPU clusters every Friday at 6 PM and recreate them Monday at 8 AM. That alone can cut GPU costs by 65%.

---

## Chapter Checklist

Before moving on, verify you can answer "yes" to each of these:

- All AI infrastructure is defined in code (Terraform or Bicep) — no portal-only resources
- GPU VM SKUs are validated in variable definitions to prevent non-GPU deployments
- AKS GPU node pools use the `sku=gpu:NoSchedule` taint
- Terraform state is stored remotely in Azure Storage with locking enabled
- CI/CD pipelines use OIDC authentication — no client secrets in GitHub
- The plan → approve → apply pattern is enforced with environment protection rules
- Azure Policy blocks GPU VMs without required tags
- All resources follow a consistent naming convention
- Every resource carries tags for environment, project, team, cost-center, and experiment
- Reusable modules are published to a registry for cross-team consumption
- GPU quota is verified before deployment
- Destruction is automated and tested — you can `terraform destroy` with confidence

---

## What's Next

Your infrastructure is now code — versioned, reproducible, and auditable. Every GPU cluster, every network rule, every RBAC binding lives in a Git repository with full history and review trails. You can spin up an identical environment in any region with a single command, and you can tear it down just as easily.

But infrastructure is only the foundation. What about the models that run on top of it? A perfectly provisioned AKS cluster means nothing if the model deployment process is manual, the container images are unscanned, and there's no rollback plan when a new model version degrades accuracy. **Chapter 6** covers the model lifecycle from an infrastructure lens: container registries, CI/CD for model deployments, A/B testing at the infrastructure layer, and supply chain security for the artifacts that run on your carefully codified platform.
