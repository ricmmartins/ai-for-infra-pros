# Cheatsheets — Quick Reference for AI Infrastructure Engineers

A condensed, at-a-glance reference covering every chapter of the book. Print this, bookmark it, pin it to your monitor — these are the numbers, commands, and checklists you'll reach for daily.

---

## Azure GPU VM Comparison *(Ch3, Ch4)*

| VM SKU | GPU | VRAM | Ideal For | Inference | Training | ~Cost/hr |
|--------|-----|------|-----------|-----------|----------|----------|
| `Standard_NC4as_T4_v3` | 1× T4 | 16 GB | Cost-effective inference | | ❌ | ~$0.53 |
| `Standard_NC6s_v3` | 1× V100 | 16 GB | General AI workloads | | | ~$0.90 |
| `Standard_NC24ads_A100_v4` | 1× A100 | 80 GB | Single-GPU training/inference | | | ~$3.67 |
| `Standard_NV36ads_A10_v5` | 1× A10 | 24 GB | Visualization + lightweight AI | | ❌ | ~$1.80 |
| `Standard_ND96asr_v4` | 8× A100 | 640 GB total | Multi-GPU LLM training | | | ~$27.20 |
| `Standard_ND96isr_H100_v5` | 8× H100 | 640 GB total | Frontier model training | | | ~$40+ |

**Pro Tip**: For inference, start with T4 (`NC4as_T4_v3`). Only move to A10 or A100 when you've proven the model doesn't fit in 16 GB VRAM or needs higher throughput.

---

## CPU vs GPU Quick Reference *(Ch3)*

| Attribute | CPU | GPU |
|-----------|-----|-----|
| Core count | 8–128 | 2,560–16,896 CUDA cores |
| Architecture | Optimized for serial/branching logic | Optimized for parallel SIMD operations |
| Memory | Shared system RAM (up to TBs) | Dedicated VRAM (16–80 GB per GPU) |
| Best for | Web apps, ETL, classical ML, preprocessing | Deep learning, embeddings, matrix math |
| Azure families | Dv5, Ev5, Fv2 | NCas_T4, NC_A100, ND_H100 |
| Cost profile | 💲 | 💲💲💲 |

**Production Gotcha**: Don't put preprocessing (image resizing, tokenization) on GPUs. Use CPU nodes for data preparation and reserve GPU exclusively for model computation.

---

## GPU Memory Math *(Ch4)*

Use these formulas to calculate whether your model fits in GPU VRAM before you provision.

### Model Parameter Memory

| Precision | Formula | 7B Model | 13B Model | 70B Model |
|-----------|---------|----------|-----------|-----------|
| FP32 | `params × 4 bytes` | 28 GB | 52 GB | 280 GB |
| FP16 / BF16 | `params × 2 bytes` | 14 GB | 26 GB | 140 GB |
| INT8 | `params × 1 byte` | 7 GB | 13 GB | 70 GB |
| INT4 (GPTQ/AWQ) | `params × 0.5 bytes` | 3.5 GB | 6.5 GB | 35 GB |

### Training Memory (Full Fine-Tuning)

```
Total VRAM ≈ Model weights + Gradients + Optimizer states + Activations
           ≈ (params × 2) + (params × 2) + (params × 8) + activations
           ≈ params × 12 bytes (AdamW, FP16 mixed precision) + activations
```

**Example**: 7B model with AdamW → `7B × 12 = 84 GB` minimum → requires 2× A100-80GB or gradient checkpointing.

### Inference Memory (Quick Estimate)

```
VRAM ≈ Model weights + KV cache
KV cache per token ≈ 2 × num_layers × hidden_dim × 2 bytes (FP16)
```

**Pro Tip**: When a model *just barely* fits in VRAM, you'll OOM under load because the KV cache grows with sequence length and batch size. Leave 20% VRAM headroom.

### GPU Count Calculator

```
Min GPUs needed = Total model memory ÷ Per-GPU VRAM × 1.2 (safety margin)
```

| Model | Precision | Min VRAM | Fits On |
|-------|-----------|----------|---------|
| Llama 2 7B | FP16 | 14 GB | 1× T4 (tight) or 1× A10 |
| Llama 2 13B | FP16 | 26 GB | 1× A100-80GB |
| Llama 2 70B | FP16 | 140 GB | 2× A100-80GB |
| Llama 2 70B | INT4 | 35 GB | 1× A100-80GB |

**Production Gotcha**: These are *weights only*. KV cache for a 4K context with batch size 32 can add 8-12 GB. Always benchmark actual memory under realistic load.

---

## Security Checklist for AI Workloads *(Ch8)*

