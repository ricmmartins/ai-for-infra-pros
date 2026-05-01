---
hide:
  - navigation
  - toc
---

<div class="hero" markdown>

# AI para Profissionais de Infraestrutura

<p class="subtitle">O Guia Prático para Engenheiros de Infraestrutura Entrando na Era da IA</p>

> *"Você não precisa ser um cientista de dados para trabalhar com IA — mas precisa entender como ela funciona, escala, quebra e custa dinheiro."*

![AI para Profissionais de Infraestrutura](images/ai4infrapros.png){ loading=lazy }

</div>

---

<div class="stats-grid" markdown>

<div class="stat-card" markdown>
<span class="number">15</span>
<span class="label">Capítulos em 5 Partes</span>
</div>

<div class="stat-card" markdown>
<span class="number">61K+</span>
<span class="label">Palavras</span>
</div>

<div class="stat-card" markdown>
<span class="number">220+</span>
<span class="label">Páginas</span>
</div>

<div class="stat-card" markdown>
<span class="number">3</span>
<span class="label">Laboratórios Práticos</span>
</div>

<div class="stat-card" markdown>
<span class="number">10</span>
<span class="label">Cenários de Troubleshooting</span>
</div>

<div class="stat-card" markdown>
<span class="number">55+</span>
<span class="label">Termos de IA no Glossário</span>
</div>

</div>

---

## Sobre Este Livro

Todo modelo de IA que chega à produção está sobre uma infraestrutura que alguém precisou construir, escalar, proteger e manter funcionando. **Esse alguém é você.**

Este guia nasceu de anos de experiência fazendo a ponte entre engenharia de sistemas e aprendizado de máquina. Ele traduz conceitos de IA para a linguagem que engenheiros de infraestrutura, cloud e DevOps já conhecem — e oferece a profundidade prática para arquitetar, implantar, monitorar e operar cargas de trabalho de IA em escala de produção.

**Este não é um livro acadêmico de IA/ML.** É um guia prático. Cada capítulo inclui exemplos de nível de produção, matrizes de decisão, laboratórios práticos e o tipo de lições que só vêm da operação de infraestrutura de IA no mundo real.

---

## O Que Você Vai Aprender

- **Arquitetura GPU e computação** — Famílias de VMs, CUDA cores vs Tensor Cores, interpretação do nvidia-smi e a matemática de memória por trás de erros OOM
- **Pipelines de dados para IA** — Arquitetura de armazenamento, BlobFuse2, staging NVMe e por que I/O é o gargalo oculto
- **Infraestrutura como Código** — Terraform e Bicep prontos para produção para clusters GPU, node pools AKS e CI/CD com OIDC
- **MLOps sob a perspectiva de infra** — Registros de modelos, CI/CD para modelos, infraestrutura de testes A/B e segurança da cadeia de suprimentos
- **Monitoramento e observabilidade** — DCGM, Managed Prometheus, consultas KQL e as seis dimensões de observabilidade de IA
- **Segurança de IA** — Defesa contra injeção de prompt, endpoints privados, identidades gerenciadas e guardrails de segurança de conteúdo
- **Engenharia de custos** — Modelagem de custos GPU, VMs spot para treinamento, economia de PTU e práticas de FinOps
- **Operações de plataforma em escala** — Multi-tenancy, scheduling GPU (Kueue, Volcano), design de SLA e gerenciamento de frota
- **Troubleshooting de produção** — 10 cenários reais de falha com diagnóstico e resolução passo a passo
- **Caminhos de carreira** — AI Infra Engineer, MLOps Engineer, AI Platform Engineer e mais

---

## Guia de Início Rápido

Cada capítulo é autocontido. Escolha seu ponto de partida baseado no que você precisa:

<div class="quick-start-grid" markdown>

<div class="qs-card" markdown>
**Entender como IA se conecta com suas habilidades**
[Capítulo 1 — Por Que a IA Precisa de Você](chapters/01-introduction.md)
</div>

