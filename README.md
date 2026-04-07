# AI for Infra Pros

### The Practical Handbook for Infrastructure Engineers Entering the AI Era

[![Netlify Status](https://api.netlify.com/api/v1/badges/69d5257f/deploy-status)](https://app.netlify.com/sites/incredible-pastelito-f2ea36/deploys)

> *"You don't need to be a data scientist to work with AI — but you do need to understand how it runs, scales, breaks, and costs money."*

**Read free chapters at [www.ai4infra.com](https://www.ai4infra.com)** · **[Get the full book on Leanpub](https://leanpub.com/ai-for-infra-pros)**

![AI for Infra Pros](/docs/images/ai4infrapros.png "AI for Infra Pros")

---

## About This Book

Every AI model that reaches production sits on top of infrastructure someone had to build, scale, secure, and keep running. That someone is you.

This handbook was born from years of bridging the gap between systems engineering and machine learning. It translates AI concepts into the language infrastructure, cloud, and DevOps engineers already speak — and gives you the practical depth to architect, deploy, monitor, and operate AI workloads at production scale.

**This is not an AI/ML textbook.** It's a practitioner's handbook. Every chapter includes production-grade examples, decision matrices, hands-on labs, and the kind of hard-won lessons that only come from running AI infrastructure in the real world.

---

## 📖 Read for Free

The following chapters are available for free at [www.ai4infra.com](https://www.ai4infra.com):

| Chapter | Description |
|---------|-------------|
| [Chapter 1 — Why AI Needs You](docs/chapters/01-introduction.md) | The infrastructure engineer's case for entering the AI world |
| [Chapter 4 — The GPU Deep Dive](docs/chapters/04-gpu-deep-dive.md) | CUDA, memory hierarchy, multi-GPU strategies, nvidia-smi, and debugging |
| [Chapter 15 — Visual Glossary](docs/chapters/15-visual-glossary.md) | 55+ AI terms explained through infrastructure analogies |
| [Hands-On Labs](docs/extras/labs/) | GPU VM with Bicep, AKS GPU with Terraform, Inference API with Azure ML |

---

## 📕 Get the Full Book

The complete book with all 15 chapters, case studies, cheatsheets, and technical FAQ is available on **[Leanpub](https://leanpub.com/ai-for-infra-pros)** in PDF, ePub, and MOBI formats — with free lifetime updates.

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

| # | Chapter | Available |
|---|---------|-----------|
| 1 | Why AI Needs You | ✦ Free |
| 2 | Data: The Fuel That Powers Everything | Full Book |
| 3 | Compute: Where Intelligence Comes to Life | Full Book |
| 4 | The GPU Deep Dive | ✦ Free |
| 5 | Infrastructure as Code for AI | Full Book |
| 6 | Model Lifecycle and MLOps from an Infra Lens | Full Book |
| 7 | Monitoring and Observability for AI Workloads | Full Book |
| 8 | Security in AI Environments | Full Book |
| 9 | Cost Engineering for AI Workloads | Full Book |
| 10 | AI Platform Operations at Scale | Full Book |
| 11 | Azure OpenAI: Tokens, Throughput, and Provisioned Capacity | Full Book |
| 12 | The Production Troubleshooting Playbook | Full Book |
| 13 | AI Use Cases for Infrastructure Engineers | Full Book |
| 14 | The AI Adoption Framework | Full Book |
| 15 | Visual Glossary: Infra to AI Translation Guide | ✦ Free |

**Extras:** Hands-On Labs (✦ Free) · Case Studies · Cheatsheets · Technical FAQ

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

## Running Locally

This book is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) and deployed automatically to [Netlify](https://www.netlify.com/) on every push.

```bash
# Install dependencies
pip install -r requirements-docs.txt

# Start local development server
mkdocs serve

# Build the site
mkdocs build
```

Visit `http://127.0.0.1:8000` to preview locally.

---

## Repository Structure

```text
ai-for-infra-pros/
├── docs/
│   ├── chapters/              # 15 chapters organized in 5 parts
│   ├── previews/              # Teaser pages for paid chapters
│   ├── extras/
│   │   ├── labs/              # 3 hands-on labs (Bicep, Terraform, Azure ML)
│   │   ├── case-studies.md
│   │   ├── cheatsheets.md
│   │   └── technical-faq.md
│   ├── images/
│   ├── stylesheets/           # Custom CSS for the website
│   └── index.md               # Sales landing page
├── manuscript/                # Leanpub manuscript files
│   ├── Book.txt               # Chapter order for full book
│   ├── Sample.txt             # Free sample chapter list
│   ├── frontmatter.md
│   ├── backmatter.md
│   ├── *.md                   # Leanpub-formatted chapters
│   └── resources/             # Images for Leanpub
├── netlify.toml               # Netlify build configuration
├── mkdocs.yml                 # MkDocs Material configuration
├── requirements-docs.txt      # Python dependencies
├── README.md
└── SUMMARY.md
```

---

## Credits

Created by **Ricardo Martins**
Principal Solutions Engineer @ Microsoft
Author of [*Azure Governance Made Simple*](https://book.azgovernance.com/) and [*Linux Hackathon*](https://linuxhackathon.com/)
[rmmartins.com](https://rmmartins.com)

---

> *"AI needs infrastructure. And infrastructure needs engineers who understand AI. This book is the bridge."*
