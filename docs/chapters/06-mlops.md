# Chapter 6 — Model Lifecycle and MLOps from an Infra Lens

*"Deploy this to production."*

---

## The Model That Arrived Without a Birth Certificate

A data scientist walks up to your desk — or, more realistically, drops a message in your team's channel — with a link to a shared drive. "Here's the model. It's a 15 GB PyTorch checkpoint. We need it in production by Friday." You open the folder and find a single file: `model_final_v2_FIXED.pt`.

You start asking questions. Which version is this? What data was it trained on? What's the rollback plan if predictions go sideways? What are the latency and throughput SLAs? What framework and CUDA version does it require? The answers are vague at best. "It's the latest one. It works on my machine. Just put it behind an API."

You've seen this movie before — just with different actors. Developers used to hand you a compiled binary and say "deploy this." That chaos led your industry to build container registries, CI/CD pipelines, semantic versioning, and automated rollback. Models are no different. They are artifacts — large, versioned, environment-dependent artifacts — and they deserve the same lifecycle management you've spent years building for application deployments. This chapter teaches you how to apply that hard-won operational discipline to the world of machine learning.

---

## Models Are Artifacts — Treat Them Like It

If you've ever pulled an image from a container registry, tagged a release in Git, or promoted a build from staging to production, you already understand the core concepts of model lifecycle management. The vocabulary changes, but the patterns are nearly identical.

🔄 **Infra ↔ AI Translation**:

| Infra Concept | ML Equivalent |
|---|---|
| Compiled binary / container image | Model checkpoint (weights file) |
| Container registry (ACR, Docker Hub) | Model registry (Azure ML, MLflow) |
| CI build | Training run |
| CD release pipeline | Model deployment pipeline |
| Build manifest (Dockerfile) | Training configuration (hyperparameters, data version, framework version) |
| Artifact signature | Model provenance and lineage |
| Blue/green deployment | A/B testing with traffic splitting |

The key insight is this: a model file without metadata is like a container image without a tag. You can deploy it, but you can't reproduce it, audit it, or safely roll it back. Model lifecycle management exists to solve three problems that every infrastructure engineer already understands.

**Reproducibility.** If something goes wrong in production, you need to recreate the exact model that's running — same weights, same preprocessing, same framework version. Without tracked lineage, "retrain the model" becomes guesswork.

**Compliance.** Regulated industries require audit trails. You need to prove which data trained a model, when it was deployed, and who approved it. This is no different from change management for infrastructure — just applied to model artifacts.

**Rollback.** When a new model degrades prediction quality or violates latency SLAs, you need to revert to the last known-good version in minutes, not hours. This requires versioned artifacts and automated deployment pipelines — tools you already know how to build.

---

## Model Registries

A model registry is the single source of truth for your organization's trained models. It stores model artifacts alongside metadata — version numbers, training metrics, lineage information, and deployment status. Think of it as your container registry, but purpose-built for ML artifacts.

### Azure Machine Learning Model Registry

Azure ML's built-in registry provides versioning, tagging, and lineage tracking integrated with the broader Azure ML workspace. Every registered model gets an immutable version number, and you can attach arbitrary tags and properties for organizational filtering.

```bash
# Register a model from a local file
az ml model create \
  --name sentiment-classifier \
  --version 3 \
  --path ./outputs/model.pt \
  --type custom_model \
  --tags task=sentiment framework=pytorch \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# List all versions of a model
az ml model list \
  --name sentiment-classifier \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws \
  --output table

# Show lineage — which run produced this model
az ml model show \
  --name sentiment-classifier \
  --version 3 \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws \
  --query "jobs"
```

💡 **Pro Tip**: Use Azure ML's model collections to group related models (e.g., all models in a recommendation pipeline). This makes it easier to promote or roll back an entire model ensemble rather than individual components.

### MLflow Model Registry

MLflow is the open-source standard for experiment tracking and model management. It's framework-agnostic — it wraps PyTorch, TensorFlow, scikit-learn, and dozens of other frameworks in a common packaging format. Azure ML natively integrates with MLflow, so you can use MLflow's APIs while storing artifacts in Azure.