| # | Control | Description | Priority |
|---|---------|-------------|----------|
| 1 | Managed Identity for all services | No service principal secrets; use `SystemAssigned` or `UserAssigned` | 🔴 Critical |
| 2 | Private Endpoints everywhere | Azure ML, Storage, ACR, Key Vault, OpenAI — no public endpoints | 🔴 Critical |
| 3 | Key Vault for all secrets | API keys, connection strings, certificates — never in code or env vars | 🔴 Critical |
| 4 | Network segmentation | Hub-spoke VNet, NSGs restricting east-west traffic | 🔴 Critical |
| 5 | Diagnostic logs enabled | All resources → central Log Analytics workspace | 🟡 High |
| 6 | RBAC least privilege | `Cognitive Services User` not `Contributor`; scope to resource not RG | 🟡 High |
| 7 | Prompt injection testing | Input validation, content filtering enabled on Azure OpenAI | 🟡 High |
| 8 | Data encryption | TLS 1.2+ in transit, SSE with CMK at rest for sensitive data | 🟡 High |
| 9 | Egress control | NSG/Firewall restricting outbound from inference nodes | 🟡 High |
| 10 | Container image scanning | Only signed images from private ACR; block `latest` tag | 🟠 Medium |
| 11 | API rate limiting | Azure API Management or Application Gateway WAF | 🟠 Medium |
| 12 | Model artifact integrity | Checksum validation on model files pulled from storage | 🟠 Medium |

---

## Monitoring and Observability *(Ch7)*

### The GPU Golden Signals

| Signal | Metric | Source | Alert Threshold |
|--------|--------|--------|-----------------|
| **Utilization** | `DCGM_FI_DEV_GPU_UTIL` | DCGM Exporter | < 20% (waste) or > 95% (saturation) |
| **Memory** | `DCGM_FI_DEV_FB_USED` / `FB_FREE` | DCGM Exporter | > 90% used (OOM risk) |
| **Temperature** | `DCGM_FI_DEV_GPU_TEMP` | DCGM Exporter | > 83°C (thermal throttling) |
| **Errors** | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | DCGM Exporter | > 0 (hardware fault) |

### Application-Level Metrics

| Metric | What It Tells You | Tool |
|--------|-------------------|------|
| P50/P95/P99 inference latency | User experience and SLA compliance | Application Insights |
| Requests per second (RPS) | Load pressure and capacity planning | Application Insights |
| Error rate (4xx, 5xx) | Client misuse vs. server issues | Application Insights |
| Token throughput (TPM) | Azure OpenAI consumption rate | Azure Monitor |
| 429 rate | Throttling frequency | Azure Monitor / Log Analytics |
| Queue depth | Backpressure in async pipelines | Prometheus / custom metric |

### Essential KQL Queries

```kusto
// GPU VM performance over last 24 hours
InsightsMetrics
| where Name == "dcgm_gpu_utilization"
| where TimeGenerated > ago(24h)
| summarize avg(Val), max(Val), percentile(Val, 95) by bin(TimeGenerated, 5m), Computer
| render timechart

// Azure OpenAI 429 errors by deployment
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultType == "429"
| summarize count() by bin(TimeGenerated, 1h), _ResourceId
| render barchart
```

---

## MLOps Commands *(Ch6)*

### Azure ML CLI v2 Essentials

```bash
# Register a model from local files
az ml model create --name fraud-detector --version 1 \
  --path ./model/ --type custom_model

# Create a managed online endpoint
az ml online-endpoint create --name fraud-api \
  --auth-mode aml_token

# Deploy a model to the endpoint
az ml online-deployment create --name blue \
  --endpoint-name fraud-api \
  --model azureml:fraud-detector:1 \
  --instance-type Standard_NC4as_T4_v3 \
  --instance-count 2 \
  --file deployment.yml

# Blue-green traffic split
az ml online-endpoint update --name fraud-api \
  --traffic "blue=80 green=20"

# Test the endpoint
az ml online-endpoint invoke --name fraud-api \
  --request-file sample-request.json
```

### Model Lifecycle Commands

```bash
# List model versions
az ml model list --name fraud-detector --output table

# Archive old model version (soft delete)
az ml model archive --name fraud-detector --version 1

# Download model artifacts for inspection
az ml model download --name fraud-detector --version 2 \
  --download-path ./local-model/
```

### MLOps Pipeline Trigger

```bash
# Submit a training pipeline run
az ml job create --file pipeline.yml \
  --set inputs.training_data.path=azureml:transactions:latest

# Monitor a running job
az ml job show --name <job-name> --output table

# Stream job logs
az ml job stream --name <job-name>
```

