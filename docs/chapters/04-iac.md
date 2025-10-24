# Chapter 4 — Infrastructure as Code (IaC) and Automation for AI

> “You don’t scale AI with spreadsheets — you scale it with code.”

---

## 🎯 Why IaC Matters for AI

AI environments are:
- **Complex** — GPUs, networking, storage, and security all interconnect.
- **Expensive** — each GPU hour can cost dozens of dollars.
- **Dynamic** — new experiments require constant environment changes.

Without automation, provisioning these environments manually becomes slow, inconsistent, and error-prone.  
**Infrastructure as Code (IaC)** solves this by defining environments **declaratively, reproducibly, and versionably**.

---

## 🧠 IaC Fundamentals for AI Workloads

| Concept | Role in AI Infrastructure |
|----------|---------------------------|
| **Idempotency** | Every deployment produces the same result, no matter how many times it runs |
| **Versioning** | Track every infra change alongside your model code |
| **Reusability** | Share modular templates across teams and projects |
| **Auditability** | Review, test, and approve infrastructure via pull requests |

**Popular Tools:**
- 🧩 **Terraform** – Multi-cloud, reusable at scale  
- 🧩 **Bicep** – Azure-native IaC  
- 🧩 **Azure CLI / PowerShell** – Fast prototyping and automation

---

## 🏗️ Common Components in AI Deployments

When provisioning an AI-ready environment, you typically define:

1. **Network:** VNets, Subnets, NSGs, Peering  
2. **Compute:** GPU VMs or AKS clusters  
3. **Storage:** Blob containers, Data Lakes, NVMe disks  
4. **Identity:** Managed identities, RBAC, Key Vault  
5. **Observability:** Log Analytics, Azure Monitor  
6. **AI Services:** Azure Machine Learning, Cognitive Services

---

## 💻 Example 1: Create a GPU VM with Bicep

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: 'vm-gpu-inference'
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_NC6s_v3'
    }
    osProfile: {
      adminUsername: 'azureuser'
      computerName: 'gpuvm'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2E...'
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

Deploy it with:

```bash
az deployment group create \
  --resource-group rg-ai \
  --template-file main.bicep
```

✅ Result: VM ready for AI workloads with SSH and GPU access.

---

## 🧩 Example 2: AKS Cluster with GPU Pool (Terraform)

```hcl
resource "azurerm_kubernetes_cluster" "aks_ai" {
  name                = "aks-ai-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aksai"

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
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_ai.id
  vm_size               = "Standard_NC6s_v3"
  node_count            = 1
  node_labels = {
    "k8s.azure.com/mode" = "User"
    "agentpool"          = "gpu"
  }
  taints = ["sku=gpu:NoSchedule"]
}
```

✅ Result: AKS cluster with CPU + GPU node pools, ready for inference workloads.

---

## ⚙️ Automation Pipeline (GitHub Actions Example)

```yaml
name: Deploy Infra

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: azure/login@v1
      - uses: azure/arm-deploy@v1
        with:
          subscriptionId: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          resourceGroupName: rg-ai
          template: ./infra/main.bicep
```

---

## 🔒 Security Through IaC

- Manage secrets via **Azure Key Vault**  
- Define RBAC roles as code  
- Restrict access via **NSGs** and **Private Endpoints**  
- Enforce **Azure Policy** for compliance

---

## 🧠 Insights for Infrastructure Engineers

- You don’t need to master ML to be essential in AI.  
- Standardizing, securing, and automating environments **is** your superpower.  
- IaC is not just about automation — it’s about **governance, reproducibility, and speed**.

---

## ✅ Conclusion

Provisioning AI environments is **an infrastructure discipline**.  
With IaC, every GPU, cluster, and dataset can be deployed predictably and securely — enabling innovation without chaos.

Next: [Chapter 5 — Monitoring and Observability for AI Workloads](05-monitoring.md)

