# AI for Infra Pros

### The Practical Handbook for Infrastructure Engineers Entering the AI Era

[![Deploy MkDocs](https://github.com/ricmmartins/ai-for-infra-pros/actions/workflows/deploy-mkdocs.yml/badge.svg)](https://github.com/ricmmartins/ai-for-infra-pros/actions/workflows/deploy-mkdocs.yml)

🌐 **Disponível em Português (Brasil):** [Leia em Português](https://github.com/ricmmartins/ai-for-infra-pros/tree/pt-br)

> *"You don't need to be a data scientist to work with AI— but you do need to understand how it runs, scales, breaks, and costs money."*

**Read online at [www.ai4infra.com](https://www.ai4infra.com)**

![AI for Infra Pros](/docs/images/ai4infrapros.png "AI for Infra Pros")

---

## About This Book

Every AI model that reaches production sits on top of infrastructure someone had to build, scale, secure, and keep running. That someone is you.

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

## Table of Contents

### Part I — Foundations

| # | Chapter | Description |
|---|---------|-------------|
| 1 | [Why AI Needs You](docs/chapters/01-introduction.md) | The infrastructure engineer's case for entering the AI world |
| 2 | [Data: The Fuel That Powers Everything](docs/chapters/02-data.md) | Storage architecture, I/O bottlenecks, and data lifecycle for AI |
| 3 | [Compute: Where Intelligence Comes to Life](docs/chapters/03-compute.md) | GPU VM families, clustering, InfiniBand, and distributed training |
| 4 | [The GPU Deep Dive](docs/chapters/04-gpu-deep-dive.md) | CUDA, memory hierarchy, multi-GPU strategies, nvidia-smi, and debugging |

### Part II — Building and Automating

| # | Chapter | Description |
|---|---------|-------------|
| 5 | [Infrastructure as Code for AI](docs/chapters/05-iac.md) | Terraform, Bicep, GitHub Actions, and governance for AI infrastructure |
| 6 | [Model Lifecycle and MLOps from an Infra Lens](docs/chapters/06-mlops.md) | Model registries, CI/CD for models, A/B testing, and supply chain security |

### Part III — Operating and Securing

| # | Chapter | Description |
|---|---------|-------------|
| 7 | [Monitoring and Observability for AI Workloads](docs/chapters/07-monitoring.md) | GPU metrics, Azure OpenAI monitoring, KQL queries, and alerting strategy |
| 8 | [Security in AI Environments](docs/chapters/08-security.md) | Identity, secrets, network isolation, content safety, and resilience |
| 9 | [Cost Engineering for AI Workloads](docs/chapters/09-cost-engineering.md) | GPU cost modeling, spot VMs, PTU economics, and FinOps practices |

### Part IV — Scaling and Troubleshooting

| # | Chapter | Description |
|---|---------|-------------|
| 10 | [AI Platform Operations at Scale](docs/chapters/10-platform-ops.md) | Multi-tenancy, GPU scheduling, SLA design, and fleet management |
| 11 | [Azure OpenAI: Tokens, Throughput, and Provisioned Capacity](docs/chapters/11-azure-openai.md) | TPM, RPM, PTU, throttling mitigation, and high-availability patterns |
| 12 | [The Production Troubleshooting Playbook](docs/chapters/12-troubleshooting.md) | 10 real failure scenarios with symptoms, diagnosis, and resolution |

### Part V — Strategy and Reference

| # | Chapter | Description |
|---|---------|-------------|
| 13 | [AI Use Cases for Infrastructure Engineers](docs/chapters/13-ai-use-cases.md) | Predictive failure, ops copilots, career paths, and a 30-day plan |
| 14 | [The AI Adoption Framework](docs/chapters/14-adoption-framework.md) | A 6-phase roadmap from AI-curious to AI-capable |
| 15 | [Visual Glossary: Infra to AI Translation Guide](docs/chapters/15-visual-glossary.md) | 55+ AI terms explained through infrastructure analogies |

---

## Quick Start Guide

Each chapter is self-contained. Pick your starting point based on what you need:

| Your Goal | Start Here |
|-----------|------------|
| Understand how AI connects to your skills | [Chapter 1 — Why AI Needs You](docs/chapters/01-introduction.md) |
| Provision your first GPU VM | [Chapter 3 — Compute](docs/chapters/03-compute.md) |
| Understand GPU memory and OOM errors | [Chapter 4 — The GPU Deep Dive](docs/chapters/04-gpu-deep-dive.md) |
| Automate AI infrastructure with IaC | [Chapter 5 — Infrastructure as Code](docs/chapters/05-iac.md) |
| Set up monitoring for AI workloads | [Chapter 7 — Monitoring and Observability](docs/chapters/07-monitoring.md) |
| Control AI costs before they control you | [Chapter 9 — Cost Engineering](docs/chapters/09-cost-engineering.md) |
| Fix a production issue right now | [Chapter 12 — Troubleshooting Playbook](docs/chapters/12-troubleshooting.md) |
| Translate an AI term you just heard | [Chapter 15 — Visual Glossary](docs/chapters/15-visual-glossary.md) |
| Get hands-on with labs | [Hands-On Labs](docs/extras/labs/) |

---

## Extras

| Resource | Description |
|----------|-------------|
| [Hands-On Labs](docs/extras/labs/) | GPU VM with Bicep, AKS GPU cluster with Terraform, inference API with Azure ML |
| [Case Studies](docs/extras/case-studies.md) | 5 production scenarios with quantified outcomes |
| [Cheatsheets](docs/extras/cheatsheets.md) | GPU SKU comparison, security checklist, monitoring metrics, deploy commands |
| [Technical FAQ](docs/extras/technical-faq.md) | Answers to the most common questions from infra engineers entering AI |

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

## By the Numbers

| Metric | Value |
|--------|-------|
| Chapters | 15 (organized in 5 parts) |
| Total words | ~61,000 |
| Estimated pages | 220+ |
| Hands-on labs | 3 |
| Troubleshooting scenarios | 10 |
| AI terms in glossary | 55+ |
| CLI commands validated against MS Learn | All of them |

---

## Repository Structure

```text
ai-for-infra-pros/
├── docs/
│   ├── chapters/              # 15 chapters organized in 5 parts
│   ├── extras/
│   │   ├── labs/              # 3 hands-on labs (Bicep, Terraform, Azure ML)
│   │   ├── case-studies.md
│   │   ├── cheatsheets.md
│   │   └── technical-faq.md
│   ├── images/
│   ├── stylesheets/           # Custom CSS for the website
│   └── index.md               # Website landing page
├── .github/workflows/         # GitHub Actions for auto-deploy
├── mkdocs.yml                 # MkDocs Material configuration
├── requirements-docs.txt      # Python dependencies
├── README.md
└── SUMMARY.md
```

---

## Credits

Created by **Ricardo Martins**
Principal Solutions Engineer @ Microsoft
Author of [*Azure Governance Made Simple*](https://book.azgovernance.com/), [*Linux Hackathon*](https://linuxhackathon.com/), [*K8s Hackathon*](https://k8shackathon.com/) and [*From Server to Cluster*](https://fromservertocluster.com/)
[rmmartins.com](https://rmmartins.com)

---

**Disclaimer:** This is an independent, personal project — not an official Microsoft publication. The views and content are solely the author's own. While many examples use Azure, the concepts, architectures, and operational practices in this book apply to any cloud platform — AWS, GCP, or on-premises.

---

> *"AI needs infrastructure. And infrastructure needs engineers who understand AI. This book is the bridge."*
