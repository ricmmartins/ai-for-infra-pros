# 🧪 AI infrastructure labs <span class="badge-free">Free</span>

Welcome to the **hands-on labs** section of the _AI for Infra Pros — The Practical Handbook for Infrastructure Engineers_.  
Each lab demonstrates how to apply the infrastructure concepts from the book in real-world Azure environments.

## Lab scope and expectations

These labs are **infrastructure-focused** and designed for:

- Provisioning GPU-enabled environments  
- Deploying inference-ready workloads  
- Validating performance, access, and observability  

They do **not** cover:

- Model training or fine-tuning  
- Data science experimentation  
- Advanced MLOps pipelines  

The goal is to help infrastructure engineers confidently **run AI workloads**, not build models from scratch.

## Lab index

| Lab | Description | Technologies |
|-----|--------------|---------------|
| [**Lab 1 — Bicep VM with GPU**](./bicep-vm-gpu/index.md) | Deploy a single GPU-enabled VM using Azure Bicep to host AI inference workloads. | Bicep, Azure CLI, NVIDIA Drivers |
| [**Lab 2 — Terraform AKS GPU Cluster**](./terraform-aks-gpu/index.md) | Provision an Azure Kubernetes Service cluster with a dedicated GPU node pool for AI workloads. | Terraform, AKS, GPU, IaC |
| [**Lab 3 — YAML Inference API (Azure ML)**](./yaml-inference-api/index.md) | Publish a trained model as an inference endpoint using Azure Machine Learning and YAML configuration. | Azure ML, YAML, CLI, REST API |

## Prerequisites

Before running any of the labs:

- Have an active **Azure Subscription**
- Install the latest **Azure CLI**
- Install **Terraform** and/or **Bicep** depending on the lab
- Ensure GPU quotas are available in your target region  
  - Common SKUs:
    - `Standard_NC4as_T4_v3` (T4 inference)
    - `Standard_NC6s_v3` (V100)
  - Check quotas with:
    ```bash
    az vm list-usage --location <your-target-region> --output table
    ```
- Install and update the Azure ML CLI extension:
  ```bash
  az extension add -n ml
  az extension update -n ml
  ```
  Tested with Azure CLI `>= 2.55.0`
- Authenticate with Azure:
  ```bash
  az login
  ```
- Have sufficient permissions (**Owner** or **Contributor** on the target Resource Group)

## ⚠️ Cost warning

These labs may create **GPU-backed resources**, which can incur significant costs if left running.

Always:

- Use the smallest GPU SKU possible  
- Complete validation steps promptly  
- Delete resource groups after finishing  

GPU resources can cost **$0.90–$30+/hour** depending on SKU.

## Lab workflow

All labs follow a similar structure:

1. **Provision** infrastructure (VM, AKS, or AML workspace)  
2. **Configure** access, security, and monitoring  
3. **Deploy** models or containers for inference  
4. **Validate** performance and connectivity  
5. **Clean up** resources to avoid unnecessary costs  

## Recommendations

- Prefer **West US 3** or **West Europe** — they historically offer broader GPU SKU availability, but quotas still apply  
- Always **tag resources** with project and owner names  
- Store deployment logs for auditing and rollback  
- For production-grade deployments, add **Private Endpoints** and **Azure Policy** validation  

## Cleanup reminder

After finishing a lab, remember to delete the created resources to prevent billing surprises:

```bash
az group delete --name <your-resource-group> --yes --no-wait
```

## References

- [Azure Machine Learning Documentation](https://learn.microsoft.com/en-us/azure/machine-learning/)
- [Terraform on Azure](https://learn.microsoft.com/en-us/azure/developer/terraform/)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure AI Infrastructure Overview](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/overview)

> “You don’t scale AI with PowerPoint — you scale it with Infrastructure as Code.”
