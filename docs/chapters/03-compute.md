# Chapter 3 — Infrastructure and Compute for AI

> “AI changed the game — but infrastructure still runs the show.”

---

## 🚀 Why AI Demands a New Infrastructure Mindset

Artificial Intelligence workloads are resource-intensive — both during **training** and **inference**.  
We’re no longer talking about traditional CPU + HDD workloads; instead, we’re dealing with **massive parallel operations**, **multi-node clusters**, and **ultra-low latency** expectations.

The good news?  
Most of what you already know about **compute, storage, networking, and security** still applies — but the scale, tuning, and inter-dependencies are much more demanding.

---

## 🧠 Training vs. Inference

| Phase | What Happens | Technical Characteristics |
|--------|----------------|----------------------------|
| **Training** | The model learns from large datasets | High GPU demand, long duration, petabytes of data |
| **Inference** | The trained model responds to new inputs | Low latency, scalable, can use CPU or GPU depending on model |

**Example:**
- Training a Large Language Model (LLM) can take **weeks** across **thousands of GPUs**.  
- Running inference with the same model takes **milliseconds** but must scale efficiently to millions of requests.

---

## 🎮 Compute Options for AI: CPU vs. GPU vs. TPU

| Type | Best For | Details |
|------|-----------|----------|
| **CPU** | Traditional workloads, light inference | Flexible but limited parallelism |
| **GPU** | Training + heavy inference | Thousands of cores optimized for matrix operations |
| **TPU** | TensorFlow-based workloads (Google Cloud only) | Specialized ASIC for deep learning |

🧩 **Infra Tip**  
- Small NLP or tabular models can run on CPU.  
- Vision, speech, or generative workloads need GPUs, even for inference.

---

## 🏗️ Azure GPU VM Families

| Family | Primary Use | Example Workload |
|---------|---------------|------------------|
| **NCas_T4_v3** | Cost-efficient inference | Chatbots, image classification |
| **ND_A100_v4/v5** | Heavy training | LLMs, multi-GPU workloads |
| **NVads_A10 / NVv4** | Visualization + light AI | R&D, desktop simulation |
| **Standard_D/E/F** | CPU-based general compute | ETL, orchestration, preprocessing |

💡 **Use Case:**  
Inference clusters often combine both:  
- **CPU pools** for orchestration  
- **GPU pools** for execution

---

## 🧱 When One VM Isn’t Enough: Clustering

AI workloads often require distributed compute due to data or model size.

| Need | Strategy | Tool |
|------|-----------|------|
| **Training across multiple GPUs** | Data or model parallelism | Horovod, PyTorch Distributed, Azure ML |
| **Horizontal scaling for inference** | Load balancing across nodes | AKS, VMSS |
| **High availability** | Zone redundancy and health probes | Azure Front Door, Application Gateway |

**AI Cluster Platforms:**
- **Azure Kubernetes Service (AKS)** – GPU container orchestration  
- **Azure Machine Learning** – training + deployment automation  
- **Ray** – distributed training framework  

---

## 🌐 Networking for AI: The Hidden Bottleneck

If your dataset sits in a slow network, GPUs will stay idle waiting for input.

| Resource | Why It Matters |
|-----------|----------------|
| **InfiniBand / RDMA** | Enables direct VM-to-VM GPU communication |
| **Accelerated Networking** | Reduces latency and jitter |
| **VNet Peering** | High-throughput internal communication |
| **BlobFuse2 with cache** | Local NVMe caching for blob reads |

🧩 **Infra Tip:**  
AI ≠ bandwidth-heavy only — it’s **latency-sensitive**.  
Each extra millisecond means thousands of GPU cores idling.

---

## 🧪 Hands-On: Create a GPU VM for Testing

```bash
az vm create \
  --name vm-gpu \
  --resource-group rg-ai-lab \
  --image Ubuntu2204 \
  --size Standard_NC6s_v3 \
  --admin-username azureuser \
  --generate-ssh-keys
```

After provisioning, install NVIDIA drivers:

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
sudo apt update && sudo apt install -y build-essential dkms
sudo ./NVIDIA-Linux-*.run
nvidia-smi
```

✅ **Expected Result:**  
GPU drivers installed successfully, `nvidia-smi` shows GPU status and utilization.

---

## 📊 Monitoring AI Workloads

| Metric | Tool |
|---------|------|
| GPU usage (memory, temperature) | `nvidia-smi`, Azure Monitor, Prometheus |
| Inference latency | Application Insights, OpenTelemetry |
| Node health | AKS metrics, VMSS diagnostics |

🧩 **Recommended Setup:**  
Use **Azure Managed Prometheus + Grafana** to visualize GPU workloads in real time.

---

## 🛡️ Security and Access Control

- Enforce RBAC for GPU resources  
- Use **Managed Identities** for AML pipelines  
- Isolate compute workloads using **AKS namespaces** or **taints/tolerations**  
- Apply **quotas** per project or team  

---

## ✅ Conclusion

AI changed the performance expectations — but the **core of reliability, networking, and scalability** is still infrastructure.  
Your expertise in compute sizing, high availability, and monitoring is what makes AI possible in production.

Next: [Chapter 4 — Infrastructure as Code and Automation for AI](04-iac.md)

