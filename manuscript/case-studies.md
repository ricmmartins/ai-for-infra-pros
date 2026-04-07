# Technical Case Studies — AI for Infrastructure Engineers

Real-world scenarios showing how infrastructure teams deliver measurable business impact with AI workloads on Azure. Each case study maps directly to the concepts covered in this book, so you can trace every decision back to a specific chapter.

These are production stories — not proofs of concept. Every metric is grounded in realistic operational data, and every architecture decision reflects the trade-offs infrastructure engineers face daily.

---

## Case Study 1 — GPU Cluster Buildout for Large-Scale Model Training

**📖 Chapters Referenced:** Ch3 (Compute), Ch4 (GPU Deep Dive), Ch5 (IaC)

### Scenario

A financial services firm needed to fine-tune a 13-billion-parameter language model on proprietary transaction data for fraud detection. Their data science team had validated the approach using a single A100 GPU in a research environment, but the full training run required multi-node distributed training across 8 nodes — 64 GPUs total — with a 72-hour training window to meet a regulatory deadline.

The infrastructure team had deep experience with high-availability compute clusters but had never provisioned GPU hardware at this scale. They faced unfamiliar challenges: InfiniBand networking requirements, NCCL collective communication tuning, and GPU memory management for a model that consumed 48 GB of VRAM per GPU before optimizer states were even loaded.

The CTO gave them three weeks to go from zero GPU infrastructure to a production training run — with full observability and cost controls in place from day one.

### Azure Services and Configuration

| Component | Service / SKU | Configuration |
|-----------|--------------|---------------|
| Compute | `Standard_ND96asr_v4` (8× A100 80 GB) | 8 nodes, InfiniBand enabled, Proximity Placement Group |
| Networking | Accelerated Networking + InfiniBand | NCCL `NCCL_IB_HCA=mlx5` environment variable set |
| Storage | Azure NetApp Files (Ultra tier) | 100 TiB volume, 4,500 MiB/s throughput for checkpoint I/O |
| IaC | Bicep modules | Parameterized templates for node count, SKU, and region |
| Monitoring | Azure Monitor + DCGM Exporter | GPU memory, SM occupancy, NVLink throughput dashboards |
| Cost control | Azure Budgets + auto-shutdown Logic App | $85K budget cap with 80%/90%/100% alert thresholds |

### What the Infra Team Did

1. **Quota validation** — Submitted quota requests for 768 A100 vCPUs in `southcentralus` two weeks early. First request was denied; they split across `southcentralus` (512) and `eastus2` (256) and got approved in 4 business days.
2. **Network topology** — Deployed all nodes in a single Proximity Placement Group within one availability zone. Configured InfiniBand SR-IOV with the `ND96asr_v4`'s built-in Mellanox ConnectX-6 adapters. Validated inter-node bandwidth at 200 Gbps using `ib_write_bw`.
3. **Storage design** — Chose Azure NetApp Files over Blob Storage after benchmarking checkpoint writes. A single 25 GB checkpoint across 64 GPUs completed in 11 seconds on ANF versus 4+ minutes on Premium Blob.
4. **IaC automation** — Built Bicep modules with a `nodeCount` parameter so the cluster could scale from 2 to 16 nodes without code changes. CI/CD pipeline in Azure DevOps ran `az deployment group what-if` on every PR.
5. **GPU memory planning** — Calculated memory requirements using the formula from Ch4: `Model params (13B) × 4 bytes (FP32) = 52 GB base`. With mixed-precision training (BF16) and ZeRO Stage 3 optimizer sharding, actual per-GPU usage dropped to 38 GB — within the 80 GB A100 envelope.
6. **Monitoring from day one** — Deployed DCGM Exporter as a DaemonSet equivalent on each VM, feeding Prometheus. Built Grafana dashboards showing per-GPU SM activity, memory utilization, and NVLink throughput. Set alerts for GPU memory > 95% and SM occupancy < 20% (indicating a stalled rank).

### Quantified Results

| Metric | Result |
|--------|--------|
| Training time (13B model, 500K samples) | 68 hours (under 72-hour deadline) |
| GPU utilization (average across 64 GPUs) | 87% SM occupancy |
| Checkpoint I/O time | 11 seconds per checkpoint (every 2 hours) |
| Total infrastructure cost | $73,400 (under $85K budget) |
| Time from zero to first training run | 16 days |

### Lessons Learned

