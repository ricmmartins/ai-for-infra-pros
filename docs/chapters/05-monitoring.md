# Chapter 5 — Monitoring and Observability for AI Workloads

> “You can’t manage what you can’t see — and in AI, that’s especially true.”

---

## 🎯 Why Monitoring AI Is Different

AI systems are not like traditional workloads.  
A VM or API may look “healthy,” yet the model could be:
- Producing **inaccurate predictions**
- Running on **underutilized GPUs**
- Experiencing **hidden latency** that hurts user experience

That’s why observability in AI must cover both **infrastructure** and **model behavior**.

---

## 🔍 What to Monitor in AI Environments

| Layer | Key Metrics |
|--------|--------------|
| **Compute (GPU/CPU)** | Utilization, memory, temperature, uptime |
| **Model (LLM/ML)** | Accuracy, inference latency, error rate |
| **Network** | Throughput, packet loss, jitter |
| **Data** | Quality, freshness, ingestion failures |
| **Cost** | GPU time, tokens per request, request volume |

---

## 🧰 Monitoring Tools in Azure

| Tool | Primary Role |
|------|---------------|
| **Azure Monitor** | Metrics, logs, and alerts across all layers |
| **Log Analytics Workspace** | Store and query logs using KQL |
| **Azure Managed Prometheus** | Collect custom metrics (e.g., GPU, AKS) |
| **Grafana** | Visualize metrics and dashboards |
| **Azure ML Studio** | Monitor model performance and endpoints |
| **Application Insights** | Trace application-level latency and failures |

---

## 🧪 Example — Monitoring GPU Utilization in AKS

### Step 1. Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prom prometheus-community/kube-prometheus-stack
```

### Step 2. Enable NVIDIA DCGM Exporter

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/deployments/kubernetes/dcgm-exporter.yaml
```

### Step 3. Visualize GPU Metrics

In Grafana, add a dashboard showing:
- `DCGM_FI_DEV_GPU_UTIL` → GPU usage  
- `DCGM_FI_DEV_FB_USED` → Memory usage  
- `DCGM_FI_DEV_POWER_USAGE` → Power draw  

✅ **Result:** Real-time visualization of GPU performance per node and pod.

---

## 📊 Tracking Inference Latency

Use **Application Insights** to measure:
- Average and P95 response time (`duration`)
- Success rate
- Correlation between latency and input size

💡 Add telemetry in your API or SDK code:
```python
from opencensus.ext.azure.log_exporter import AzureLogHandler
logger.addHandler(AzureLogHandler(connection_string="InstrumentationKey=..."))
```

---

## 💰 Cost and Efficiency Observability

GPU workloads can easily exceed thousands of dollars monthly.  
To control this:
- Use **Cost Management** for GPU and API spend
- Correlate cost with performance metrics
- Tag resources (`Project=AI`, `Team=ML`) for segmentation

---

## 🧠 Predictive Observability with AI

You can apply AI to observability itself:
- Forecast GPU usage or request load  
- Detect anomalies in logs using **Azure Anomaly Detector**  
- Auto-scale based on model performance or response latency

---

## 🔔 Alerts and Automation

| Event | Action |
|--------|--------|
| GPU usage > 90% for 30 min | Check for data bottlenecks |
| Latency > 1s | Investigate network or model inefficiency |
| Data ingestion failure | Trigger backup pipeline |
| Drop in model accuracy | Re-train or roll back model |

Set these up in **Azure Monitor Action Groups** or via **Logic Apps**.

---

## 🧩 KQL Example — GPU Metric Query

```kql
Perf
| where ObjectName == "GPU Adapter"
| summarize avg(CounterValue) by bin(TimeGenerated, 5m), CounterName
```

---

## 🧠 Key Takeaways for Infrastructure Teams

- GPU is often the **true bottleneck**, not the model.  
- Observability isn’t just uptime — it’s **performance + cost + quality**.  
- Every AI system should log, measure, and alert from **GPU → Model → API → User**.

---

## ✅ Conclusion

Well-monitored AI systems are faster, cheaper, and more reliable.  
A good infra engineer can make AI invisible — because when it works perfectly, no one notices.

Next: [Chapter 6 — Security and Resilience in AI Environments](06-security.md)

