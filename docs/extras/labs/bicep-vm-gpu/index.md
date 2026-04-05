# Lab 1 — Deploy a GPU Virtual Machine with Azure Bicep

> *"A misconfigured GPU cluster costs you thousands per day."* — Chapter 5, Infrastructure as Code for AI

---

## Why this lab matters

In **Chapter 3** you learned that AI compute isn't about raw horsepower — it's about choosing the *right* GPU SKU for the workload. In **Chapter 5** you saw why Infrastructure as Code is a survival mechanism when a single typo can burn through thousands of dollars on the wrong VM family. This lab brings both lessons together. You'll define a complete GPU-enabled VM environment in Bicep — networking, security, and compute — deploy it with a single command, and validate that the GPU is ready for real inference work. Think of it as provisioning a high-performance API server, except the "application" is a neural network and the "CPU" is an NVIDIA V100.

By the end of this lab you will have a repeatable, version-controlled template you can adapt for any GPU workload — from running a pre-trained model to hosting a containerized inference API.

---

## What you'll build

The Bicep template provisions five Azure resources that form a minimal but functional GPU compute environment:

```text
┌─────────────────────────────────────────────────┐
│                  Resource Group                 │
│                  (rg-ai-lab)                    │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │          Virtual Network (VNet)           │  │
│  │          10.20.0.0/16                     │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │     Subnet  10.20.1.0/24            │  │  │
│  │  │     ┌─────────────────────────────┐ │  │  │
│  │  │     │   NIC ──► GPU VM            │ │  │  │
│  │  │     │   (Standard_NC6s_v3)        │ │  │  │
│  │  │     └─────────────────────────────┘ │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  NSG (Allow SSH) ────► attached to subnet       │
│  Public IP (Static) ─► attached to NIC          │
└─────────────────────────────────────────────────┘
```

| Resource | Purpose |
|----------|---------|
| **Network Security Group** | Controls inbound traffic — allows SSH (port 22) from a configurable source CIDR |
| **Virtual Network + Subnet** | Provides isolated networking; the NSG is associated at the subnet level |
| **Public IP (Standard SKU)** | Gives the VM a static, internet-routable address for SSH access |
| **Network Interface** | Connects the VM to the subnet and attaches the public IP |
| **Virtual Machine** | Ubuntu 22.04 LTS Gen2 on a GPU-enabled N-series SKU with Premium SSD, SSH-key authentication |

💡 **Pro Tip**: The template uses `Standard` SKU for the public IP, which is zone-redundant by default. The older `Basic` SKU is being retired — always use Standard for new deployments.

---

## Prerequisites

Before starting, confirm each requirement:

- ✅ **Azure CLI** ≥ 2.55.0 — [Install guide](https://learn.microsoft.com/cli/azure/install-azure-cli)
- ✅ **Bicep CLI** — run `az bicep install` or `az bicep upgrade` to get the latest
- ✅ **SSH key pair** — have your public key ready (`~/.ssh/id_rsa.pub` or equivalent)
- ✅ **RBAC permissions** — **Contributor** or **Owner** on the target subscription or resource group
- ✅ **GPU quota** in your target region — this is the step most people skip

### Verify GPU quota

GPU quota is allocated per VM family per region. The default for most subscriptions is **zero**. Check before you deploy:

```bash
az vm list-usage --location eastus \
  --query "[?contains(name.value, 'Standard NCSv3')]" \
  --output table
```

You need at least **6 vCPUs** available for `Standard_NC6s_v3`. If the `currentValue` equals the `limit`, request an increase through the Azure portal under **Subscriptions → Usage + quotas**.

⚠️ **Production Gotcha**: Quota requests for GPU SKUs can take hours or even days for approval, depending on the region and your subscription type. Always check quota *before* starting a deployment — not after a cryptic `QuotaExceeded` error.

---

## Estimated cost

| Resource | SKU | Approximate cost (pay-as-you-go) |
|----------|-----|----------------------------------|
| GPU VM | Standard_NC6s_v3 (V100) | ~$3.06/hr |
| Public IP | Standard, static | ~$0.005/hr |
| Premium SSD (OS disk) | 30 GiB P4 | ~$5.28/month |
| VNet / NSG / NIC | — | Free |
| **Total (1-hour lab)** | | **~$3.10** |

Deallocate or delete the VM immediately after completing the lab. A forgotten GPU VM running over a weekend costs roughly **$150**.

---

## Folder structure

```text
bicep-vm-gpu/
├── main.bicep          # All resource definitions
├── parameters.json     # Runtime values (SSH key, VM size, source CIDR)
└── index.md            # This guide
```

---

## Understanding the Bicep template

Before deploying, let's walk through the key sections of `main.bicep` so you know exactly what you're provisioning. *(Refer to Chapter 5 for a full comparison of Bicep vs. Terraform for AI workloads.)*

### Parameters — making the template reusable

```bicep
@description('GPU VM size. Ensure quota exists in the chosen region.')
param vmSize string = 'Standard_NC6s_v3'

@description('Restrict SSH to this CIDR (use your public IP /32).')
param sshSourceCidr string = '*'

@description('SSH public key to place in authorized_keys.')
param adminPublicKey string
```

Every value that changes between environments is a parameter. The defaults are safe for a lab; `parameters.json` lets you override them without touching the template.

### Network Security Group — defense at the perimeter

```bicep
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${vmName}-nsg'
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
          sourceAddressPrefix: sshSourceCidr
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}
```

The NSG is the first resource defined because the subnet depends on it. By default `sshSourceCidr` is `'*'` (open to all), which is acceptable for a short-lived lab but dangerous in production.

⚠️ **Production Gotcha**: Never deploy a GPU VM with SSH open to `0.0.0.0/0` in a real environment. Crypto-mining botnets scan Azure IP ranges continuously. Lock the source CIDR to your corporate egress IP or, better yet, use Azure Bastion (see *Production Considerations* below).

### The VM — where the GPU lives

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'gpuvm'
      adminUsername: adminUsername
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
          properties: { primary: true }
        }
      ]
    }
  }
}
```

Key design decisions:

- **Gen2 image** — required for N-series VMs; Gen1 images won't expose the GPU correctly.
- **Premium_LRS OS disk** — GPU workloads are often I/O-sensitive during model loading; Premium SSD avoids a storage bottleneck.
- **SSH-key only** — password authentication is disabled. This is a security best practice, not a preference.

The template outputs the public IP and the VM resource ID, giving you everything you need for the next steps:

```bicep
output publicIpAddress string = publicIp.properties.ipAddress
output vmResourceId string = vm.id
```

---

## Step-by-step deployment

### 1. Authenticate and select your subscription

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Create a resource group

```bash
az group create --name rg-ai-lab --location eastus
```

💡 **Pro Tip**: Use **East US**, **West US 3**, or **West Europe** — these regions historically have the broadest GPU SKU availability. Check the [Azure products-by-region page](https://azure.microsoft.com/explore/global-infrastructure/products-by-region/) to confirm before deploying.

### 3. Configure parameters

Edit `parameters.json` with your values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "adminPublicKey": {
      "value": "ssh-rsa AAAAB3...your-full-public-key"
    },
    "vmSize": {
      "value": "Standard_NC6s_v3"
    },
    "sshSourceCidr": {
      "value": "203.0.113.50/32"
    }
  }
}
```

Find your public IP for the `sshSourceCidr` parameter:

```bash
curl -s https://ifconfig.me
```

### 4. Deploy

```bash
az deployment group create \
  --name gpu-vm-deploy \
  --resource-group rg-ai-lab \
  --template-file main.bicep \
  --parameters @parameters.json
```

Deployment typically completes in 3–5 minutes. Bicep compiles to ARM JSON transparently — you never need to manage an intermediate file.

### 5. Retrieve the public IP and connect

```bash
VM_IP=$(az deployment group show \
  --resource-group rg-ai-lab \
  --name gpu-vm-deploy \
  --query "properties.outputs.publicIpAddress.value" -o tsv)

echo "Connecting to $VM_IP..."
ssh azureuser@$VM_IP
```

---

## Install NVIDIA drivers

The VM ships with a bare Ubuntu 22.04 image — no GPU drivers pre-installed. You have two paths.

### Option A — NVIDIA GPU Driver Extension (recommended)

Microsoft maintains a VM extension that automatically installs the correct driver for your SKU. Run this from your **local machine** (not inside the VM):

```bash
az vm extension set \
  --resource-group rg-ai-lab \
  --vm-name vm-gpu-inference \
  --name NvidiaGpuDriverLinux \
  --publisher Microsoft.HpcCompute
```

The extension takes 5–10 minutes and may reboot the VM. Wait for the command to return, then SSH back in.

### Option B — Manual install

