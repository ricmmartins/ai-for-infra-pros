# Chapter 9 — Cost Engineering for AI Workloads

> "The cloud doesn't have a spending problem. It has a visibility problem."

---

## The $127,000 Monday Morning

It's Monday morning. You're halfway through your coffee when an email from finance lands with the subject line: **"URGENT: Azure bill — $127,000 — please explain."** Last month's forecast was $42,000. You open Azure Cost Management and start drilling down. Two ND96isr_H100_v5 VMs jump off the screen — provisioned three weeks ago for a "quick experiment" and never shut down. At roughly $98/hour each, running 24/7 for three weeks, that's approximately $33,000 in idle GPU time. Nobody was using them. Nobody even remembered they were running.

This isn't a hypothetical. Variations of this story play out in organizations every month. The ML engineer who provisioned those VMs wasn't being reckless — they were iterating fast, which is exactly what you want from your data science team. The failure wasn't human; it was systemic. No auto-shutdown policy, no budget alerts, no tagging to trace the VMs back to a project or owner.

This chapter gives you the frameworks, formulas, and operational practices to make sure that email never lands in your inbox. Not by slowing down experimentation, but by building guardrails that make cost awareness automatic.

---

## Why AI Cost Engineering Is Different

If you've managed cloud costs for traditional workloads, you already know the fundamentals: right-size VMs, use reserved instances, shut down dev/test environments at night. AI workloads follow the same principles — but the stakes are dramatically higher and the spending patterns are far less predictable.

### GPU VMs Cost 10–100× More Than General-Purpose VMs

A Standard_D4s_v5 (4 vCPUs, 16 GB RAM) costs roughly $0.19/hour. An ND96isr_H100_v5 (8× H100 GPUs) costs roughly $98/hour. That's a 500× difference. A misconfigured general-purpose VM running idle for a weekend costs you $9. A misconfigured GPU VM running idle for a weekend costs you $4,700. The margin for error shrinks dramatically.

### Training Is Bursty

Traditional workloads tend toward steady-state patterns — web servers handle predictable traffic, databases serve consistent queries. AI training is fundamentally different. A team might consume zero GPU hours for two weeks while preparing data, then spike to 64 GPUs for a five-day training run, then drop back to zero. This burst pattern makes forecasting difficult and makes reserved capacity commitments risky without careful planning.

### Token-Based Pricing Adds a Variable Layer

When your teams consume Azure OpenAI services, costs scale with usage in a way that's harder to predict than VM hours. A chatbot that handles 1,000 queries per day with short prompts costs a fraction of one that processes 1,000 legal documents with 100K-token contexts. Both are "the same application" from an infrastructure perspective, but the cost profiles are wildly different.

### Experimentation Culture Conflicts with Budget Discipline

Data scientists need to experiment — that's how models improve. But experimentation means spinning up resources on short notice, trying different configurations, and sometimes abandoning approaches midway. Telling the ML team "submit a purchase order before provisioning any GPU" kills velocity. The solution isn't less experimentation; it's better guardrails around experimentation.

**Infra ↔ AI Translation**: GPU idle time is like leaving every light on in a stadium after the game ends. The hourly electricity bill is enormous, nobody's benefiting from it, and the fix is a simple timer — but someone has to install the timer before the first game.

---

## GPU Cost Modeling

Before you can optimize costs, you need to model them. AI workloads have two fundamentally different cost profiles: **training** (running your own models on GPU VMs) and **inference** (consuming a model API like Azure OpenAI). Let's build the formulas for each.

### GPU VM Pricing by Family

The table below provides approximate pay-as-you-go costs for common Azure GPU VM SKUs. These prices change frequently — always verify against the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for current rates.