```bash
# Start a local MLflow tracking server (for dev/test)
mlflow server \
  --backend-store-uri sqlite:///mlflow.db \
  --default-artifact-root ./mlruns \
  --host 0.0.0.0 --port 5000

# Register a model via the MLflow CLI
mlflow models register \
  --model-uri runs:/<run-id>/model \
  --name sentiment-classifier

# Transition a model to production stage
mlflow models transition-stage \
  --name sentiment-classifier \
  --version 3 \
  --stage Production
```

MLflow's `stages` concept (Staging, Production, Archived) maps directly to the promotion model infrastructure engineers use for application deployments. A model starts in "None," moves to "Staging" after validation, gets promoted to "Production" after approval, and is "Archived" when superseded.

### Container Registries for Model Serving

When models are served via containerized inference servers (like NVIDIA Triton, TorchServe, or a custom FastAPI wrapper), the container image itself becomes the deployable artifact. In this pattern, Azure Container Registry (ACR) acts as both your model registry and your container registry.

```bash
# Build and push a model-serving container
az acr build \
  --registry mlmodelsacr \
  --image sentiment-classifier:v3 \
  --file Dockerfile.serve .

# Verify the image
az acr repository show-tags \
  --name mlmodelsacr \
  --repository sentiment-classifier \
  --output table
```

This approach works well when you want a single artifact (the container) to encapsulate model weights, dependencies, and serving code. It simplifies deployment because your existing container orchestration tooling (AKS, Container Apps) handles everything downstream.

### 📊 Decision Matrix: Choosing a Model Registry

| Criteria | Azure ML Registry | MLflow Registry | ACR (Container) |
|---|---|---|---|
| **Best for** | Azure-native ML teams | Multi-cloud / OSS teams | Containerized serving |
| **Versioning** | Built-in, immutable | Built-in with stages | Image tags |
| **Lineage tracking** | Deep (jobs, data, env) | Run-level | Dockerfile only |
| **Max artifact size** | Effectively unlimited | Backend-dependent | Layer-based |
| **Framework lock-in** | None | None | None |
| **Infra overhead** | Managed | Self-hosted or Azure ML | Managed (ACR) |
| **When to avoid** | Multi-cloud requirement | Need deep Azure integration | Models without containers |

⚠️ **Production Gotcha**: Don't use shared file systems or blob storage as your "registry." Without immutable versions, atomic uploads, and metadata APIs, you end up with `model_final_v2_FIXED_actually_final.pt` — the exact chaos this chapter exists to prevent.

---

## CI/CD for Models

Model deployment is not a manual process. It's a pipeline — with stages, gates, and rollback mechanisms — just like your application CI/CD. The difference is that model validation involves statistical testing (accuracy, latency, fairness) in addition to the functional tests you're used to.

### The Model Promotion Pipeline

A production-grade model pipeline has three stages, each with distinct infrastructure requirements and validation gates.

```
┌─────────┐     ┌─────────────┐     ┌──────────────┐
│   DEV   │────▶│   STAGING   │────▶│  PRODUCTION  │
│         │     │             │     │              │
│ Train   │     │ Validate    │     │ Serve        │
│ Track   │     │ Benchmark   │     │ Monitor      │
│ Version │     │ Security    │     │ Auto-rollback│
└─────────┘     └─────────────┘     └──────────────┘
     │               │                    │
  GPU Compute    Inference Infra      Load Balanced
  Blob Storage   Test Data Access     Multi-replica
  Experiment     Isolated Network     Prod Network
  Tracking                            SLA-bound
```

**Dev**: Data scientists train models using GPU compute. Your responsibility is providing the compute environment (GPU VMs or AKS GPU node pools), storage for training data and checkpoints, and experiment tracking infrastructure. Models that pass initial evaluation get registered in the model registry.

**Staging**: Registered models are deployed to a staging environment that mirrors production infrastructure — same VM SKUs, same network configuration, same inference server. Automated tests validate accuracy against a holdout dataset, measure latency under load, and run security scans. This stage is where most models fail, and that's by design.

**Production**: Models that clear all staging gates are deployed to production with traffic management (canary or blue/green). Monitoring detects degradation and triggers automated rollback. Your infrastructure must support running multiple model versions simultaneously during transitions.

### Automated Validation Gates

Every stage transition requires passing automated gates. Here's what to validate and what infrastructure each gate requires:

