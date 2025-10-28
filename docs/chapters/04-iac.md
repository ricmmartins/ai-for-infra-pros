# Chapter 4 — Infrastructure as Code (IaC) and AI environments

> “You don’t scale AI with spreadsheets. You scale it with code.”

## Why IaC Is essential for AI workloads

AI environments are:

- **Complex:** Combine GPU, networking, storage, and advanced permissions.  
- **Costly:** Every GPU hour is expensive.  
- **Dynamic:** Each experiment may require a unique setup.  

Manual provisioning is slow, error-prone, and not scalable.  
That’s why **Infrastructure as Code (IaC)** is the foundation of modern AI — not a luxury.

## Direct benefits

| Without IaC | With IaC |
|--------------|----------|
| Manual configurations | Versioned infrastructure as code |
| Frequent human errors | Automated testing and validation |
| Hard to scale quickly | Consistent deployments in minutes |
| Lack of standardization | Reusable and auditable modules |

💬 IaC turns a test environment into something **reproducible, traceable, and secure**.

## IaC fundamentals for AI

| Concept | Role in AI environments |
|----------|--------------------------|
| **IaC (Infrastructure as Code)** | Defines infrastructure through declarative files |
| **Idempotency** | Running the same code always produces the same result |
| **Reusability** | Templates and modules that teams can replicate |
| **Auditability** | Versioned, reviewed, and traceable code |

### Core Tools

✅ **Terraform** — Multi-cloud, ideal for reusability and standardization  
✅ **Bicep** — Azure-native, modern syntax, integrated with ARM  
✅ **Azure CLI** — For quick tests or simple automation  
✅ **GitHub Actions** — For CI/CD pipelines for infrastructure

## Common components of an AI environment

- **Networking:** VNets, subnets, NSGs, Peering  
- **Compute:** GPU VMs, AKS with GPU node pools  
- **Storage:** Blob, Data Lake, local NVMe disks  
- **Identity:** RBAC, Managed Identity, Key Vault  
- **Monitoring:** Log Analytics, Application Insights  
- **AI Services:** Azure ML, OpenAI, Front Door, Purview  

## Example 1: Creating a GPU VM with Bicep

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: 'vm-gpu'
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_NC6'
    }
    osProfile: {
      adminUsername: 'azureuser'
      computerName: 'gpuvm'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
    }
  }
}
```

### Deploy

```bash
az deployment group create \
  --resource-group rg-ai \
  --template-file main.bicep
```

## Example 2: AKS cluster with GPU node pool (Terraform)

```hcl
resource "azurerm_kubernetes_cluster" "aks_ai" {
  name                = "aks-ai-cluster"
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

resource "azurerm_kubernetes_cluster_node_pool" "gpu_pool" {
  name                = "gpu"
  vm_size             = "Standard_NC6"
  enable_auto_scaling = true
}
```

💡 **Tip:** Use `terraform apply -auto-approve` for quick tests and **modules** for complex environments.

## Automating deployments with GitHub Actions

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: azure/login@v1
      - uses: azure/arm-deploy@v1
        with:
          template: ./infra.bicep
```

💡 Combine GitHub Actions with **protected environments**, **reviewers**, and **approval policies** for IaC governance.

## Recommended patterns

- Separate modules for **network**, **compute**, **storage**, and **observability**.  
- Configurable parameters (region, SKU, scalability).  
- Automation for model updates, such as:  
  Upload new model to Blob → Update AKS pod → Recreate inference endpoint.  

##  Pro insight

> “If you can deploy your entire environment with a `terraform apply` or `az deployment`, you’re doing it right.”

## Security and governance with IaC

- **RBAC** for data and MLOps teams  
- Automated **Key Vault** for secrets  
- **NSGs** and **Private Link** to isolate endpoints  
- **Policies** and **Blueprints** for automated compliance  

## Hands-On: Quick deploy with Azure CLI + Bicep

```bash
az group create --name rg-ai-test --location eastus

az deployment group create \
  --resource-group rg-ai-test \
  --template-file main.bicep
```

Then:

- Connect via SSH  
- Install NVIDIA drivers  
- Validate with `nvidia-smi`  

## Advanced curiosity

Did you know you can estimate the **average request size** of your AI models based on **TPM (Tokens per Minute)** and **QPS (Queries per Second)**?  
👉 See **Chapter 8** to learn how to calculate this and prevent throttling in critical AI workloads.

## References

- [Azure Bicep Docs](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)  
- [Terraform on Azure](https://learn.microsoft.com/azure/developer/terraform/)  
- [GitHub Actions for Azure](https://learn.microsoft.com/azure/developer/github/)  


<!-- ### Next chapter

Continue to explore how to monitor and observe your AI infrastructure in [**Chapter 5 — Monitoring and observability for AI workloads**](05-monitoring.md). -->
