# Technical FAQ — AI Infrastructure Essentials

Practical answers for infrastructure engineers working with AI on Azure. Every answer cross-references the relevant chapter so you can dive deeper when needed.

---

## 1. Can I run AI workloads without a GPU? *(Ch3)*

**Yes, but know the boundaries.** Classical ML models — linear regression, decision trees, random forests, gradient-boosted trees — run efficiently on CPU. Many of these serve predictions in under 10 ms on a `Standard_D4s_v5`. Even some smaller neural networks (MobileNet, DistilBERT) can run acceptably on CPU if your latency budget is generous (200+ ms per request).

However, anything involving large matrix multiplications at scale — LLM inference, diffusion models, video processing, large embedding generation — will be 10-100× slower on CPU. A GPT-class model that responds in 200 ms on a T4 GPU would take 5-15 seconds on CPU.

**Rule of thumb**: If your model has more than 100M parameters, you almost certainly need a GPU. If it's under 10M parameters and uses tabular data, CPU is likely fine.

�� **Pro Tip**: Before requesting GPU quota, benchmark your model on a `Standard_D8s_v5` (CPU) first. If latency meets your SLA, you just saved 5× on compute costs.

---

## 2. What's the difference between training and inference from an infra perspective? *(Ch3)*

| Aspect | Training | Inference |
|--------|----------|-----------|
| **Compute pattern** | Batch, hours-to-weeks | Real-time, milliseconds per request |
| **GPU memory** | Needs weights + gradients + optimizer (12× params) | Needs weights + KV cache only (2-4× params) |
| **Scaling** | Scale up (bigger GPUs, more nodes) | Scale out (more replicas) |
| **Availability** | Tolerates interruptions (checkpointing) | Requires high availability (SLA) |
| **Network** | InfiniBand for multi-node (NCCL) | Standard Ethernet is fine |
| **Cost model** | Spot VMs viable (60-90% savings) | On-demand or Reserved (needs uptime) |
| **Storage** | High-throughput for datasets + checkpoints | Low-latency for model loading |

**Infra analogy**: Training is a massive batch ETL job that processes terabytes. Inference is a latency-sensitive API behind a load balancer. You'd never architect them the same way — and the same applies to AI.

---

## 3. How do I calculate whether my model fits in GPU memory? *(Ch4)*

Start with the parameter count and target precision:

```
FP16 memory = Parameters × 2 bytes
INT8 memory = Parameters × 1 byte  
INT4 memory = Parameters × 0.5 bytes
```

**For inference**, add KV cache overhead:

```
KV cache ≈ 2 × layers × hidden_dim × max_seq_len × batch_size × 2 bytes
```

**For training** (full fine-tuning with AdamW):

```
Total ≈ params × 12 bytes + activation memory
```

**Practical example**: Llama 2 13B at FP16 = 26 GB for weights alone. On an A100 (80 GB), that leaves 54 GB for KV cache and activations — comfortable for inference with batch size up to ~32. But for full fine-tuning, you'd need 13B × 12 = 156 GB — requiring at least 2× A100 with ZeRO Stage 3 sharding.

⚠️ **Production Gotcha**: PyTorch's CUDA memory allocator fragments memory over time. Even if your model fits in 15 GB on a 16 GB T4, it will OOM after a few hours under load. Leave 20% headroom minimum, or configure `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`.

---

## 4. What causes GPU OOM errors and how do I fix them? *(Ch4, Ch12)*

**Most common causes** (in order of frequency):

1. **Batch size too large** — Each sample in a batch consumes GPU memory. Reduce batch size by 50% and test.
2. **Sequence length too long** — KV cache grows linearly with sequence length. Set `max_tokens` or `max_seq_len` to the minimum your application needs.
3. **Model too large for the GPU** — Calculate required memory (see Q3). Quantize to INT8/INT4, or use a larger GPU.
4. **Memory leak in preprocessing** — Tensors created on GPU during preprocessing that aren't freed. Always preprocess on CPU.
5. **Memory fragmentation** — Long-running inference servers fragment GPU memory. Restart the process periodically, or use `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`.