**Pro Tip**: Always version your models with semantic versioning in the model registry. When an inference endpoint degrades, you need to roll back to `fraud-detector:3` not "whatever was deployed last Tuesday."

---

## Infrastructure Quick Deploy Commands *(Ch5)*

### Create a GPU VM

```bash
az vm create \
  --resource-group rg-ai-lab \
  --name vm-gpu-inference \
  --image Ubuntu2204 \
  --size Standard_NC4as_T4_v3 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --priority Spot \
  --max-price 0.35 \
  --eviction-policy Deallocate
```

**Production Gotcha**: Always check GPU quota *before* deploying: `az vm list-usage --location eastus -o table | grep -i "NC"`. Quota requests take 1-5 business days.

### AKS GPU Node Pool (Terraform)

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpuinfer"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_NC4as_T4_v3"
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 6

  node_labels = {
    "hardware" = "gpu"
    "gpu-type" = "t4"
  }

  node_taints = ["nvidia.com/gpu=present:NoSchedule"]

  tags = {
    Environment  = "production"
    WorkloadType = "inference"
    CostCenter   = "ai-platform"
  }
}
```

### Kubernetes GPU Pod Manifest

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: inference-server
spec:
  tolerations:
  - key: "nvidia.com/gpu"
    operator: "Equal"
    value: "present"
    effect: "NoSchedule"
  nodeSelector:
    hardware: gpu
  containers:
  - name: model
    image: myacr.azurecr.io/inference:v2.1
    resources:
      limits:
        nvidia.com/gpu: 1
      requests:
        nvidia.com/gpu: 1
        memory: "8Gi"
        cpu: "4"
```

---

## Cost Engineering Quick Reference *(Ch9)*

### Cost Optimization Levers

| Lever | Savings Range | Risk | Best For |
|-------|--------------|------|----------|
| **Spot VMs** | 60-90% | Eviction (batch only) | Training, batch inference |
| **Reserved Instances (1-yr)** | 20-35% | Commitment | Steady-state inference |
| **Reserved Instances (3-yr)** | 40-55% | Long commitment | Permanent workloads |
| **VM Scheduling** | 30-50% | Cold start latency | Business-hours-only workloads |
| **Right-sizing** | 15-40% | Performance testing needed | Over-provisioned clusters |
| **PTU vs Standard (OpenAI)** | 20-50% | Capacity commitment | Sustained >100K TPM |
| **Quantization (INT8/INT4)** | 50-75% GPU reduction | Slight accuracy loss | Inference (not training) |

### Quick Cost Estimation

```
Monthly GPU cost = (Hourly rate × Hours/day × 30) × VM count
                 = ($0.53 × 12 × 30) × 4 = $763/month (T4, 12hr/day)

Annual savings from RI = Monthly cost × 12 × 0.30 (avg 1-yr discount)
                       = $763 × 12 × 0.30 = $2,747/year
```

### Azure Cost Management Commands

```bash
# Current month spend by resource group
az consumption usage list \
  --start-date $(date -d "$(date +%Y-%m-01)" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName,'gpu')].{Name:instanceName,Cost:pretaxCost}" \
  --output table

# Create a budget with alerts
az consumption budget create \
  --budget-name ai-gpu-budget \
  --amount 5000 \
  --category cost \
  --time-grain monthly \
  --start-date 2025-01-01 \
  --end-date 2025-12-31
```

### Chargeback Tagging (Azure Policy)

```json
{
  "if": {
    "allOf": [
      { "field": "type", "equals": "Microsoft.Compute/virtualMachines" },
      { "field": "Microsoft.Compute/virtualMachines/vmSize", "like": "Standard_N*" },
      { "field": "tags['CostCenter']", "exists": false }
    ]
  },
  "then": { "effect": "deny" }
}
```

**Pro Tip**: Set up a weekly cost anomaly alert at 120% of your trailing 4-week average. GPU costs can spike fast when someone forgets to deallocate a training VM.

---

## Platform Ops Commands *(Ch10)*

### Namespace Isolation for Multi-Tenancy

```yaml
# Resource quota per team namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.nvidia.com/gpu: "4"
    requests.cpu: "32"
    requests.memory: "128Gi"
    pods: "50"
---
# Limit range to prevent single-pod resource hogging
apiVersion: v1
kind: LimitRange
metadata:
  name: gpu-limits
  namespace: team-alpha
spec:
  limits:
  - type: Container
    max:
      nvidia.com/gpu: "2"
      memory: "64Gi"
    default:
      cpu: "2"
      memory: "8Gi"
```

