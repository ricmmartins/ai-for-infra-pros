# Chapter 7 — Monitoring and Observability for AI Workloads

*"Everything looked green on the dashboard. And that was exactly the problem."*

---

## The Silent Failure

Your Azure OpenAI endpoint is returning 200 OK on every request. Latency looks normal — P95 is under 800ms. CPU and memory utilization are well within thresholds. The Kubernetes cluster shows all pods healthy, no restarts, no evictions. By every infrastructure metric you've ever trusted, the system is perfectly fine.

But the support tickets keep coming. Users are reporting that the chatbot is "giving worse answers." The responses are technically fluent but factually wrong — hallucinations have increased, summaries miss key points, and code suggestions introduce subtle bugs. Your product manager is alarmed. The VP of Engineering wants answers by end of day.

You pull up your monitoring stack. Azure Monitor: green. Application Insights: green. Grafana dashboards: all green. You're staring at a wall of healthy metrics while the system is actively failing your users.

The problem? **Model drift**. A recent fine-tuning run introduced a regression in response quality. The model's outputs degraded gradually over two weeks, but no alert fired — because you're monitoring infrastructure metrics, not AI metrics. Your observability stack is built for traditional workloads where "the server is up and responding" equals "the system is working." In AI, a model can be running perfectly and still be wrong.

This is the fundamental challenge of AI observability: **the infrastructure can be healthy while the workload is broken**. Traditional monitoring answers "Is it running?" AI monitoring must also answer "Is it working correctly?" and "Is it worth the cost?" This chapter teaches you to see across all six dimensions of AI observability — so you never confuse a green dashboard with a healthy system again.

---

## The Six Dimensions of AI Observability

Traditional infrastructure monitoring covers compute, network, and storage. That's necessary but insufficient for AI workloads. You need to monitor six dimensions simultaneously, because failures in any one of them can manifest as a degraded user experience — and the symptoms often overlap in ways that make root cause analysis tricky.

**Infra ↔ AI Translation**: Think of it this way — monitoring a web server means watching CPU, memory, disk, and network. Monitoring an AI workload is like monitoring a web server, a database, a billing system, and a quality assurance department simultaneously. The model is not just consuming resources; it's producing outputs that have a correctness dimension traditional infrastructure doesn't have.

### 1. Compute — GPU Utilization, Memory, Temperature

This is the dimension closest to traditional monitoring. You're tracking GPU utilization percentage, HBM memory consumption, GPU temperature, power draw, and ECC (Error Correcting Code) memory errors. Low GPU utilization during inference may indicate inefficient batching. High temperatures approaching thermal throttling thresholds (typically 83°C for data center GPUs) signal cooling issues or sustained overload. ECC errors, especially uncorrectable ones, indicate hardware degradation.

### 2. Model — Accuracy, Drift, Latency Distribution, Error Rates

This is the dimension that catches the failure from our opening story. You're tracking inference accuracy (when measurable), output quality scores, model version performance comparisons, and response distribution shifts. For LLMs, this includes tracking hallucination rates, refusal rates, and response coherence. Model drift happens when the statistical properties of the inputs or the model's performance change over time, even though nothing in the infrastructure changed.

### 3. Network — Throughput, InfiniBand Health, Cross-Node Latency

Multi-GPU training jobs and distributed inference rely heavily on network performance. You need to monitor InfiniBand link health, NCCL communication throughput, cross-node latency, and packet drops. A single degraded InfiniBand link in a multi-node training cluster can reduce throughput by 30-50% because distributed training requires all nodes to synchronize at the pace of the slowest communicator.

### 4. Data — Pipeline Freshness, Quality, Ingestion Failures

AI workloads consume data through pipelines, and pipeline failures are a top source of incidents. Monitor data ingestion latency, schema validation errors, missing feature values, and training data staleness. A retrieval-augmented generation (RAG) application that stops indexing new documents will keep running perfectly — it just won't know about anything that happened after the pipeline broke.

### 5. Cost — GPU Spend, Token Consumption, Cost Per Inference