| VM SKU | GPU | GPU Count | GPU Memory | Approx. Cost/Hour (Pay-as-you-go) | Primary Use Case |
|---|---|---|---|---|---|
| NC4as_T4_v3 | NVIDIA T4 | 1 | 16 GB | ~$0.53 | Inference, light fine-tuning |
| NC24ads_A100_v4 | NVIDIA A100 | 1 | 80 GB | ~$3.67 | Training, inference |
| NC48ads_A100_v4 | NVIDIA A100 | 2 | 160 GB | ~$7.35 | Multi-GPU training |
| ND96asr_v4 | NVIDIA A100 | 8 | 320 GB | ~$27.20 | Large-scale training |
| ND96isr_H100_v5 | NVIDIA H100 | 8 | 640 GB | ~$98.00 | Frontier model training |

> **Note**: Prices are approximate, in USD, and vary by region. East US and West US 2 tend to have the most availability for GPU SKUs.

### Training Cost Formula

For training workloads running on GPU VMs, the core formula is:

```
Training Cost = (GPU count × Hours × Price/GPU-hour) + Storage + Networking
```

**Worked example — fine-tuning a 7B parameter model:**

| Component | Calculation | Cost |
|---|---|---|
| Compute | 2× A100 GPUs × 18 hours × $3.67/hr | $132.12 |
| Storage | 500 GB Premium SSD × 18 hours | ~$2.50 |
| Networking | Negligible (single VM) | ~$0 |
| **Total** | | **~$135** |

**Worked example — pre-training a 70B parameter model:**

| Component | Calculation | Cost |
|---|---|---|
| Compute | 64× H100 GPUs (8 VMs) × 72 hours × $98/hr per VM | $56,448 |
| Storage | 10 TB across nodes × 72 hours | ~$85 |
| Networking | Inter-node InfiniBand (included in ND SKU) | $0 |
| **Total** | | **~$56,533** |

The difference between these examples illustrates why right-sizing matters. Provisioning H100s for a job that runs fine on A100s doesn't just waste money — it wastes 3–4× the money.

### Inference Cost Formula (Azure OpenAI)

For Azure OpenAI consumption, costs are token-based:

```
Inference Cost = Requests × Avg Tokens/Request × Price per 1K Tokens
```

**Worked example — customer support chatbot (GPT-4o):**

| Component | Calculation | Cost |
|---|---|---|
| Input tokens | 10,000 requests/day × 800 tokens × $0.0025/1K | $20.00/day |
| Output tokens | 10,000 requests/day × 400 tokens × $0.01/1K | $40.00/day |
| **Daily total** | | **$60/day** |
| **Monthly total** | $60 × 30 | **~$1,800/month** |

**Worked example — same chatbot using GPT-4o-mini:**

| Component | Calculation | Cost |
|---|---|---|
| Input tokens | 10,000 requests/day × 800 tokens × $0.00015/1K | $1.20/day |
| Output tokens | 10,000 requests/day × 400 tokens × $0.0006/1K | $2.40/day |
| **Daily total** | | **$3.60/day** |
| **Monthly total** | $3.60 × 30 | **~$108/month** |

That's a 94% cost reduction for queries where GPT-4o-mini delivers acceptable quality — and for many customer support scenarios, it does.

> **Note**: Token prices shown are approximate and subject to change. Always verify current pricing on the [Azure OpenAI pricing page](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/).

### Decision Matrix: Compute Purchasing Models

| Factor | Pay-as-you-go | 1-Year Reserved | 3-Year Reserved | Spot VMs |
|---|---|---|---|---|
| **Discount** | 0% (baseline) | ~30–40% | ~50–60% | ~60–90% |
| **Commitment** | None | 1 year | 3 years | None |
| **Eviction risk** | None | None | None | High |
| **Best for** | Experimentation, unpredictable workloads | Steady-state inference | Long-term training clusters | Fault-tolerant training |
| **Budget predictability** | Low | High | High | Low |
| **Flexibility** | Maximum | Moderate (can exchange) | Low | Maximum |

**Pro Tip**: Don't commit to reserved instances until you have at least 2–3 months of utilization data. Many organizations reserve too early, then end up paying for GPUs they don't use. Start with pay-as-you-go, measure actual consumption, then reserve only the baseline you're confident you'll sustain.

---

## Spot and Low-Priority VMs for Training

Azure Spot VMs offer the same GPU hardware at 60–90% discount — but Azure can reclaim them with as little as 30 seconds' notice when capacity is needed. For the right workloads, this is the single biggest cost lever available.