- **Quota lead time is your critical path** — start GPU quota requests before any other work. *(Ch3)*
- **InfiniBand is non-negotiable for multi-node training** — standard Ethernet added 3× communication overhead in their benchmarks. *(Ch4)*
- **GPU memory math eliminates guesswork** — the per-layer memory formula prevented two OOM incidents during hyperparameter sweeps. *(Ch4)*
- **IaC pays for itself on the first resize** — when the data science team requested a 12-node run, the infra team delivered in 20 minutes by changing one parameter. *(Ch5)*

---

## Case Study 2 — Infrastructure as Code for Multi-Environment ML Pipelines

**📖 Chapters Referenced:** Ch5 (IaC), Ch6 (MLOps), Ch8 (Security)

### Scenario

A healthcare analytics company ran their ML training pipelines using manually provisioned Azure ML workspaces. Each data scientist had their own workspace with inconsistent configurations — different compute SKUs, no network isolation, and secrets stored in plaintext config files. When an audit revealed PHI (Protected Health Information) was being processed in a workspace without Private Link, the CISO mandated a full infrastructure rebuild with compliance controls.

The platform engineering team had 6 weeks to deliver a repeatable, auditable infrastructure stack that supported three environments (dev, staging, prod) with identical security controls. They also needed to integrate the infrastructure lifecycle with the data science team's model training pipelines so that environment provisioning and model deployment were part of the same CI/CD flow.

### Azure Services and Configuration

| Component | Service | Configuration |
|-----------|---------|---------------|
| IaC | Terraform (AzureRM provider 3.x) | Modules for workspace, compute, networking, RBAC |
| ML Platform | Azure Machine Learning | Private Link-enabled workspace, managed VNet |
| Networking | VNet + Private Endpoints + NSGs | Hub-spoke topology, no public endpoints |
| Secrets | Azure Key Vault | Managed Identity access, no API key usage |
| CI/CD | GitHub Actions | `terraform plan` on PR, `terraform apply` on merge to main |
| Policy | Azure Policy | Deny public endpoints, require encryption, enforce tagging |

### What the Infra Team Did

1. **Module architecture** — Created four Terraform modules: `network` (VNet, subnets, NSGs, Private DNS zones), `workspace` (Azure ML workspace, linked Key Vault, Storage, ACR), `compute` (training clusters with auto-scale), and `rbac` (role assignments per environment). Each module was versioned independently in a Terraform registry.
2. **Environment parity** — Used `tfvars` files per environment with identical module references. The only differences were compute SKU sizes (dev: `Standard_DS3_v2`, prod: `Standard_NC6s_v3`) and node counts.
3. **Security hardening** — Deployed Azure Policy assignments that denied creation of any Azure ML workspace without Private Link. Added Key Vault access policies using Managed Identity only — no service principal secrets. Enabled diagnostic settings on every resource, forwarding to a central Log Analytics workspace.
4. **MLOps integration** — The model training pipeline (defined in Azure ML YAML) referenced compute targets by name. Since Terraform created compute targets with deterministic names (`train-cpu-dev`, `train-gpu-prod`), the data science team's pipeline YAML worked across environments without modification.
5. **Drift detection** — Configured a nightly GitHub Actions workflow that ran `terraform plan` against each environment and opened an issue if drift was detected. In the first month, it caught 3 manual changes made through the portal.

### Quantified Results

| Metric | Result |
|--------|--------|
| Environment provisioning time | 22 minutes (was 2-3 days manual) |
| Security audit findings | 0 critical (was 14) |
| Configuration drift incidents (monthly) | 3 detected and remediated automatically |
| Developer onboarding time (new data scientist) | 4 hours (was 2 days) |
| Terraform modules reused across teams | 3 teams adopted the same modules within 2 months |

### Lessons Learned

- **IaC is a security control, not just automation** — the audit passed because infrastructure was code-reviewed, not because of a checklist. *(Ch5)*
- **MLOps and IaC must share a naming contract** — when compute target names are deterministic, pipeline YAML becomes environment-agnostic. *(Ch6)*
- **Private Link adds 15-20 minutes to provisioning** — plan for it in CI/CD timeouts and communicate the trade-off to stakeholders. *(Ch8)*

💡 **Pro Tip**: Run `terraform plan` in your PR pipeline and post the output as a PR comment. Reviewers catch misconfigurations before they reach any environment.

---

## Case Study 3 — Observability Platform for GPU-Accelerated Inference