GPUs and tokens are expensive, and costs can escalate rapidly without visibility. Track GPU-hours consumed per team or project, token consumption per model deployment, cost per inference request, and spend versus budget projections. An unoptimized prompt that sends 4,000 tokens per request instead of 500 can multiply your Azure OpenAI bill by 8× overnight.

### 6. Security — Access Patterns, Prompt Injection, Data Exfiltration

AI systems introduce novel security monitoring requirements. Watch for anomalous API access patterns, prompt injection attempts (inputs designed to manipulate model behavior), attempts to extract training data or system prompts, and unusual token consumption spikes that could indicate abuse. These are threats that traditional WAF and NSG logs won't catch.

**Decision Matrix — What to Monitor First**

| Priority | Dimension | Why |
|----------|-----------|-----|
| **P0** | Compute (GPU) | Hardware failures cause immediate outages |
| **P0** | Cost | Unchecked spend can blow budgets in hours |
| **P1** | Model | Quality degradation affects users silently |
| **P1** | Security | Prompt injection and data exfiltration are active threats |
| **P2** | Network | Impacts multi-node workloads significantly |
| **P2** | Data | Pipeline freshness affects downstream accuracy |

---

## GPU Monitoring Deep Dive

GPU monitoring is the foundation of AI observability. Without it, you're flying blind on the most expensive resource in your stack. The toolchain has matured significantly, and Azure provides a managed path that eliminates most of the operational overhead.

### DCGM Exporter as a DaemonSet in AKS

NVIDIA's Data Center GPU Manager (DCGM) Exporter runs as a DaemonSet — one pod per GPU node — and exposes GPU metrics in Prometheus format. This is the standard approach for Kubernetes-based GPU monitoring.

```bash
# Add the NVIDIA Helm repository
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Install DCGM Exporter as a DaemonSet on GPU nodes
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-monitoring \
  --create-namespace \
  --set nodeSelector."agentpool"="gpu"
```

DCGM Exporter exposes metrics on port 9400 by default. Once running, Prometheus can scrape these metrics automatically.

### Azure Managed Prometheus for GPU Metrics

Azure Managed Prometheus eliminates the need to run your own Prometheus server. Enable it on your AKS cluster and configure it to scrape DCGM metrics:

```bash
# Enable Azure Monitor managed service for Prometheus
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-azure-monitor-metrics

# Verify the monitoring add-on is enabled
az aks show \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --query "azureMonitorProfile.metrics.enabled"
```

💡 **Pro Tip**: Managed Prometheus does **not** scrape DCGM metrics just because a `dcgm-exporter` pod exists. For AKS, you need the managed GPU metrics prerequisites: a managed NVIDIA GPU node pool, Azure Managed Prometheus enabled on the cluster, and an `ama-metrics-settings-configmap` in `kube-system` with `dcgmexporter = true`. Once that profile is enabled, existing and new managed GPU node pools are scraped automatically.

### Key GPU Metrics and Alert Thresholds

| Metric | DCGM Name | Warning | Critical | What It Means |
|--------|-----------|---------|----------|---------------|
| GPU Utilization | `DCGM_FI_DEV_GPU_UTIL` | < 30% sustained | < 10% sustained | Underutilization — wasting GPU spend |
| GPU Memory Used | `DCGM_FI_DEV_FB_USED` | > 85% | > 95% | OOM risk for new workloads |
| GPU Temperature | `DCGM_FI_DEV_TEMPERATURE` | > 78°C | > 83°C | Thermal throttling imminent |
| ECC Errors (Uncorrectable) | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | > 0 | > 0 | Hardware degradation — replace GPU |
| Memory Clock Throttle | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | Thermal | HW Slowdown | Performance capped by thermals or power |

⚠️ **Production Gotcha**: Low GPU utilization isn't always a problem. Some inference workloads are latency-sensitive and intentionally keep GPU utilization low to maintain fast response times. Before alerting on low utilization, verify whether the workload is optimized for throughput (training — high utilization expected) or latency (inference — moderate utilization acceptable).

### nvidia-smi for Ad-Hoc Debugging

When you need to troubleshoot a specific node, `nvidia-smi` is your go-to tool (see Chapter 4 for deep-dive GPU diagnostics). Use it to get a real-time snapshot:

```bash
# Basic GPU status
nvidia-smi

# Continuous monitoring at 1-second intervals
nvidia-smi dmon -s pucvmet -d 1

# Check GPU topology and NVLink status
nvidia-smi topo -m
```

---

## Azure OpenAI Monitoring

Azure OpenAI has its own monitoring requirements that are distinct from self-hosted model infrastructure. The key metrics revolve around token consumption, rate limiting, and perceived latency.

### Key Metrics

**TPM (Tokens Per Minute)** measures your throughput consumption against your allocated capacity. When you hit your TPM limit, Azure throttles your requests with HTTP 429 responses. Monitor how close you are to your limit — sustained usage above 80% of your TPM allocation means you need to plan for more capacity.

**RPM (Requests Per Minute)** caps the number of individual API calls regardless of token count. A flood of small requests can hit RPM limits even when TPM has headroom. This often catches teams off guard when they switch from a few large requests to many small ones.

**TTFT (Time to First Token)** measures the perceived latency for streaming responses. Users perceive latency based on when the first token appears, not when the full response completes. A TTFT above 2 seconds feels sluggish to users even if total generation time is acceptable.

**HTTP 429 Rate** is the throttling signal. Any sustained 429 rate above 1% deserves investigation. Spikes during peak hours may indicate you need to implement request queuing, deploy across multiple regions, or upgrade from pay-as-you-go to Provisioned Throughput Units (PTUs).

### Monitoring Throttling in Practice

Configure diagnostic settings on your Azure OpenAI resource to send logs and metrics to a Log Analytics workspace. For Azure OpenAI, you want both the request/response logs and the usage logs. `AzureOpenAIRequestUsage` is the category that captures per-request token usage data in `AzureDiagnostics`; without it, your cost and token attribution queries are blind.

```bash
# Enable diagnostic logging for Azure OpenAI
az monitor diagnostic-settings create \
  --resource "/subscriptions/<sub-id>/resourceGroups/myRG/providers/Microsoft.CognitiveServices/accounts/myAOAI" \
  --name "aoai-diagnostics" \
  --workspace "/subscriptions/<sub-id>/resourceGroups/myRG/providers/Microsoft.OperationalInsights/workspaces/myWorkspace" \
  --logs '[{"category":"RequestResponse","enabled":true},{"category":"Audit","enabled":true},{"category":"AzureOpenAIRequestUsage","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

⚠️ **Production Gotcha**: Azure OpenAI diagnostic logs can generate significant volume in busy deployments. A deployment handling 1,000 RPM produces roughly 1.4 million log entries per day. Set appropriate retention policies on your Log Analytics workspace — 30 days is sufficient for operational debugging, while compliance requirements may dictate longer retention.

### Token Consumption for Cost Attribution

Track token usage by deployment, application, and team to understand cost drivers:

```python
from opentelemetry import metrics

meter = metrics.get_meter("azure-openai-tracking")
token_counter = meter.create_counter(
    "aoai.tokens.consumed",
    description="Tokens consumed per request",
    unit="tokens"
)

# After each API call, record token usage with attribution labels
token_counter.add(
    response.usage.total_tokens,
    attributes={
        "deployment": deployment_name,
        "model": model_name,
        "application": app_name,
        "team": team_tag,
        "token_type": "total"
    }
)
```

**Infra ↔ AI Translation**: Think of TPM limits like bandwidth throttling and RPM limits like connection-rate limiting. You've managed both in networking for years — the same patterns apply. Token budgets are the AI equivalent of data transfer quotas.

---

## Application-Level Observability

Infrastructure metrics tell you whether the system is healthy. Application-level observability tells you whether it's working correctly and efficiently.

### OpenTelemetry for Distributed Tracing

Modern AI applications involve multiple services: API gateways, preprocessing steps, embedding generation, vector search, LLM inference, and post-processing. OpenTelemetry provides the distributed tracing standard that lets you follow a single request through this entire pipeline.

```python
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace

# Configure Azure Monitor exporter
# Requires APPLICATIONINSIGHTS_CONNECTION_STRING environment variable
configure_azure_monitor()

