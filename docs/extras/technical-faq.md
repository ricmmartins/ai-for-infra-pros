# Technical FAQ: AI infrastructure essentials

A practical reference for infrastructure and cloud engineers adopting Artificial Intelligence in their environments.

---

## 1. Can I run AI workloads without a GPU?

**Yes, but with limitations.**

- Lightweight models (regression, decision trees, classical ML) can run efficiently on CPU.
- Large Language Models (LLMs), computer vision, and deep learning workloads require GPUs for acceptable latency and throughput.
- For cost‑effective inference on Azure, consider **Standard_NC4as_T4_v3** or **Standard_NV36ads_A10_v5** SKUs.

💡 *Tip:* Use **Spot VMs** only for non‑critical inference or batch jobs and always implement checkpointing and retries.

---

## 2. What’s the difference between training and inference?

| Stage | Purpose | Infrastructure analogy |
|------|--------|------------------------|
| **Training** | Builds the model using historical data | Large batch job or offline benchmark |
| **Inference** | Executes the model for predictions | Stateless API responding to requests |

💡 *Infra lens:* Training is bursty and compute‑heavy. Inference is latency‑sensitive and continuous.

---

## 3. How can I auto‑scale AI workloads?

**Recommended signals:**

- GPU utilization and memory usage
- Request queue depth
- P95/P99 inference latency
- Tokens per minute (TPM) growth rate

**Azure implementations:**

- **AKS:** Cluster Autoscaler + HPA using Prometheus metrics
- **Azure ML:** `min_instances` / `max_instances` on online endpoints
- **VMSS:** Autoscale rules based on custom GPU metrics

💡 *Best practice:* Always configure cooldown periods to avoid scale oscillation.

---

## 4. How do I secure inference endpoints?

**Baseline controls:**

- Private Endpoints with VNet integration
- Authentication using **Entra ID (Azure AD)** where supported
- API keys only as a fallback, stored in **Azure Key Vault**
- WAF or API Management for throttling and abuse prevention
- Diagnostic logs enabled in **Application Insights**

💡 *Zero Trust rule:* Treat inference endpoints like any external‑facing production API.

---

## 5. How much does AI cost to run on Azure?

Costs vary by region, model, and usage profile.

| Resource | Typical cost range | Notes |
|--------|-------------------|------|
| Standard_NC6s_v3 | ~$1–$1.5/hr | Entry GPU workloads |
| Standard_NC4as_T4_v3 | ~$0.8–$1/hr | Best inference cost efficiency |
| Standard_ND96amsr_A100_v4 | $25–$35/hr | High‑end training |
| Azure OpenAI (Standard) | Pay per token | Variable latency |
| Azure OpenAI (PTU) | Fixed hourly | Predictable throughput |

💡 *Tip:* Always pair GPU usage with **Azure Cost Management budgets and alerts**.

---

## 6. How do I monitor GPU usage and model latency?

**Key telemetry sources:**

- `nvidia-smi` for node‑level checks
- **DCGM Exporter** for Prometheus
- **Azure Monitor for Containers**
- **Application Insights** for request latency, errors, and dependencies
- **Grafana** for unified dashboards

💡 *Golden rule:* Correlate GPU utilization, latency, and token throughput.

---

## 7. What are common bottlenecks in AI infrastructure?

| Area | Bottleneck | Mitigation |
|-----|-----------|-----------|
| Storage | Slow dataset reads | NVMe, Premium SSD |
| Network | Cross‑region latency | Regional inference, Private Link |
| Compute | GPU idle time | Autoscaling, batching |
| Cost | Idle clusters | Scheduled shutdowns |

💡 *Reality:* The bottleneck is often the data path, not the GPU.

---

## 8. How do I estimate TPM, RPM, and cost for Azure OpenAI?

**Formula:**

```
TPM = Tokens per request × Requests per minute
```

**Important considerations:**

- Tokens include both prompt and response.
- Retries amplify real TPM consumption.
- Monitor HTTP 429 and `Retry-After` headers.

💡 *Rule:* For sustained production traffic, evaluate **Provisioned Throughput Units (PTUs)**.

---

## 9. What’s the best architecture for hybrid environments?

**Reference pattern:**

- Azure Arc for resource management
- Azure Monitor Agent for telemetry
- Private Link for secure connectivity
- Arc‑enabled AKS for unified Kubernetes control

💡 *Design principle:* Keep inference close to the data to minimize latency and egress.

---

## 10. What’s the best way to learn AI for infra engineers?

**Suggested path:**

1. AI‑900: Azure AI Fundamentals
2. Hands‑on labs (GPU VM, AKS GPU, Azure ML inference)
3. Azure OpenAI and monitoring deep dives
4. Build an internal Copilot or automation assistant

💡 *Mindset:* You don’t need to become a data scientist. You need to master **how AI runs**.

---

> Infrastructure doesn’t compete with AI.  
> It makes AI reliable, secure, and scalable.