| Gate | What It Checks | Infra Required |
|---|---|---|
| **Accuracy threshold** | Model metrics ≥ baseline (e.g., F1 > 0.92) | Test dataset storage, compute for evaluation |
| **Latency benchmark** | P95 latency ≤ SLA (e.g., < 200ms) | Load testing infrastructure |
| **Throughput test** | Requests/sec ≥ target under load | Load generator (k6, Locust) |
| **Security scan** | No vulnerable dependencies, signed artifact | Container scanning (Triton, Defender) |
| **Data validation** | Input schema matches expected format | Schema registry or validation service |
| **Cost estimate** | Projected serving cost within budget | Cost modeling based on compute SKU |

### GitHub Actions Workflow for Model Deployment

Here's a practical CI/CD workflow that infrastructure engineers can own. It triggers when a new model version is registered, runs validation, and promotes to production.

```yaml
# .github/workflows/model-deploy.yml
name: Model Deployment Pipeline

on:
  workflow_dispatch:
    inputs:
      model_name:
        description: 'Model name in registry'
        required: true
      model_version:
        description: 'Model version to deploy'
        required: true

env:
  AZURE_RG: ml-prod-rg
  AZURE_ML_WS: ml-prod-ws
  ACR_NAME: mlmodelsacr
  AKS_CLUSTER: ml-inference-aks

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Download model from registry
        run: |
          az ml model download \
            --name ${{ inputs.model_name }} \
            --version ${{ inputs.model_version }} \
            --download-path ./model \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}

      - name: Run accuracy validation
        run: |
          python scripts/validate_model.py \
            --model-path ./model \
            --test-data ./data/holdout.csv \
            --min-accuracy 0.92

      - name: Run latency benchmark
        run: |
          python scripts/benchmark_latency.py \
            --model-path ./model \
            --max-p95-ms 200 \
            --num-requests 1000

  deploy-staging:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging endpoint
        run: |
          az ml online-deployment create \
            --name staging-${{ inputs.model_version }} \
            --endpoint-name sentiment-staging \
            --model azureml:${{ inputs.model_name }}:${{ inputs.model_version }} \
            --instance-type Standard_NC4as_T4_v3 \
            --instance-count 1 \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}

      - name: Smoke test staging
        run: |
          python scripts/smoke_test.py \
            --endpoint sentiment-staging \
            --expected-status 200

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval
    steps:
      - name: Deploy canary (10% traffic)
        run: |
          az ml online-deployment create \
            --name prod-${{ inputs.model_version }} \
            --endpoint-name sentiment-prod \
            --model azureml:${{ inputs.model_name }}:${{ inputs.model_version }} \
            --instance-type Standard_NC4as_T4_v3 \
            --instance-count 2 \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}

          az ml online-endpoint update \
            --name sentiment-prod \
            --traffic "prod-stable=90 prod-${{ inputs.model_version }}=10" \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}
```

🔄 **Infra ↔ AI Translation**: This is your blue/green deployment pipeline, but for model weights instead of container images. The `--traffic` flag works exactly like weighted routing in Azure Front Door or Application Gateway — you're shifting a percentage of production requests to the new model version while the old one continues serving.

### Infrastructure Responsibilities at Each Stage

As the infrastructure engineer, your ownership spans the full pipeline:

- **Compute provisioning**: GPU node pools for training (Dev), inference VMs for validation (Staging), auto-scaling GPU clusters for serving (Production).
- **Networking**: Isolated VNets for staging, private endpoints for model registry access, load balancer configuration for traffic splitting.
- **Storage**: High-throughput blob storage for training data, low-latency storage for model artifacts, retention policies for old model versions.
- **Secrets management**: Key Vault integration for API keys, managed identity for pipeline authentication, RBAC for model registry access.
- **Monitoring**: Deployment health dashboards, latency alerting, automated rollback triggers.

---

## A/B Testing and Canary Deployments for Models

Deploying a model to production isn't a binary event. You don't flip a switch and hope for the best. Instead, you gradually shift traffic to the new model version while monitoring performance — the same canary and blue/green patterns you use for application deployments.

### Traffic Splitting Patterns

Three patterns dominate model deployments, each with different infrastructure requirements:

**Canary (90/10 → 70/30 → 0/100).** Route a small percentage of traffic to the new model version. If metrics hold, increase the percentage. If they degrade, roll back. This is the safest pattern and the most common. Azure ML managed endpoints support this natively with the `--traffic` parameter.

