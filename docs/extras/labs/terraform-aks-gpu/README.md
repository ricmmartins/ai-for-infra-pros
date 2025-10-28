# Lab: Deploying an AKS cluster with GPU node pool using Terraform

## Objective
Provision an **Azure Kubernetes Service (AKS)** cluster with a **dedicated GPU node pool** for AI and inference workloads.

This lab demonstrates how to:
- Use Terraform for Infrastructure-as-Code (IaC)
- Deploy a GPU-enabled AKS node pool
- Prepare your cluster for AI workloads such as Azure OpenAI, MLflow, or custom inference containers


## Prerequisites
Before running this lab, make sure you have:

- ✅ [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) installed (v1.5+ recommended)
- ✅ [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- ✅ Access to an Azure subscription with permission to create resource groups and AKS clusters
- ✅ A quota for **GPU-enabled VM SKUs** (e.g., `Standard_NC6s_v3` or `Standard_NCas_T4_v3`)

## Folder Structure
```
terraform-aks-gpu/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

## Configuration

### 1. Define environment variables
Authenticate and set your default subscription:
```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review and validate the plan
```bash
terraform plan -out=tfplan
```

### 4. Apply the configuration
```bash
terraform apply "tfplan"
```

## What this deployment creates
| Resource | Description |
|-----------|--------------|
| **Resource group** | A logical container for all deployed resources |
| **AKS cluster** | Managed Kubernetes cluster configured with default node pool |
| **GPU node pool** | A secondary node pool using `Standard_NC6s_v3` (or similar) |
| **Managed identity** | Used for AKS and node pool operations |
| **Network resources** | VNet, subnets, NSG (if defined) |

## Validation
After deployment, verify your GPU node pool:
```bash
az aks nodepool list \
  --cluster-name aks-ai-cluster \
  --resource-group rg-ai-lab \
  --query "[].{Name:name,VMSize:vmSize,NodeCount:count,Mode:mode}"
```

You can also connect to your cluster:
```bash
az aks get-credentials --resource-group rg-ai-lab --name aks-ai-cluster
kubectl get nodes -o wide
```

Check that the GPU node pool is labeled and ready:
```bash
kubectl get nodes -l "agentpool=gpu"
```

## Next steps
- Install the [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin) to expose GPU metrics
- Deploy your first inference workload (see `yaml-inferencia-api/` lab)
- Integrate monitoring with [Prometheus + DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)

## Cleanup
To remove all resources:
```bash
terraform destroy
```

## References
- [Terraform AKS Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)
- [Azure GPU SKUs](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes-gpu)
- [AKS GPU Node Pools](https://learn.microsoft.com/en-us/azure/aks/gpu-cluster)
