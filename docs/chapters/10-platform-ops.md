# Chapter 10 — AI Platform Operations at Scale

*You built an AI environment. Now you need to run an AI platform.*

---

## The Slack Channel That Ate Your Calendar

Six months ago, you provisioned a single GPU VM for the ML team. You set up the drivers, mounted the storage, and moved on. It felt like any other infrastructure request — a ticket in, a resource out, close the loop.

Today, you have four teams, three AKS clusters, dozens of GPU node pools, and a growing collection of Azure OpenAI endpoints. Each team wants their own resources, their own quotas, and their own SLAs. Your Slack DMs have become a help desk. "Can you give us more GPUs?" "Why is my training job stuck in Pending?" "Who's using all the A100s?" You're spending more time answering questions than actually engineering anything.

This is the inflection point every infrastructure organization hits. You've gone from supporting AI projects to being the bottleneck for an AI platform. The solution isn't working harder — it's building the systems, policies, and automation that let teams serve themselves while you maintain control. This chapter shows you how.

---

## From AI Project to AI Platform

### The Platform Engineering Mindset

Platform engineering isn't new. You've been doing it for years with web apps, databases, and CI/CD pipelines. The core idea is simple: build reusable, self-service infrastructure that product teams consume without filing tickets. An internal developer platform (IDP) provides golden paths — opinionated, well-tested workflows that teams follow to get from code to production.

AI infrastructure follows the same principle. Instead of provisioning GPU VMs ad hoc, you build templates. Instead of manually creating Kubernetes namespaces, you offer a self-service portal. Instead of answering "how do I deploy a model?", you provide a pipeline that does it.

🔄 **Infra ↔ AI Translation:** Platform engineering is the same discipline you already know — now applied to GPU compute, model registries, and inference endpoints instead of web apps and SQL databases. The abstraction layers change; the thinking doesn't.

### What to Automate vs. What to Manage

Not everything should be self-service. The decision depends on blast radius and cost.

| Category | Self-Service | Managed (Requires Approval) |
|---|---|---|
| Dev/test namespaces | ✅ | |
| Small GPU allocations (1–2 GPUs) | ✅ | |
| Production inference endpoints | | ✅ |
| Large training jobs (8+ GPUs) | | ✅ |
| New cluster provisioning | | ✅ |
| Jupyter notebook environments | ✅ | |
| Azure OpenAI endpoint creation | | ✅ |
| Storage volumes for datasets | ✅ | |

The rule of thumb: if a mistake costs less than a few hundred dollars and can be reversed in minutes, make it self-service. If it involves expensive resources, production traffic, or cross-team impact, put a gate on it.

---

## Multi-Tenancy for AI Infrastructure

### Isolation Patterns

Multi-tenancy in AI infrastructure is about balancing isolation against efficiency. Too little isolation and one team's runaway training job starves everyone. Too much isolation and you're managing dozens of clusters with terrible GPU utilization.

There are four levels of isolation, each with different tradeoffs:

### 📊 Decision Matrix: Team Isolation Levels

| Isolation Level | Cost Efficiency | Security Boundary | Operational Overhead | Best For |
|---|---|---|---|---|
| **Namespace** | ⭐⭐⭐⭐⭐ | Low | Low | Trusted teams sharing a cluster |
| **Node pool** | ⭐⭐⭐⭐ | Medium | Medium | Teams needing dedicated GPU types |
| **Cluster** | ⭐⭐⭐ | High | High | Teams with different compliance needs |
| **Subscription** | ⭐⭐ | Very High | Very High | Regulated workloads, separate billing |

Most organizations land on a hybrid: one or two shared clusters with per-team namespaces and dedicated GPU node pools, plus separate clusters for production inference and regulated workloads.

### RBAC Scoping for Multi-Team GPU Access

In AKS, RBAC should scope each team to their own namespace. Use Microsoft Entra ID groups mapped to Kubernetes ClusterRoles for consistent access control.

```yaml
# team-data-science-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: team-data-science
  name: gpu-workload-role
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "persistentvolumeclaims"]
    verbs: ["get", "list", "create", "delete", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "create", "update", "delete"]
```

Bind this role to the team's Microsoft Entra ID group. They can deploy workloads in their namespace but can't touch other teams' resources or cluster-level objects.

