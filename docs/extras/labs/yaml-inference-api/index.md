# Lab 3: Deploy a Real-Time Inference API with Azure ML Managed Endpoints

## Why managed endpoints matter for infra engineers

If you've ever stood up an API behind a load balancer — provisioning VMs, configuring health probes, wiring up TLS termination, bolting on autoscaling rules, and then doing it all again for the next release — you already understand the pain that Azure ML Managed Online Endpoints eliminate.

A managed endpoint is, at its core, **a fully managed load balancer + auto-scaled compute pool + API gateway**, all declared in a handful of YAML files. Azure handles the container orchestration, health monitoring, traffic splitting, and TLS — you define *what* to deploy and *how much* compute to allocate. Think of it as the difference between managing bare-metal web servers and dropping an app into Azure App Service: same workload, radically less operational overhead.

This lab walks you through every step — from training a model locally to invoking a production-grade REST endpoint — using the Azure ML CLI v2 and declarative YAML. No Kubernetes clusters, no custom Docker networking, no hand-rolled load balancer configs.

> 📖 **Book cross-reference:** This lab complements **Chapter 6 (MLOps Pipelines)** for CI/CD integration and **Chapter 7 (Monitoring AI Workloads)** for observability patterns.

---

## What you'll build

```text
┌──────────────────────────────────────────────────────────┐
│                    Azure ML Workspace                    │
│                                                          │
│  ┌─────────────┐    ┌──────────────────────────────────┐ │
│  │  Registered  │    │     Managed Online Endpoint      │ │
│  │    Model     │───▶│        "infer-demo"              │ │
│  │  (model.pkl) │    │                                  │ │
│  └─────────────┘    │  ┌────────────────────────────┐  │ │
│                      │  │  Deployment "blue"          │  │ │
│  ┌─────────────┐    │  │  ┌──────┐ ┌──────┐        │  │ │
│  │ Environment  │───▶│  │  │ VM 1 │ │ VM 2 │ ...    │  │ │
│  │ (container   │    │  │  └──────┘ └──────┘        │  │ │
│  │  image +     │    │  │  score.py + model.pkl      │  │ │
│  │  conda deps) │    │  └────────────────────────────┘  │ │
│  └─────────────┘    │                                  │ │
│                      │  TLS ─ Health probes ─ Autoscale │ │
│                      └──────────────────────────────────┘ │
│                         ▲                                 │
│                         │ HTTPS (key or Entra token)      │
└─────────────────────────┼────────────────────────────────┘
                          │
                     Client / curl
```

**The infra analogy:** The *endpoint* is your public-facing load balancer with a DNS name and auth policy. Each *deployment* is a backend pool of identical VMs running your scoring container. The *environment* is your golden VM image — a base container plus conda dependencies. And `score.py` is the application code that runs on each instance. You can run multiple deployments behind one endpoint (e.g., "blue" and "green") and split traffic between them — exactly like weighted backend pools in Azure Application Gateway.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Azure CLI** | v2.50+ with the `ml` extension |
| **Python** | 3.9 or later (local training only) |
| **RBAC** | *Contributor* on the resource group + *AzureML Data Scientist* on the workspace |
| **Quota** | At least 2 vCPU of `Standard_DS2_v2` available in your target region |

Install or update the ML extension:

```bash
az extension add -n ml -y && az extension update -n ml
```

💡 **Pro Tip:** Run `az ml online-deployment list -e infer-demo` early — if it errors with "extension not found," your `ml` extension is missing or outdated. Fix that before proceeding.

---

## File structure and what each file does

```text
yaml-inference-api/
├── endpoint.yml        # Endpoint definition (load balancer layer)
├── deployment.yml      # Deployment definition (backend pool)
├── environment.yml     # Container image + dependencies (golden image)
├── score.py            # Inference logic (app code)
├── train_model.py      # One-time local training script
├── requirements.txt    # Local Python deps for training
└── sample-request.json # Test payload
```

---

## Understanding the YAML declarations

Before running anything, let's inspect the three YAML files that define the entire deployment topology. If you've ever written ARM templates or Terraform for a web app, this will feel familiar — but scoped to ML serving.

### `endpoint.yml` — The front door

```yaml
$schema: https://azuremlschemas.azureedge.net/latest/managedOnlineEndpoint.schema.json
name: infer-demo
auth_mode: key
```