**Blue/Green.** Run two full production environments simultaneously. Route all traffic to "blue" (current) while validating "green" (new). When ready, switch the DNS or load balancer to green. Rollback is instant — just switch back. This pattern doubles your infrastructure cost during deployment but eliminates partial-traffic risks.

**Shadow (Dark Launch).** Route 100% of traffic to the current model, but also send a copy of each request to the new model. Compare responses offline without affecting users. This is ideal for high-stakes deployments where even 10% traffic risk is unacceptable. The trade-off is double the inference compute during the shadow period.

```bash
# Azure ML: Shift traffic gradually
# Start with 10% to the new deployment
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "stable=90 canary-v4=10" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# After monitoring confirms parity, increase to 50%
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "stable=50 canary-v4=50" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# Full cutover
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "canary-v4=100" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws
```

### Monitoring Model Performance During A/B Tests

During a canary deployment, you're comparing two model versions head-to-head. Your monitoring must answer: is the new model at least as good as the old one? Here's what to track:

| Metric | Why It Matters | Alert Threshold |
|---|---|---|
| **Prediction latency (P50/P95/P99)** | User experience and SLA compliance | P95 > 1.2× baseline |
| **Error rate** | Model failures, timeout, OOM | > 0.5% |
| **Prediction distribution** | Detect model drift or bias shift | Distribution divergence > threshold |
| **GPU utilization** | Efficiency and cost impact | Sustained < 30% or > 95% |
| **Request throughput** | Capacity validation | Drops below expected RPS |

### Automated Rollback Triggers

Don't rely on humans to catch degradation at 3 AM. Configure automated rollback rules that revert traffic when metrics breach thresholds. Azure ML managed endpoints support deployment health monitoring, and you can build custom rollback logic using Azure Monitor alerts and Logic Apps or GitHub Actions webhooks.

```bash
# Emergency rollback — shift all traffic back to stable
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "stable=100" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# Then delete the failed deployment
az ml online-deployment delete \
  --name canary-v4 \
  --endpoint-name sentiment-prod \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws \
  --yes
```

💡 **Pro Tip**: Define your rollback criteria before deployment, not after. Write them into your pipeline configuration. Common triggers: P95 latency exceeds 2× baseline for 5 minutes, error rate exceeds 1% for 3 minutes, or prediction confidence distribution diverges beyond a statistical threshold.

---

## Model Supply Chain Security

You wouldn't pull an unsigned container image from an unknown registry and run it in production. The same discipline must apply to model artifacts. Model files are executable code — especially when serialized with Python's `pickle` format — and the ML ecosystem is still maturing its security practices.

### Model Signing and Provenance

Establish a chain of custody for every model artifact. At minimum, track:

- **Who** initiated the training run (identity and authorization)
- **What** code, data, and hyperparameters were used (reproducibility)
- **When** the model was trained and registered (auditability)
- **Where** the training ran (compute environment, region)

Azure ML automatically captures training job lineage. For additional signing, consider using Notary v2 (notation) to sign model containers stored in ACR:

```bash
# Sign a model container image with notation
notation sign \
  mlmodelsacr.azurecr.io/sentiment-classifier:v3 \
  --key mySigningKey

# Verify before deployment
notation verify \
  mlmodelsacr.azurecr.io/sentiment-classifier:v3
```

### Container Image Security for Model Serving

Model serving containers inherit all the security concerns of any production container — plus additional risks from ML framework dependencies. Your container scanning pipeline should include:

```bash
# Scan the model-serving image with Defender for Containers
az acr task run \
  --registry mlmodelsacr \
  --name scan-sentiment-v3 \
  --file scan-task.yaml

# Check for known vulnerabilities in ML framework dependencies
# (PyTorch, TensorFlow, ONNX Runtime, etc.)
az acr repository show \
  --name mlmodelsacr \
  --image sentiment-classifier:v3 \
  --query "changeableAttributes"
```

⚠️ **Production Gotcha**: Model files downloaded from public hubs like Hugging Face can contain malicious code. PyTorch's default serialization uses Python `pickle`, which can execute arbitrary code during deserialization. A model file named `pytorch_model.bin` could contain a reverse shell payload that activates when your inference server loads the weights. **Always** scan model files from untrusted sources, prefer SafeTensors format over pickle, and run model loading in sandboxed environments before promoting to your registry. Treat model files with the same suspicion you'd give an unsigned container image from Docker Hub.