tracer = trace.get_tracer("inference-pipeline")

def process_request(user_query):
    with tracer.start_as_current_span("inference-pipeline") as span:
        # Step 1: Embed the query
        with tracer.start_as_current_span("generate-embedding"):
            embedding = embed(user_query)

        # Step 2: Retrieve context from vector store
        with tracer.start_as_current_span("vector-search"):
            context = search(embedding, top_k=5)

        # Step 3: Generate response via LLM
        with tracer.start_as_current_span("llm-inference") as llm_span:
            response = generate(user_query, context)
            llm_span.set_attribute("tokens.prompt", response.usage.prompt_tokens)
            llm_span.set_attribute("tokens.completion", response.usage.completion_tokens)

        return response
```

### Custom Metrics for AI Workloads

Beyond traces, instrument your application with metrics that capture AI-specific behavior:

- **Inference latency percentiles** — P50, P95, and P99. The P50 tells you typical experience; P95/P99 reveal tail latency that affects your worst-served users.
- **Tokens per second** — throughput measure for LLM inference. Dropping TPS may indicate GPU memory pressure or model degradation.
- **Queue depth** — how many requests are waiting for GPU resources. Rising queue depth with stable throughput signals you need to scale out.
- **Cache hit rate** — for semantic caching layers. High cache hit rates reduce both latency and cost.

### Structured Logging for ML Pipelines

Standard application logs are unstructured text that's hard to query. For AI workloads, use structured logging that captures the fields you'll need during incident investigation:

```python
import logging
import json

class StructuredFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "message": record.getMessage(),
            "service": getattr(record, "service", "inference-api"),
            "model_version": getattr(record, "model_version", "unknown"),
            "deployment": getattr(record, "deployment", "unknown"),
            "request_id": getattr(record, "request_id", None),
            "tokens_used": getattr(record, "tokens_used", None),
            "latency_ms": getattr(record, "latency_ms", None),
        }
        return json.dumps(log_entry)
```

Structured logs let you filter by model version, correlate by request ID, and aggregate by deployment — all critical during an incident. Without structured logging, you're grepping through free-form text at 3 AM.

💡 **Pro Tip**: Always log the model version and deployment name with every trace and metric. When you deploy a new model version and latency increases by 40%, you need to correlate the performance change with the deployment event. Without version tagging, you'll waste hours investigating infrastructure when the model itself is the cause.

---

## KQL Queries for AI Troubleshooting

These production-ready KQL queries are split by telemetry source, because Azure OpenAI and your application do **not** land in the same tables:

- **Azure OpenAI resource telemetry** goes to `AzureDiagnostics` (resource logs) and `AzureMetrics` (platform metrics).
- **Your application's telemetry** goes to `AppRequests` (Application Insights workspace-based tables).

Mixing those sources is a fast way to get empty result sets or misleading numbers.

### Azure OpenAI Resource Telemetry

### 1. HTTP 429 Throttling Rate from Azure OpenAI Request Logs

Use the `RequestResponse` resource log category to spot throttling windows and correlate them with gateway-observed latency.

```kusto
AzureDiagnostics
| where TimeGenerated > ago(7d)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where Category == "RequestResponse"
| summarize
    TotalRequests = count(),
    ThrottledRequests = countif(ResultSignature == "429"),
    ThrottleRatePct = round(100.0 * countif(ResultSignature == "429") / count(), 2),
    P95GatewayLatencyMs = percentile(DurationMs, 95)
    by bin(TimeGenerated, 1h), OperationName
| where ThrottledRequests > 0
| order by TimeGenerated desc
```

### 2. Azure OpenAI Latency by Deployment from Platform Metrics

For Azure OpenAI latency, use the Azure OpenAI metrics — not the legacy Cognitive Services `Latency` metric.

```kusto
AzureMetrics
| where TimeGenerated > ago(24h)
| where MetricName == "AzureOpenAITTLTInMS"
| extend Dimensions = parse_json(Tags)
| extend Deployment = tostring(Dimensions["ModelDeploymentName"])
| summarize
    AvgLatencyMs = avg(Average),
    P95LatencyMs = percentile(Average, 95),
    MaxLatencyMs = max(Maximum)
    by bin(TimeGenerated, 15m), Deployment