This is deliberately minimal. The endpoint is the **network-facing resource** — it gets a unique HTTPS scoring URI, manages auth (key-based here, Entra token in production), and routes traffic to one or more deployments. Think of it as the Application Gateway definition without backend pools.

⚠️ **Production Gotcha:** `auth_mode: key` is fine for dev/test but keys are shared secrets that can't be scoped per-caller or audited in Entra sign-in logs. Switch to `aad_token` for anything beyond experimentation (see the *Production considerations* section below).

### `deployment.yml` — The backend pool

```yaml
$schema: https://azuremlschemas.azureedge.net/latest/managedOnlineDeployment.schema.json
name: blue
endpoint_name: infer-demo

model: azureml:sklearn-diabetes@latest
environment: azureml:infer-sklearn-diabetes@latest

code_configuration:
  code: .
  scoring_script: score.py

instance_type: Standard_DS2_v2
instance_count: 1
```

This is where the compute decisions live. Key fields:

- **`model`** — References a registered model by name and version. Azure ML mounts it into the container at `AZUREML_MODEL_DIR`.
- **`environment`** — The container image + conda dependencies (defined separately in `environment.yml`).
- **`code_configuration`** — Points to your scoring script. The entire current directory (`.`) is uploaded as a code snapshot.
- **`instance_type` / `instance_count`** — Your SKU and replica count, exactly like choosing a VM size and scale set count.

💡 **Pro Tip:** Use `Standard_DS2_v2` (2 vCPU, 7 GB RAM, ~$0.096/hr) for CPU-based models. For GPU inference, switch to `Standard_NC6s_v3` or similar — but check regional quota first with `az vm list-usage -l <region>`.

### `environment.yml` — The golden container image

```yaml
$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: infer-sklearn-diabetes
image: mcr.microsoft.com/azureml/minimal-ubuntu22.04-py310-cpu-inference:latest
inference_config:
  liveness_route:
    path: /health
    port: 5001
  readiness_route:
    path: /health
    port: 5001
  scoring_route:
    path: /score
    port: 5001
conda_file: |
  channels:
    - conda-forge
  dependencies:
    - python=3.10
    - pip
    - pip:
      - numpy
      - scikit-learn
      - joblib
      - azureml-inference-server-http
```

Notice the `inference_config` block — it defines the health probe endpoints and scoring route, just like health probe paths on an Azure Load Balancer. The `liveness_route` restarts unhealthy containers; the `readiness_route` gates traffic until startup completes.

⚠️ **Production Gotcha:** Keep your conda dependencies minimal. Every extra package increases the container build time and cold-start latency. A bloated environment can push deployment from 5 minutes to 20+.

### `score.py` — The application logic

```python
import json, os, joblib, numpy as np

MODEL = None

def init():
    """Called once when the container starts. Load the model into memory."""
    global MODEL
    model_dir = os.environ.get("AZUREML_MODEL_DIR", ".")
    model_path = os.path.join(model_dir, "model.pkl")
    MODEL = joblib.load(model_path)

def run(raw_data):
    """Called on every scoring request. Parse JSON, predict, return results."""
    try:
        payload = json.loads(raw_data)
        data = np.array(payload["data"], dtype=float)
        preds = MODEL.predict(data)
        return preds.tolist()
    except Exception as e:
        return {"error": str(e)}
```

Two functions, that's it. `init()` runs once at container start (load the model into memory — equivalent to application warm-up). `run()` handles every incoming HTTP request. Azure ML's inference server wraps these in a Flask-like HTTP server automatically.

---

## Step-by-step deployment

### Step 0 — Configure your Azure context

```bash
az login
az account set --subscription "<your-subscription-id>"
az configure --defaults group="<your-rg>" workspace="<your-aml-workspace>"
```

Verify the workspace is reachable:

```bash
az ml workspace show --query "{name:name, location:location, rg:resource_group}" -o table
```

### Step 1 — Train the model locally

```bash
python -m pip install -r requirements.txt
python train_model.py
```

This trains a Ridge regression on the built-in scikit-learn diabetes dataset and saves `model/model.pkl`. The model is trivial on purpose — the infrastructure is the point of this lab.

Verify the file was created:

```bash
ls -lh model/model.pkl    # Linux/macOS
dir model\model.pkl        # Windows
```

### Step 2 — Register the model in Azure ML

```bash
az ml model create \
  --name sklearn-diabetes \
  --path ./model \
  --type custom_model \
  --description "Ridge regression on diabetes dataset - online endpoint lab"
```

Confirm registration:

```bash
az ml model list --query "[?name=='sklearn-diabetes'] | [0].{name:name, version:version}" -o table
```

### Step 3 — Create the environment and endpoint

Register the environment first — the deployment references it by name:

```bash
az ml environment create -f environment.yml
```

Then create the endpoint (the front door):

```bash
az ml online-endpoint create -f endpoint.yml
```

Wait for provisioning to complete and verify:

```bash
az ml online-endpoint show -n infer-demo \
  --query "{name:name, state:provisioning_state, auth:auth_mode, uri:scoring_uri}" -o table
```

You should see `provisioning_state: Succeeded` before proceeding.

### Step 4 — Create the deployment and route traffic

```bash
az ml online-deployment create -f deployment.yml --all-traffic
```

This builds the container, provisions the VM(s), mounts the model, and starts the inference server. Expect **5–10 minutes** for the first deployment while the container image is built.

Validate the deployment:

```bash
az ml online-deployment show \
  --name blue --endpoint-name infer-demo \
  --query "{name:name, state:provisioning_state, instance_type:instance_type, instance_count:instance_count}" \
  -o table
```

💡 **Pro Tip:** Subsequent deployments with the same environment are much faster — Azure ML caches the built container image, similar to how Docker layer caching works.

### Step 5 — Test the endpoint

**Quick test with the CLI:**

```bash
az ml online-endpoint invoke -n infer-demo --request-file sample-request.json
```

Expected output — a JSON array of predictions:

```json
[153.47]
```

**Test with curl** (closer to how a real client would call it):

```bash
SCORING_URI=$(az ml online-endpoint show -n infer-demo --query scoring_uri -o tsv)
API_KEY=$(az ml online-endpoint get-credentials -n infer-demo --query primaryKey -o tsv)

curl -s -X POST "$SCORING_URI" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d @sample-request.json
```

**Check deployment logs** for any runtime issues:

```bash
az ml online-deployment get-logs --name blue --endpoint-name infer-demo --lines 50
```

**Verify endpoint health metrics:**

```bash
az ml online-endpoint show -n infer-demo \
  --query "{traffic:traffic, provisioning:provisioning_state}" -o json
```

---

## Production considerations

This lab uses `auth_mode: key` and a single instance for simplicity. Here's what a production deployment looks like:

| Concern | Lab setting | Production recommendation |
|---|---|---|
| **Authentication** | `key` (shared secret) | `aad_token` — integrates with Entra ID, supports RBAC, auditable |
| **Network** | Public endpoint | Private endpoint via Azure Private Link; disable public access |
| **Identity** | None | System-assigned managed identity for accessing Key Vault, Storage, etc. |
| **Scaling** | `instance_count: 1` | Autoscale rules based on CPU, request latency, or queue depth |
| **Releases** | Single "blue" deployment | Blue-green: deploy "green," shift traffic 10% → 50% → 100%, delete "blue" |
| **Monitoring** | Manual log checks | Integrate with Azure Monitor and Application Insights (see **Chapter 7**) |
| **Security** | N/A | Network isolation, RBAC scoping, secret rotation (see **Chapter 8**) |

**Blue-green deployment example:**

```bash
# Deploy new version as "green"
az ml online-deployment create -f deployment-green.yml

# Shift 10% of traffic to green
az ml online-endpoint update -n infer-demo --traffic "blue=90 green=10"

# After validation, shift all traffic
az ml online-endpoint update -n infer-demo --traffic "blue=0 green=100"

# Clean up old deployment
az ml online-deployment delete --name blue --endpoint-name infer-demo --yes
```

> 📖 **Book cross-reference:** Blue-green and canary patterns are covered in depth in **Chapter 6 (MLOps Pipelines)**. For securing endpoints with private networking and managed identities, see **Chapter 8 (Security for AI Workloads)**.

---

## Cost estimates

Managed endpoints bill for compute while the deployment is provisioned — whether or not it's receiving traffic.

