# Chapter 11 — Azure OpenAI: Tokens, Throughput, and Provisioned Capacity

> "The model is the easy part. Keeping it fast, available, and within budget at scale — that's the infrastructure challenge."

---

## The 429 That Changed Everything

Your team launched an internal GPT-4o chatbot on a Monday. Day one: smooth sailing, enthusiastic Slack messages, demos for leadership. Day three: users start reporting "the bot is slow." Day five: 30 percent of requests return HTTP 429 errors. You pull up Azure Monitor and discover you're hitting the 80K TPM quota ceiling. The data science team's response? "Just increase the limit."

But it's not that simple. Quota increases aren't instant, and throwing more TPM at the problem doesn't address the underlying design. Some requests are consuming 4,000 tokens for a question that could be answered in 200. The system prompt alone is 1,800 tokens — copied from a blog post and never trimmed. Retry logic is hammering the endpoint with no backoff, turning a throttling event into a cascading failure.

What you need isn't a bigger pipe. You need to understand how Azure OpenAI measures, limits, and bills for capacity — and how to architect around those constraints. That's what this chapter delivers. By the end, you'll speak the capacity planning language of Azure OpenAI as fluently as you speak VM sizing and network bandwidth.

---

## Token Fundamentals

Before you can plan capacity for Azure OpenAI, you need to understand tokens — the fundamental unit of work for large language models.

### What Is a Token?

A token is a piece of a word. Large language models don't process text character by character or word by word — they break text into subword fragments called tokens. In English, one token is roughly four characters or three-quarters of a word. The word "infrastructure" becomes three tokens. The word "the" is one token. A code snippet like `kubectl get pods` might be five or six tokens.