| order by TimeGenerated desc
```

### 3. Token Consumption by Deployment

Use Azure OpenAI platform metrics for deployment-level prompt and completion token volume.

```kusto
AzureMetrics
| where TimeGenerated > ago(24h)
| where MetricName in ("ProcessedPromptTokens", "GeneratedTokens")
| extend Dimensions = parse_json(Tags)
| extend Deployment = tostring(Dimensions["ModelDeploymentName"])
| extend TokenType = iff(MetricName == "ProcessedPromptTokens", "Prompt", "Completion")
| summarize
    TotalTokens = sum(Total)
    by Deployment, TokenType
| order by Deployment asc, TokenType asc
```

### 4. PTU Utilization Hot Spots

If you're on Provisioned Throughput, this is the query that tells you whether you're living near the cliff edge.

```kusto
AzureMetrics
| where TimeGenerated > ago(6h)
| where MetricName == "AzureOpenAIProvisionedManagedUtilizationV2"
| extend Dimensions = parse_json(Tags)
| extend Deployment = tostring(Dimensions["ModelDeploymentName"])
| summarize
    AvgUtilizationPct = avg(Average),
    MaxUtilizationPct = max(Maximum)
    by bin(TimeGenerated, 5m), Deployment
| where MaxUtilizationPct > 80
| order by MaxUtilizationPct desc
```

### Application Telemetry (`AppRequests`)

### 5. End-to-End Application Latency and Error Rate

Use `AppRequests` for what the user actually experienced in your app: ingress, orchestration, vector search, retries, and downstream time combined.

```kusto
AppRequests
| where TimeGenerated > ago(24h)
| summarize
    RequestCount = count(),
    AvgDurationMs = avg(DurationMs),
    P95DurationMs = percentile(DurationMs, 95),
    ErrorRatePct = round(100.0 * countif(toint(ResultCode) >= 500) / count(), 2)
    by bin(TimeGenerated, 15m), AppRoleName
| order by TimeGenerated desc
```

### 6. Error Rate Spike Detection in the Application Layer

Detect sudden increases in application error rates by comparing the current hour to the rolling baseline.

```kusto
let baseline = AppRequests
    | where TimeGenerated between (ago(7d) .. ago(1d))
    | summarize BaselineErrorRatePct = 100.0 * countif(toint(ResultCode) >= 500) / count()
        by AppRoleName;
AppRequests
| where TimeGenerated > ago(1h)
| summarize
    CurrentErrorRatePct = 100.0 * countif(toint(ResultCode) >= 500) / count(),
    TotalRequests = count()
    by AppRoleName
| join kind=inner baseline on AppRoleName
| extend SpikeRatio = iff(BaselineErrorRatePct > 0, CurrentErrorRatePct / BaselineErrorRatePct, 0.0)
| where SpikeRatio > 2.0 and TotalRequests > 100
| project
    AppRoleName,
    CurrentErrorRatePct = round(CurrentErrorRatePct, 2),
    BaselineErrorRatePct = round(BaselineErrorRatePct, 2),
    SpikeRatio = round(SpikeRatio, 2),
    TotalRequests
