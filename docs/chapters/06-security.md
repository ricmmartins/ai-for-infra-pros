# Chapter 6 — Security and Resilience in AI Environments

> “Powerful models require equally strong protections.”

---

## 🎯 Why AI Security Is Different

AI workloads introduce new and unique risks:
- **Data leakage** (PII or intellectual property)
- **Prompt injection** or model manipulation
- **Abuse of inference APIs**
- **Unexpected GPU cost spikes**
- **Downtime in mission-critical decision systems**

AI doesn’t run in isolation — it depends on secure, resilient, and auditable infrastructure.  
That’s where infrastructure engineers shine.

---

## 🔐 Core Security Pillars for AI

| Pillar | Applied to AI |
|---------|----------------|
| **Identity & Access** | Who can access models, data, and GPUs? |
| **Data Security** | Encryption, DLP, data classification |
| **API Protection** | Auth, throttling, validation of inference requests |
| **Secrets Management** | Keys, credentials, and tokens |
| **Governance** | Auditing, compliance, environment isolation |

---

## 👤 Identity and Access Control

- Use **Azure RBAC** for VMs, AKS, AML, and storage.
- Prefer **User-Assigned Managed Identity** for pipelines.
- Enforce **Conditional Access** and MFA for dashboards and endpoints.
- Avoid static keys — use federated identities via OIDC.

---

## 🔒 Data Protection

| Action | Azure Feature |
|---------|----------------|
| **Encryption at rest** | Server-Side Encryption (SSE) enabled by default |
| **Encryption in transit** | Enforce HTTPS, TLS 1.2+ |
| **Data classification** | Microsoft Purview |
| **Environment isolation** | VNets, NSGs, and separate workspaces |
| **Model/data backups** | Azure Backup, snapshots, GitHub repos |

💡 **Best practices:**
- Never expose model endpoints without authentication.
- Use **SAS tokens with short TTL** for temporary dataset access.
- Store secrets only in **Key Vault**, never in code.

---

## 🧬 Securing Models and Inference APIs

| Risk | Recommended Mitigation |
|------|------------------------|
| **Prompt Injection / Jailbreaks** | Input sanitization, parameter validation |
| **Model Abuse / Overuse** | Auth + Rate limiting |
| **Model Extraction (stealing)** | Limit requests per IP/token |
| **Unauthorized GPU access** | Taints, tolerations, RBAC in AKS / AML |

---

## 🛡️ Building Resilience for AI Workloads

1. **Availability Zones:** deploy across multiple zones/regions.  
2. **Azure Front Door / App Gateway:** load balancing + health probes.  
3. **Auto-scaling:** use GPU metrics, latency, and QPS thresholds.  
4. **Container probes:** restart on failed inference.  
5. **Retry and fallback logic:** ensure continuity for critical endpoints.

---

## 🧪 Example — Restricting Endpoint Access

```bash
az ml online-endpoint update \
  --name my-endpoint \
  --resource-group rg-ai \
  --set public_network_access=disabled
```

✅ Allow access only via private VNet and firewall rules.

---

## ⚙️ Resilience Patterns

| Component | Strategy |
|------------|-----------|
| **Storage** | Geo-redundant or zone-redundant replication |
| **Compute** | Multiple node pools (GPU + CPU) |
| **API** | Front Door failover between regions |
| **Pipeline** | Retry policy + circuit breaker pattern |

---

## 🧠 AI Security ≠ Traditional Security

| Traditional Security | AI Security Adds |
|----------------------|------------------|
| Protect servers & networks | Protect *models* and *data flows* |
| Monitor login attempts | Monitor token usage and inference logs |
| Patch management | Model version control and drift detection |
| Firewall rules | API-level filters and input validation |

---

## 📋 Security & Resilience Checklist

| Item | Status |
|-------|--------|
| Managed identities, no static keys | ✅ |
| Data & models encrypted | ✅ |
| Rate limiting and API auth | ✅ |
| Access logs enabled | ✅ |
| Deployment in private VNet | ✅ |
| Prompt injection testing performed | ✅ |
| Model backups isolated | ✅ |

---

## ✅ Conclusion

AI infrastructure must be both **secure and resilient**.  
Your expertise in segmentation, high availability, and access control is vital to make AI reliable.  
You don’t need to know everything about LLMs — but you must ensure they run safely, efficiently, and continuously.

Next: [Chapter 7 — AI Use Cases for Infrastructure Engineers](07-use-cases.md)

