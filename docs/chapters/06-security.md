# Chapter 6 — Security and Resilience in AI Environments

> “Powerful models demand equally strong protections.”

---

## 🚨 Why AI Security Is Different

AI environments face unique risks that go beyond traditional application security:

- Leakage of sensitive data (PII, intellectual property, customer data)  
- Model misuse, such as prompt injection and jailbreaks  
- Attacks on inference APIs and quota exploitation  
- Unexpected costs from GPU abuse or token consumption  
- Dependency on critical infrastructure — where failures can halt business decisions  

AI doesn’t run in isolation — it depends on **secure, resilient, and auditable infrastructure**.  
That’s your domain as an infrastructure professional.

---

## 🧱 Security Fundamentals for AI Environments

| Security Pillar | Application in AI |
|------------------|------------------|
| **Identity and Access** | Who can access the model, data, and GPU |
| **Data Protection** | Encryption, DLP, classification, segregation |
| **API Security** | Authentication, rate limiting, WAF, monitoring |
| **Secret Management** | Keys, connections, and tokens stored securely |
| **Governance and Auditability** | Compliance, logging, traceability |

💡 Security in AI isn’t just about firewalls — it’s about **trust, traceability, and ethical use**.

---

## 👤 Identity and Access Control

- Use **Azure RBAC** to control access to resources (VMs, AKS, AML, Storage).  
- Apply **Managed Identities (UAMI)** in pipelines and automated services.  
- Adopt **Azure AD + Conditional Access + MFA** for human authentication.  
- Avoid static keys — prefer **federated identities (OIDC)** and **temporary tokens**.  

```bash
az ad sp create-for-rbac --name "ai-aks-service" --role contributor \
  --scopes /subscriptions/{id}/resourceGroups/rg-ai
```

🔐 **Tip:** Temporary and federated identities drastically reduce credential exposure risks.

---

## 🔑 Secrets and Key Protection

| Resource | Function | Best Practice |
|-----------|-----------|----------------|
| **Azure Key Vault** | Secure storage for keys and secrets | Use RBAC and restrictive access policies |
| **Managed Identity** | Avoids credential exposure | Replaces static passwords in pipelines |
| **API Tokens** | Fine-grained control over usage and billing | Combine with rate limiting |
| **Azure Policy** | Governance for diagnostics and logging | Ensures active logging and compliance |

```bash
az keyvault set-policy --name kv-ai --object-id <principalId> --secret-permissions get list
```

---

## 🔐 Data and Model Protection

| Action | Azure Tool / Service | Note |
|---------|----------------------|------|
| **Encryption at rest** | SSE enabled by default on Storage | Use customer-managed keys (CMK) |
| **Encryption in transit** | TLS 1.2+ and mandatory HTTPS | Include valid certificates in Front Door / Gateway |
| **Data classification** | Microsoft Purview | Identify PII and sensitive data |
| **Environment segregation** | VNets, NSGs, isolated workspaces | Separate dev/test/prod |
| **Model backups** | Azure Backup, Snapshots, Git repos | Include metadata and versioning |

🚫 **Never expose inference endpoints publicly without authentication.**  
Use **Private Endpoints** and **API Management** for control and logging.

---

## ⚔️ Model and Inference Security

| Risk | Recommended Mitigation |
|------|-------------------------|
| **Prompt Injection / Jailbreaks** | Input sanitization, filters, and validation |
| **Model Misuse** | Authentication and rate limiting on APIs |
| **Model Stealing (Reverse Extraction)** | Limit requests per IP/token |
| **GPU Access Abuse** | RBAC + taints/tolerations in AKS |
| **Data Leakage** | Audit logs and anonymize prompts/responses |

💡 Conduct **internal red teaming** to test prompt and response vulnerabilities.

---

## 🛡️ Network Protections

| Resource | Recommended Use |
|-----------|----------------|
| **Private Endpoints** | Private communication with OpenAI, AML, and Storage |
| **NSG + UDR** | Restrict traffic in GPU subnets |
| **Azure Firewall / WAF** | Block payload injection attacks |
| **API Management** | Authentication, quotas, logging, centralized auditing |
| **Front Door / App Gateway** | Load balancing with TLS and health probes |

```bash
az ml online-endpoint update \
  --name my-endpoint \
  --resource-group rg-ai \
  --set public_network_access=disabled
```

🔧 Allow access **only via VNet** with **Private Link** and properly configured firewalls.

---

## 🔁 Resilience: Designing for High Availability

Strategies for inference workloads and critical pipelines:

- **Availability Zones:** Deploy across multiple zones/regions.  
- **Load Balancing:** Use Front Door or Application Gateway.  
- **Intelligent Autoscaling:** Based on GPU usage, latency, or request queues.  
- **Health Probes and Auto-Restart:** For AKS pods and critical containers.  
- **Retry and Fallback:** With alternate models or cached responses.  
- **Disaster Recovery:** Replicate data and models across secondary regions.  

```mermaid
graph LR
  user["User / API Client"] --> APIM["API Management"]
  APIM --> WAF["Web Application Firewall"]
  WAF --> AKS["AKS with GPU"]
  AKS --> OpenAI["Azure OpenAI (Private Endpoint)"]
  AKS --> KV["Key Vault"]
  AKS --> Log["Azure Monitor + Log Analytics"]
  KV --> Storage["Blob with Models / Checkpoints"]
```

---

## 💡 Production Lessons (Real Cases)

❌ Pod froze after 200 requests without readiness probe → ✅ **Fix:** Add health check + auto-restart.  
❌ Key Vault token expired and blocked pipeline → ✅ **Fix:** Use Managed Identity with auto-renewal.  
❌ Logs captured customer prompts → ✅ **Fix:** Mask and anonymize logs.  

🔄 **Test your incidents before they happen.**  
Resilience is built *before* failure.

---

## 🧾 Security and Resilience Checklist

| Item | Status |
|------|---------|
| Managed identities, no static keys | ✅ |
| Models and data encrypted | ✅ |
| API rate limiting and authentication | ✅ |
| Centralized logging and auditing | ✅ |
| Private VNet deployment with NSG | ✅ |
| Prompt injection / abuse testing | 🔲 |
| Model backup and versioning | ✅ |
| Disaster recovery strategy defined | ✅ |

---

## ✅ Conclusion

Security and resilience are what sustain AI in production.  
Without them, even the most advanced model can become a liability.

You don’t need to understand every layer of the model to be essential in AI —  
but you must ensure it operates securely, efficiently, and continuously.

---

### ➡️ Next Chapter

Discover how real-world teams are applying these principles in [**AI Use Cases for Infrastructure Professionals**](07-ai-use-cases.md).