### When Spot Is Safe

Spot VMs work well when your training framework supports **checkpoint-and-resume**. This means the training job periodically saves its state (model weights, optimizer state, learning rate schedule, current epoch) to durable storage. If the VM is evicted, a new Spot VM picks up from the last checkpoint instead of starting over.

Frameworks that support this well:

- **PyTorch Lightning**: Built-in checkpointing with `ModelCheckpoint` callback
- **DeepSpeed**: Automatic checkpointing integrated with ZeRO optimizer
- **Hugging Face Transformers**: `save_steps` and `resume_from_checkpoint` parameters
- **Azure ML**: Managed checkpointing for training jobs

### When Spot Is NOT Safe

Do not use Spot VMs when:

- **Deadlines are non-negotiable**: If a model must be trained by Friday, repeated evictions could push you past deadline
- **Checkpointing isn't implemented**: Without checkpointing, every eviction restarts training from scratch — potentially costing more than pay-as-you-go
- **Jobs are very short** (under 1 hour): The overhead of checkpoint/resume outweighs the savings
- **You're running inference in production**: Production endpoints need availability guarantees that Spot cannot provide

### Implementing Checkpoint-and-Resume

The pattern is straightforward:

1. **Save checkpoints to Azure Blob Storage or Azure Files** — not to local SSD (which is lost on eviction)
2. **Set checkpoint frequency** based on cost of lost work. If training costs $50/hour, checkpoint every 15 minutes to cap re-work at $12.50 per eviction
3. **Build your startup script** to check for existing checkpoints and resume if found
4. **Use Azure VM Scale Sets with Spot** to automatically replace evicted VMs

**Production Gotcha**: Spot VMs can be evicted with only 30 seconds' notice. Your checkpoint must write to durable storage, not local disk. If your checkpoint takes 5 minutes to write 20 GB of model state, you'll lose it on eviction. Either checkpoint more frequently with smaller state, or use faster storage (Premium SSD or Azure NetApp Files as a staging layer before Blob).

### Spot Savings Example

| Scenario | Pay-as-you-go | Spot (70% discount) | Savings |
|---|---|---|---|
| 8× A100 training, 72 hours | $1,958 | $587 | $1,371 |
| 8× H100 training, 72 hours | $7,056 | $2,117 | $4,939 |
| 4× T4 inference testing, 40 hours | $85 | $25 | $60 |

Even accounting for occasional evictions and re-work, Spot VMs typically deliver 50–80% net savings on fault-tolerant training workloads.

---

## Right-Sizing Strategies

The most expensive GPU is the one that's doing nothing — or doing work that a cheaper GPU could handle equally well. Right-sizing AI workloads requires matching the GPU to the task, not defaulting to the most powerful hardware available.

### Don't Use H100s When T4s Will Do

This is the most common cost mistake in AI infrastructure. A team requests H100s "because we want the best performance," but their actual workload is running inference on a 7B parameter model that fits comfortably in a T4's 16 GB of memory. The H100 is 185× more expensive per hour than a single T4. Unless they're training a frontier model or need the H100's specific capabilities (FP8 Tensor Cores, higher memory bandwidth), they're burning money.

**General sizing guidelines:**

| Workload | Recommended Starting SKU | Why |
|---|---|---|
| Inference (models ≤13B) | NC-series T4 | 16 GB memory, cost-effective |
| Inference (models 13B–70B) | NC-series A100 | 80 GB memory, good throughput |
| Fine-tuning (models ≤13B) | NC-series A100 (1–2 GPUs) | Sufficient memory with LoRA/QLoRA |
| Fine-tuning (models 70B+) | ND-series A100 (8 GPUs) | Needs multi-GPU + NVLink |
| Pre-training | ND-series H100 | Maximum throughput, NVLink + InfiniBand |

### GPU Utilization Benchmarking

Before scaling up, measure what you're actually using. Run `nvidia-smi` or use Azure Monitor GPU metrics to check:

