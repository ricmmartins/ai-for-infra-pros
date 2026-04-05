# Lab 2 — GPU-Enabled AKS Cluster with Terraform

*Applies to: [Chapter 3 — Compute](../../../chapters/03-compute.md) · [Chapter 5 — IaC](../../../chapters/05-iac.md) · [Chapter 10 — Platform Ops](../../../chapters/10-platform-ops.md)*

---

## Why AKS + GPU?

If a standalone GPU VM (Lab 1) is like renting a single workshop, an AKS cluster with GPU node pools is like building an entire **factory floor** — complete with a foreman (the Kubernetes scheduler), dedicated assembly lines (node pools), and safety rails that keep expensive machinery from being misused (taints and tolerations).

Most production AI workloads eventually land on Kubernetes for one simple reason: **orchestration**. You don't just need *a* GPU; you need to schedule dozens of inference jobs, scale them up during peak traffic, roll back bad model versions without downtime, and keep your GPU nodes from running general-purpose cron jobs that could have run on a $0.05/hr CPU node.

AKS gives infrastructure teams a platform they already understand — Kubernetes — with Azure-managed control plane, integrated identity, and native GPU support. In this lab you'll build that foundation from scratch using Terraform, the lingua franca of infrastructure-as-code ([Chapter 5](../../../chapters/05-iac.md)).

---

## What you'll build

```text
┌─────────────────────────────────────────────────────┐
│                    AKS Cluster                      │
│                  (aks-ai-gpu)                       │
│                                                     │
│  ┌──────────────────┐    ┌───────────────────────┐  │
│  │  System Pool      │    │  GPU Pool             │  │
│  │  Standard_DS2_v2  │    │  Standard_NC4as_T4_v3 │  │
│  │  1 node (CPU)     │    │  1 node (T4 GPU)      │  │
│  │  Mode: System     │    │  Mode: User           │  │
│  │                   │    │  Taint: sku=gpu        │  │
│  │  Runs:            │    │                       │  │
│  │  - CoreDNS        │    │  Runs:                │  │
│  │  - kube-proxy     │    │  - NVIDIA plugin      │  │
│  │  - metrics-server │    │  - AI workloads       │  │
│  └──────────────────┘    └───────────────────────┘  │
│                                                     │
│  Network Plugin: Azure CNI                          │
│  Identity: System-Assigned Managed Identity         │
│  Kubernetes: 1.30                                   │
└─────────────────────────────────────────────────────┘
```

**Key design decisions:**

| Decision | Choice | Why |
|---|---|---|
| GPU SKU | `Standard_NC4as_T4_v3` | NVIDIA T4 — best price/performance for inference (see [Chapter 3](../../../chapters/03-compute.md)) |
| Separate node pools | System (CPU) + User (GPU) | Isolates control-plane components from expensive GPU workloads |
| Network plugin | Azure CNI | Pod-level VNET integration; required for most enterprise network policies |
| Identity | System-assigned managed identity | No credentials to manage, rotate, or leak |
| Region | West US 3 | Strong NC-series availability and competitive pricing |

---

## Prerequisites

### Tools