```

⚠️ **Production Gotcha**: KQL's `percentile()` and `percentile_tdigest()` are both approximate percentile estimators. `percentile_tdigest()` gives you a t-digest-based approximation that's useful for rollups and merging — it is **not** exact math. For audit-grade or contract-grade SLO reporting, export the raw latency samples and calculate exact percentiles offline.

---

## Alerting Strategy

The goal of alerting is to notify the right person at the right time with enough context to act. In AI workloads, over-alerting is a real danger — GPU utilization spikes, token consumption fluctuations, and latency variance are all normal behaviors that can trigger false alarms if you set thresholds too aggressively.

### What to Alert On (and What Not To)

**Alert on these — they require human action:**
- GPU ECC uncorrectable errors (hardware failure imminent)
- HTTP 429 rate exceeding 5% for more than 10 minutes
- Inference latency P99 exceeding SLO for 15+ minutes
- GPU temperature above 83°C sustained
- Cost spend exceeding daily budget by 20%+
- Zero successful requests for any deployment (complete outage)

**Don't alert on these — they're informational:**
- GPU utilization fluctuations during normal operation
- Single 429 responses (transient throttling is expected)
- Short latency spikes during model cold starts
- Token consumption within 80% of budget (log it, don't page)

### Tiered Alerting

| Tier | Response Time | Channel | Example Trigger |
|------|--------------|---------|-----------------|
| **P1 — Critical** | 5 minutes | PagerDuty / phone | Complete outage, GPU hardware failure, cost runaway |
| **P2 — Warning** | 30 minutes | Slack / Teams | Sustained throttling, latency SLO breach, high error rate |
| **P3 — Info** | Next business day | Email / ticket | Approaching quota limits, cost trending above forecast |

### Auto-Remediation Actions

For predictable failure modes, configure automated responses:

```text
Trigger: HTTP 429 rate > 5% for 10 minutes
  → Action: Scale out to additional Azure OpenAI deployment (load balancer failover)

Trigger: GPU memory > 95% on inference pods
  → Action: Trigger HPA to add inference replicas

Trigger: Request queue depth > 100 for 5 minutes
  → Action: Scale AKS node pool, notify on-call engineer

Trigger: GPU temperature > 83°C
  → Action: Reduce batch size via ConfigMap update, alert infra team
```

💡 **Pro Tip**: Start with alerting only — no auto-remediation. Once you've validated that an alert consistently represents a real problem (not a false alarm), then automate the response. Auto-remediation on a false signal can cause more damage than the original issue.

---

## Dashboards That Tell a Story

A dashboard should answer a specific question for a specific audience. Three dashboards cover most AI infrastructure needs.

### Executive Dashboard — "How is the AI platform performing?"

This dashboard goes to leadership and finance. Keep it high-level and business-oriented.

- **Availability**: SLA compliance percentage (target: 99.9%)
- **Cost**: Daily and monthly GPU and token spend, trend versus budget
- **Usage**: Total requests served, active deployments, user count
- **Incidents**: Open P1/P2 alerts, mean time to resolution (MTTR)

### Engineering Dashboard — "What needs my attention?"

This is the daily driver for the infrastructure and ML platform team.

- **GPU Utilization**: Per-node utilization heatmap, memory pressure
- **Latency Percentiles**: P50/P95/P99 by deployment, with SLO reference lines
- **Error Rates**: 4xx and 5xx by endpoint, with spike annotations
- **Throughput**: Requests per second and tokens per second, by model
- **Queue Depth**: Pending requests waiting for GPU resources

### Capacity Dashboard — "When do we need to scale?"

This dashboard supports capacity planning and procurement decisions.

- **Quota Usage**: Current GPU quota consumption versus limits, by region
- **Scaling Headroom**: How many additional pods/nodes can be added before hitting limits
- **Growth Projection**: Request volume trendline with 30/60/90-day forecast
- **Token Budget Burn Rate**: Days remaining at current consumption rate

**Decision Matrix — Dashboard Design**

| Audience | Refresh Rate | Data Retention | Key Questions |
|----------|-------------|---------------|---------------|
| **Executives** | Hourly | 90 days | "Are we on budget? Are users happy?" |
| **Engineers** | Real-time (30s) | 30 days | "What's broken? What's degrading?" |
| **Capacity planners** | Daily | 180 days | "When do we run out of headroom?" |

---

## Hands-On: Set Up GPU Monitoring with Prometheus and Grafana

This walkthrough takes you from a bare AKS cluster with GPU nodes to a fully instrumented monitoring stack. Estimated time: 20 minutes.

### Prerequisites

- AKS cluster with GPU node pool (see Chapter 3)
- `kubectl` and `helm` configured
- Azure CLI authenticated

### Step 1: Enable Azure Managed Prometheus and Grafana

```bash
# Create an Azure Monitor workspace
az monitor account create \
  --name ai-monitor-workspace \
  --resource-group myResourceGroup \
  --location eastus

# Create an Azure Managed Grafana instance
az grafana create \
  --name ai-grafana \
  --resource-group myResourceGroup \
  --location eastus