- **GPU Compute Utilization (%)**: If consistently below 30%, the GPU is oversized for the workload or the data pipeline is the bottleneck
- **GPU Memory Utilization (%)**: If below 50%, a smaller GPU may work. If above 90%, you may need more memory or to enable gradient checkpointing
- **GPU Memory Used (GB)**: Compare to the GPU's total memory to understand headroom

**Infra ↔ AI Translation**: Right-sizing GPUs is exactly like right-sizing VMs in traditional infrastructure. You wouldn't run a static website on a 64-core VM. Same principle — but the cost of getting it wrong is 100× higher because GPU VMs are 100× more expensive.

### Auto-Shutdown Policies for Dev/Test

Every GPU VM provisioned for development, experimentation, or testing should have an **auto-shutdown policy**. Azure supports this natively through two mechanisms:

- **Azure DevTest Labs auto-shutdown**: Set a daily shutdown time on individual VMs
- **Azure Automation runbooks**: Schedule shutdown across resource groups or by tag
- **Azure Policy**: Enforce that all GPU VMs in dev/test subscriptions must have auto-shutdown enabled

**Pro Tip**: Set the default auto-shutdown time to 7:00 PM local time for all dev/test GPU VMs. Engineers who need their VM to run overnight can extend it manually — but the default should be "off." A single ND96isr_H100_v5 left running from Friday evening to Monday morning costs approximately $4,700. Auto-shutdown eliminates this entirely.

### Scaling Down After Experiments

Establish a process — not just a hope — for decommissioning experiment resources:

1. **Tag every GPU resource** with `experiment-name`, `owner`, and `expected-end-date`
2. **Run a weekly report** listing GPU VMs older than their expected end date
3. **Auto-notify owners** 48 hours before you deallocate
4. **Deallocate** if no response — data is on persistent storage, the VM can be recreated

---

## Azure OpenAI Cost Optimization

Azure OpenAI pricing splits into two models: **Standard (pay-per-token)** and **Provisioned Throughput Units (PTU)**. Choosing the wrong one — or not choosing at all — is one of the most common sources of unexpected AI spend.

### Standard (Pay-per-Token)

Standard deployment charges per 1,000 tokens consumed. It's simple, requires no commitment, and scales to zero when unused. This is the right choice for:

- Applications in development or early production
- Workloads with unpredictable or variable traffic
- Low-volume use cases (under a few hundred thousand tokens per day)

The risk is that costs scale linearly with usage. If your application goes viral or an upstream team starts sending higher volumes, your bill grows proportionally with no ceiling.

### Provisioned Throughput Units (PTU)