| Tool | Minimum version | Install |
|---|---|---|
| Terraform CLI | 1.5+ | [terraform.io/downloads](https://developer.hashicorp.com/terraform/downloads) |
| Azure CLI | 2.50+ | [learn.microsoft.com/cli/azure/install-azure-cli](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| kubectl | 1.28+ | Bundled with `az aks install-cli` |

### Azure access

You need **Contributor** (or **Owner**) on the target subscription and sufficient quota for the GPU SKU.

```bash
# Authenticate and set your subscription
az login
az account set --subscription "<your-subscription-id>"
```

### Check GPU quota (do this first!)

The single most common reason this lab fails is **missing GPU quota**. NC-series VMs require an explicit quota allocation that most subscriptions don't have by default.

```bash
# Check NCasv3-series vCPU quota in West US 3
az vm list-usage \
  --location westus3 \
  --output table \
  | grep -i "Standard NCASv3"
```

You need at least **4 vCPUs** available (the `Standard_NC4as_T4_v3` uses 4 vCPUs). If the `CurrentValue` equals the `Limit`, you must request a quota increase through the Azure portal before continuing.

⚠️ **Production Gotcha**: Quota requests for GPU SKUs can take **24–72 hours** in popular regions. Don't start this lab at 4 PM on a Friday expecting instant approval. Plan ahead, or use an alternate region where you already have quota.

💡 **Pro Tip**: Run `az vm list-skus --location westus3 --size Standard_NC --output table` to confirm the SKU is actually available in your target region. Azure occasionally retires SKUs or restricts them to specific availability zones.

---

## Cost estimate

GPU nodes bill by the minute whether you're running workloads or not. Here's what this lab costs:

| Resource | SKU | Estimated cost |
|---|---|---|
| AKS control plane | Free tier | $0.00/hr |
| System node pool | 1 × Standard_DS2_v2 | ~$0.10/hr |
| GPU node pool | 1 × Standard_NC4as_T4_v3 | ~$0.53/hr |
| **Total** | | **~$0.63/hr (~$15/day)** |

*Prices are pay-as-you-go estimates for West US 3 as of 2025. Check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for current rates.*

⚠️ **Production Gotcha**: The GPU node pool bills from the moment `terraform apply` completes, not from when you deploy your first workload. Set a calendar reminder to run `terraform destroy` when you're done. A forgotten GPU node left running over a long weekend costs ~$45.

---

## Step 1 — Understand the Terraform configuration

The lab uses three files. Let's walk through each one.

### variables.tf — Configurable parameters

```hcl
variable "location" {
  description = "Azure region"
  type        = string
  default     = "westus3"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "rg-ai-aks-gpu"
}

variable "aks_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-ai-gpu"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "gpu_vm_size" {
  description = "GPU VM SKU for node pool"
  type        = string
  default     = "Standard_NC4as_T4_v3"
}
```

Every value has a sensible default, so you can run this lab without creating a `terraform.tfvars` file. To override — for example, to use a different region — pass it at plan time: `terraform plan -var="location=eastus2"`.

### main.tf — The infrastructure

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.90.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-aigpu"

  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
    mode       = "System"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.gpu_vm_size
  node_count            = 1
  mode                  = "User"

  node_taints = [
    "sku=gpu:NoSchedule"
  ]

  tags = {
    workload = "gpu"
  }
}
```

**Three things worth highlighting:**

1. **Separate node pools** — The `default_node_pool` (named `system`) runs Kubernetes components on cheap CPU VMs. The `azurerm_kubernetes_cluster_node_pool` resource adds the GPU pool as a `User` mode pool. This separation means kube-system pods never consume your expensive GPU nodes.

2. **Azure CNI network plugin** — The `network_profile` uses `azure` (Azure CNI), which assigns VNET IP addresses directly to pods. This is the preferred choice for enterprise environments where pods need to be addressable from other VNET resources or on-premises networks.

3. **System-assigned managed identity** — No service principals, no client secrets, no rotation policies. The cluster identity is lifecycle-managed by Azure (see [Chapter 10](../../../chapters/10-platform-ops.md) on identity strategies).

### Understanding the GPU taint

The most important line in this entire lab is:

```hcl
node_taints = [
  "sku=gpu:NoSchedule"
]
```

A **taint** is Kubernetes' way of saying "this node is special — don't schedule anything here unless the workload explicitly opts in." The taint `sku=gpu:NoSchedule` tells the scheduler: *refuse to place any pod on this node unless that pod has a matching toleration.*

Think of it as a **"GPU Authorized Personnel Only"** sign on the factory floor. Without it, Kubernetes will happily schedule your logging agent, metrics collector, and that developer's debug pod onto your $0.53/hr GPU node — wasting expensive hardware on jobs that don't need it.

The matching toleration (which we'll use in the test pod) looks like this:

```yaml
tolerations:
  - key: "sku"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
```

💡 **Pro Tip**: Taints *repel* pods; tolerations *permit* pods. But tolerations don't *attract* — a pod with a GPU toleration could still land on a CPU node. For deterministic placement, pair tolerations with `nodeSelector` or node affinity rules pointing to `agentpool=gpu`.

### outputs.tf — Post-deployment values

```hcl
output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}
```

The `kubeconfig_command` output gives you a ready-to-paste command to configure `kubectl` after deployment — no hunting through the portal.

---

## Step 2 — Deploy the cluster

```bash
# Initialize the Terraform working directory
terraform init

# Preview what will be created
terraform plan -out=tfplan