### Network Policy for Namespace Isolation

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: team-alpha
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: team-alpha
  - to:  # Allow DNS
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
```

### GPU Time-Slicing Configuration

```yaml
# NVIDIA device plugin ConfigMap for time-slicing
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin
  namespace: kube-system
data:
  config: |
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 2
```

**Production Gotcha**: GPU time-slicing provides no memory isolation. If Pod A allocates 14 GB on a 16 GB T4, Pod B will OOM even though Kubernetes shows the GPU as "available." Only use time-slicing in dev/test.

---

## Azure OpenAI Throughput Reference *(Ch11)*

### Deployment Types Comparison

| Attribute | Standard (PayGo) | Provisioned (PTU) | Global Standard |
|-----------|-------------------|-------------------|-----------------|
| Billing | Per 1K tokens | Hourly (per PTU) | Per 1K tokens |
| Latency guarantee | None (best effort) | SLA-backed | None |
| Throttling | TPM/RPM limits | Provisioned capacity | Higher limits |
| Best for | Dev/test, bursty | Production, steady | Global routing |
| Min commitment | None | 1 month | None |
| Scale | Auto (with limits) | Fixed provisioned | Auto |

### PTU Sizing Estimator

```
Step 1: Measure average tokens per request
         Avg input tokens:  800
         Avg output tokens: 400
         Total per request: 1,200

Step 2: Calculate sustained TPM
         Requests per minute: 150
         Sustained TPM = 150 × 1,200 = 180,000 TPM

Step 3: Use Azure capacity calculator or:
         ~1 PTU ≈ 3,600 TPM (GPT-4o, approximate)
         PTUs needed ≈ 180,000 ÷ 3,600 = 50 PTUs

Step 4: Add 25% headroom for bursts
         Recommended: 63 PTUs
```

### Token Estimation Rules of Thumb

| Content Type | Approximate Tokens |
|-------------|-------------------|
| 1 English word | ~1.3 tokens |
| 1 page of text (~500 words) | ~650 tokens |
| 1 line of code | ~10-15 tokens |
| A 100-line code file | ~1,200 tokens |
| JSON payload (1 KB) | ~300 tokens |

### Azure OpenAI Monitoring Commands

```bash
# Check current deployments and their TPM limits
az cognitiveservices account deployment list \
  --resource-group rg-ai-prod \
  --name aoai-prod \
  --output table

# Query 429 throttling events (last 24h)
az monitor metrics list \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{name} \
  --metric "AzureOpenAIRequests" \
  --dimension StatusCode \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1H \
  --output table
```

**Pro Tip**: If your 429 rate exceeds 5%, you're leaving performance on the table. Either increase your TPM quota, migrate to PTU, or implement client-side exponential backoff with jitter.

---

## Troubleshooting Decision Tree *(Ch12)*

### GPU Not Detected

```
GPU not visible to workload?
├── Check VM SKU → Is it an N-series VM?
│   └── No → Wrong VM SKU. Redeploy with NC/ND/NV series.
├── nvidia-smi returns error?
│   ├── Driver not installed → Install NVIDIA driver extension:
│   │   az vm extension set --name NvidiaGpuDriverLinux \
│   │     --publisher Microsoft.HCPCompute --version 1.9 \
│   │     --vm-name <vm> --resource-group <rg>
│   └── Driver version mismatch → Check CUDA compatibility matrix
├── In AKS pod, `nvidia-smi` not found?
│   ├── Missing GPU device plugin → Deploy NVIDIA device plugin DaemonSet
│   ├── Pod missing resource request → Add `nvidia.com/gpu: 1` to limits
│   └── Pod not scheduled on GPU node → Check tolerations and nodeSelector
└── nvidia-smi shows GPU but CUDA fails?
    └── CUDA toolkit version doesn't match driver → Rebuild container with matching CUDA
```

### Inference Latency Spikes

```
P95 latency exceeding SLA?
├── Check GPU utilization
│   ├── > 95% → GPU saturated. Scale out (more replicas) or optimize batch size.
│   └── < 50% → GPU is not the bottleneck. Check below.
├── Check GPU memory
│   ├── > 90% → KV cache pressure. Reduce max sequence length or batch size.
│   └── Normal → Not memory-bound. Check below.
├── Check CPU utilization
│   ├── > 80% → Preprocessing bottleneck. Move to dedicated CPU pods.
│   └── Normal → Check below.
├── Check network / storage
│   ├── Model loading slow → Cache model on local NVMe, not Blob Storage.
│   └── High network latency → Check Private Endpoint routing.
└── Check application code
    ├── No request batching → Implement dynamic batching (batch size 8-32).
    └── Synchronous preprocessing → Move to async pipeline.