**📖 Chapters Referenced:** Ch7 (Monitoring), Ch4 (GPU Deep Dive), Ch12 (Troubleshooting)

### Scenario

A media company ran a real-time content moderation system powered by a vision transformer model deployed on AKS with GPU node pools. The system processed 15,000 images per minute during peak hours. The operations team had basic Kubernetes monitoring (CPU, memory, pod restarts) but no GPU-specific telemetry. When latency spikes occurred during traffic surges, they had no way to distinguish between GPU saturation, model inefficiency, and storage I/O bottlenecks.

After a 45-minute outage where P95 latency exceeded 8 seconds (SLA was 500 ms), the VP of Engineering mandated a full observability overhaul. The infrastructure team needed to build a monitoring stack that could pinpoint the root cause of latency degradation within 2 minutes — fast enough for the on-call engineer to act before users noticed.

### Azure Services and Configuration

| Component | Service | Configuration |
|-----------|---------|---------------|
| Compute | AKS with `Standard_NC16as_T4_v3` node pool | 6 nodes, cluster autoscaler (min 4, max 12) |
| GPU metrics | DCGM Exporter (DaemonSet) | Exported: `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`, `DCGM_FI_DEV_SM_CLOCK` |
| Metrics pipeline | Prometheus (Azure Managed) + Grafana | 15-second scrape interval, 30-day retention |
| Application telemetry | Application Insights (SDK instrumented) | Custom metrics: `inference_latency_ms`, `batch_size`, `model_version` |
| Alerting | Azure Monitor Action Groups | PagerDuty integration for P1, Teams webhook for P2/P3 |
| Log aggregation | Container Insights + Log Analytics | KQL queries for pod-level correlation |

### What the Infra Team Did

1. **GPU telemetry pipeline** — Deployed DCGM Exporter as a DaemonSet with tolerations for the GPU node pool taint. Configured Prometheus to scrape GPU metrics at 15-second intervals. Built Grafana dashboards with four panels: GPU utilization (%), GPU memory usage (MB), SM clock frequency (MHz), and PCIe throughput (GB/s).
2. **Application-level instrumentation** — Worked with the ML engineering team to add custom Application Insights metrics to the inference service. Every request logged: `inference_latency_ms`, `preprocessing_time_ms`, `postprocessing_time_ms`, `batch_size`, and `model_version`. This separated model computation time from I/O overhead.
3. **Correlation dashboards** — Built a Grafana dashboard that overlaid GPU utilization, P95 inference latency, and pod count on the same time axis. This immediately revealed a pattern: latency spikes correlated with GPU memory > 90%, not GPU compute utilization. The bottleneck was memory pressure from large batch sizes, not insufficient GPU cores.
4. **Alert hierarchy** — Defined three alert tiers:
   - **P1** (PagerDuty, immediate): P95 latency > 2 seconds for 3 consecutive minutes
   - **P2** (Teams, 15-min response): GPU memory > 85% sustained for 10 minutes
   - **P3** (Daily digest): GPU utilization < 30% for 1 hour (waste detection)
5. **Runbook automation** — Created an Azure Automation runbook triggered by P2 alerts that automatically reduced the inference batch size from 32 to 16, buying the team time to investigate without user impact.

### Quantified Results

| Metric | Before | After |
|--------|--------|-------|
| Mean time to detect (MTTD) | 12 minutes | 90 seconds |
| Mean time to resolve (MTTR) | 45 minutes | 8 minutes |
| P95 latency (peak hours) | 1,200 ms (with spikes to 8s) | 380 ms (stable) |
| False positive alerts (monthly) | 47 | 6 |
| GPU waste identified (monthly savings) | — | $2,800 from right-sizing batch sizes |

### Lessons Learned

- **GPU utilization alone is misleading** — high utilization looks healthy, but if GPU memory is saturated, latency still degrades. Always monitor both. *(Ch4, Ch7)*
- **Application-level metrics are non-negotiable** — without `inference_latency_ms` broken down by phase, the team would have blamed the GPU when the real bottleneck was image preprocessing on CPU. *(Ch7)*
- **Structured alert tiers prevent alert fatigue** — the old system had 47 false positives per month. The new tiered approach reduced noise by 87%. *(Ch7, Ch12)*

⚠️ **Production Gotcha**: DCGM Exporter's default metric set is enormous. Export only the 8-10 metrics you actually dashboard — otherwise Prometheus storage costs will surprise you.

---