### Resource Quota Enforcement

Without quotas, one team will inevitably consume all available GPUs. Kubernetes ResourceQuotas enforce hard limits per namespace.

```yaml
# team-data-science-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  namespace: team-data-science
  name: gpu-quota
spec:
  hard:
    requests.cpu: "64"
    requests.memory: 256Gi
    requests.nvidia.com/gpu: "8"
    limits.cpu: "128"
    limits.memory: 512Gi
    limits.nvidia.com/gpu: "8"
    pods: "50"
```

This caps the data science team at 8 GPUs, 64 CPU cores, and 256 GiB of memory. They can distribute that budget across any number of pods — one job with 8 GPUs or eight jobs with 1 GPU each — but they can't exceed the total.

⚠️ **Production Gotcha:** ResourceQuotas only enforce at scheduling time. If you lower a quota below current usage, existing pods won't be evicted — but new pods will be rejected. Plan quota changes during maintenance windows when teams can reschedule their workloads.

### Network Isolation

Network policies prevent lateral traffic between team namespaces. This is especially important when teams handle different data classifications.

```yaml
# deny-cross-namespace.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  namespace: team-data-science
  name: deny-other-namespaces
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
```

This policy allows pods within the `team-data-science` namespace to communicate with each other but blocks all inbound traffic from other namespaces. You'll need to add explicit rules for shared services like model registries or monitoring endpoints.

---

## GPU Scheduling and Queue Management

### The Fundamental Problem

GPU resources are finite and expensive. A single A100 node costs roughly $3 per hour on Azure. When you have 20 nodes and 4 teams, simple Kubernetes scheduling — first-come, first-served — creates constant friction. Training jobs hog GPUs for hours. Inference workloads get starved. Data scientists submit 10 jobs at once and wonder why only 2 are running.

You need scheduling that understands priorities, fairness, and the unique characteristics of AI workloads.

### Kubernetes Native Scheduling

Start with the basics. Every GPU workload must specify resource requests and limits. Without them, Kubernetes can't make intelligent scheduling decisions.

```yaml
# training-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: bert-fine-tuning
  namespace: team-nlp
spec:
  template:
    spec:
      containers:
        - name: trainer
          image: myregistry.azurecr.io/bert-trainer:v2.1
          resources:
            requests:
              cpu: "8"
              memory: 32Gi
              nvidia.com/gpu: "4"
            limits:
              cpu: "16"
              memory: 64Gi
              nvidia.com/gpu: "4"
      restartPolicy: Never
      tolerations:
        - key: "sku"
          operator: "Equal"
          value: "gpu"
          effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia-a100
```

💡 **Pro Tip:** Always set GPU requests equal to GPU limits. Unlike CPU and memory, GPUs can't be overcommitted. A pod requesting 1 GPU will exclusively own that GPU regardless of its limit value, so mismatched values only create confusion.

### Priority Classes

Priority classes tell the scheduler which workloads matter most. Define a clear hierarchy that reflects your business needs.

```yaml
# priority-classes.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-inference
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Production model-serving workloads — never preempted by training."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: scheduled-training
value: 100000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Scheduled training jobs with deadlines."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: exploratory
value: 1000
globalDefault: true
preemptionPolicy: Never
description: "Interactive notebooks, experiments — can be preempted."
```

With this hierarchy, a production inference pod will preempt a training job if GPUs are scarce, and training jobs will preempt exploratory notebooks. But exploratory workloads will never preempt anything — they wait.

💡 **Pro Tip:** Use `preemptionPolicy: Never` for exploratory workloads. This prevents a stampede where 50 notebook pods all try to preempt each other in a tight GPU environment.

### Kueue: Fair Scheduling for Batch AI Workloads

Kubernetes doesn't natively understand job queuing. If you submit 100 training jobs and you have capacity for 10, Kubernetes will create 100 pending pods. Kueue solves this by adding a queuing layer that admits jobs based on available capacity and fair-share policies.

