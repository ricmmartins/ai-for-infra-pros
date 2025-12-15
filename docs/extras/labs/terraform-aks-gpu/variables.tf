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
  default     = "1.27.9"
}

variable "gpu_vm_size" {
  description = "GPU VM SKU for node pool"
  type        = string
  default     = "Standard_NCas_T4_v3"
}