## Case Study 4 — Cost Engineering for a Mixed GPU/CPU Inference Fleet

**📖 Chapters Referenced:** Ch9 (Cost Engineering), Ch3 (Compute), Ch11 (Azure OpenAI)

### Scenario

A B2B SaaS company operated three AI-powered features: document summarization (Azure OpenAI GPT-4o), image classification (custom vision model on GPU VMs), and anomaly detection (classical ML on CPU). Their monthly Azure AI spend had grown from $18K to $67K in 6 months with no corresponding increase in customer usage. The CFO demanded a 35% cost reduction without degrading service quality.

The infrastructure team discovered several cost drivers: GPU VMs running 24/7 for a workload that peaked only 10 hours per day, Azure OpenAI standard deployments with 40% of requests hitting 429 throttling (triggering expensive retries), and no chargeback visibility — three product teams consumed GPU resources but costs were allocated to a single "AI Infrastructure" budget line.

### What the Infra Team Did

1. **Usage analysis** — Exported 90 days of Azure Cost Management data and correlated it with Prometheus GPU utilization metrics. Found that GPU VMs averaged 22% utilization during off-peak hours (10 PM – 8 AM) and 78% during business hours.
2. **GPU scheduling** — Implemented Azure Automation runbooks to deallocate the image classification VMs from 10 PM to 7 AM daily. Added a 30-minute warm-up buffer with health checks before the first request was routed. Saved 37% on GPU compute.
3. **Azure OpenAI migration to PTU** — Analyzed token consumption patterns: the document summarization feature consumed a steady 180K TPM during business hours. Migrated from standard (pay-per-token) to 300 PTU, which provided 200K+ TPM at a fixed hourly rate. This eliminated 429 errors and reduced cost per token by 42%.
4. **Spot VMs for batch workloads** — Moved the nightly model retraining job (anomaly detection) to `Standard_NC4as_T4_v3` Spot VMs with a max price of 60% of on-demand. Implemented checkpointing every 30 minutes so evictions only lost 30 minutes of work. Spot eviction rate averaged 3% over 90 days.
5. **Chargeback tagging** — Implemented mandatory resource tags (`CostCenter`, `Product`, `WorkloadType`) enforced by Azure Policy. Built a Power BI dashboard showing cost per product team per AI feature. Within one month, the image classification team voluntarily reduced their batch size after seeing their per-request cost.
6. **Reserved Instances** — Purchased 1-year reservations for the 4 GPU VMs that ran during business hours, saving an additional 21% versus pay-as-you-go.

### Quantified Results

| Cost Lever | Monthly Savings | Percentage |
|------------|----------------|------------|
| GPU VM scheduling (off-hours deallocation) | $8,900 | 37% of GPU compute |
| Azure OpenAI PTU migration | $6,200 | 42% per-token cost reduction |
| Spot VMs for batch training | $1,800 | 58% vs. on-demand |
| Reserved Instances (1-year) | $4,100 | 21% of reserved VM costs |
| **Total monthly savings** | **$21,000** | **31% of total AI spend** |

*Post-optimization monthly spend: $46,000 (down from $67,000).*

### Lessons Learned

- **GPU utilization data is the foundation of cost engineering** — without Prometheus metrics, the team would have guessed at scheduling windows. *(Ch9)*
- **PTU is almost always cheaper for sustained workloads** — the break-even point was roughly 120K TPM sustained for 8+ hours/day. *(Ch11)*
- **Chargeback changes behavior** — teams optimize when they see their own costs. Tag enforcement is a cost control. *(Ch9)*

💡 **Pro Tip**: Before committing to PTU, run a 2-week analysis of your standard deployment's actual TPM consumption. Azure OpenAI's metrics in Azure Monitor give you the exact numbers to calculate break-even.

---

## Case Study 5 — Multi-Team Platform Operations for AI Workloads

**📖 Chapters Referenced:** Ch10 (Platform Ops), Ch5 (IaC), Ch8 (Security)

### Scenario

A technology company with 200+ engineers had four product teams running AI workloads on Azure — each with their own AKS clusters, storage accounts, and networking configurations. The result was infrastructure sprawl: 14 AKS clusters, 23 storage accounts, inconsistent security policies, and no shared GPU capacity. When one team needed A100 GPUs for a training sprint, they waited 3 weeks for quota approval while another team's A100 nodes sat idle at 12% utilization.

The CTO tasked the platform engineering team with building a shared AI platform that provided self-service capabilities while maintaining security guardrails, cost visibility, and efficient GPU utilization across all teams.