This matters because everything in Azure OpenAI is measured in tokens: billing, throughput limits, context windows, and rate limiting. When you send a request to the API, the total token count is the sum of input tokens (your prompt, system message, and any context) plus output tokens (the model's response). Both directions count.

### Estimating Token Counts

For capacity planning, use these rules of thumb:

| Text Type | Approximate Tokens per 1,000 Characters |
|---|---|
| English prose | ~250 tokens |
| Source code | ~300–350 tokens |
| Structured data (JSON, XML) | ~350–400 tokens |
| Mixed content (RAG context) | ~280 tokens |

A practical formula for a single request:

```
Total Tokens = System Prompt Tokens + User Input Tokens + Output Tokens
```

For a typical chatbot interaction — 500-token system prompt, 300-token user question, 800-token response — you're consuming 1,600 tokens per request. Multiply that by your concurrent user base and requests per minute, and you have your throughput requirement.

### Context Window Sizes

Each model has a maximum context window — the upper limit on total tokens in a single request (input plus output combined):

| Model | Context Window |
|---|---|
| GPT-4o | 128K tokens |
| GPT-4o-mini | 128K tokens |
| GPT-4 Turbo | 128K tokens |
| GPT-3.5 Turbo | 16K tokens |

A large context window doesn't mean you should fill it. Every token in the context window counts against your TPM quota. A single 100K-token request with a RAG-stuffed prompt consumes as much throughput as 62 shorter 1,600-token requests.

🔄 **Infra ↔ AI Translation**: Think of tokens as the packet payload of AI. TPM is your bandwidth ceiling — the total data throughput you can push through per minute. RPM is your packets-per-second limit. Just like networking, you can be bandwidth-constrained (large payloads, few requests) or PPS-constrained (small payloads, many requests). Same diagnostic thinking, different units.

---

## Deployment Types — The Critical Decision

When you create an Azure OpenAI deployment, you're making an architectural decision that determines your cost model, throughput guarantees, and failure modes. Azure OpenAI offers several deployment types, and choosing the wrong one is the most common capacity planning mistake teams make.

### 📊 Decision Matrix: Standard vs Global Standard vs Provisioned (PTU)

| Characteristic | Standard | Global Standard | Provisioned (PTU) |
|---|---|---|---|
| **Billing model** | Pay per token | Pay per token | Fixed monthly cost per PTU |
| **Throughput** | Quota-limited (TPM/RPM) | Quota-limited, higher defaults | Guaranteed reserved capacity |
| **Latency** | Variable (shared infra) | Variable (Microsoft-routed) | Predictable, low variance |
| **Data residency** | Single region | Microsoft selects region | Single region |
| **Throttling** | 429 when quota exceeded | 429 when quota exceeded | No throttling within PTU capacity |
| **Capacity guarantee** | ❌ Best-effort | ❌ Best-effort | ✅ Reserved and guaranteed |
| **Minimum commitment** | None | None | Typically monthly |
| **Best for** | Dev/test, variable workloads | Global apps, higher default limits | Production, SLA-bound apps |

### Standard Deployments

Standard deployments are pay-per-token with rate limits expressed as TPM (Tokens Per Minute) and RPM (Requests Per Minute) quotas. You set these quotas when creating the deployment, drawing from a per-subscription, per-region, per-model pool. If your subscription has 300K TPM quota for GPT-4o in East US, you can split that across multiple deployments — say, 200K for production and 100K for development.

Standard is the right choice when workloads are unpredictable or bursty. You pay only for what you consume. The trade-off: during peak demand, latency increases and 429 errors are possible. There's no dedicated infrastructure behind your deployment — you're sharing capacity with other Azure OpenAI customers in that region.

### Global Standard Deployments

Global Standard uses the same pay-per-token pricing but routes requests across Microsoft's global infrastructure. You don't choose which region handles a specific request — Microsoft manages routing for optimal availability. This typically results in higher default quotas and better availability during regional capacity pressure.

The trade-off is data residency. If your compliance requirements mandate that data stays in a specific region, Global Standard isn't an option. For most internal-facing applications without regulatory constraints, it's a strong default choice.

### Data Zone Deployments

Data Zone deployments offer a middle ground for data residency. Traffic stays within a defined geographic boundary (for example, the US or Europe) but can be routed between regions within that boundary. This gives you some of the availability benefits of Global Standard while keeping data within a compliance-friendly geography.

### Provisioned Throughput Units (PTU)

PTU deployments reserve dedicated inference capacity for your workload. You purchase a fixed number of Provisioned Throughput Units, each representing a specific amount of model processing capacity. The key benefit: no throttling. If your workload fits within your provisioned capacity, every request is served without 429 errors and with consistent, predictable latency.

PTU makes sense when you need SLA-level guarantees — customer-facing copilots, revenue-generating applications, or workloads where a 429 error has direct business impact. It also makes sense at scale: once your Standard consumption is high enough, PTU becomes more cost-effective because you're paying a flat rate regardless of usage.

⚠️ **Production Gotcha**: PTU throughput varies by model, prompt length, and generation length. A PTU configured for GPT-4o doesn't deliver a fixed TPM number — throughput depends on the mix of input and output tokens in your actual workload. Never hardcode TPM-per-PTU ratios from documentation. Use the [Azure OpenAI capacity calculator](https://oai.azure.com/portal/calculator) with your real traffic patterns to estimate PTU requirements, and validate with load testing before committing.

### Choosing the Right Deployment Type

Use this decision flow:

1. **Variable, low-volume, or experimental workload?** → Standard or Global Standard
2. **Need higher default quotas, no data residency constraints?** → Global Standard
3. **Data residency within a geography (US, EU)?** → Data Zone
4. **Production workload with SLA requirements, or consistently high volume?** → Provisioned (PTU)
5. **Critical production with overflow capacity needed?** → PTU primary + Standard overflow (see High-Availability Architecture)

💡 **Pro Tip**: Many production architectures combine deployment types. Route baseline traffic to PTU for guaranteed latency and overflow traffic to Standard or Global Standard during peaks. API Management makes this routing straightforward — we'll cover the pattern later in this chapter.

---

## Understanding Throttling

Throttling is the first capacity problem you'll encounter with Azure OpenAI, and it's the most misunderstood. Two independent limits control your throughput, and hitting either one triggers throttling.

### TPM — Tokens Per Minute

TPM is the total throughput ceiling. It caps the aggregate number of tokens — input and output combined — that your deployment can process per minute. If your deployment has an 80K TPM quota and you send requests totaling 85K tokens in a one-minute window, the requests that push you past 80K are rejected with HTTP 429.

### RPM — Requests Per Minute

RPM caps the number of individual API calls per minute, regardless of how many tokens each request contains. Azure OpenAI sets a default RPM derived from your TPM allocation (typically TPM ÷ 6 for chat models), but the actual binding limit depends on your workload shape.

### Why You Hit One Before the Other

Understanding which limit you'll hit first is critical for diagnostics:

- **Many small requests** (autocomplete, classification, short Q&A): You hit RPM before TPM. Each request uses few tokens, but the sheer volume of calls exceeds the request count limit.
- **Few large requests** (RAG with large context, document summarization): You hit TPM before RPM. Each request is token-heavy, so you exhaust the token budget long before hitting the request count ceiling.

This distinction matters because the fix is different. RPM-bound workloads benefit from request batching or consolidation. TPM-bound workloads benefit from shorter prompts, smaller context windows, or simply more TPM quota.

### The 429 Response

When throttling occurs, Azure OpenAI returns an HTTP 429 with a `Retry-After` header indicating how many seconds to wait before retrying. A well-designed client respects this header. A poorly designed client ignores it, retries immediately, and amplifies the problem — every rejected retry counts against your quota window too.

### Retry Strategy: Exponential Backoff with Jitter

The correct retry pattern for 429 responses:

```
wait_time = min(base_delay × 2^attempt + random_jitter, max_delay)
```

| Attempt | Base Delay | Backoff | Jitter (example) | Total Wait |
|---|---|---|---|---|
| 1 | 1s | 2s | +0.3s | ~2.3s |
| 2 | 1s | 4s | +0.7s | ~4.7s |
| 3 | 1s | 8s | +0.1s | ~8.1s |
| 4 | 1s | 16s | +0.5s | ~16.5s |

Jitter prevents the "thundering herd" problem where multiple clients retry simultaneously, creating another spike. If the `Retry-After` header value is longer than your calculated backoff, always use `Retry-After` instead.

⚠️ **Production Gotcha**: Aggressive retries on Standard deployments can create a feedback loop. The retries themselves consume quota, meaning each retry cycle makes the next one more likely to fail. Cap your retry count (3–5 attempts max), and if the `Retry-After` header exceeds 60 seconds, route the request to a fallback deployment in another region instead of waiting.

---

## Capacity Planning

Capacity planning for Azure OpenAI follows the same principles as any infrastructure sizing exercise: estimate demand, plan for peaks, and build in headroom. The units are just different.

### Estimating TPM Requirements

The core formula:

```
Required TPM = Concurrent Users × Requests per Minute per User × Avg Tokens per Request
```

### Worked Example

Suppose you're deploying a customer support chatbot with these characteristics:

| Parameter | Value |
|---|---|
| Concurrent users | 500 |
| Requests per minute per user | 2 |
| Avg tokens per request (input + output) | 1,500 |

```
Required TPM = 500 × 2 × 1,500 = 1,500,000 TPM (1.5M)
```

That's well above the default quota for most models. You'll need to request a quota increase, split traffic across multiple deployments or regions, or consider PTU.

### Planning for Peaks vs Average

Average TPM is useful for cost modeling. Peak TPM is what determines whether users see 429 errors. Production workloads typically show 2–5× the average during peak periods (Monday mornings, end-of-quarter, product launches). Size your quota for peak, not average.

| Planning Target | Formula | Use For |
|---|---|---|
| Average TPM | Users × RPM × Tokens/Request | Cost estimation, PTU sizing |
| Peak TPM | Average TPM × Peak multiplier (2–5×) | Quota allocation, Standard deployment sizing |
| Burst TPM | Peak TPM + 30% headroom | Production safety margin |

### Quota Increases

Default quotas are starting points, not hard ceilings. You can request quota increases through the Azure Portal under your Azure OpenAI resource → Quotas. Increases are subject to regional capacity availability — popular models in popular regions (GPT-4o in East US) may have longer wait times. Plan ahead and request increases before you need them, not during an outage.

### Multi-Deployment Load Balancing

When a single deployment's quota isn't enough, spread traffic across multiple deployments. You can deploy the same model multiple times within a region (each drawing from the region's quota pool) or across regions. Azure API Management is the natural front door for this pattern — it can round-robin requests, route based on priority, and automatically fail over on 429 responses.

💡 **Pro Tip**: When requesting quota for capacity planning, document your expected peak usage and use case. Quota reviewers approve increases faster when they understand the workload. "We need 2M TPM for a 500-user internal support chatbot with documented peak patterns" gets approved faster than "please increase our quota."

---

## High-Availability Architecture

A production Azure OpenAI deployment needs the same resilience patterns as any critical service: redundancy, failover, and intelligent routing. The difference is that your failure mode is often throttling rather than crashes — and the routing logic needs to be token-aware.

### Multi-Region Deployment Pattern

Deploy the same model in at least two Azure regions. If your primary region hits capacity limits or experiences an outage, traffic routes to the secondary. With Global Standard, Microsoft handles some of this routing automatically. With Standard or PTU, you manage it through your own load balancing layer.

### API Management as Smart Router

Azure API Management (APIM) sits between your application and Azure OpenAI, providing:

- **Retry on 429**: When a backend deployment returns 429, APIM automatically retries against an alternate deployment
- **Load balancing**: Distribute requests across multiple deployments using round-robin or weighted routing
- **Priority routing**: Send critical requests to PTU (guaranteed capacity), overflow to Standard
- **Rate limiting**: Apply per-client or per-application quotas on top of Azure OpenAI quotas
- **Token tracking**: Log token consumption per client for chargeback and cost allocation

### Priority-Based Routing (PTU + Standard)

The most common production pattern combines PTU and Standard deployments:

```
┌─────────────────┐
│   Application    │
└────────┬────────┘
         │
┌────────▼────────┐
│  API Management  │
│  (Smart Router)  │
└───┬─────────┬───┘
    │         │
    ▼         ▼
┌───────┐ ┌──────────┐
│  PTU  │ │ Standard │
│Primary│ │ Overflow │
└───────┘ └──────────┘
```

All traffic routes to the PTU deployment first. If the PTU deployment can't handle the load (or is in maintenance), APIM routes overflow to a Standard deployment. This gives you predictable latency for your baseline traffic and elastic capacity for peaks — without paying PTU prices for burst capacity.

### Circuit Breaker Pattern

When a deployment is consistently returning errors, stop sending it traffic temporarily rather than hammering it with retries. Implement a circuit breaker in your APIM policy:

- **Closed** (normal): All requests route to the deployment
- **Open** (tripped): After N consecutive failures, stop routing to this deployment for a cooldown period
- **Half-Open** (testing): After the cooldown, send a single test request. If it succeeds, close the circuit; if it fails, reopen

This prevents a failing deployment from consuming your retry budget and degrading the experience for all users.

💡 **Pro Tip**: Tag your APIM policies with the deployment type. When the circuit breaker trips on a Standard deployment due to regional capacity pressure, it should fail over to a different region's Standard deployment — not to your PTU deployment, which should be reserved for priority traffic.

---

## Monitoring Azure OpenAI

You can't optimize what you can't measure. Azure OpenAI exposes key metrics through Azure Monitor, and diagnostic logs flow to Log Analytics for deep analysis.

### Key Metrics to Track

| Metric | What It Tells You | Alert Threshold |
|---|---|---|
| Azure OpenAI Requests | Total request count per deployment | Baseline + 50% |
| Generated Completion Tokens | Output tokens consumed | Trending toward quota |
| Processed Prompt Tokens | Input tokens consumed | Trending toward quota |
| Provisioned-managed Utilization (PTU) | Percentage of PTU capacity in use | > 80% |
| HTTP 429 Count | Throttled requests | > 0 in production |
| Time to First Token (TTFT) | Latency before response starts streaming | > 2s for chat workloads |

### KQL Queries for Azure OpenAI Diagnostics

Once you enable diagnostic logging on your Azure OpenAI resource, request data flows to the `AppRequests` table in Log Analytics. Here are queries you'll reach for repeatedly.

**Throttling rate over time (429 errors):**

```kql
AppRequests
| where TimeGenerated > ago(24h)
| where Url contains "openai"
| summarize
    TotalRequests = count(),
    ThrottledRequests = countif(ResultCode == "429"),
    ThrottleRate = round(100.0 * countif(ResultCode == "429") / count(), 2)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**Token consumption by deployment:**

```kql
AppRequests
| where TimeGenerated > ago(24h)
| where Url contains "openai"
| extend
    PromptTokens = toint(Properties["promptTokens"]),
    CompletionTokens = toint(Properties["completionTokens"])
| summarize
    TotalPromptTokens = sum(PromptTokens),
    TotalCompletionTokens = sum(CompletionTokens),
    TotalTokens = sum(PromptTokens) + sum(CompletionTokens),
    RequestCount = count()
    by tostring(Properties["deploymentId"])
```

**Latency percentiles (P50, P95, P99):**

```kql
AppRequests
| where TimeGenerated > ago(1h)
| where Url contains "openai"
| where ResultCode == "200"
| summarize
    P50 = percentile(DurationMs, 50),
    P95 = percentile(DurationMs, 95),
    P99 = percentile(DurationMs, 99),
    AvgDuration = avg(DurationMs)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Alerting Strategy

Set up alerts before you need them:

- **Token utilization > 80%**: Warning — you're approaching your quota ceiling. Start planning for a quota increase or additional deployments.
- **429 rate > 1%**: Critical — users are experiencing failures. Investigate immediately.
- **P95 latency > 5 seconds**: Warning — user experience is degrading, even if requests are succeeding.
- **PTU utilization > 90%**: Critical — your reserved capacity is nearly saturated. Overflow traffic will need a fallback path.

⚠️ **Production Gotcha**: Azure OpenAI metrics in Azure Monitor have a 1–3 minute reporting delay. Don't rely on real-time dashboards for incident response on throttling events. Instead, instrument your application layer (Application Insights, OpenTelemetry) for sub-minute visibility into 429 rates and latency.

---

## Optimization Techniques

Once your Azure OpenAI deployment is instrumented and monitored, optimization becomes a data-driven exercise. Every token you save reduces cost and frees throughput for additional requests.

### Prompt Caching

Azure OpenAI supports prompt caching for repeated prefixes. If your system prompt is identical across requests (and it usually should be), the service caches the processed representation and skips recomputing it on subsequent calls. This reduces both latency and effective token consumption for the cached portion. Prompt caching works automatically when the beginning of your prompt matches a previous request — no configuration required.

### Shorter System Prompts

Every token in your system prompt counts against TPM on every request. An 1,800-token system prompt copied from a tutorial consumes 1,800 tokens even when the user's actual question is 50 tokens. Trim ruthlessly. Most production system prompts can be reduced to 200–400 tokens without losing effectiveness. That's a potential 80% reduction in per-request overhead.

### Response Length Limits

Set the `max_tokens` parameter to cap output length. Without it, the model generates until it hits its natural stopping point — which might be 2,000 tokens when your UI only displays the first 500. For classification tasks (sentiment, category, yes/no), set `max_tokens` to 10–50. For summaries, 200–500. Only leave it uncapped when you genuinely need open-ended generation.

### Model Routing — Right-Size Every Request

Not every request needs GPT-4o. Build a routing layer that matches request complexity to model capability:

| Request Type | Recommended Model | Why |
|---|---|---|
| Classification, tagging, extraction | GPT-4o-mini | Fast, cheap, accurate for structured tasks |
| Short Q&A, FAQ lookup | GPT-4o-mini | Sufficient quality at ~20× lower cost |
| Complex reasoning, code generation | GPT-4o | Higher accuracy justifies higher cost |
| Document summarization, analysis | GPT-4o | Better at nuanced, long-context tasks |

A simple keyword-based or ML-based classifier at the API gateway can route 60–70% of requests to GPT-4o-mini, reducing total token costs significantly.

### Batch API for Non-Real-Time Workloads

Azure OpenAI's Batch API processes requests asynchronously at a 50% discount compared to standard pricing. If your workload doesn't need real-time responses — nightly report generation, bulk document processing, batch classification — use the Batch API. You submit a file of requests and retrieve results later (typically within 24 hours).

### Streaming for Better Perceived Latency

Streaming doesn't reduce total token consumption or cost, but it dramatically improves perceived latency. Instead of waiting for the entire response to generate before displaying anything, the client receives tokens as they're produced. Time to First Token (TTFT) drops from seconds to milliseconds. For interactive applications, always enable streaming.

🔄 **Infra ↔ AI Translation**: Model routing is the AI equivalent of tiered storage. You don't store every file on premium NVMe — you tier based on access patterns and performance requirements. Similarly, you don't route every prompt to GPT-4o. Hot requests (complex, user-facing) get the premium model. Warm requests (simple, background) get the cost-effective one.

---

## Chapter Checklist

Before moving on, verify you've addressed these capacity planning fundamentals:

- ✅ **Token estimation**: You can estimate tokens per request for your workload (system prompt + input + output)
- ✅ **Deployment type selected**: Standard, Global Standard, or PTU — chosen based on workload predictability and SLA requirements
- ✅ **TPM/RPM quotas sized**: Calculated for peak, not average, with headroom
- ✅ **Throttling understood**: You know whether your workload is TPM-bound or RPM-bound, and have retry logic with exponential backoff and jitter
- ✅ **Capacity plan documented**: Concurrent users × requests/min × tokens/request = required TPM, with peak multiplier applied
- ✅ **Multi-region failover configured**: At least two deployments in different regions with API Management routing
- ✅ **Monitoring enabled**: Diagnostic logs flowing to Log Analytics, alerts on 429 rate, latency, and token utilization
- ✅ **Optimization applied**: System prompts trimmed, max_tokens set, model routing implemented for cost-appropriate model selection
- ✅ **Batch API evaluated**: Non-real-time workloads moved to Batch API for 50% cost savings
- ✅ **PTU sizing validated**: If using PTU, throughput tested with real traffic patterns — never relying on hardcoded TPM-per-PTU ratios

---

## What's Next

You now understand the capacity planning language of Azure OpenAI — tokens, throughput models, deployment types, and the architectural patterns that keep production workloads fast and resilient. But what happens when things go wrong — not just throttling, but GPU driver crashes, pod scheduling failures, and inference latency spikes? Chapter 12 is the troubleshooting playbook you'll bookmark.

**Next: [Chapter 12 — Troubleshooting AI Infrastructure](12-troubleshooting.md)**