### Securing the Model Pipeline

Apply the same supply chain principles you use for application code:

- **Private registries only**: Store models in Azure ML registries or private ACR instances — never on shared drives or public storage.
- **Managed identity for access**: Use Azure Managed Identity for pipeline authentication to model registries. No service principal secrets in CI/CD variables.
- **Network isolation**: Model registries should be accessible only via private endpoints. Training and inference compute should pull artifacts through your VNet.
- **Immutable versions**: Once a model version is registered, it should not be overwritten. Treat model versions like container image digests — append, never mutate.

---

## Reproducible Training Environments

When a model needs retraining — because data drifts, requirements change, or a bug is discovered — you need to recreate the exact environment that produced the current version. "It worked on my machine" is even more dangerous in ML because training outcomes depend on framework versions, CUDA drivers, random seeds, and even GPU hardware generation.

### What to Pin

A reproducible training environment locks down four categories:

| Category | What to Pin | Example |
|---|---|---|
| **Framework** | ML library version | `pytorch==2.2.1`, `transformers==4.38.0` |
| **Runtime** | CUDA, cuDNN, Python | `CUDA 12.1`, `cuDNN 8.9.7`, `Python 3.11.8` |
| **Data** | Dataset version or snapshot | `dataset-v2.3`, timestamped blob snapshot |
| **Hardware** | GPU SKU and count | `Standard_NC24ads_A100_v4`, 4x A100 80GB |

```dockerfile
# Example: Pinned training environment
FROM mcr.microsoft.com/aifx/acpt/stable-ubuntu2204-cu121-py311-torch221:latest

WORKDIR /training

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY configs/ ./configs/

# Pin the random seed for reproducibility
ENV PYTHONHASHSEED=42
ENV CUBLAS_WORKSPACE_CONFIG=:4096:8

ENTRYPOINT ["python", "src/train.py"]
```

💡 **Pro Tip**: Use Azure ML curated environments or Microsoft's ACPT (Azure Container for PyTorch) base images. These are pre-validated combinations of CUDA, cuDNN, and framework versions that are tested against Azure GPU SKUs. Building your own CUDA stack from scratch is a reliability risk you don't need to take.

### Storage Architecture for Training Artifacts

Training produces a surprising volume of artifacts beyond the final model. Your storage architecture must handle:

- **Checkpoints**: Intermediate model snapshots saved every N steps. A single training run on a large model can produce hundreds of gigabytes of checkpoints. Use Azure Blob Storage with hot tier for active runs, then lifecycle policies to move older checkpoints to cool or archive tier.
- **Logs and metrics**: Per-step training metrics (loss, learning rate, gradient norms) logged to experiment tracking (MLflow or Azure ML). These are small but numerous — thousands of metric points per run.
- **Datasets**: Versioned snapshots of training data. Use Azure Data Lake Storage Gen2 with hierarchical namespace for efficient large-dataset access. Enable versioning or immutable storage for compliance.
- **Configuration**: Hyperparameters, environment definitions, and pipeline configurations. Store these in Git alongside your training code.

```bash
# Create a storage account optimized for training artifacts
az storage account create \
  --name mltrainingartifacts \
  --resource-group ml-prod-rg \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hns true \
  --enable-hierarchical-namespace true

# Set lifecycle policy to archive old checkpoints
az storage account management-policy create \
  --account-name mltrainingartifacts \
  --resource-group ml-prod-rg \
  --policy @lifecycle-policy.json
```

---

## Feature Stores — The Infra View

At some point, your ML teams will ask for a "feature store." If this term is new, don't worry — from an infrastructure perspective, it's a caching and data-serving layer that you already know how to build.

### What Feature Stores Are and Why They Exist

A feature is a transformed data point used as input to a model. For example, a raw transaction log might contain timestamps and dollar amounts. Features derived from that data might include "average transaction amount in the last 7 days" or "number of transactions in the last hour." Computing these features is expensive, and different models often need the same features. A feature store computes features once and serves them to any model that needs them.

From your perspective, a feature store is a system with two data paths and a consistency requirement between them.