### Azure Services and Configuration

| Component | Service | Configuration |
|-----------|---------|---------------|
| Compute platform | AKS (3 clusters: dev, staging, prod) | Shared GPU node pools with namespace isolation |
| Multi-tenancy | Kubernetes namespaces + NetworkPolicy | Per-team namespaces, resource quotas, limit ranges |
| GPU sharing | NVIDIA MPS + time-slicing | 2× time-slicing on T4 nodes for dev, dedicated for prod |
| IaC | Terraform + Atlantis | PR-based workflow, mandatory plan review |
| Self-service | Backstage developer portal | Templates for "new ML project" provisioning |
| Cost allocation | Kubecost + Azure Cost Management | Per-namespace cost attribution with daily reports |
| Security | Azure Policy + OPA Gatekeeper | Enforce private registries, block privileged containers |

### What the Infra Team Did

1. **Cluster consolidation** — Reduced 14 AKS clusters to 3 (dev, staging, prod). Each cluster used namespace-level isolation with Kubernetes ResourceQuotas capping per-team GPU requests (`requests.nvidia.com/gpu`). NetworkPolicies enforced namespace-to-namespace isolation — teams could not access each other's inference endpoints.
2. **GPU sharing strategy** — Implemented NVIDIA GPU time-slicing on T4 dev nodes, allowing 2 workloads to share a single GPU. Production workloads on A100 nodes got dedicated GPU access — no time-slicing. This increased dev GPU utilization from 12% to 64% without purchasing additional hardware.
3. **Self-service provisioning** — Built Backstage templates that let data scientists provision a new ML project namespace with: a GPU resource quota, a dedicated Azure Container Registry scope, Key Vault access for secrets, and a pre-configured Prometheus ServiceMonitor. Provisioning time dropped from a 3-week ticket to 15 minutes.
4. **GitOps workflow** — All infrastructure changes went through Terraform PRs reviewed by the platform team via Atlantis. No `kubectl apply` was allowed in production — ArgoCD synced manifests from Git. This created a full audit trail of every infrastructure change.
5. **Cost attribution** — Deployed Kubecost with Azure Cost Management integration. Each namespace's compute, storage, and network costs were attributed to the owning team's cost center. Monthly reports were auto-generated and sent to team leads. GPU idle time was flagged separately, showing cost of reserved-but-unused GPU hours.
6. **Guardrails via policy** — OPA Gatekeeper policies enforced: no `latest` image tags, mandatory resource limits on all pods, GPU requests must include matching limits (preventing overallocation), and all images must come from the internal ACR. Azure Policy enforced network-level controls — no public load balancers, mandatory Private Link for storage access.

### Quantified Results

| Metric | Before | After |
|--------|--------|-------|
| AKS clusters | 14 | 3 |
| GPU utilization (dev) | 12% | 64% |
| GPU utilization (prod) | 41% | 78% |
| New project provisioning time | 3 weeks | 15 minutes |
| Monthly GPU compute spend | $89,000 | $52,000 (42% reduction) |
| Security policy violations (monthly) | Unknown | 0 (enforced by Gatekeeper) |
| Infrastructure team headcount for AI ops | 6 FTEs across 4 teams | 2 FTEs on platform team |

### Lessons Learned

- **Shared platforms are a cost multiplier** — consolidating 14 clusters to 3 saved more than the GPU scheduling optimization did. *(Ch10)*
- **GPU time-slicing is safe for dev, dangerous for prod** — in production, a noisy neighbor on a shared GPU caused a 3× latency spike during their first week. They reverted to dedicated GPUs for prod immediately. *(Ch10, Ch4)*
- **Self-service without guardrails is chaos; guardrails without self-service are bottlenecks** — the Backstage + Gatekeeper combination gave teams speed with safety. *(Ch10, Ch8)*
- **Cost visibility drives organic optimization** — two teams voluntarily reduced their GPU quotas after seeing Kubecost reports, freeing capacity for the team that actually needed it. *(Ch9)*

⚠️ **Production Gotcha**: Kubernetes ResourceQuotas cap the number of GPUs a namespace can *request*, but they don't prevent a single pod from consuming all GPU memory. Always pair ResourceQuotas with container-level `resources.limits` enforcement via OPA Gatekeeper.

---

> "The best AI infrastructure isn't the one with the most GPUs — it's the one where every GPU-hour produces business value."