# Apply the plan (takes 5–8 minutes)
terraform apply tfplan
```

Terraform will create three resources: a resource group, an AKS cluster with the system node pool, and the GPU user node pool. The GPU node pool takes the longest because Azure must allocate and configure the physical GPU hardware.

---

## Step 3 — Connect to the cluster

```bash
# Get credentials (use the output from terraform)
az aks get-credentials \
  --resource-group rg-ai-aks-gpu \
  --name aks-ai-gpu

# Verify connectivity
kubectl get nodes
```

You should see two nodes — one from each pool:

```text
NAME                             STATUS   ROLES    AGE   VERSION
aks-gpu-12345678-vmss000000      Ready    <none>   3m    v1.30.x
aks-system-87654321-vmss000000   Ready    <none>   5m    v1.30.x
```

---

## Step 4 — Install the NVIDIA device plugin

AKS provisions GPU-capable VMs, but Kubernetes doesn't know GPUs exist until a **device plugin** tells it. The [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin) runs as a DaemonSet on every GPU node and does three things:

1. **Discovers** NVIDIA GPUs on the host
2. **Advertises** them to the kubelet as the schedulable resource `nvidia.com/gpu`
3. **Allocates** GPUs to containers at runtime via the NVIDIA container runtime

Without it, `kubectl describe node` shows zero GPUs, and any pod requesting `nvidia.com/gpu` stays in `Pending` forever.

```bash
# Deploy NVIDIA device plugin v0.18.0
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.18.0/deployments/static/nvidia-device-plugin.yml
```

Wait for the plugin pods to start:

```bash
kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds -w
```

You should see one pod per GPU node, with status `Running`:

```text
NAME                                   READY   STATUS    RESTARTS   AGE
nvidia-device-plugin-ds-xxxxx          1/1     Running   0          30s
```

⚠️ **Production Gotcha**: The NVIDIA device plugin must run on GPU nodes, but those nodes have a `sku=gpu:NoSchedule` taint. The upstream DaemonSet manifest already includes the correct toleration. If you're building your own manifests or using Helm, **verify the toleration is present** or the plugin will never start on the GPU nodes — and you'll stare at `Pending` pods wondering why GPU resources show as zero.

---

## Step 5 — Validate GPU availability

Before deploying any AI workload, confirm that Kubernetes can see and allocate GPUs.

### Check node labels and allocatable resources

```bash
# List only GPU pool nodes
kubectl get nodes -l agentpool=gpu

# Inspect the GPU node in detail
kubectl describe node -l agentpool=gpu | grep -A 5 "Allocatable:" 
```

Look for this line in the output:

```text
nvidia.com/gpu:  1
```

If you see `nvidia.com/gpu: 0` or the field is missing entirely, the NVIDIA device plugin hasn't initialized correctly. Check its logs:

```bash
kubectl -n kube-system logs -l name=nvidia-device-plugin-ds
```

### Check taints are applied

```bash
kubectl describe node -l agentpool=gpu | grep -A 3 "Taints:"
```

Expected output:

```text
Taints:  sku=gpu:NoSchedule
```

---

## Step 6 — Run a GPU validation pod

Deploy a test pod that requests one GPU and runs `nvidia-smi` to confirm end-to-end functionality.

Save the following as `gpu-test.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: Never
  tolerations:
    - key: "sku"
      operator: "Equal"
      value: "gpu"
      effect: "NoSchedule"
  containers:
    - name: cuda-test
      image: nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["bash", "-lc", "nvidia-smi && sleep 5"]
      resources:
        limits:
          nvidia.com/gpu: 1
```

**What each section does:**

- **`tolerations`** — Matches the `sku=gpu:NoSchedule` taint on the GPU node pool, allowing the pod to be scheduled there
- **`resources.limits.nvidia.com/gpu: 1`** — Requests one GPU; the NVIDIA device plugin handles the allocation
- **`nvidia-smi`** — NVIDIA's system management interface; if this runs, the full GPU stack (driver → runtime → plugin) is working

```bash
# Deploy the test pod
kubectl apply -f gpu-test.yaml

# Wait for completion (the pod runs nvidia-smi and exits)
kubectl wait --for=condition=Ready pod/gpu-test --timeout=120s || true

