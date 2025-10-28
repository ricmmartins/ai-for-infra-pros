# 🧠 Technical FAQ: AI infrastructure essentials

A practical reference for infrastructure and cloud engineers adopting Artificial Intelligence in their environments.

## ❓ 1. Can I run AI workloads without a GPU?

**Yes, but with limitations.**

- Lightweight models (e.g., regression, decision trees) can run on CPU.  
- Large Language Models (LLMs), image, and deep learning tasks need GPUs for performance.  
- For cost-effective inference, use **Standard_NCas_T4_v3** or **NVads_A10** SKUs on Azure.

💡 *Tip:* Use ephemeral or spot instances for testing workloads.

## ❓ 2. What’s the difference between training and inference?

| Stage | Purpose | Analogy for Infra Engineers |
|--------|----------|-----------------------------|
| **Training** | Teaches the model using historical data | Like running a batch performance benchmark across datasets |
| **Inference** | Uses the trained model to generate predictions | Like responding to API requests in production |

💡 *Infra lens:* Training = heavy batch job; Inference = lightweight request-response workload.

## ❓ 3. How can I auto-scale AI workloads?

**Approaches:**
- Use **GPU metrics (utilization, temperature, queue length)** for autoscaling triggers.  
- In **AKS**, combine the **Cluster Autoscaler** with custom metrics from Prometheus.  
- In **Azure Machine Learning**, configure **min_instances** and **max_instances** on endpoints.  

💡 *Best practice:* Set a cooldown window between scale events to prevent oscillation.


## ❓ 4. How do I secure inference endpoints?

**Recommendations:**
- Use **Private Endpoints** and **Network Security Groups (NSGs)**.  
- Authenticate via **Azure AD tokens** instead of static keys.  
- Store secrets in **Azure Key Vault**, never in code.  
- Enable diagnostic logs in **Application Insights** to detect unauthorized access.

💡 *Zero Trust principle:* Assume every request is external — even from inside the VNet.

## ❓ 5. How much does AI cost to run on Azure?

**Depends on compute + model type.**

| Resource | Approx. Cost (USD/hr) | Use Case |
|-----------|----------------------|-----------|
| Standard_NC6s_v3 | ~$1.20/hr | Entry-level GPU workloads |
| Standard_NCas_T4_v3 | ~$0.90/hr | Cost-efficient inference |
| ND_A100_v4 | $25–$35/hr | Training large LLMs |
| Azure OpenAI (Standard) | Pay-per-token | API-based inference |
| Azure OpenAI (PTU) | Fixed monthly per unit | Guaranteed throughput |

💡 *Tip:* Monitor with **Azure Cost Management** and set budgets with alerts.

## ❓ 6. How do I monitor GPU usage and model latency?

**Use these telemetry tools:**
- **nvidia-smi** (local GPU metrics)
- **NVIDIA DCGM Exporter** (for Prometheus)
- **Azure Monitor for Containers**
- **Application Insights** (API latency and errors)
- **Grafana Dashboards** (custom visualization)

💡 *Goal:* Measure latency, token usage, and error rates — not just uptime.

## ❓ 7. What are common bottlenecks in AI infrastructure?

| Category | Common Issue | Mitigation |
|-----------|---------------|------------|
| **Storage** | Slow dataset reads | Use NVMe or Premium SSD for training datasets |
| **Network** | Latency in model API calls | Use Private Link and regional deployments |
| **Compute** | GPU idle time | Implement autoscaling and caching |
| **Cost** | Unused resources | Automate shutdown for idle clusters |

💡 *Tip:* Often the bottleneck isn’t the GPU — it’s the data path.

## ❓ 8. How do I estimate TPM, RPM, and cost for Azure OpenAI?

**Formula:**
```
TPM = (Tokens per Request × Requests per Minute)
```
- Start with average prompt size (input + output tokens).  
- Compare to Azure’s model quota (e.g., 600K TPM / 100 RPM for gpt-4-turbo).  
- Use **Application Insights** or **Log Analytics** to track consumption.  

💡 *Tip:* For steady traffic, consider **Provisioned Throughput Units (PTUs)**.

## ❓ 9. What’s the best architecture for hybrid environments?

**Recommended baseline:**
- **Azure Arc** for hybrid management  
- **Azure Monitor Agent** for telemetry ingestion  
- **Private Link** to ensure secure hybrid connectivity  
- **AKS on-prem (Arc-enabled)** for unified control plane  

💡 *Reality check:* Keep inference close to your data, minimize egress latency.

## ❓ 10. What’s the best way to learn AI for infra engineers?

**Suggested roadmap:**
1. Earn the **AI-900 Azure AI Fundamentals** certification.  
2. Complete this handbook’s mini-labs (VM GPU, AKS GPU, AML Inference).  
3. Explore **Azure OpenAI Service** and **Azure Machine Learning**.  
4. Build a small internal Copilot (e.g., chatbot or monitoring assistant).  

💡 *Mindset:* You don’t need to master data science — start by mastering *how AI runs*.
