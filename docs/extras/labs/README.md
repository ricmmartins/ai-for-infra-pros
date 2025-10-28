# 🧪 AI infrastructure labs

Welcome to the **hands-on labs** section of the _AI for Infra Pros — The Practical Handbook for Infrastructure Engineers_.  
Each lab demonstrates how to apply the infrastructure concepts from the book in real-world Azure environments.

## Lab index

| Lab | Description | Technologies |
|-----|--------------|---------------|
| [**Terraform AKS GPU Cluster**](./terraform-aks-gpu/README.md) | Provision an Azure Kubernetes Service cluster with a dedicated GPU node pool for AI workloads. | Terraform, AKS, GPU, IaC |
| [**Bicep VM with GPU**](./bicep-vm-gpu/README.md) | Deploy a single GPU-enabled VM using Azure Bicep to host AI inference workloads. | Bicep, Azure CLI, NVidia Drivers |
| [**YAML Inference API (Azure ML)**](./yaml-inference-api/README.md) | Publish a trained model as an inference endpoint using Azure Machine Learning and YAML configuration. | Azure ML, YAML, CLI, REST API |

## Prerequisites

Before running any of the labs:
- Have an active **Azure Subscription**
- Install the latest **Azure CLI**
- Install **Terraform** and/or **Bicep** depending on the lab
- Ensure GPU quotas are available in your target region
- Have sufficient permissions (Owner or Contributor on the Resource Group)

## Lab workflow

All labs follow a similar structure:

1. **Provision** infrastructure (VM, AKS, or AML workspace)  
2. **Configure** access, security, and monitoring  
3. **Deploy** models or containers for inference  
4. **Validate** performance and connectivity  
5. **Clean up** resources to avoid unnecessary costs


## Recommendations

- Use **East US** or **West Europe** regions — they typically have better GPU availability.  
- Always **tag resources** with project and owner names for tracking.  
- Store deployment logs for auditing and rollback.  
- For production-grade deployments, add **Private Endpoints** and **Azure Policy** validation.

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