# Enable Managed Prometheus on your AKS cluster
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id \
    "/subscriptions/<sub-id>/resourceGroups/myResourceGroup/providers/Microsoft.Monitor/accounts/ai-monitor-workspace" \
  --grafana-resource-id \
    "/subscriptions/<sub-id>/resourceGroups/myResourceGroup/providers/Microsoft.Dashboard/grafana/ai-grafana"
```

### Step 2: Deploy DCGM Exporter

```bash
# Add the NVIDIA Helm repository
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Install DCGM Exporter
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-monitoring \
  --create-namespace \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.interval=15s

# Verify pods are running on GPU nodes
kubectl get pods -n gpu-monitoring -o wide
```

### Step 3: Enable the Managed GPU Metrics Scrape Profile

On AKS, use the Azure Monitor agent's `ama-metrics-settings-configmap` to enable the built-in `dcgmexporter` scrape profile:

```yaml
# ama-metrics-settings-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ama-metrics-settings-configmap
  namespace: kube-system
data:
  schema-version: v1
  config-version: ver1
  default-scrape-settings-enabled: |-
    dcgmexporter = true
```

```bash
kubectl apply -f ama-metrics-settings-configmap.yaml
```

### Step 4: Import GPU Dashboard in Grafana

```bash
# Get Grafana endpoint URL
az grafana show \
  --name ai-grafana \
  --resource-group myResourceGroup \
  --query "properties.endpoint" -o tsv
```

Navigate to the Grafana URL and import the NVIDIA DCGM dashboard:

1. Go to **Dashboards → Import**
2. Enter dashboard ID **12239** (NVIDIA DCGM Exporter community dashboard)
3. Select your Azure Managed Prometheus data source
4. Click **Import**

You should now see GPU utilization, memory usage, temperature, power draw, and ECC error panels updating in real time.

### Step 5: Verify Metrics Are Flowing

```bash
# Query Prometheus for DCGM metrics via kubectl
kubectl run prom-test --rm -it --image=curlimages/curl -- \
  curl -s "http://dcgm-exporter.gpu-monitoring:9400/metrics" | head -20
```

You should see metric lines like `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`, and `DCGM_FI_DEV_TEMPERATURE` with current values.

⚠️ **Production Gotcha**: DCGM Exporter requires the NVIDIA GPU driver and DCGM libraries to be present on the host. On AKS managed GPU node pools, verify that the NVIDIA GPU components are actually installed on the nodes before you troubleshoot scraping. If `dcgm-exporter` pods are crashing, first check the GPU node pool status and then inspect the NVIDIA-managed pods on the cluster with `kubectl get pods -A | grep -i nvidia`.

---

## Chapter Checklist

Before moving on, verify you have these capabilities in place:

- **GPU metrics flowing** — DCGM Exporter deployed, Prometheus scraping, Grafana visualizing
- **Azure OpenAI monitoring** — TPM/RPM tracked, 429 alerting configured, TTFT measured
- **Distributed tracing** — OpenTelemetry instrumented across your inference pipeline
- **KQL queries saved** — Throttling, latency, error rate, and token consumption queries bookmarked
- **Tiered alerting** — P1/P2/P3 alerts defined with appropriate channels and response times
- **Cost visibility** — Token consumption and GPU spend tracked per team/project/deployment
- **Three dashboards** — Executive (cost/SLA), Engineering (latency/errors), Capacity (quotas/scaling)
- **Security monitoring** — Access patterns and anomalous usage tracked
- **Auto-remediation** — At least one automated response for a validated failure mode
- **No alert fatigue** — Alert thresholds tuned to minimize false alarms

---

## What's Next

You can now see everything happening in your AI infrastructure. Every GPU, every token, every latency spike, every cost anomaly — you have the visibility to detect problems before they become outages and the dashboards to communicate platform health to any audience.

But seeing isn't enough — you need to protect it. AI systems introduce attack surfaces that traditional infrastructure never had: prompt injection, model extraction, training data poisoning, and adversarial inputs that bypass your safety filters. Chapter 8 covers security in AI environments — the new threats AI brings, and the infrastructure controls that stop them.