# Check the output
kubectl logs gpu-test
```

Successful output looks like this:

```text
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.xx.xx    Driver Version: 535.xx.xx    CUDA Version: 12.2               |
|  GPU   Name        Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC         |
|  0     Tesla T4           Off    | 00000001:00:00.0 Off |                    0         |
+-----------------------------------------------------------------------------------------+
```

If you see the Tesla T4 listed, **congratulations** — your AKS cluster has a fully operational GPU pipeline. Clean up the test pod:

```bash
kubectl delete pod gpu-test --ignore-not-found
```

---

## Production considerations

This lab deploys a minimal configuration for learning. A production GPU cluster requires additional layers, all covered in depth across the book.

### Network and security

- **Private cluster** — Disable the public API server endpoint (`private_cluster_enabled = true`) so the control plane is only reachable from your VNET. See [Chapter 10](../../../chapters/10-platform-ops.md).
- **Network policies** — Enable Calico or Azure network policies to restrict pod-to-pod traffic. GPU inference endpoints should not be reachable by every namespace.
- **Private container registry** — Pull images from Azure Container Registry over a private endpoint, not the public internet.

### Scaling

- **Cluster autoscaler** — Set `auto_scaling_enabled = true`, `min_count = 0`, and `max_count = N` on the GPU node pool. Scaling to zero when idle eliminates GPU costs during off-hours.
- **KEDA** — For event-driven scaling of inference workloads based on queue depth or HTTP request rate.

💡 **Pro Tip**: Setting `min_count = 0` on GPU node pools is the single highest-impact cost optimization for non-24/7 workloads. A T4 node sitting idle overnight costs ~$4.25 for nothing. The autoscaler takes 3–5 minutes to provision a new GPU node — acceptable for batch inference, too slow for real-time APIs. Know your latency budget.

### Monitoring

- **Container Insights** — Enable Azure Monitor for containers to track GPU utilization, memory pressure, and throttling. Without it, you're flying blind on your most expensive resource. See [Chapter 7](../../../chapters/07-monitoring.md).
- **NVIDIA DCGM exporter** — Exposes GPU-level metrics (temperature, power draw, SM clock, memory utilization) to Prometheus. Essential for capacity planning.
- **Alerts** — Set alerts for GPU utilization consistently below 20% (right-sizing opportunity) or above 95% (scaling needed).

### Multi-GPU and advanced SKUs

For training workloads or large model inference, consider:

| SKU | GPUs | GPU memory | Use case |
|---|---|---|---|
| Standard_NC4as_T4_v3 | 1 × T4 | 16 GB | Small model inference (this lab) |
| Standard_NC24ads_A100_v4 | 1 × A100 | 80 GB | Large model inference, fine-tuning |
| Standard_ND96asr_v4 | 8 × A100 | 640 GB | Distributed training |

See [Chapter 3 — Compute](../../../chapters/03-compute.md) for the complete GPU SKU decision matrix.

---

## Cleanup

**Do not skip this step.** GPU nodes bill until they're deleted.

```bash
# Delete the test pod if still running
kubectl delete pod gpu-test --ignore-not-found

# Destroy all Azure resources created by this lab
terraform destroy
```

Type `yes` when prompted. Terraform will remove the GPU node pool, the AKS cluster, and the resource group. Verify in the Azure portal that no resources remain in `rg-ai-aks-gpu`.

---

## What you learned

In this lab you:

1. Provisioned an AKS cluster with separate system (CPU) and user (GPU) node pools using Terraform
2. Applied the `sku=gpu:NoSchedule` taint to prevent non-GPU workloads from consuming expensive nodes
3. Installed the NVIDIA device plugin to expose GPUs as schedulable Kubernetes resources
4. Validated the full GPU stack — from Azure VM hardware through the NVIDIA driver to a CUDA container

These are the foundational building blocks for any AI platform on Kubernetes. From here, you can layer on model serving frameworks (TorchServe, Triton, vLLM), autoscaling policies, and CI/CD pipelines for model deployment — all topics covered in the remaining chapters.

---

## References

- [Use GPUs on AKS — Microsoft Learn](https://learn.microsoft.com/azure/aks/gpu-cluster)
- [AKS best practices — Cluster isolation](https://learn.microsoft.com/azure/aks/operator-best-practices-cluster-isolation)
- [Terraform azurerm_kubernetes_cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster)
- [Terraform azurerm_kubernetes_cluster_node_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool)
- [NVIDIA device plugin for Kubernetes](https://github.com/NVIDIA/k8s-device-plugin)
- [Azure GPU VM pricing](https://azure.microsoft.com/pricing/details/virtual-machines/linux/)
- [Azure VM quota management](https://learn.microsoft.com/azure/quotas/per-vm-quota-requests)