```yaml
# cluster-queue.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: gpu-cluster-queue
spec:
  namespaceSelector: {}
  resourceGroups:
    - coveredResources: ["cpu", "memory", "nvidia.com/gpu"]
      flavors:
        - name: a100-spot
          resources:
            - name: "cpu"
              nominalQuota: 128
            - name: "memory"
              nominalQuota: 512Gi
            - name: "nvidia.com/gpu"
              nominalQuota: 16
        - name: a100-ondemand
          resources:
            - name: "cpu"
              nominalQuota: 64
            - name: "memory"
              nominalQuota: 256Gi
            - name: "nvidia.com/gpu"
              nominalQuota: 8
  preemption:
    withinClusterQueue: LowerPriority
---
# local-queue.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  namespace: team-nlp
  name: team-nlp-queue
spec:
  clusterQueue: gpu-cluster-queue
```

Kueue holds jobs in a queue until resources are available, then admits them in priority order. Teams submit jobs to their LocalQueue; the ClusterQueue enforces global capacity. This eliminates the "100 pending pods" problem — jobs stay queued, not scheduled, until there's room.

### Volcano: Gang Scheduling for Distributed Training

Distributed training jobs need multiple GPUs across multiple nodes to start simultaneously. Standard Kubernetes scheduling doesn't guarantee this — it might schedule 3 of 4 required pods, leaving all three sitting idle while waiting for the fourth.

Volcano provides gang scheduling: all pods in a job start together, or none of them start. This prevents deadlocks and wasted resources.

```yaml
# distributed-training-volcano.yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: distributed-llm-training
  namespace: team-nlp
spec:
  minAvailable: 4
  schedulerName: volcano
  plugins:
    svc: ["--publish-not-ready-addresses"]
  tasks:
    - replicas: 4
      name: worker
      template:
        spec:
          containers:
            - name: trainer
              image: myregistry.azurecr.io/llm-trainer:v1.0
              resources:
                requests:
                  nvidia.com/gpu: "4"
                limits:
                  nvidia.com/gpu: "4"
              env:
                - name: WORLD_SIZE
                  value: "4"
          restartPolicy: OnFailure
```

The `minAvailable: 4` field tells Volcano: don't schedule any workers unless you can schedule all four. This prevents partial allocation — the most common source of wasted GPU hours in distributed training.

---

## Quota and Capacity Management

### The Quota Stack

GPU capacity is managed at multiple layers. Miss any layer and you'll hit a wall.

| Layer | Mechanism | Who Manages It |
|---|---|---|
| **Azure subscription** | Regional vCPU quotas | Cloud admin (portal or support request) |
| **AKS cluster** | Node pool scaling limits | Platform team |
| **Kubernetes namespace** | ResourceQuota objects | Platform team |
| **Kueue** | ClusterQueue nominal quotas | Platform team |
| **Team-level** | LocalQueue admission | Self-service within limits |

### Capacity Reservation

For production inference workloads that can't tolerate scheduling delays, use Azure Capacity Reservations. This guarantees that specific VM sizes are available in your region when you need them.

```bash
# Reserve 4x Standard_NC24ads_A100_v4 in East US
az capacity reservation group create \
  --resource-group rg-ai-platform \
  --name crg-inference-prod \
  --location eastus

az capacity reservation create \
  --resource-group rg-ai-platform \
  --capacity-reservation-group crg-inference-prod \
  --name cr-a100-inference \
  --sku Standard_NC24ads_A100_v4 \
  --capacity 4
```

You pay for reserved capacity whether you use it or not — but you're guaranteed the VMs are there. For production inference serving real-time traffic, this tradeoff is almost always worth it.

### Request-and-Approval Workflows

For GPU allocations above the self-service threshold, build a lightweight approval workflow. This doesn't need to be complex — a GitHub issue template or a Teams form that triggers an Azure Logic App works well.

The workflow should capture: which team is requesting, how many GPUs, for how long, what workload type (training vs. inference), and a business justification. Route approvals to the platform team lead for standard requests and to engineering leadership for large allocations. Auto-approve requests that fall within pre-approved budgets and escalate everything else.

The goal isn't bureaucracy — it's visibility. You want to know about large GPU allocations before they happen, not after your quota is exhausted.

### Monitoring Quota Usage

Build a dashboard that shows quota consumption across every layer. The Azure CLI gives you subscription-level visibility:

```bash
# Check GPU quota usage in East US
az vm list-usage --location eastus \
  --query "[?contains(name.value, 'NC') || contains(name.value, 'ND')].{Name:name.localizedValue, Current:currentValue, Limit:limit}" \
  --output table
```