Use this only when you need a specific driver version for CUDA compatibility. Follow the [N-series driver setup guide for Linux](https://learn.microsoft.com/azure/virtual-machines/linux/n-series-driver-setup).

---

## Validate the GPU environment

Don't stop at `nvidia-smi`. A proper validation confirms the driver, the CUDA toolkit, and actual GPU compute capability.

### Check 1 — Driver and GPU detection

```bash
nvidia-smi
```

Expected output: one **Tesla V100** (for NC6s_v3) with driver version and CUDA version displayed. If `nvidia-smi` returns `command not found`, the extension hasn't finished — wait and retry.

### Check 2 — Driver version details

```bash
cat /proc/driver/nvidia/version
```

This confirms the kernel module loaded successfully and shows the exact driver build.

### Check 3 — CUDA device query

If the CUDA toolkit was installed by the driver extension, run:

```bash
/usr/local/cuda/extras/demo_suite/deviceQuery
```

Look for `Result = PASS` at the end. This exercises the CUDA runtime and proves user-space GPU access is functional.

### Check 4 — Quick inference smoke test with Python

Install a minimal Python environment and run a real GPU tensor operation:

```bash
sudo apt-get update && sudo apt-get install -y python3-pip
pip3 install torch --index-url https://download.pytorch.org/whl/cu118
python3 -c "
import torch
print(f'CUDA available: {torch.cuda.is_available()}')
print(f'GPU device:     {torch.cuda.get_device_name(0)}')
t = torch.randn(1000, 1000, device='cuda')
print(f'Tensor on GPU:  {t.device} — shape {t.shape}')
print('GPU inference smoke test PASSED')
"
```

If all four checks pass, your GPU VM is ready for production inference workloads.

💡 **Pro Tip**: The PyTorch install is ~2 GiB. For repeated lab runs, consider baking a custom VM image with drivers and frameworks pre-installed using Azure Image Builder (see Chapter 10 — AI Platform Operations at Scale).

---

## Production considerations

This lab template is designed for learning. Before adapting it for production, address these gaps:

### Remove the public IP — use Azure Bastion or a VPN

Expose the VM only through [Azure Bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) or a site-to-site VPN. Remove the public IP resource and NSG SSH rule entirely. In Bicep, this means deleting the `publicIp` resource and removing the `publicIPAddress` property from the NIC's IP configuration.

### Add a managed identity

Assign a **system-assigned managed identity** to the VM so it can authenticate to Azure services (Key Vault, Storage, Container Registry) without storing credentials:

```bicep
identity: {
  type: 'SystemAssigned'
}
```

Add this property to the `vm` resource block. Then grant the identity least-privilege RBAC roles on the resources it needs to access (see Chapter 8 — Security in AI Environments).

### Enable diagnostics and monitoring

Send boot diagnostics, OS metrics, and GPU telemetry to a Log Analytics workspace:

- **Boot diagnostics** — catches driver installation failures before you can SSH in.
- **Azure Monitor Agent** — streams OS and GPU performance counters.
- **DCGM Exporter** — exposes NVIDIA Data Center GPU Manager metrics for Prometheus-compatible monitoring (see Chapter 7 — Monitoring and Observability for AI Workloads).

### Add data disks for model storage

Production inference VMs typically need a separate managed disk or Azure Files mount for model weights. The OS disk should hold only the operating system and drivers — model artifacts belong on a dedicated volume you can snapshot, resize, and back up independently.

---

## Cleanup

Delete the entire resource group to remove all resources at once:

```bash
az group delete --name rg-ai-lab --yes --no-wait
```

The `--no-wait` flag returns immediately while deletion proceeds in the background. Confirm it's gone with:

```bash
az group show --name rg-ai-lab --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Deleted"
```

⚠️ **Production Gotcha**: GPU VMs continue billing even when stopped (deallocated) if the **public IP** remains allocated. Deleting the resource group is the only way to guarantee zero charges.

---

## Chapter cross-references

| Topic | Chapter |
|-------|---------|
| Choosing the right GPU SKU for training vs. inference | Chapter 3 — Compute |
| Why IaC is non-negotiable for AI workloads | Chapter 5 — Infrastructure as Code |
| Monitoring GPU utilization with DCGM and Azure Monitor | Chapter 7 — Observability |
| Locking down GPU environments (NSG, Bastion, managed identity) | Chapter 8 — Security |
| Estimating and controlling GPU spend | Chapter 9 — Cost Engineering |
| Building reusable VM images for AI | Chapter 10 — Platform Operations |

---

## References

- [Azure Bicep documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Quickstart: Create a Linux VM with Bicep](https://learn.microsoft.com/azure/virtual-machines/linux/quick-create-bicep)
- [GPU-optimized VM sizes](https://learn.microsoft.com/azure/virtual-machines/sizes-gpu)
- [NVIDIA driver setup for Linux N-series VMs](https://learn.microsoft.com/azure/virtual-machines/linux/n-series-driver-setup)
- [NVIDIA GPU Driver Extension for Linux](https://learn.microsoft.com/azure/virtual-machines/extensions/hpccompute-gpu-linux)
- [Azure Bastion documentation](https://learn.microsoft.com/azure/bastion/bastion-overview)
- [Azure products by region](https://azure.microsoft.com/explore/global-infrastructure/products-by-region/)