PTU deployments reserve dedicated model capacity, measured in Provisioned Throughput Units. You pay a fixed hourly or monthly rate regardless of how many tokens you consume. Throughput per PTU varies by model, version, and region, so you should always use the [Azure OpenAI capacity calculator](https://oai.azure.com/portal/calculator) to estimate PTU requirements for your specific workload.

PTU makes sense when:

- You have **sustained, predictable traffic** with high utilization
- You need **guaranteed latency** that shared (standard) deployments can't provide
- Your token volume is high enough that the **per-token cost under PTU is lower** than standard pricing

### When PTU Pays for Itself

The break-even point depends on your model, region, and traffic pattern, but as a general guideline: if your standard deployment is consistently utilized at **60–70% or above** of what a PTU allocation would provide, PTU typically becomes cheaper. Below that utilization, you're paying for reserved capacity you're not using.

### Decision Matrix: Standard vs PTU

| Factor | Standard (Pay-per-Token) | Provisioned Throughput (PTU) |
|---|---|---|
| **Pricing model** | Per 1K tokens consumed | Fixed hourly/monthly rate |
| **Commitment** | None | Monthly or yearly |
| **Best for** | Variable/unpredictable traffic | Steady, high-volume traffic |
| **Latency** | Shared capacity (variable) | Dedicated capacity (consistent) |
| **Cost at low volume** | Lower | Higher (paying for idle capacity) |
| **Cost at high volume** | Higher (linear scaling) | Lower (amortized across tokens) |
| **Scale to zero** | Yes | No (minimum PTU commitment) |

> **Note**: PTU pricing, throughput-per-unit ratios, and minimum commitments vary by model, version, and region. Always use the Azure OpenAI capacity calculator for accurate sizing.

### Token Optimization Strategies

Regardless of whether you use Standard or PTU, reducing token consumption directly reduces cost:

**Prompt caching**: Azure OpenAI supports automatic prompt caching for repeated prefixes. If your system prompt is 2,000 tokens and identical across all requests, cached tokens are charged at a reduced rate. Structure your prompts with the static portion first.

**Shorter system prompts**: A 3,000-token system prompt that could be 800 tokens wastes 2,200 tokens per request. At 10,000 requests per day with GPT-4o, that's 22 million wasted input tokens — roughly $55/day or $1,650/month in unnecessary spend.

**Response length limits**: Use the `max_tokens` parameter to cap response length. If your application only needs 200-word answers, don't allow 2,000-token responses. This is both a cost and a latency optimization.

**Multi-model routing**: Not every request needs your most capable (and most expensive) model. Route simple classification, extraction, or FAQ queries to GPT-4o-mini and reserve GPT-4o for complex reasoning, multi-step analysis, or tasks where quality measurably suffers with the smaller model. A well-implemented routing layer can cut inference costs by 50–80%.

**Pro Tip**: Build a simple evaluation harness that runs the same 200 representative queries through both GPT-4o and GPT-4o-mini, then have a domain expert score the outputs. If GPT-4o-mini scores within 5% on 70%+ of queries, you've identified a huge cost savings opportunity with minimal quality impact.

---

## FinOps Practices for AI

FinOps — the practice of bringing financial accountability to cloud spending — is critical for AI workloads because the cost of getting it wrong is so much higher. A team that over-provisions CPU VMs might waste hundreds of dollars. A team that over-provisions GPU VMs wastes tens of thousands.

### Cost Attribution: Tagging

Every AI resource should be tagged with at minimum:

| Tag | Purpose | Example |
|---|---|---|
| `cost-center` | Financial attribution | `CC-4521-ML` |
| `project` | Which initiative | `customer-churn-model` |
| `team` | Who owns it | `data-science-west` |
| `environment` | Dev, test, prod | `dev` |
| `expected-end-date` | When to review/delete | `2025-03-15` |

Use **Azure Policy** to enforce that GPU VM SKUs (NC*, ND*) cannot be created without these tags. This is a non-negotiable governance control.

**Production Gotcha**: Tags are only useful if they're enforced at provisioning time. If you allow untagged resources and try to tag retroactively, you'll always be playing catch-up. Deploy an Azure Policy with `deny` effect that blocks GPU VM creation without required tags. Teams will push back — hold the line.

### Budgets and Alerts

Azure Cost Management supports budgets with action-triggered alerts. For AI workloads, set up a three-tier alerting strategy:

| Alert Threshold | Action | Purpose |
|---|---|---|
| 50% of monthly budget | Email notification to team leads | Early visibility |
| 75% of monthly budget | Email + Teams notification to team + finance | Escalation |
| 90% of monthly budget | Email + automated action (e.g., stop non-production VMs) | Prevention |

Create separate budgets for GPU compute, Azure OpenAI, and storage — don't lump them into one budget where a spike in GPU spend hides behind headroom in storage.

### Chargeback and Showback

For organizations with shared GPU clusters, decide between:

- **Showback**: Teams see what they consume but aren't billed directly. Lower friction, but weaker incentive to optimize
- **Chargeback**: Teams are billed for consumption from their own budget. Stronger incentive, but requires accurate metering and can create perverse incentives (teams hoard reserved capacity)

Most organizations start with showback and move to chargeback as the AI practice matures and cost attribution tooling becomes reliable.

### GPU Quota Governance

Azure GPU quotas are your first line of defense against runaway provisioning. By default, most subscriptions have zero quota for ND-series VMs — you must explicitly request it. Use this to your advantage:

1. **Centralize quota requests** through a platform or FinOps team
2. **Approve quota by project**, not by individual
3. **Set subscription-level quotas** that cap the maximum number of GPU VMs any single team can provision
4. **Review quota allocations quarterly** and reclaim unused quota

### Regular Cost Reviews

Schedule a **monthly AI cost review** that brings together infrastructure, data science, and finance stakeholders. Review:

- Total GPU spend vs budget
- GPU utilization rates across all VMs
- Azure OpenAI token consumption trends
- Top 5 cost drivers and optimization opportunities
- Resources older than their expected end date

This meeting is where you catch the "$33,000 idle GPU" problem before it becomes a "$127,000 email from finance" problem.

---

## Cost Attribution in Shared Clusters (AKS)

When multiple teams share an AKS cluster with GPU node pools, cost attribution becomes more complex than simple VM tagging. You need namespace-level visibility into who's consuming what.

### Namespace-Level Cost Tracking

In a shared AKS cluster, each team or project should have its own Kubernetes namespace. This gives you a natural boundary for cost attribution:

- **Azure Cost Analysis** can break down AKS costs by namespace when the AKS cost analysis add-on is enabled
- **OpenCost** (CNCF project) provides real-time cost allocation by namespace, pod, and label
- **Kubecost** offers similar functionality with additional optimization recommendations

### Resource Quotas per Namespace

Kubernetes **ResourceQuotas** prevent any single namespace from consuming more than its share of cluster resources. For GPU workloads, this is essential:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: team-nlp
spec:
  hard:
    requests.nvidia.com/gpu: "4"
    limits.nvidia.com/gpu: "4"
```

This caps the `team-nlp` namespace at 4 GPUs, regardless of how many pods they try to schedule. Without this, a single team's runaway training job could consume every GPU in the cluster.

### Cluster Proportional Autoscaler

Use the **cluster autoscaler** to scale GPU node pools to zero when no GPU pods are pending. This ensures you're not paying for idle GPU nodes during off-hours. Configure the autoscaler with:

- **Scale-down delay**: How long a node must be idle before being removed (e.g., 10 minutes for dev clusters, 30 minutes for production)
- **Scale-down utilization threshold**: Remove nodes below a GPU utilization threshold
- **Maximum node count**: Hard cap on how many GPU nodes the autoscaler can provision

### Tools Comparison

| Tool | Cost | Namespace Attribution | GPU Support | Optimization Recommendations |
|---|---|---|---|---|
| Azure Cost Analysis | Included | Yes (with add-on) | Yes | Basic |
| OpenCost | Free (open-source) | Yes | Yes | Limited |
| Kubecost | Free tier + paid | Yes | Yes | Detailed |

**Pro Tip**: Enable the AKS cost analysis add-on (`az aks update --enable-cost-analysis`) before you need it. It requires time to accumulate data before it becomes useful. If you enable it after a cost incident, you won't have historical data to analyze.

---

## Chapter Checklist

Before moving on, confirm you have these cost engineering practices in place:

- **Cost model documented** for both training (GPU-hours) and inference (tokens) workloads
- **Tagging policy enforced** via Azure Policy — all GPU resources tagged with cost-center, project, team, and environment
- **Budget alerts configured** at 50%, 75%, and 90% thresholds with escalating actions
- **Auto-shutdown enabled** on all dev/test GPU VMs
- **Spot VMs evaluated** for fault-tolerant training workloads with checkpointing implemented
- **Right-sizing validated** — GPU utilization benchmarked before provisioning larger SKUs
- **Azure OpenAI pricing model selected** — Standard vs PTU evaluated based on utilization data
- **Token optimization implemented** — prompt caching, system prompt trimming, response length limits, multi-model routing
- **GPU quota governance** centralized with approval workflow
- **Monthly cost review meeting** scheduled with infra, data science, and finance stakeholders
- **Namespace-level cost tracking** enabled for shared AKS clusters
- **Weekly idle resource report** running to catch forgotten experiments

---

## What's Next

Cost is controlled. But as your AI platform grows from one team to ten, you need operational patterns that scale: fleet management, multi-tenancy, scheduling, and SLA design. Chapter 10 takes you from running AI projects to running an AI platform.
