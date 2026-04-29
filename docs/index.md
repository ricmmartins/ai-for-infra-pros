---
hide:
  - navigation
  - toc
---

<div class="hero" markdown>

# AI for Infra Pros

<p class="subtitle">The Practical Handbook for Infrastructure Engineers Entering the AI Era</p>

> *"You don't need to be a data scientist to work with AI — but you do need to understand how it runs, scales, breaks, and costs money."*

![AI for Infra Pros](images/ai4infrapros.png){ loading=lazy }

</div>

---

<div class="stats-grid" markdown>

<div class="stat-card" markdown>
<span class="number">15</span>
<span class="label">Chapters in 5 Parts</span>
</div>

<div class="stat-card" markdown>
<span class="number">61K+</span>
<span class="label">Words</span>
</div>

<div class="stat-card" markdown>
<span class="number">220+</span>
<span class="label">Pages</span>
</div>

<div class="stat-card" markdown>
<span class="number">3</span>
<span class="label">Hands-On Labs</span>
</div>

<div class="stat-card" markdown>
<span class="number">10</span>
<span class="label">Troubleshooting Scenarios</span>
</div>

<div class="stat-card" markdown>
<span class="number">55+</span>
<span class="label">AI Terms in Glossary</span>
</div>

</div>

---

## About This Book

Every AI model that reaches production sits on top of infrastructure someone had to build, scale, secure, and keep running. **That someone is you.**

This handbook was born from years of bridging the gap between systems engineering and machine learning. It translates AI concepts into the language infrastructure, cloud, and DevOps engineers already speak — and gives you the practical depth to architect, deploy, monitor, and operate AI workloads at production scale.

**This is not an AI/ML textbook.** It's a practitioner's handbook. Every chapter includes production-grade examples, decision matrices, hands-on labs, and the kind of hard-won lessons that only come from running AI infrastructure in the real world.

---

## What You'll Learn

- **GPU architecture and compute** — VM families, CUDA cores vs Tensor Cores, nvidia-smi interpretation, and the memory math behind OOM errors
- **Data pipelines for AI** — storage architecture, BlobFuse2, NVMe staging, and why I/O is the hidden bottleneck
- **Infrastructure as Code** — production-ready Terraform and Bicep for GPU clusters, AKS node pools, and CI/CD with OIDC
- **MLOps from an infra lens** — model registries, CI/CD for models, A/B testing infrastructure, and supply chain security
- **Monitoring and observability** — DCGM, Managed Prometheus, KQL queries, and the six dimensions of AI observability
- **AI security** — prompt injection defense, private endpoints, managed identities, and content safety guardrails
- **Cost engineering** — GPU cost modeling, spot VMs for training, PTU economics, and FinOps practices
- **Platform operations at scale** — multi-tenancy, GPU scheduling (Kueue, Volcano), SLA design, and fleet management
- **Production troubleshooting** — 10 real-world failure scenarios with step-by-step diagnosis and resolution
- **Career paths** — AI Infra Engineer, MLOps Engineer, AI Platform Engineer, and more

---

## Quick Start Guide

Each chapter is self-contained. Pick your starting point based on what you need:

<div class="quick-start-grid" markdown>

<div class="qs-card" markdown>
**Understand how AI connects to your skills**
[Chapter 1 — Why AI Needs You](chapters/01-introduction.md)
</div>

<div class="qs-card" markdown>
**Provision your first GPU VM**
[Chapter 3 — Compute](chapters/03-compute.md)
</div>

<div class="qs-card" markdown>
**Understand GPU memory and OOM errors**
[Chapter 4 — The GPU Deep Dive](chapters/04-gpu-deep-dive.md)
</div>

<div class="qs-card" markdown>
**Automate AI infrastructure with IaC**
[Chapter 5 — Infrastructure as Code](chapters/05-iac.md)
</div>

<div class="qs-card" markdown>
**Set up monitoring for AI workloads**
[Chapter 7 — Monitoring](chapters/07-monitoring.md)
</div>

<div class="qs-card" markdown>
**Control AI costs before they control you**
[Chapter 9 — Cost Engineering](chapters/09-cost-engineering.md)
</div>

<div class="qs-card" markdown>
**Fix a production issue right now**
[Chapter 12 — Troubleshooting](chapters/12-troubleshooting.md)
</div>

<div class="qs-card" markdown>
**Translate an AI term you just heard**
[Chapter 15 — Visual Glossary](chapters/15-visual-glossary.md)
</div>

</div>

---

## Who This Book Is For

This handbook is written for professionals with **5+ years of infrastructure experience** who are new to AI but technically sharp:

- **Infrastructure and Cloud Engineers** (Azure, AWS, GCP)
- **DevOps and Site Reliability Engineers**
- **Solutions and Cloud Architects**
- **Platform Engineers**
- **Security and Governance Professionals**
- **Data Engineers** who want to understand the infrastructure side of AI

No prior AI/ML knowledge is required. Every concept is explained through infrastructure analogies you already know.

---

## Credits

Created by **Ricardo Martins**

:fontawesome-solid-briefcase: Principal Solutions Engineer @ Microsoft
:fontawesome-solid-book: Author of [*Azure Governance Made Simple*](https://book.azgovernance.com/), [*Linux Hackathon*](https://linuxhackathon.com/), [*K8s Hackathon*](https://k8shackathon.com/) and [*From Server to Cluster*](https://fromservertocluster.com/)
:fontawesome-solid-globe: [rmmartins.com](https://rmmartins.com)

---

<div class="disclaimer" markdown>

**Disclaimer:** This is an independent, personal project — not an official Microsoft publication. The views and content are solely the author's own. While many examples use Azure, the concepts, architectures, and operational practices in this book apply to any cloud platform — AWS, GCP, or on-premises. If you manage infrastructure, this book was written for you, regardless of your cloud provider.

</div>

---

> *"AI needs infrastructure. And infrastructure needs engineers who understand AI. This book is the bridge."*