<div class="qs-card" markdown>
**Provisionar sua primeira VM GPU**
[Capítulo 3 — Computação](chapters/03-compute.md)
</div>

<div class="qs-card" markdown>
**Entender memória GPU e erros OOM**
[Capítulo 4 — O Mergulho Profundo na GPU](chapters/04-gpu-deep-dive.md)
</div>

<div class="qs-card" markdown>
**Automatizar infraestrutura de IA com IaC**
[Capítulo 5 — Infraestrutura como Código](chapters/05-iac.md)
</div>

<div class="qs-card" markdown>
**Configurar monitoramento para workloads de IA**
[Capítulo 7 — Monitoramento](chapters/07-monitoring.md)
</div>

<div class="qs-card" markdown>
**Controlar custos de IA antes que eles controlem você**
[Capítulo 9 — Engenharia de Custos](chapters/09-cost-engineering.md)
</div>

<div class="qs-card" markdown>
**Resolver um problema de produção agora**
[Capítulo 12 — Troubleshooting](chapters/12-troubleshooting.md)
</div>

<div class="qs-card" markdown>
**Traduzir um termo de IA que você acabou de ouvir**
[Capítulo 15 — Glossário Visual](chapters/15-visual-glossary.md)
</div>

</div>

---

## Para Quem É Este Livro

Este guia é escrito para profissionais com **5+ anos de experiência em infraestrutura** que são novos em IA mas tecnicamente afiados:

- **Engenheiros de Infraestrutura e Cloud** (Azure, AWS, GCP)
- **Engenheiros DevOps e de Confiabilidade de Sites (SRE)**
- **Arquitetos de Soluções e Cloud**
- **Engenheiros de Plataforma**
- **Profissionais de Segurança e Governança**
- **Engenheiros de Dados** que querem entender o lado de infraestrutura da IA

Nenhum conhecimento prévio de IA/ML é necessário. Cada conceito é explicado através de analogias de infraestrutura que você já conhece.

---

## Trilha de Aprendizado

Este livro faz parte de um ecossistema completo de aprendizado para profissionais de infraestrutura.

<div class="grid cards" markdown>

- :fontawesome-brands-linux: **[Linux Hackathon](https://linuxhackathon.com/)**

    Domine os fundamentos de Linux. 20 desafios práticos.

- :material-book-open-variant: **[From Server to Cluster](https://fromservertocluster.com/)**

    Faça a ponte das suas habilidades Linux para Kubernetes. 15 capítulos.

- :material-kubernetes: **[K8s Hackathon](https://k8shackathon.com/)**

    Maestria em Kubernetes. 20 desafios cobrindo CKA + CKAD + CKS.

- :material-robot: **[AI for Infra Pros](https://ai4infra.com/)** *(Você está aqui)*

    IA/ML para engenheiros de infraestrutura. De GPUs a MLOps.

</div>

---

## Créditos

Criado por **Ricardo Martins**

:fontawesome-solid-briefcase: Principal Solutions Engineer @ Microsoft

:fontawesome-solid-book: Autor de [*Azure Governance Made Simple*](https://book.azgovernance.com/), [*Linux Hackathon*](https://linuxhackathon.com/), [*K8s Hackathon*](https://k8shackathon.com/) e [*From Server to Cluster*](https://fromservertocluster.com/)

:fontawesome-solid-globe: [rmmartins.com](https://rmmartins.com)

---

<div class="disclaimer" markdown>

**Aviso:** Este é um projeto independente e pessoal — não uma publicação oficial da Microsoft. As opiniões e o conteúdo são exclusivamente do autor. Embora muitos exemplos usem Azure, os conceitos, arquiteturas e práticas operacionais deste livro se aplicam a qualquer plataforma de nuvem — AWS, GCP ou on-premises. Se você gerencia infraestrutura, este livro foi escrito para você, independentemente do seu provedor de nuvem.

</div>

---

> *"A IA precisa de infraestrutura. E infraestrutura precisa de engenheiros que entendam IA. Este livro é a ponte."*
