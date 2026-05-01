# AI para Profissionais de Infraestrutura

### O Guia Prático para Engenheiros de Infraestrutura Entrando na Era da IA

[![Deploy MkDocs](https://github.com/ricmmartins/ai-for-infra-pros/actions/workflows/deploy-mkdocs.yml/badge.svg)](https://github.com/ricmmartins/ai-for-infra-pros/actions/workflows/deploy-mkdocs.yml)

🌐 **Available in English:** [Read in English](https://github.com/ricmmartins/ai-for-infra-pros/tree/en-us)

> *"Você não precisa ser um cientista de dados para trabalhar com IA — mas precisa entender como ela funciona, escala, quebra e custa dinheiro."*

**Leia online em [www.ai4infra.com](https://www.ai4infra.com)**

![AI para Profissionais de Infraestrutura](/docs/images/ai4infrapros.png "AI para Profissionais de Infraestrutura")

---

## Sobre Este Livro

Todo modelo de IA que chega à produção está sobre uma infraestrutura que alguém precisou construir, escalar, proteger e manter funcionando. Esse alguém é você.

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

## Sumário

### Parte I — Fundamentos

| # | Capítulo | Descrição |
|---|---------|-------------|
| 1 | [Por Que a IA Precisa de Você](docs/chapters/01-introduction.md) | O caso do engenheiro de infraestrutura para entrar no mundo da IA |
| 2 | [Dados: O Combustível Que Move Tudo](docs/chapters/02-data.md) | Arquitetura de armazenamento, gargalos de I/O e ciclo de vida dos dados para IA |
| 3 | [Computação: Onde a Inteligência Ganha Vida](docs/chapters/03-compute.md) | Famílias de VMs GPU, clustering, InfiniBand e treinamento distribuído |
| 4 | [O Mergulho Profundo na GPU](docs/chapters/04-gpu-deep-dive.md) | CUDA, hierarquia de memória, estratégias multi-GPU, nvidia-smi e debugging |

### Parte II — Construindo e Automatizando

| # | Capítulo | Descrição |
|---|---------|-------------|
| 5 | [Infraestrutura como Código para IA](docs/chapters/05-iac.md) | Terraform, Bicep, GitHub Actions e governança para infraestrutura de IA |
| 6 | [Ciclo de Vida de Modelos e MLOps sob a Perspectiva de Infra](docs/chapters/06-mlops.md) | Registros de modelos, CI/CD para modelos, testes A/B e segurança da cadeia de suprimentos |

### Parte III — Operando e Protegendo

| # | Capítulo | Descrição |
|---|---------|-------------|
| 7 | [Monitoramento e Observabilidade para Cargas de Trabalho de IA](docs/chapters/07-monitoring.md) | Métricas GPU, monitoramento Azure OpenAI, consultas KQL e estratégia de alertas |
| 8 | [Segurança em Ambientes de IA](docs/chapters/08-security.md) | Identidade, segredos, isolamento de rede, segurança de conteúdo e resiliência |
| 9 | [Engenharia de Custos para Cargas de Trabalho de IA](docs/chapters/09-cost-engineering.md) | Modelagem de custos GPU, VMs spot, economia de PTU e práticas de FinOps |

### Parte IV — Escalando e Solucionando Problemas

| # | Capítulo | Descrição |
|---|---------|-------------|
| 10 | [Operações de Plataforma de IA em Escala](docs/chapters/10-platform-ops.md) | Multi-tenancy, scheduling GPU, design de SLA e gerenciamento de frota |
| 11 | [Azure OpenAI: Tokens, Throughput e Capacidade Provisionada](docs/chapters/11-azure-openai.md) | TPM, RPM, PTU, mitigação de throttling e padrões de alta disponibilidade |
| 12 | [O Playbook de Troubleshooting de Produção](docs/chapters/12-troubleshooting.md) | 10 cenários reais de falha com sintomas, diagnóstico e resolução |

### Parte V — Estratégia e Referência

| # | Capítulo | Descrição |
|---|---------|-------------|
| 13 | [Casos de Uso de IA para Engenheiros de Infraestrutura](docs/chapters/13-ai-use-cases.md) | Falha preditiva, copilots de operação, caminhos de carreira e plano de 30 dias |
| 14 | [O Framework de Adoção de IA](docs/chapters/14-adoption-framework.md) | Um roadmap de 6 fases de AI-curioso a AI-capaz |
| 15 | [Glossário Visual: Guia de Tradução Infra para IA](docs/chapters/15-visual-glossary.md) | 55+ termos de IA explicados através de analogias de infraestrutura |

---

## Guia de Início Rápido

Cada capítulo é autocontido. Escolha seu ponto de partida baseado no que você precisa:

| Seu Objetivo | Comece Aqui |
|-----------|------------|
| Entender como IA se conecta com suas habilidades | [Capítulo 1 — Por Que a IA Precisa de Você](docs/chapters/01-introduction.md) |
| Provisionar sua primeira VM GPU | [Capítulo 3 — Computação](docs/chapters/03-compute.md) |
| Entender memória GPU e erros OOM | [Capítulo 4 — O Mergulho Profundo na GPU](docs/chapters/04-gpu-deep-dive.md) |
| Automatizar infraestrutura de IA com IaC | [Capítulo 5 — Infraestrutura como Código](docs/chapters/05-iac.md) |
| Configurar monitoramento para cargas de trabalho de IA | [Capítulo 7 — Monitoramento e Observabilidade](docs/chapters/07-monitoring.md) |
| Controlar custos de IA antes que eles controlem você | [Capítulo 9 — Engenharia de Custos](docs/chapters/09-cost-engineering.md) |
| Resolver um problema de produção agora | [Capítulo 12 — Playbook de Troubleshooting](docs/chapters/12-troubleshooting.md) |
| Traduzir um termo de IA que você acabou de ouvir | [Capítulo 15 — Glossário Visual](docs/chapters/15-visual-glossary.md) |
| Praticar com laboratórios | [Laboratórios Práticos](docs/extras/labs/) |

---

## Extras

| Recurso | Descrição |
|----------|-------------|
| [Laboratórios Práticos](docs/extras/labs/) | VM GPU com Bicep, cluster AKS GPU com Terraform, API de inferência com Azure ML |
| [Estudos de Caso](docs/extras/case-studies.md) | 5 cenários de produção com resultados quantificados |
| [Cheatsheets](docs/extras/cheatsheets.md) | Comparação de SKUs GPU, checklist de segurança, métricas de monitoramento, comandos de deploy |
| [FAQ Técnico](docs/extras/technical-faq.md) | Respostas para as perguntas mais comuns de engenheiros de infra entrando na IA |

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

## Em Números

| Métrica | Valor |
|--------|-------|
| Capítulos | 15 (organizados em 5 partes) |
| Total de palavras | ~61.000 |
| Páginas estimadas | 220+ |
| Laboratórios práticos | 3 |
| Cenários de troubleshooting | 10 |
| Termos de IA no glossário | 55+ |
| Comandos CLI validados contra MS Learn | Todos |

---

## Estrutura do Repositório

```text
ai-for-infra-pros/
├── docs/
│   ├── chapters/              # 15 capítulos organizados em 5 partes
│   ├── extras/
│   │   ├── labs/              # 3 laboratórios práticos (Bicep, Terraform, Azure ML)
│   │   ├── case-studies.md
│   │   ├── cheatsheets.md
│   │   └── technical-faq.md
│   ├── images/
│   ├── stylesheets/           # CSS customizado para o website
│   └── index.md               # Página inicial do website
├── .github/workflows/         # GitHub Actions para deploy automático
├── mkdocs.yml                 # Configuração MkDocs Material
├── requirements-docs.txt      # Dependências Python
├── README.md
└── SUMMARY.md
```

---

## Créditos

Criado por **Ricardo Martins**
Principal Solutions Engineer @ Microsoft
Autor de [*Azure Governance Made Simple*](https://book.azgovernance.com/), [*Linux Hackathon*](https://linuxhackathon.com/), [*K8s Hackathon*](https://k8shackathon.com/) e [*From Server to Cluster*](https://fromservertocluster.com/)
[rmmartins.com](https://rmmartins.com)

---

**Aviso:** Este é um projeto independente e pessoal — não uma publicação oficial da Microsoft. As opiniões e o conteúdo são exclusivamente do autor. Embora muitos exemplos usem Azure, os conceitos, arquiteturas e práticas operacionais deste livro se aplicam a qualquer plataforma de nuvem — AWS, GCP ou on-premises.

---

> *"A IA precisa de infraestrutura. E infraestrutura precisa de engenheiros que entendam IA. Este livro é a ponte."*
