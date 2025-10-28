# Lab: Deploying a GPU virtual machine using Azure Bicep

## Objective
This lab demonstrates how to provision an **Azure Virtual Machine (VM)** with GPU acceleration using **Bicep**, the Azure-native Infrastructure-as-Code (IaC) language.

You’ll deploy a GPU-enabled Ubuntu VM, connect to it via SSH, install the NVIDIA drivers, and validate GPU availability with `nvidia-smi`.


## Prerequisites
Before starting, ensure you have:

- ✅ [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- ✅ [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- ✅ Access to an Azure subscription with GPU quotas
- ✅ SSH key pair generated locally
- ✅ A **resource group** for your deployment (or Terraform-created one)



## Folder structure
```
bicep-vm-gpu/
├── main.bicep
├── parameters.json
└── README.md
```

## Bicep template overview

### main.bicep
Defines the VM configuration, network interface, and OS profile.

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: 'vm-gpu-inference'
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_NC6s_v3'
    }
    osProfile: {
      computerName: 'gpuvm'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: '<your-public-ssh-key>'
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

## Deployment steps

### 1. Login and set your subscription
```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Create a resource group
```bash
az group create --name rg-ai-lab --location eastus
```

### 3. Deploy the Bicep template
```bash
az deployment group create \
  --resource-group rg-ai-lab \
  --template-file main.bicep \
  --parameters @parameters.json
```

## Validation

After deployment completes, connect to your VM:
```bash
ssh azureuser@<public-ip>
```

Check the GPU status:
```bash
nvidia-smi
```

✅ **Expected output:** A list showing your NVIDIA GPU (e.g., Tesla T4, V100) with active driver and CUDA version.

## Optional: Install NVIDIA drivers manually

If drivers are not pre-installed:
```bash
sudo apt update && sudo apt install -y build-essential dkms
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/535.54.03/NVIDIA-Linux-x86_64-535.54.03.run
chmod +x NVIDIA-Linux-*.run
sudo ./NVIDIA-Linux-*.run
```

Reboot and re-check:
```bash
sudo reboot
nvidia-smi
```

## Next steps
- Attach a **data disk** or mount a **Blob Storage container** for datasets  
- Containerize your model inference workload with **Docker + CUDA**  
- Connect to **Azure ML Workspace** for managed experimentation

## Cleanup
To remove the VM and its resources:
```bash
az group delete --name rg-ai-lab --yes --no-wait
```

## References
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure VM GPU Sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes-gpu)
- [Install NVIDIA Drivers on Linux VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/n-series-driver-setup)