### Online vs. Offline Stores

| Component | Purpose | Latency | Storage | Example Tech |
|---|---|---|---|---|
| **Offline store** | Batch training data retrieval | Seconds to minutes | Terabytes to petabytes | Azure Data Lake, Synapse, Delta Lake |
| **Online store** | Real-time inference serving | Single-digit milliseconds | Gigabytes to terabytes | Azure Cache for Redis, Cosmos DB |

**Offline stores** serve training pipelines. Data scientists query historical feature values to build training datasets. Performance requirements are throughput-oriented — scanning large volumes of data efficiently. This maps to your existing data lake architecture.

**Online stores** serve inference endpoints. When a model receives a prediction request, it needs the latest feature values with sub-10ms latency. This is a key-value lookup pattern — exactly like the caching layers you've built for web applications.

### Infrastructure Components

A feature store deployment typically includes:

```
┌────────────────────────────────────────────┐
│              Feature Store                  │
│                                             │
│  ┌──────────┐    Sync    ┌──────────────┐  │
│  │ Offline  │ ─────────▶ │   Online     │  │
│  │ Store    │            │   Store      │  │
│  │ (ADLS)   │            │ (Redis/      │  │
│  │          │            │  Cosmos DB)  │  │
│  └──────────┘            └──────────────┘  │
│       ▲                        │           │
│       │                        ▼           │
│  Training                  Inference       │
│  Pipelines                 Endpoints       │
└────────────────────────────────────────────┘
```

- **Azure Data Lake Storage Gen2** for the offline store — batch access, schema evolution, and cost-effective storage for historical feature data.
- **Azure Cache for Redis** or **Cosmos DB** for the online store — sub-millisecond reads for real-time serving. Choose Redis for simple key-value patterns with extreme low latency. Choose Cosmos DB when you need multi-region replication, richer query patterns, or SLA-backed availability.
- **A synchronization pipeline** (Azure Data Factory, Spark, or custom) that materializes features from the offline store to the online store on a schedule or triggered by new data.

💡 **Pro Tip**: Treat the online feature store like any other caching tier. Apply the same operational practices — monitor hit rates, set eviction policies, plan capacity for peak load, and test failure scenarios. If Redis goes down, your inference endpoints lose access to features and predictions fail. This is a critical-path dependency.

---

## ✅ Chapter Checklist

Before moving to Chapter 7, verify that your model lifecycle management covers these essentials:

- [ ] **Model registry in place** — All production models are registered with immutable versions, metadata, and lineage tracking (Azure ML, MLflow, or ACR).
- [ ] **CI/CD pipeline for models** — Automated pipeline with Dev → Staging → Production stages and validation gates at each transition.
- [ ] **Validation gates defined** — Accuracy thresholds, latency benchmarks, throughput tests, and security scans run automatically before any model reaches production.
- [ ] **Traffic management configured** — Canary or blue/green deployment capability with percentage-based traffic splitting for safe model rollouts.
- [ ] **Automated rollback** — Monitoring alerts trigger automatic traffic revert when model performance degrades beyond defined thresholds.
- [ ] **Model supply chain secured** — Model artifacts are signed, scanned, stored in private registries, and accessed via managed identity and private endpoints.
- [ ] **Reproducible training environments** — Framework, CUDA, Python, and data versions are pinned. Training runs in containerized environments with deterministic configurations.
- [ ] **Storage architecture planned** — Blob storage for checkpoints with lifecycle policies, experiment tracking for metrics, versioned data lake for datasets.
- [ ] **Feature store infrastructure scoped** — If required, offline store (ADLS), online store (Redis/Cosmos DB), and synchronization pipeline are provisioned and monitored.
- [ ] **Rollback tested** — You've actually tested rolling back a model version in a non-production environment. Don't wait for a 2 AM incident to discover your rollback process has gaps.

---

## Bridge to Chapter 7

Your models now have a lifecycle — versioned, tested, and deployable through automated pipelines with rollback capabilities. But deployment is only the beginning of a model's life in production. How do you know the model is performing well after the canary period ends? How do you detect when prediction quality degrades because the real world changed? How do you alert on GPU utilization patterns that indicate wasted spend?

Chapter 7 covers monitoring and observability for AI workloads: what to measure, how to alert, and why GPU metrics are only the beginning.
