# Lab: Deploying a GPU virtual machine using Azure Bicep

## Objective
This lab provisions an **Azure Virtual Machine (VM)** with GPU acceleration using **Bicep** (Azure-native IaC).

You will:
1. Deploy a GPU-enabled Ubuntu VM (N-series).
2. Connect via SSH.
3. Install NVIDIA drivers using the **supported Azure approach**.
4. Validate GPU availability with `nvidia-smi`.
5. Clean up resources.

---

## Prerequisites

- ✅ Azure CLI installed. https://learn.microsoft.com/cli/azure/install-azure-cli
- ✅ Bicep installed (or use `az bicep install`). https://learn.microsoft.com/azure/azure-resource-manager/bicep/install
- ✅ GPU quota available in the target region for your chosen SKU (example: `Standard_NC6s_v3`).
- ✅ SSH public key available locally.
- ✅ RBAC permissions: **Owner** or **Contributor** on the target resource group.

Optional but recommended:
- ✅ Know your outbound IP, so you can restrict SSH access in the NSG rule.

---

## Folder structure
```text
bicep-vm-gpu/
├── main.bicep
├── parameters.json
└── README.md
```

---

## What was fixed vs the draft

The original snippet referenced `nic.id` but didn’t define the NIC/VNet/Public IP resources.
This version includes:
- VNet, Subnet
- Public IP
- NIC
- NSG with SSH rule
- Outputs for the public IP so you can SSH without guessing

It also replaces the manual `.run` driver install with the Microsoft-supported **GPU Driver Extension** path.

---

## 1. Login and select the subscription

```bash
az login
az account set --subscription "<your-subscription-id>"
```

---

## 2. Create a resource group

```bash
az group create --name rg-ai-lab --location eastus
```

---

## 3. Update `parameters.json`

Set your SSH public key and optionally adjust VM size.

- `adminPublicKey`: contents of your `~/.ssh/id_rsa.pub` (or equivalent)
- `vmSize`: example `Standard_NC6s_v3`

---

## 4. Deploy the Bicep template

```bash
az deployment group create   --resource-group rg-ai-lab   --template-file main.bicep   --parameters @parameters.json
```

---

## 5. SSH into the VM

Get the VM public IP from deployment output:

```bash
az deployment group show   --resource-group rg-ai-lab   --name <deployment-name>   --query "properties.outputs.publicIpAddress.value" -o tsv
```

Then connect:

```bash
ssh azureuser@<public-ip>
```

---

## 6. Install NVIDIA drivers (recommended, supported path)

### Option A. Install using the NVIDIA GPU Driver Extension (recommended)

Microsoft provides the **NVIDIA GPU Driver Extension for Linux** for N-series VMs. The VM may reboot during installation.  
Docs. https://learn.microsoft.com/azure/virtual-machines/extensions/hpccompute-gpu-linux

Run from your local machine:

```bash
az vm extension set   --resource-group rg-ai-lab   --vm-name vm-gpu-inference   --name NvidiaGpuDriverLinux   --publisher Microsoft.HpcCompute
```

Wait a few minutes. Then SSH back in (VM may reboot).

### Option B. Manual install (only if you have a specific driver requirement)

Follow Microsoft’s supported N-series driver setup guidance for Linux to choose the correct driver for your VM family and distro.  
Docs. https://learn.microsoft.com/azure/virtual-machines/linux/n-series-driver-setup

---

## 7. Validate

On the VM:

```bash
nvidia-smi
```

Expected output:
- A detected NVIDIA GPU (example: V100 or T4 depending on SKU)
- A loaded driver and CUDA version (if applicable)

---

## Next steps

- Attach a **data disk** or mount a **Blob Storage container** for datasets
- Containerize inference with **Docker + NVIDIA Container Toolkit**
- Add observability: DCGM exporter, Azure Monitor, Log Analytics

---

## Cleanup

```bash
az group delete --name rg-ai-lab --yes --no-wait
```

---

## References

- Azure Bicep docs. https://learn.microsoft.com/azure/azure-resource-manager/bicep/
- Quickstart: Bicep Ubuntu VM. https://learn.microsoft.com/azure/virtual-machines/linux/quick-create-bicep
- GPU VM sizes. https://learn.microsoft.com/azure/virtual-machines/sizes-gpu
- NVIDIA driver setup for Linux N-series. https://learn.microsoft.com/azure/virtual-machines/linux/n-series-driver-setup
- NVIDIA GPU Driver Extension for Linux. https://learn.microsoft.com/azure/virtual-machines/extensions/hpccompute-gpu-linux