**Debugging commands:**

```bash
# Check current GPU memory usage
nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# Inside Python, get detailed allocation breakdown
python -c "import torch; print(torch.cuda.memory_summary())"
```

**Quick fix checklist:**
- [ ] Reduce batch size
- [ ] Reduce max sequence length
- [ ] Enable gradient checkpointing (training)
- [ ] Quantize the model (INT8 with bitsandbytes, INT4 with GPTQ/AWQ)
- [ ] Move to a GPU with more VRAM
- [ ] Enable tensor parallelism across multiple GPUs

---

## 5. How should I set up auto-scaling for GPU inference? *(Ch3, Ch7)*

**Recommended scaling signals** (in priority order):

1. **P95 inference latency** — Scale out when latency approaches your SLA threshold. This is the most user-visible metric.
2. **GPU utilization** — Scale out when sustained above 80%. Scale in when below 30% for 15+ minutes.
3. **Request queue depth** — If your inference server queues requests, scale when queue depth exceeds 2× your batch size.
4. **GPU memory utilization** — Scale out when above 85% (KV cache pressure).

**Azure implementations:**

| Platform | Scaling Mechanism | GPU Metric Source |
|----------|-------------------|-------------------|
| AKS | HPA + Cluster Autoscaler | DCGM Exporter → Prometheus → HPA custom metrics |
| Azure ML | `min_instances`/`max_instances` | Built-in autoscaler (request latency based) |
| VMSS | Autoscale rules | Azure Monitor custom metrics via DCGM |

**Critical settings:**
- **Scale-out cooldown**: 3-5 minutes (GPU nodes take time to initialize)
- **Scale-in cooldown**: 15-20 minutes (avoid thrashing during traffic dips)
- **Min replicas**: Never set to 0 in production (cold start for GPU workloads is 2-5 minutes for model loading)

💡 **Pro Tip**: For AKS, set `min_count: 1` on your GPU node pool even during off-hours. The cost of one idle T4 (~$380/month) is far less than the user impact of a 5-minute cold start.

---

## 6. What is a model registry and why should infra engineers care? *(Ch6)*

A model registry is a versioned artifact store for ML models — think of it like a container registry (ACR) but for model files instead of Docker images. Azure ML's model registry stores model weights, metadata (accuracy metrics, training parameters), and lineage (which dataset and code produced this version).

**Why it matters for infra:**

- **Rollback capability** — When a new model degrades production inference, you need to redeploy version N-1 in minutes, not hours. The registry gives you `az ml model download --name fraud-detector --version 3`.
- **Deployment automation** — CI/CD pipelines reference `model-name:version` to deploy deterministically. No more "which model file is currently in the blob container?"
- **Storage management** — Model files are large (7B model = 14 GB at FP16). The registry handles deduplication and lifecycle.
- **Audit trail** — Regulated industries require proof of which model version served which predictions. The registry provides this.

**Minimum viable MLOps for infra teams:**

```bash
# Register model
az ml model create --name fraud-detector --version 4 --path ./model/

# Deploy specific version
az ml online-deployment create --endpoint-name prod-api \
  --model azureml:fraud-detector:4 --file deployment.yml

# Rollback (swap traffic)
az ml online-endpoint update --name prod-api --traffic "v3=100 v4=0"
```

⚠️ **Production Gotcha**: Model files in Azure ML's default storage account can accumulate fast. Set up lifecycle policies to archive versions older than 90 days — a single team can generate 500+ GB of model artifacts per quarter.

---

## 7. How do I monitor GPU workloads effectively? *(Ch7)*