Set alerts when any quota crosses 80% utilization. At 80%, you still have time to request an increase. At 95%, you're one training job away from a hard stop.

💡 **Pro Tip:** Azure quota increases can take days for GPU SKUs in popular regions. File your increase request well before you need it — ideally when you hit 60% utilization, not 90%.

---

## SLA/SLO Design for Inference Endpoints

### Defining What "Good" Looks Like

Every inference endpoint needs clear service-level objectives. Without them, every latency spike is a fire drill and every team's workload is equally "critical."

### 📊 Decision Matrix: SLO Tiers for AI Services

| Tier | Latency (P99) | Availability | Throughput | Example Use Cases |
|---|---|---|---|---|
| **Real-time** | < 200ms | 99.95% | > 1000 req/s | Customer-facing chat, search ranking |
| **Near-real-time** | < 2s | 99.9% | > 100 req/s | Content moderation, recommendations |
| **Batch** | < 1 hour | 99.5% | N/A (job-based) | Document processing, embedding generation |

Define these tiers early and assign every workload to one. This drives architecture decisions — real-time endpoints need autoscaling and capacity reservations; batch workloads can use spot instances and preemptible scheduling.

### Error Budgets for AI Services

Error budgets quantify how much unreliability you can tolerate. A 99.9% availability SLO gives you 43 minutes of downtime per month. Spend that budget wisely.

Track error budget consumption in real time. When the budget is burning fast — say you've consumed 50% in the first week — freeze changes and focus on reliability. When the budget is healthy, you have room for deployments and experiments.

### Health Probes for Model Serving

Model containers fail in ways that traditional health checks miss. A container can be running but the model hasn't loaded yet, or the GPU is in a bad state, or inference is returning garbage. Design health probes that verify actual model functionality.

```yaml
# inference-deployment.yaml (partial)
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
  failureThreshold: 2
startupProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30
```

⚠️ **Production Gotcha:** Large models can take 5–10 minutes to load into GPU memory. Set `startupProbe.failureThreshold` high enough to cover your largest model's load time, or Kubernetes will kill the container in a restart loop before the model is ready.

### Graceful Degradation

When your primary model is overloaded or down, don't return errors — degrade gracefully. Common patterns:

- **Fallback models:** Route to a smaller, faster model when the primary model's latency exceeds SLO thresholds.
- **Cached responses:** Return cached results for common queries while the model recovers.
- **Queue-based buffering:** Accept requests into a queue and process them when capacity returns, returning a "processing" status to the client.
- **Circuit breakers:** Stop sending traffic to a failing endpoint after a threshold of errors, giving it time to recover.

---

## Fleet Management

### The Multi-Cluster Reality

At scale, you won't have one cluster — you'll have several. Production inference in East US and West Europe. Training clusters with spot node pools. A dev/test cluster with cheaper GPU SKUs. Managing these consistently is the difference between a platform and a collection of snowflakes.

A typical fleet layout for a mid-size AI organization looks like this:

| Cluster | Region | Purpose | GPU SKUs | Node Scaling |
|---|---|---|---|---|
| prod-inference-eastus | East US | Real-time serving | A100, A10G | Capacity reserved |
| prod-inference-westeu | West Europe | Real-time serving (DR) | A100, A10G | Capacity reserved |
| training-eastus | East US | Training, fine-tuning | A100, H100 | Spot + on-demand |
| dev-eastus | East US | Dev/test, notebooks | T4, A10G | Spot only |

Each cluster has a distinct purpose, and that purpose drives its configuration — spot tolerance, GPU SKU selection, scaling behavior, and upgrade cadence. Don't try to make one cluster do everything. The operational overhead of managing four focused clusters is lower than managing one cluster that tries to serve every workload pattern.

### GitOps for GPU Infrastructure

Use Flux or ArgoCD to manage cluster configuration declaratively. Every cluster pulls its configuration from a Git repository. Changes go through pull requests, get reviewed, and roll out automatically.

```text
fleet-config/
├── base/
│   ├── namespaces/
│   ├── rbac/
│   ├── resource-quotas/
│   ├── network-policies/
│   ├── priority-classes/
│   └── kueue/
├── clusters/
│   ├── prod-eastus/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   ├── prod-westeurope/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   └── dev-eastus/
│       ├── kustomization.yaml
│       └── patches/
```