| SKU | vCPU | RAM | Approx. cost/hr | Typical use case |
|---|---|---|---|---|
| `Standard_DS2_v2` | 2 | 7 GB | ~$0.10 | Lightweight CPU models (sklearn, XGBoost) |
| `Standard_DS3_v2` | 4 | 14 GB | ~$0.20 | Mid-size models, higher throughput |
| `Standard_NC6s_v3` | 6 | 112 GB + 1×V100 | ~$3.06 | GPU inference (PyTorch, TensorFlow) |

💡 **Pro Tip:** For dev/test, scale to `instance_count: 0` when you're not actively testing — or simply delete the deployment and recreate it when needed. The model and environment remain registered, so redeployment takes minutes, not hours. Run `az ml online-deployment update --name blue --endpoint-name infer-demo --instance-count 0` to scale down.

---

## Troubleshooting

### Deployment stuck in "Updating" or "Creating"

This usually means the container image is building or a health probe is failing.

```bash
# Get detailed logs
az ml online-deployment get-logs --name blue --endpoint-name infer-demo --lines 300

# Check provisioning state
az ml online-deployment show --name blue --endpoint-name infer-demo \
  --query "{state:provisioning_state, error:error}" -o json
```

Common causes: missing packages in `environment.yml`, syntax errors in `score.py`, or insufficient quota for the chosen VM SKU.

### 401 Unauthorized on invoke

```bash
# Retrieve current keys
az ml online-endpoint get-credentials -n infer-demo -o json
```

Make sure you're using the `primaryKey` or `secondaryKey` in the `Authorization: Bearer <key>` header. Keys rotate — if you stored one earlier, re-fetch it.

### ImportError or ModuleNotFoundError in logs

Your `environment.yml` conda dependencies are missing a package that `score.py` needs. Add the package, then rebuild:

```bash
az ml environment create -f environment.yml   # Creates a new version
az ml online-deployment update -f deployment.yml
```

### Model file not found at startup

The `init()` function in `score.py` expects `model.pkl` at `AZUREML_MODEL_DIR`. This fails when:

- The model wasn't registered (`az ml model create` was skipped)
- The `model` field in `deployment.yml` has a typo or wrong version
- The model was registered with a nested folder structure — adjust the path in `score.py` accordingly

### Quota exceeded

```bash
az vm list-usage --location <your-region> -o table | grep -i "Standard DS"
```

Request a quota increase via the Azure portal or switch to a smaller SKU for testing.

### High latency on first request (cold start)

The first request after deployment warms up the inference server and loads the model. For sklearn models this is typically 1–3 seconds. To reduce cold-start impact:

- Keep the container image lean (fewer conda deps)
- Use a readiness probe so the endpoint only routes traffic once the model is loaded
- For latency-sensitive production workloads, maintain `instance_count: 2` minimum

---

## Cleanup

Delete resources in reverse order:

```bash
# Delete the deployment (stops compute billing)
az ml online-deployment delete --name blue --endpoint-name infer-demo --yes

# Delete the endpoint (removes the DNS entry and auth keys)
az ml online-endpoint delete --name infer-demo --yes

# Optional: delete the entire resource group
az group delete --name <your-rg> --yes --no-wait
```

⚠️ **Production Gotcha:** Deleting an endpoint is irreversible — the scoring URI and any keys are permanently removed. In production, prefer scaling to zero over deleting.

---

## References

- [Managed online endpoints overview](https://learn.microsoft.com/azure/machine-learning/concept-endpoints-online)
- [Online endpoint YAML schema](https://learn.microsoft.com/azure/machine-learning/reference-yaml-endpoint-online)
- [Managed online deployment YAML schema](https://learn.microsoft.com/azure/machine-learning/reference-yaml-deployment-managed-online)
- [Deploy with blue-green traffic routing](https://learn.microsoft.com/azure/machine-learning/how-to-safely-rollout-online-endpoints)
- [Autoscale managed online endpoints](https://learn.microsoft.com/azure/machine-learning/how-to-autoscale-endpoints)
- [Network isolation for managed endpoints](https://learn.microsoft.com/azure/machine-learning/how-to-secure-online-endpoint)
- [Azure ML inference server (HTTP)](https://learn.microsoft.com/azure/machine-learning/how-to-inference-server-http)
 