```

### Azure OpenAI 429 Throttling

```
Getting HTTP 429 responses?
├── Check Retry-After header value
│   ├── < 10 seconds → Implement exponential backoff with jitter
│   └── > 60 seconds → You've hit a hard quota limit
├── Check deployment TPM/RPM limits
│   ├── Near limit → Request quota increase or add second deployment
│   └── Well under limit → Check for retry storms amplifying actual TPM
├── Multiple consumers sharing one deployment?
│   └── Yes → Separate deployments per consumer with dedicated quotas
└── Sustained high usage?
    └── Evaluate PTU migration (see PTU Sizing above)
```

### OOM (Out of Memory) Errors

```
CUDA out of memory error?
├── Calculate model memory requirement (see GPU Memory Math above)
│   ├── Model too large for GPU → Quantize (INT8/INT4) or use larger GPU
│   └── Model fits → Batch size or sequence length too high
├── Reduce batch size by 50%, retry
│   ├── Works → Gradually increase to find sweet spot
│   └── Still OOM → Enable gradient checkpointing (training) or reduce max_seq_len
├── Multi-GPU available?
│   └── Enable tensor parallelism (inference) or ZeRO Stage 3 (training)
└── Still failing?
    └── Profile with `torch.cuda.memory_summary()` to find the allocation spike
```

---

## Performance and Throughput Formulas *(Ch3, Ch11)*

| Metric | Formula | Example |
|--------|---------|---------|
| **TPM** | `Avg tokens/request × RPM` | 1,200 × 150 = 180K TPM |
| **QPS** | `RPM ÷ 60` | 300 RPM = 5 QPS |
| **Model VRAM (FP16)** | `Parameters × 2 bytes` | 7B × 2 = 14 GB |
| **Training VRAM (AdamW)** | `Parameters × 12 bytes + activations` | 7B × 12 = 84 GB + activations |
| **GPU utilization efficiency** | `Active compute time ÷ Total allocated time` | 80% = healthy |
| **Cost per 1K inferences** | `(VM $/hr ÷ inferences/hr) × 1000` | ($0.53 ÷ 3600) × 1000 = $0.15 |
| **PTU break-even TPM** | `PTU hourly cost ÷ Standard per-token cost` | Varies by model and region |

---

## Where to Run Your Model — Decision Flow *(Ch3, Ch10)*

```
Is it a proprietary/custom model?
├── Yes → Do you need to train it?
│   ├── Yes → Azure ML Compute Clusters (managed) or GPU VMs (full control)
│   └── No (inference only) → How much traffic?
│       ├── < 10 QPS → Azure ML Managed Endpoint or single GPU VM
│       ├── 10-100 QPS → AKS with GPU node pool + HPA
│       └── > 100 QPS → AKS multi-node GPU pool + cluster autoscaler
└── No (using a foundation model) → Azure OpenAI Service
    ├── Dev/test or bursty → Standard (PayGo) deployment
    ├── Sustained production → Provisioned (PTU) deployment
    └── Need global distribution → Global Standard deployment
```

---

## Resource Tagging Convention *(Ch9, Ch10)*

| Tag | Example | Purpose | Required By |
|-----|---------|---------|-------------|
| `Environment` | `dev`, `staging`, `prod` | Lifecycle stage | Azure Policy |
| `CostCenter` | `CC-4521` | Chargeback and budgeting | Azure Policy |
| `Team` | `ml-platform` | Ownership and escalation | Convention |
| `WorkloadType` | `training`, `inference`, `batch` | Cost analysis and scheduling | Convention |
| `Model` | `fraud-detector-v2`, `gpt-4o` | Correlate to model metrics | Convention |
| `DataClassification` | `public`, `confidential`, `restricted` | Security controls | Azure Policy |
| `AutoShutdown` | `true`, `business-hours` | Cost automation triggers | Automation Runbook |

---

## Reference Links

- [Azure GPU VM sizes](https://learn.microsoft.com/azure/virtual-machines/sizes/overview#gpu-accelerated)
- [Azure OpenAI quotas and limits](https://learn.microsoft.com/azure/ai-services/openai/quotas-limits)
- [AKS GPU scheduling](https://learn.microsoft.com/azure/aks/gpu-cluster)
- [Azure ML CLI v2 reference](https://learn.microsoft.com/cli/azure/ml)
- [Azure Cost Management](https://learn.microsoft.com/azure/cost-management-billing/)
- [DCGM Exporter metrics](https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/latest/dcgm-exporter.html)
- [NVIDIA GPU time-slicing](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
- [Azure Monitor container insights](https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-overview)