The `base/` directory contains shared configuration — namespaces, RBAC, quotas, priority classes. Each cluster directory layers on environment-specific patches. Add a new team? Create the namespace and quota in `base/`, and every cluster picks it up on the next sync.

### Rolling Upgrades Across the Fleet

Beyond GPU drivers, you'll need to coordinate CUDA toolkit versions, container runtime updates, and Kubernetes version upgrades across your fleet. Version mismatches between clusters are a constant source of "it works in dev but not in prod" bugs.

Maintain a fleet compatibility matrix that tracks the exact versions of every component across every cluster. Update it with every change. When a data scientist reports that their training job fails on the production cluster but works on dev, the first thing you check is this matrix.

```text
Fleet Compatibility Matrix (2024-Q4)
─────────────────────────────────────────────────────────────
Component          prod-eastus    prod-westeu    training    dev
─────────────────────────────────────────────────────────────
Kubernetes         1.29.4         1.29.4         1.29.4      1.30.1
GPU Driver         550.54.15      550.54.15      550.54.15   550.90.07
CUDA Toolkit       12.4           12.4           12.4        12.6
cuDNN              9.1.0          9.1.0          9.1.0       9.3.0
Container Runtime  containerd 1.7 containerd 1.7 containerd 1.7 containerd 1.7
─────────────────────────────────────────────────────────────
```

💡 **Pro Tip:** Keep production clusters on identical versions. Let the dev cluster run one version ahead as your early-warning system. When a new CUDA version breaks a popular training framework, you want to discover that in dev — not in the middle of a two-week production training run.

### GPU Driver Upgrades

GPU driver upgrades are the most dangerous operation in your fleet. A bad driver can cause silent data corruption in model training, kernel panics, or total GPU failure. Treat driver upgrades with the same care as a kernel upgrade.

⚠️ **Production Gotcha:** Never upgrade GPU drivers on all clusters simultaneously. Use a canary deployment strategy: upgrade the dev cluster first, run validation workloads for 48 hours, then move to one production cluster. Wait another 48 hours before rolling to the rest of the fleet. Silent GPU errors can take days to surface in training loss curves.

Build standardized VM images with pre-baked GPU drivers using Azure Image Builder or Packer. This ensures every node in every cluster runs identical driver versions. Never rely on driver installation at boot time — it's slow, fragile, and adds unpredictable startup latency to your node pools.

---

## Observability at Scale

### Centralized Monitoring

When you have multiple clusters, you need a single pane of glass. Azure Monitor with Container Insights can aggregate metrics across clusters, but for GPU-specific observability, DCGM Exporter feeding into a centralized Prometheus instance (or Azure Monitor Managed Prometheus) gives you the granularity you need.

Key metrics to centralize:

| Metric | Source | Alert Threshold |
|---|---|---|
| GPU utilization | DCGM Exporter | < 20% for 1h (waste) |
| GPU memory used | DCGM Exporter | > 95% (OOM risk) |
| GPU temperature | DCGM Exporter | > 83°C |
| Inference latency P99 | Application metrics | > SLO threshold |
| Queue depth | Kueue metrics | > 50 pending jobs |
| Node pool utilization | AKS metrics | > 85% |
| Quota consumption | Azure Monitor | > 80% |

### Cross-Cluster Dashboards

Build Grafana dashboards that show fleet-wide health at a glance. The top-level dashboard should answer three questions in under 10 seconds:

1. **Is anything broken?** Red/green status for every inference endpoint across all clusters.
2. **Is anything wasted?** GPU utilization heat map showing underused capacity.
3. **Is anything at risk?** Quota consumption and capacity trends that predict when you'll run out.

Drill-down dashboards should let you go from "GPU utilization is low on cluster prod-eastus" to "team-nlp's namespace has 4 idle GPUs allocated to a completed job that was never cleaned up."

### Cost Attribution

When four teams share a GPU cluster, someone will ask "how much is each team spending?" Build cost attribution from day one — it's much harder to retrofit.

Tag every resource with team ownership. Use Kubernetes labels consistently:

```yaml
metadata:
  labels:
    team: data-science
    project: recommendation-engine
    cost-center: cc-4521
    environment: production
```