**The four GPU golden signals** (analogous to Google's four golden signals for services):

1. **GPU Utilization** (`DCGM_FI_DEV_GPU_UTIL`) — Are the CUDA cores busy? < 20% means waste; > 95% means saturation.
2. **GPU Memory** (`DCGM_FI_DEV_FB_USED`) — How much VRAM is consumed? > 90% means OOM risk.
3. **GPU Temperature** (`DCGM_FI_DEV_GPU_TEMP`) — Above 83°C, NVIDIA GPUs thermal-throttle, silently reducing performance.
4. **GPU Errors** (`DCGM_FI_DEV_ECC_DBE_VOL_TOTAL`) — Double-bit ECC errors indicate hardware failure. Alert immediately.

**Monitoring stack recommendation:**

```
DCGM Exporter (DaemonSet) → Prometheus (scrape) → Grafana (dashboards)
                                                 → Alertmanager (alerts)
Application Insights SDK → Azure Monitor → Action Groups (PagerDuty/Teams)
```

**Three alerts every GPU deployment needs:**

| Alert | Condition | Severity |
|-------|-----------|----------|
| GPU OOM imminent | Memory > 90% for 5 min | P1 (page) |
| GPU waste | Utilization < 20% for 60 min | P3 (daily report) |
| Thermal throttling | Temperature > 83°C for 10 min | P2 (Teams) |

💡 **Pro Tip**: `nvidia-smi` is fine for a quick check, but it samples once per invocation. DCGM Exporter provides continuous 1-second resolution metrics — the difference matters when debugging intermittent latency spikes.

---

## 8. How do I secure AI inference endpoints? *(Ch8)*

Follow the same zero-trust principles you'd apply to any production API, plus AI-specific controls:

**Network layer:**
- Deploy inference behind **Private Endpoints** — no public IP
- Use **NSG rules** to restrict inbound to known clients only
- For Azure OpenAI, enable **VNet integration** and disable public access

**Identity layer:**
- **Managed Identity** for service-to-service auth (Azure ML, AKS pods, Functions)
- **Entra ID (Azure AD)** for user-facing applications
- API keys as last resort — rotate every 90 days, store in **Key Vault**

**AI-specific controls:**
- Enable **content filtering** on Azure OpenAI deployments
- Implement **input validation** — reject prompts exceeding max token limits
- Log all prompts and completions to **Log Analytics** for audit (comply with privacy policies)
- Rate-limit per client to prevent prompt injection brute-force attempts

**Quick validation:**

```bash
# Verify no public endpoints on Azure OpenAI
az cognitiveservices account show --name aoai-prod --resource-group rg-ai \
  --query "properties.publicNetworkAccess"
# Should return: "Disabled"
```

---

## 9. What are Spot VMs and when should I use them for AI? *(Ch9)*

**Spot VMs** offer unused Azure capacity at 60-90% discount but can be evicted with 30 seconds notice when Azure needs the capacity back.

**Safe for:**
- Model training (with checkpointing every 15-30 minutes)
- Batch inference (process queued items, re-queue on eviction)
- Hyperparameter sweeps (embarrassingly parallel — eviction loses one trial, not all)
- Dev/test GPU workloads

**Not safe for:**
- Production real-time inference (eviction = downtime)
- Workloads that can't checkpoint (you lose all progress)
- Anything with an SLA

**Implementation pattern for training:**

```bash
az vm create --name train-gpu --size Standard_NC24ads_A100_v4 \
  --priority Spot --max-price 0.60 --eviction-policy Deallocate \
  --resource-group rg-training --image Ubuntu2204 --generate-ssh-keys
```

**Checkpoint strategy:**
```python
# Save checkpoint every 30 minutes
if step % checkpoint_interval == 0:
    torch.save({
        'step': step,
        'model_state': model.state_dict(),
        'optimizer_state': optimizer.state_dict(),
    }, f"azureml://checkpoint-{step}.pt")  # Save to Azure Blob
```

⚠️ **Production Gotcha**: Spot eviction rates vary by region and VM size. `Standard_NC24ads_A100_v4` in `eastus` might see 2% eviction rate, while `westus2` sees 15%. Check [Azure Spot VM eviction data](https://learn.microsoft.com/azure/virtual-machines/spot-vms) before committing.

---

## 10. How do I estimate and control Azure OpenAI costs? *(Ch9, Ch11)*

**Step 1: Measure your token consumption**

```bash
# Query actual token usage over the last 7 days
az monitor metrics list \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{name} \
  --metric "ProcessedPromptTokens" "GeneratedCompletionTokens" \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1H --output table
```

**Step 2: Calculate monthly cost**

```
Monthly cost = (Avg prompt tokens/request × prompt price per 1K)
             + (Avg completion tokens/request × completion price per 1K)
             × Requests per month

Example (GPT-4o):
  800 prompt tokens × $0.0025/1K = $0.002
  400 completion tokens × $0.01/1K = $0.004
  Per request = $0.006
  100K requests/month = $600/month
```

**Step 3: Evaluate PTU vs Standard**

| Factor | Standard (PayGo) | Provisioned (PTU) |
|--------|-------------------|-------------------|
| Best when | < 100K TPM sustained | > 100K TPM sustained for 8+ hrs/day |
| Cost model | Per token | Fixed hourly per PTU |
| 429 risk | Yes (quota-limited) | No (provisioned capacity) |
| Break-even | Below crossover point | Above crossover point |

**Step 4: Set guardrails**

- Azure Budget alert at 80% of expected monthly spend
- Per-deployment TPM/RPM limits to prevent runaway costs
- Log token usage per caller for chargeback

💡 **Pro Tip**: Retries are hidden cost amplifiers. If 10% of requests get 429'd and retry 3 times, your actual token consumption is 1.3× what your application logs show. Always measure at the Azure resource level, not the application level.

---

## 11. What's the difference between PTU and Standard deployments? *(Ch11)*

| Attribute | Standard (PayGo) | Provisioned (PTU) |
|-----------|-------------------|-------------------|
| **Billing** | Per 1K tokens (input + output priced separately) | Hourly per PTU (fixed cost regardless of usage) |
| **Latency** | Best-effort, variable | Lower and more consistent (dedicated capacity) |
| **Throttling** | TPM/RPM limits, 429 responses when exceeded | Provisioned capacity, minimal 429s |
| **Commitment** | None | Minimum 1-month reservation |
| **Best for** | Dev/test, bursty workloads, low volume | Production, steady traffic, latency-sensitive apps |
| **Scaling** | Automatic (within quota) | Manual (add/remove PTUs) |

**When to switch to PTU:**
1. Your standard deployment's 429 rate exceeds 5%
2. You have sustained traffic above 100K TPM for 8+ hours/day
3. Latency consistency matters (e.g., user-facing chat)
4. You can commit to 1+ month of capacity

**PTU sizing calculation:**

```
Sustained TPM needed: 180,000
Approximate PTU capacity (GPT-4o): ~3,600 TPM per PTU
Base PTUs: 180,000 ÷ 3,600 = 50 PTUs
With 25% burst headroom: 63 PTUs
```

⚠️ **Production Gotcha**: PTUs are region-specific and subject to availability. If you need 100+ PTUs of a specific model, check regional capacity with your Microsoft account team *before* planning the migration. Popular regions fill up.

---

## 12. How do I implement multi-tenancy for AI workloads on AKS? *(Ch10)*

**Three isolation levels, from lightest to strictest:**

| Level | Mechanism | GPU Isolation | Use When |
|-------|-----------|---------------|----------|
| Namespace + ResourceQuota | Kubernetes namespaces | Time-slicing (shared) | Dev/test, trusted teams |
| Namespace + NetworkPolicy + dedicated nodes | Node pool per tenant | Dedicated GPU per pod | Production, compliance |
| Separate clusters | Cluster per tenant | Full isolation | Regulated industries, untrusted tenants |

**Minimum viable multi-tenancy (namespace level):**

1. One namespace per team with `ResourceQuota` capping GPU requests
2. `NetworkPolicy` denying cross-namespace traffic
3. `LimitRange` preventing any single pod from consuming all resources
4. OPA Gatekeeper policies enforcing image sources and resource limits
5. Kubecost for per-namespace cost attribution

**GPU-specific considerations:**
- **ResourceQuotas** limit the *number* of GPUs a namespace can request, but not GPU *memory* — a pod can still consume all VRAM on a shared GPU
- **NVIDIA GPU time-slicing** allows 2-4 workloads to share a GPU but provides zero memory isolation
- **NVIDIA MPS (Multi-Process Service)** offers slightly better sharing but still no hard memory boundaries
- For production multi-tenancy, use **dedicated GPU nodes** per team via node selectors and taints

💡 **Pro Tip**: Label your GPU nodes with `gpu-type: t4` or `gpu-type: a100` and use `nodeSelector` in deployments. This prevents a dev workload from accidentally landing on an expensive A100 node.

---

## 13. How do I troubleshoot GPU driver issues on Azure VMs? *(Ch12)*

**Symptom: `nvidia-smi` returns "command not found" or "driver not loaded"**

```bash
# Step 1: Check if the NVIDIA driver extension is installed
az vm extension list --resource-group <rg> --vm-name <vm> --output table

# Step 2: If missing, install it
az vm extension set \
  --resource-group <rg> --vm-name <vm> \
  --name NvidiaGpuDriverLinux \
  --publisher Microsoft.HCPCompute \
  --version 1.9

# Step 3: Reboot and verify
az vm restart --resource-group <rg> --name <vm>
# After reboot, SSH in and run:
nvidia-smi
```

**Symptom: Driver installed but CUDA errors in your application**

This is almost always a CUDA toolkit version mismatch. Check compatibility:

```bash
# Check driver version
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# Example output: 535.129.03

# Check CUDA version the driver supports
nvidia-smi | head -3
# Look for "CUDA Version: 12.2"

# Verify your container's CUDA toolkit matches
docker inspect <image> | grep CUDA
```

The CUDA toolkit in your container must be ≤ the driver's supported CUDA version. If your container uses CUDA 12.3 but the driver supports 12.2, it will fail silently or throw `CUDA error: no kernel image is available`.

⚠️ **Production Gotcha**: The Azure NVIDIA driver extension auto-updates by default. Pin the version in production to prevent an auto-update from breaking CUDA compatibility: `--version 1.9 --settings '{"driverVersion":"535.129.03"}'`.

---

## 14. How do I handle Azure OpenAI 429 (throttling) errors? *(Ch11, Ch12)*

**Understand the 429:**
Azure OpenAI returns HTTP 429 when your requests exceed the deployment's TPM (Tokens Per Minute) or RPM (Requests Per Minute) quota. The response includes a `Retry-After` header indicating how long to wait.

**Immediate mitigations (no infrastructure changes):**

1. **Exponential backoff with jitter** — Don't retry immediately. Wait `min(2^attempt × 100ms + random(0-100ms), 60s)`.
2. **Reduce prompt size** — Shorter system prompts consume fewer tokens. Every token saved increases effective throughput.
3. **Limit max_tokens** — Set it to the minimum your application needs, not the model maximum.

**Infrastructure mitigations:**

1. **Increase quota** — Request higher TPM/RPM limits via Azure portal (may take 1-3 business days).
2. **Add deployments** — Deploy the same model in a second region and load-balance with Azure API Management or a custom router.
3. **Migrate to PTU** — Provisioned capacity eliminates quota-based throttling entirely.
4. **Implement a token budget** — Track cumulative TPM per caller and reject requests at the application layer before they hit Azure OpenAI.

**Monitoring query (KQL):**

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultType == "429"
| summarize ThrottledRequests = count() by bin(TimeGenerated, 5m)
| render timechart
```

---

## 15. What storage backend should I use for model files and training data? *(Ch3, Ch6)*

| Storage Type | Throughput | Latency | Best For | Cost |
|-------------|-----------|---------|----------|------|
| **Azure Blob (Hot)** | 60 Gbps (per account) | ~10-20 ms | Model artifact storage, training data archive | 💲 |
| **Azure Blob (Premium)** | Higher IOPS | ~2-5 ms | Active training datasets | 💲💲 |
| **Azure NetApp Files** | 4,500 MiB/s (Ultra) | ~1 ms | Multi-node training checkpoints, shared data | 💲💲💲 |
| **NVMe (local SSD)** | 7+ GB/s | ~0.1 ms | Model loading cache, scratch space | Included in VM |
| **Azure Managed Lustre** | 500+ MB/s per client | ~1 ms | HPC-scale training datasets | 💲💲💲 |

**Recommended pattern:**
- Store model artifacts in **Blob Storage (Hot)** → download to local NVMe on pod/VM start
- Training datasets on **Blob (Premium)** or **ANF** depending on I/O requirements
- Checkpoints to **ANF** or **Blob** (ANF if checkpoint frequency < 5 min; Blob otherwise)

💡 **Pro Tip**: For AKS inference pods, use an init container that copies the model from Blob to the node's local SSD (`emptyDir`). This eliminates Blob latency on every model reload and survives pod restarts on the same node.

---

## 16. How do I implement blue-green deployments for ML models? *(Ch6, Ch10)*

**Azure ML Managed Endpoints** support traffic splitting natively:

```bash
# Deploy new model version as "green"
az ml online-deployment create --name green \
  --endpoint-name prod-api \
  --model azureml:fraud-detector:5 \
  --instance-type Standard_NC4as_T4_v3 \
  --instance-count 2

# Shift 10% traffic to green (canary)
az ml online-endpoint update --name prod-api \
  --traffic "blue=90 green=10"

# Monitor for 1 hour, then promote
az ml online-endpoint update --name prod-api \
  --traffic "blue=0 green=100"

# Delete old deployment
az ml online-deployment delete --name blue --endpoint-name prod-api --yes
```

**On AKS**, use Kubernetes-native strategies:

1. Deploy the new model version as a separate Deployment with a different label (`model-version: v5`)
2. Use an **Istio VirtualService** or **NGINX ingress** weighted routing to split traffic
3. Monitor P95 latency and error rate between versions
4. Promote or rollback by adjusting traffic weights

⚠️ **Production Gotcha**: ML model blue-green is more expensive than app blue-green because each deployment holds a full copy of the model in GPU memory. During the transition, you're paying for 2× the GPU capacity. Keep the transition window short (hours, not days).

---

## 17. How do I right-size GPU VMs for inference? *(Ch3, Ch9)*

**Step 1: Profile your model's memory and compute requirements**

```bash
# Run a benchmark with realistic input
python benchmark.py --model ./model --batch-size 1 --num-requests 1000
# Output: Avg latency 45ms, P95 72ms, GPU util 34%, VRAM used 11.2GB
```

**Step 2: Match to the smallest GPU that fits**

| If VRAM needed is... | And target latency is... | Use... |
|----------------------|-------------------------|--------|
| < 14 GB | < 100 ms | `Standard_NC4as_T4_v3` (T4, 16 GB) |
| 14-22 GB | < 50 ms | `Standard_NV36ads_A10_v5` (A10, 24 GB) |
| 22-75 GB | < 30 ms | `Standard_NC24ads_A100_v4` (A100, 80 GB) |
| > 80 GB | Any | Multi-GPU (ND96 series) |

**Step 3: Validate with load testing**

Run a realistic load test for 30+ minutes and check:
- GPU memory doesn't grow over time (no leak)
- P95 latency stays within SLA at peak QPS
- GPU utilization is 40-80% at expected traffic (room for bursts)

💡 **Pro Tip**: Start with the smallest GPU that fits your model and scale *out* (more replicas) rather than *up* (bigger GPU). Two T4 replicas often cost less than one A100 and provide better availability.

---

## 18. What should I include in an AI workload runbook? *(Ch7, Ch12)*

**Every GPU inference service should have a runbook covering:**

1. **Service overview** — Model name/version, endpoint URL, expected QPS, SLA targets
2. **Architecture diagram** — Compute (VM/AKS), storage, networking, dependencies
3. **Health check commands:**
   ```bash
   curl -s https://inference.internal/health | jq .status
   kubectl get pods -n ml-prod -l app=inference -o wide
   nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv
   ```
4. **Common failure scenarios and fixes:**
   - OOM → Reduce batch size or restart pod
   - High latency → Check GPU utilization, scale out if > 80%
   - 5xx errors → Check model loading, verify model file integrity
   - Pod CrashLoopBackOff → Check GPU driver compatibility, review container logs
5. **Escalation path** — L1 (restart pod), L2 (scale cluster), L3 (ML engineering team)
6. **Rollback procedure** — Steps to revert to the previous model version

---

## 19. How do I handle GPU quota limitations on Azure? *(Ch3, Ch4)*

**The quota challenge**: GPU VMs (N-series) have per-subscription, per-region vCPU quotas that default to 0 in most regions. You must request increases before deploying.

**Check current quotas:**

```bash
az vm list-usage --location eastus --output table | grep -i "NC\|ND\|NV"
```

**Request an increase:**
1. Azure Portal → Subscriptions → Usage + Quotas → Request increase
2. Or use the CLI: `az quota create` (requires `Microsoft.Quota` provider registration)

**Strategies for limited quota:**

- **Multi-region deployment** — Split workloads across 2-3 regions (e.g., 50% eastus, 50% westus2)
- **Right-size first** — Don't request A100 quota if T4 meets your latency SLA
- **Spot VMs for dev/test** — Spot quota is separate from on-demand and often more available
- **Subscription splitting** — Enterprise teams sometimes use separate subscriptions per workload to get independent quotas

⚠️ **Production Gotcha**: Quota approval is not instant. Plan 3-5 business days for standard requests, 1-2 weeks for large A100/H100 requests. Start the quota process the moment you begin capacity planning — not when you're ready to deploy.

---

## 20. What's the recommended learning path for infra engineers getting into AI? *(Ch1, Ch15)*

**Phase 1 — Foundation (Weeks 1-2):**
- Read Ch1-4 of this book (why AI matters, data basics, compute, GPU deep dive)
- Get **AI-900: Azure AI Fundamentals** certification
- Deploy a GPU VM and run `nvidia-smi` — understand what you're looking at

**Phase 2 — Hands-On (Weeks 3-4):**
- Complete the labs in this book's extras
- Deploy a model on AKS with a GPU node pool
- Set up monitoring with DCGM Exporter + Prometheus + Grafana
- Deploy an Azure OpenAI instance and hit it with a load test

**Phase 3 — Production Skills (Weeks 5-8):**
- Implement IaC for an ML workspace (Bicep or Terraform)
- Build a cost dashboard for GPU workloads
- Practice troubleshooting: simulate OOM, 429 throttling, driver issues
- Read Ch7-12 and apply monitoring, security, cost engineering, and platform ops

**Phase 4 — Leadership (Ongoing):**
- Build an internal AI platform for your org (Ch10)
- Present cost optimization results to leadership (Ch9)
- Create runbooks and operational documentation (Ch12)
- Mentor other infra engineers on AI readiness (Ch14)

💡 **Pro Tip**: You don't need to understand backpropagation or loss functions. Your job is to make AI *run* — reliably, securely, and cost-effectively. Focus on the infrastructure layer, and partner with data scientists on the model layer.

---

> Infrastructure doesn't compete with AI — it makes AI reliable, secure, and scalable.