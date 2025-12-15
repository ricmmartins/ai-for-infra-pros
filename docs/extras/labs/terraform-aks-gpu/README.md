# Lab: Deploying an AKS cluster with GPU node pool using Terraform

## Objective
Provision an **Azure Kubernetes Service (AKS)** cluster with a **dedicated GPU node pool** for AI and inference workloads.

This lab shows how infrastructure engineers can:
- Provision AKS using Terraform
- Add a **GPU-enabled user node pool**
- Prepare the cluster so GPUs are actually usable by workloads

Region: **West US 3**  
GPU SKU: **Standard_NCas_T4_v3** (cost‑efficient inference GPU)

---

## Lab scope and expectations

This is an **infrastructure enablement lab**.

It covers:
- AKS cluster provisioning
- CPU system node pool + GPU user node pool
- GPU readiness using the NVIDIA device plugin
- Basic validation with a GPU test pod

It does **not** cover:
- Model training or fine-tuning
- Advanced MLOps pipelines
- Production hardening (private AKS, firewall, policy-as-code)

---

## Prerequisites

- Terraform CLI (v1.5+)
- Azure CLI
- kubectl
- Azure subscription with AKS + GPU quota in **West US 3**
- RBAC: **Owner** or **Contributor** on the subscription

Login first:
```bash
az login
az account set --subscription "<your-subscription-id>"
```

---

## ⚠️ Cost warning

GPU node pools are **expensive** and bill while nodes exist.

This lab uses:
- 1 × `Standard_NCas_T4_v3` GPU node

Destroy resources when finished.

---

## Folder structure

```text
terraform-aks-gpu/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

---

## Deploy the cluster

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Validate AKS and GPU nodes

```bash
az aks get-credentials   --resource-group rg-ai-aks-gpu   --name aks-ai-gpu
```

```bash
kubectl get nodes
kubectl get nodes -l agentpool=gpu
```

---

## Enable GPU support (required)

AKS does not expose GPUs automatically.

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/nvidia-device-plugin.yml
```

Verify:
```bash
kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds
```

---

## GPU validation test

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: Never
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    command: ["bash", "-lc", "nvidia-smi && sleep 5"]
    resources:
      limits:
        nvidia.com/gpu: 1
```

```bash
kubectl apply -f gpu-test.yaml
kubectl logs gpu-test
```

---

## Cleanup

```bash
terraform destroy
kubectl delete pod gpu-test --ignore-not-found
```

---

## References

- AKS GPU clusters: https://learn.microsoft.com/azure/aks/gpu-cluster
- Terraform AKS: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster
- NVIDIA device plugin: https://github.com/NVIDIA/k8s-device-plugin