Feed these labels into your cost monitoring tool — whether that's Azure Cost Management, Kubecost, or OpenCost. Report costs by team and project monthly. Teams that see their GPU spend are teams that clean up idle resources.

### Capacity Planning

Collect historical utilization data and use it to forecast demand. Simple linear regression on weekly GPU utilization trends will tell you when you'll exhaust current capacity. Factor in known upcoming projects — if the NLP team is starting a large language model training run next quarter, account for that spike now.

Plan GPU capacity 8–12 weeks ahead. This accounts for Azure quota increase lead times, procurement cycles for reserved instances, and the time needed to provision and configure new node pools.

---

## Self-Service Patterns

### Team Onboarding

New team onboarding should be a pull request, not a ticket. Build Terraform modules or Backstage templates that create everything a team needs in one shot.

A team onboarding module should provision:

- Kubernetes namespace with resource quotas
- RBAC bindings for the team's Microsoft Entra ID group
- Network policies
- Kueue LocalQueue linked to the cluster queue
- Azure Container Registry access
- Default storage class and persistent volume claims
- Monitoring dashboards pre-filtered to the team's namespace

```bash
# Team onboarding via Terraform
terraform apply -var="team_name=robotics" \
  -var="gpu_quota=4" \
  -var="cpu_quota=32" \
  -var="memory_quota=128Gi" \
  -var="aad_group_id=<group-object-id>" \
  -target=module.team_onboarding
```

One command. Five minutes. The team has everything they need to start deploying workloads. No tickets, no waiting, no Slack messages.

### Pre-Configured Environments

Data scientists don't want to build Docker images or write Kubernetes manifests. They want a notebook with GPUs. Meet them where they are.

- **JupyterHub on AKS:** Deploy JupyterHub with GPU-enabled server profiles. Scientists pick a profile ("2x A100, PyTorch 2.1, CUDA 12.1"), click launch, and get a notebook with GPUs attached. The platform team maintains the profiles.
- **VS Code Dev Containers:** Provide `.devcontainer` configurations with GPU passthrough. Data scientists clone a repo and get a fully configured development environment.
- **Training job templates:** Offer a simple CLI or web form: "I want to fine-tune a model. Here's my script, here's my dataset, here's how many GPUs I need." The template generates the Kubernetes Job manifest, submits it through Kueue, and sends the scientist a link to the logs.

🔄 **Infra ↔ AI Translation:** This is the same abstraction pattern you've used for years. VMs became containers. Containers became serverless functions. Now, GPU access becomes a profile dropdown. Every generation of infrastructure goes through this arc from manual to self-service.

---

## Chapter Checklist

- ✅ Defined isolation boundaries for each team (namespace, node pool, cluster, or subscription)
- ✅ Implemented ResourceQuotas to cap GPU, CPU, and memory per namespace
- ✅ Set up RBAC scoping with Microsoft Entra ID groups mapped to Kubernetes roles
- ✅ Applied network policies to prevent cross-namespace traffic
- ✅ Created priority classes separating production inference, training, and exploratory workloads
- ✅ Deployed Kueue for job queueing and fair-share scheduling
- ✅ Evaluated Volcano for distributed training with gang scheduling
- ✅ Set up Azure capacity reservations for production inference GPU VMs
- ✅ Configured quota usage alerts at 80% thresholds
- ✅ Defined SLO tiers (real-time, near-real-time, batch) for inference endpoints
- ✅ Implemented health probes with startup probe timeouts that cover model load time
- ✅ Built a GitOps repository structure for multi-cluster fleet management
- ✅ Established a canary strategy for GPU driver upgrades
- ✅ Centralized observability with cross-cluster GPU monitoring dashboards
- ✅ Implemented cost attribution with consistent Kubernetes labels
- ✅ Automated team onboarding via Terraform modules or platform templates
- ✅ Provided self-service environments (JupyterHub, training templates) for data scientists

---

## What's Next

Your AI platform is running at scale — multi-tenant, well-scheduled, and observable. Teams can onboard themselves, submit training jobs through queues, and deploy inference endpoints with clear SLOs. You've moved from answering Slack messages to engineering systems.

Now let's dive deep into the service that's driving more AI conversations than any other: Azure OpenAI. Chapter 11 covers tokens, throughput, and provisioned capacity — the capacity planning chapter every Azure OpenAI deployment needs.
