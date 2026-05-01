# Capítulo 1 — Por Que a IA Precisa de Você

> "A melhor infraestrutura de IA que já vi não foi construída por um engenheiro de machine learning. Foi construída por um sysadmin que ficou curioso."

---

## A Mensagem de Segunda-Feira de Manhã

São 8h47 de uma segunda-feira. Você está no meio do seu café, revisando um plano de Terraform para um redesign de rede, quando uma mensagem no Slack ilumina sua tela. É do líder do time de data science:

> *"E aí — precisamos de 8 VMs com GPU provisionadas até quarta-feira para um job de fine-tuning. Também precisamos de um private endpoint para a API de inferência do modelo, e você pode configurar o monitoramento de TPM? Valeu!"*

Você lê duas vezes. VMs com GPU? Fine-tuning? Você sabe o que é um private endpoint — já criou centenas. Monitoramento? Isso é o seu arroz com feijão. Mas o que diabos é "TPM" nesse contexto? Não é Trusted Platform Module — é **Tokens Per Minute** (Tokens por Minuto), uma métrica de throughput para large language models. Você ainda não sabe disso, mas a questão é: todo o resto nesse pedido é pura infraestrutura.

Provisionar compute. Configurar segurança de rede. Montar observabilidade. Você faz isso há anos. A única diferença é o tipo de workload. Este livro existe para preencher essa lacuna — traduzir o que você já sabe para a linguagem da IA, e fazer de você o engenheiro que todo time de IA está desesperado para encontrar.

---

## O Que a IA Realmente É (Do Seu Ponto de Vista)

Vamos cortar o hype. Se você tirar os buzzwords, IA é um workload. Ela consome compute, storage e rede — assim como qualquer outro workload que você já gerenciou. A diferença está no *formato* desse consumo: mais computação paralela, datasets maiores e métricas de desempenho diferentes.

Veja como o panorama da IA se divide, explicado em termos que você já conhece:

**Inteligência Artificial (IA)** é a disciplina ampla. Pense nela como "computação em nuvem" — um enorme guarda-chuva que abrange desde automação simples até sistemas complexos de raciocínio. **Machine Learning (ML)** é um subconjunto em que os sistemas aprendem padrões a partir de dados em vez de serem explicitamente programados. Se IA é "cloud", então ML é "IaaS" — uma camada específica e prática dentro dela. **Deep Learning (DL)** vai mais fundo ainda, usando redes neurais com muitas camadas para lidar com tarefas complexas como reconhecimento de imagens e geração de linguagem. É o equivalente a um serviço altamente otimizado e construído sob medida.

### O Stack de IA: Três Camadas Que Você Já Conhece

Todo sistema de IA se apoia em três pilares, e você vai reconhecê-los imediatamente:

| Camada de IA | O Que Faz | Seu Equivalente em Infraestrutura |
|----------|-------------|-------------------------------|
| **Dados** | Alimenta o modelo com exemplos para aprender | Storage — Blob, Data Lake, NFS, bancos de dados |
| **Modelo** | Aprende padrões e faz previsões | A aplicação — seu binário compilado que roda em compute |
| **Infraestrutura** | Sustenta tudo por baixo | Seu domínio — compute, rede, segurança, observabilidade |

O modelo é a aplicação. Os dados são o que ele consome e produz. A infraestrutura é tudo que faz isso funcionar de forma confiável, segura e em escala. Essa última parte? É você.

### Tradução Infra ↔ IA

Este é o modelo mental que vai acompanhar você ao longo de todo o livro. Quando alguém do time de IA usar um jargão desconhecido, mapeie de volta para o que você já sabe:

| Conceito de IA | Equivalente em Infraestrutura | Por Que o Mapeamento Funciona |
|-----------|--------------------------|-------------|
| Um modelo treinado | Um binário compilado | É um artefato estático produzido por um processo de build, implantado para atender requisições |
| Treinar um modelo | Um batch job | Processo de longa duração, intensivo em compute, que lê dados e produz um artefato de saída |
| Inferência | Uma chamada de API | Uma requisição entra, o modelo processa, uma resposta sai — igual a qualquer microsserviço |
| Fine-tuning | Aplicar um patch em um binário | Você pega um artefato existente e customiza para o seu ambiente |
| Um dataset | Um banco de dados ou data lake | Entrada estruturada da qual o workload depende |
| Um pipeline de treinamento | Um pipeline de CI/CD | Workflow automatizado: ingestão → processamento → build → validação → deploy |
| Model registry | Repositório de artefatos | Armazenamento versionado para artefatos implantáveis (pense no Azure Container Registry, mas para modelos) |
| Cluster de GPUs | Camada de compute de alto desempenho | Hardware especializado alocado para workloads exigentes |

💡 **Dica**: Quando você estiver numa reunião e o time de data science começar a falar sobre "epochs," "hiperparâmetros" e "loss functions," não entre em pânico. Esses são os *ajustes finos deles* — o equivalente aos seus tamanhos de connection pool, TTLs de cache e thresholds de autoscale. Você não precisa dominar os ajustes deles. Você precisa entender o que esses ajustes *exigem da sua infraestrutura*.

---

## Infraestrutura Tradicional vs. Infraestrutura de IA

Aqui vai a boa notícia: infraestrutura de IA não é um planeta estrangeiro. É mais como um bairro novo numa cidade que você já conhece. As ruas seguem o mesmo padrão, os serviços básicos funcionam da mesma forma — mas os prédios parecem diferentes e os inquilinos têm exigências incomuns.

### O Que Muda

| Dimensão | Infraestrutura Tradicional | Infraestrutura de IA | O Que Você Precisa Aprender |
|-----------|---------------------------|-------------------|----------------------|
| **Compute** | CPUs, VMs de propósito geral | GPUs (NVIDIA T4, A100, H100), nós multi-GPU | Famílias de SKU de GPU, compatibilidade CUDA, vGPU vs. passthrough |
| **Storage** | SSD/HDD, SAN/NAS, managed disks | Data Lakes, Blob com tiers de alto throughput, NVMe local para scratch | Padrões de I/O para treinamento (leituras sequenciais), armazenamento de checkpoints |
| **Rede** | Ethernet 1–25 GbE, load balancers | InfiniBand (até 400 Gb/s), RDMA, comunicação GPU-to-GPU | Topologias de treinamento multi-nó, configuração NCCL |
| **Deploy** | VMs, App Services, containers | Inference endpoints, model-as-a-service, containers com GPU | Endpoints gerenciados vs. self-hosted, comportamento de cold start |
| **Observabilidade** | CPU %, memória, disk I/O, latência de requisição | Utilização de GPU, uso de VRAM, tokens/segundo, time-to-first-token | Novas categorias de métricas, coleta de telemetria específica de GPU |
| **Modelo de Custo** | $/hora por VM, reservas de instância | $/hora por GPU (10-30× o custo de CPU), PTUs para serviços gerenciados de IA | Governança de custos específica para GPU, agendamento, auto-shutdown |

### O Que Permanece Igual

Isso é igualmente importante — talvez até mais. Esses fundamentos não mudam só porque o workload roda em GPUs:

- **Segurança**: Segmentação de rede, private endpoints, gerenciamento de identidade, criptografia em repouso e em trânsito. Uma VM com GPU ainda precisa de um NSG. Uma API de inferência ainda precisa de autenticação.
- **Rede**: VNets, subnets, DNS, load balancing, conectividade privada. Os pacotes continuam fluindo da mesma forma.
- **Infraestrutura como Código**: Bicep, Terraform, templates ARM. VMs com GPU ainda são recursos do Azure com propriedades e parâmetros.
- **Monitoramento e alertas**: Você ainda define thresholds, constrói dashboards e responde a incidentes. As métricas apenas têm nomes diferentes.
- **Resposta a incidentes**: Quando a API de inferência do modelo cai às 2 da manhã, alguém ainda precisa fazer a triagem. Esse alguém deveria ser você.
- **Gestão de custos**: Orçamentos, tagging, right-sizing, capacidade reservada. Se tem algo diferente, é que a governança de custos é *ainda mais* crítica com workloads de IA.

⚠️ **Pegadinha de Produção**: Não assuma que workloads de IA precisam de ferramentas totalmente novas. Times frequentemente investem demais em "plataformas de ML" especializadas enquanto ignoram a higiene básica de infraestrutura. As falhas de produção mais comuns em sistemas de IA não são problemas de acurácia do modelo — são os mesmos velhos culpados: disco cheio, timeout de rede, certificado expirado, permissão RBAC faltando. Seus instintos estão certos.

---

## Onde Você Se Encaixa: O Stack de IA Precisa de Engenheiros de Infraestrutura

A indústria de IA tem um problema de pessoal, e não é o que você imagina. Há muitos data scientists que sabem construir modelos em Jupyter notebooks. O que é criticamente escasso são engenheiros que conseguem pegar esses modelos e rodá-los de forma confiável em produção. Essa é a lacuna. É aí que você entra.

### Três Mundos em Colisão

Projetos de IA ficam na interseção de três disciplinas que historicamente operavam em silos:

| Papel | O Que Trazem | O Que Normalmente Falta |
|------|----------------|------------------------|
| **Desenvolvedores** | Lógica de aplicação, APIs, integração com frontend | Conhecimento de infraestrutura de GPU, arquitetura de rede |
| **Data Scientists / Engenheiros de ML** | Desenvolvimento de modelos, treinamento, avaliação | Operações de produção, segurança, consciência de custos |
| **Engenheiros de Infraestrutura** | Confiabilidade, segurança, escalabilidade, governança de custos | Vocabulário de IA/ML, entendimento do ciclo de vida de modelos |

Quando esses mundos colidem sem uma linguagem comum, coisas ruins acontecem. O time de data science provisiona VMs com GPU diretamente pelo portal — sem IaC, sem tagging, sem políticas de auto-shutdown. Os desenvolvedores expõem a API do modelo em um endpoint público porque "é só para testes." Ninguém monitora a utilização de GPU, então metade do compute caro fica ocioso.

Você já viu esse padrão antes. É o mesmo caos que aconteceu quando os desenvolvedores ganharam acesso à cloud pela primeira vez sem guardrails. E assim como a governança de cloud, a solução é a disciplina de engenharia de infraestrutura aplicada a um novo tipo de workload.

### O Que Dá Errado Sem Expertise de Infraestrutura

Estes não são cenários hipotéticos. São padrões reais que eu vi repetidamente em organizações adotando IA:

**Sprawl desgovernado de GPUs.** Um data scientist solicita quatro VMs `Standard_NC24ads_A100_v4` para um experimento de treinamento. Sem resource locks, sem alertas de orçamento, sem tagging. Três semanas depois, as VMs ainda estão rodando — ninguém lembra quem provisionou ou se o experimento terminou. Custo mensal: mais de $35.000.

**Inference endpoints expostos.** O time de ML faz deploy de um modelo em um managed endpoint do Azure Machine Learning com IP público. Sem private endpoint, sem WAF, sem API management. O modelo serve respostas que incluem lógica de negócios proprietária e padrões de dados de clientes.

**Pontos cegos na observabilidade.** O time monitora a acurácia do modelo, mas não a saúde da infraestrutura. Quando a latência de inferência dispara de 200ms para 8 segundos, ninguém consegue dizer se é o modelo, o compute, a rede ou um noisy neighbor. Não há métricas de GPU no stack de monitoramento.

⚠️ **Pegadinha de Produção — O Final de Semana de $50K em GPU**: Um time provisionou 8 × VMs `Standard_ND96asr_v4` (GPUs A100) numa sexta-feira à tarde para um job de treinamento que esperavam terminar até sábado de manhã. O job de treinamento crashou às 3 da manhã por causa de uma configuração incorreta do armazenamento de checkpoints, mas as VMs continuaram rodando. Ninguém tinha configurado políticas de auto-shutdown ou alertas de orçamento. Surpresa de segunda-feira de manhã: **$53.000 em cobranças de compute** por 60 horas de tempo ocioso de GPU. Um engenheiro de infraestrutura teria configurado `auto-shutdown`, definido um alerta de orçamento em $5.000 e armazenado os checkpoints em Blob com lifecycle policies. Quinze minutos de trabalho de infraestrutura teriam economizado $48.000.

---

## O Profissional de Infraestrutura Preparado para IA

Você não precisa se reinventar. Você precisa estender sua expertise existente para um novo domínio. Pense como quando a virtualização chegou — você não parou de ser um engenheiro de servidores. Você aprendeu uma nova camada de abstração e se tornou mais valioso. Infraestrutura de IA é a mesma transição.

### Habilidades Que Você Já Tem e Se Transferem Diretamente

Faça o inventário do que você traz para a mesa. É mais do que você imagina:

| Sua Habilidade Atual | Como se Aplica à IA |
|---------------------|---------------------|
| Provisionamento e gestão de VMs | Seleção de SKU de GPU, gerenciamento de drivers CUDA, configuração multi-GPU |
| Arquitetura de rede | Private endpoints para APIs de modelo, integração com VNet, InfiniBand para treinamento distribuído |
| Kubernetes (AKS) | Node pools com GPU, NVIDIA device plugin, servir modelos em containers |
| Arquitetura de storage | Design de data lake, storage de alto throughput para treinamento, gerenciamento de checkpoints |
| IaC (Terraform/Bicep) | Automatizando infraestrutura de IA — mesmos recursos, novos parâmetros |
| Monitoramento e alertas | Telemetria de GPU, dashboards de latência de inferência, alertas de throughput de tokens |
| Segurança e compliance | Autenticação de endpoints de modelo, criptografia de dados, isolamento de rede |
| Gestão de custos | Governança de custos de GPU, reservas de instância para GPUs, spot instances para treinamento |
| Resposta a incidentes | Triagem de falhas de inferência, erros de memória de GPU, gargalos de storage |

### Novas Habilidades para Adicionar

A lacuna é menor do que você imagina. Aqui está o que você vai aprender ao longo deste livro:

- **Fundamentos de GPU**: Famílias de SKU (NC, ND, NV), compatibilidade CUDA, memória da GPU (VRAM) como restrição de capacidade, interconexões multi-GPU
- **Ciclo de vida de modelos**: Como modelos vão do treinamento ao deploy, o que significa "serving", estratégias de versionamento e rollback
- **Observabilidade de IA**: Novas métricas como tokens por segundo, time-to-first-token, utilização de GPU e pressão de VRAM, profundidade da fila de inferência
- **Rede específica para IA**: Topologia InfiniBand para treinamento multi-nó, padrões de comunicação NCCL, requisitos de largura de banda entre nós de GPU
- **Serviços gerenciados de IA**: Tipos de deploy do Azure OpenAI (standard vs. provisioned), endpoints do Azure Machine Learning, AI Foundry

💡 **Dica**: Você não precisa aprender Python, TensorFlow ou PyTorch. Você não precisa entender backpropagation ou gradient descent. Você precisa entender o que essas ferramentas e processos *exigem da infraestrutura*. Quando um data scientist diz "meu job de treinamento precisa de 8 GPUs A100 com NVLink e 2 TB de espaço NVMe para scratch," você precisa saber qual SKU de VM do Azure entrega isso — e não como o algoritmo de treinamento funciona internamente.

### Caminhos de Carreira em Infraestrutura de IA

Isso não é um nicho. É um campo em rápido crescimento com múltiplas trajetórias:

| Papel | Área de Foco | Habilidades-Chave |
|------|-----------|-----------|
| **Engenheiro de Infraestrutura de IA** | Provisionamento e gerenciamento de GPU compute, storage e rede para workloads de IA | SKUs de GPU, InfiniBand, storage de alto desempenho, IaC |
| **Engenheiro de MLOps** | Automatizando o ciclo de vida do modelo — treinamento, validação, deploy, monitoramento | CI/CD para modelos, model registries, deploy A/B |
| **Arquiteto de Cloud para IA** | Projetando plataformas de IA de ponta a ponta, arquiteturas de referência, frameworks de governança | Serviços de IA do Azure, otimização de custos, arquitetura de segurança |
| **Engenheiro de Plataforma de IA** | Construindo plataformas internas que permitem aos times de data science operar com autonomia | Kubernetes, developer experience, API management, quotas |

**Matriz de Decisão — Por Onde Começar**:
- Se você é forte em **compute e rede** → comece como Engenheiro de Infraestrutura de IA
- Se você é forte em **automação e CI/CD** → comece como Engenheiro de MLOps
- Se você é forte em **arquitetura e governança** → comece como Arquiteto de Cloud para IA
- Se você é forte em **Kubernetes e ferramentas de plataforma** → comece como Engenheiro de Plataforma de IA

---

## Termos-Chave Que Você Vai Encontrar

Aqui está um glossário expandido com analogias de infraestrutura para cada termo. Marque esta seção — você vai consultá-la ao longo de todo o livro.

| Termo | Definição | Analogia de Infraestrutura |
|------|-----------|----------------------|
| **Inferência** | Executar um modelo treinado para obter previsões a partir de novos dados de entrada | Uma chamada de API — requisição entra, resposta sai. Esta é a fase de "produção". |
| **Treinamento** | O processo de ensinar um modelo alimentando-o com dados | Um batch job — longa duração, intensivo em compute, produz um artefato (o modelo treinado) |
| **Fine-tuning** | Customizar um modelo pré-treinado com seus dados específicos | Aplicar um patch em um binário — você pega um artefato existente e o adapta para o seu ambiente |
| **GPU** | Graphics Processing Unit — hardware otimizado para operações matemáticas paralelas | Um coprocessador, como uma placa de offload de rede, mas para cálculos matriciais. Milhares de pequenos núcleos trabalhando em paralelo. |
| **CUDA** | Framework da NVIDIA para programação de GPUs | Um framework de driver e runtime — como a camada de hypervisor que permite ao seu workload conversar com o hardware |
| **VRAM** | Video RAM — a memória dedicada da GPU | Pense nela como a "RAM" da GPU. Modelos precisam caber na VRAM para rodar. É a restrição de capacidade mais comum. |
| **LLM** | Large Language Model (GPT, Llama, Mistral) | Uma aplicação grande e stateful que requer compute e memória significativos para ser servida |
| **Token** | Um pedaço de texto (~4 caracteres) que o modelo processa | A unidade de trabalho — como um pacote em redes ou uma transação em um banco de dados |
| **TPM** | Tokens Per Minute — métrica de throughput para modelos de linguagem | Equivalente a requisições por segundo (RPS) — mede quanto trabalho o modelo consegue fazer |
| **PTU** | Provisioned Throughput Unit — capacidade reservada no Azure OpenAI | Instâncias reservadas — você paga por capacidade garantida em vez de pay-as-you-go |
| **MLOps** | Práticas de DevOps aplicadas ao ciclo de vida de machine learning | DevOps para modelos — controle de versão, CI/CD, monitoramento, rollback, mas para artefatos de modelo |
| **ONNX** | Open Neural Network Exchange — formato portável de modelo | Como um OVA/OVF para VMs — um formato padronizado que roda em diferentes runtimes |
| **Checkpoint** | Um snapshot do estado do modelo salvo durante o treinamento | Um snapshot de VM ou backup de banco de dados — permite retomar o treinamento de um estado bom conhecido |
| **Epoch** | Uma passagem completa pelo dataset de treinamento | Como um ciclo de backup completo — o job processa todos os registros uma vez |
| **Inference endpoint** | Uma API que serve previsões do modelo | Um endpoint de web service — mesmos conceitos de escala, load balancing e health probes |

**Tradução Infra ↔ IA — A Cola Rápida de Uma Linha**: Um modelo treinado é um binário compilado. Treinamento é um batch job. Inferência é uma chamada de API. Um dataset é um banco de dados. Um pipeline de treinamento é um pipeline de CI/CD. Se você conseguir manter esse modelo mental, consegue navegar qualquer conversa de arquitetura de IA.

---

## Mão na Massa: Sua Primeira Exploração de Infraestrutura de IA

Vamos ao prático. Você não precisa treinar um modelo ou escrever Python. Você precisa entender qual compute de GPU está disponível para você e quais são os limites da sua assinatura. Isso é reconhecimento — o mesmo primeiro passo que você daria antes de arquitetar qualquer novo workload.

### Passo 1: Descubra os SKUs de VMs com GPU na Sua Região

Abra seu terminal e execute o seguinte comando, substituindo `<sua-regiao>` pela sua região do Azure (ex.: `eastus2`, `westus3`, `swedencentral`):

```bash
az vm list-skus --location <sua-regiao> --size Standard_N --output table
```

Isso filtra pela família `Standard_N`, que inclui todas as VMs aceleradas por GPU no Azure. Você verá nomes de SKU como `Standard_NC24ads_A100_v4`, `Standard_ND96asr_v4` e `Standard_NV36ads_A10_v5`.

💡 **Dica**: Preste atenção em três prefixos de família de VMs com GPU:
- **NC** — GPUs otimizadas para compute, voltadas para treinamento e inferência (NVIDIA T4, A100)
- **ND** — GPUs de alto desempenho projetadas para deep learning distribuído com InfiniBand (A100, H100)
- **NV** — GPUs para visualização e inferência leve (AMD Radeon, NVIDIA A10)

Para workloads de IA em produção, você vai trabalhar principalmente com as séries NC e ND. As VMs da série ND com InfiniBand são o que os jobs de treinamento em larga escala exigem.

### Passo 2: Verifique Sua Quota de GPU

Ter SKUs disponíveis em uma região não significa que você pode implantá-los. Você precisa de quota. Execute este comando para ver seus limites atuais de vCPU por família de GPU e o uso corrente:

```bash
az vm list-usage --location <sua-regiao> --output table | Select-String -Pattern "NC|ND|NV"
```

> **Nota**: No Linux/macOS, substitua `Select-String -Pattern "NC|ND|NV"` por `grep -E "NC|ND|NV"`.

Isso mostra quantas vCPUs você usou e seu limite atual para cada família de GPU. Se o limite for 0, você precisará solicitar um aumento de quota antes de implantar qualquer VM com GPU.

### Perguntas para Explorar

Agora que você tem o resultado, tente responder:

1. Qual SKU de VM usa a GPU **NVIDIA T4**? (Dica: procure por `NC*T4*` no nome — ótimo para workloads de inferência)
2. Qual SKU usa a **NVIDIA A100**? (Dica: procure por `NC*A100*` ou `ND*A100*` — o cavalo de batalha do treinamento)
3. Qual é a diferença na **contagem de vCPUs** entre o menor e o maior SKU de GPU disponível?
4. Quais são suas **quotas de vCPU** atuais para as famílias NC e ND? Você conseguiria fazer deploy de uma única VM A100 hoje?
5. Quantas **GPUs por VM** os SKUs da série ND oferecem? (Alguns fornecem até 8 GPUs em um único nó)

⚠️ **Pegadinha de Produção**: Solicitações de quota de GPU no Azure podem levar de **24 a 72 horas** para aprovação, às vezes mais para SKUs de alta demanda como A100 e H100. Se um projeto tem prazo na quarta-feira, não espere até terça para solicitar quota. Incorpore o planejamento de quota no kickoff do seu projeto de IA — da mesma forma que você planejaria espaço de endereços IP ou limites de assinatura para qualquer grande implantação.

---

## Checklist do Capítulo

Antes de seguir em frente, certifique-se de que está confortável com estes conceitos:

- **IA é um workload de infraestrutura**, não um mistério de data science. Ela consome compute, storage e rede — seu domínio.
- **O stack de IA tem três camadas**: dados (storage), modelo (a aplicação) e infraestrutura (sua responsabilidade).
- **Um modelo treinado é um binário compilado.** Treinamento é um batch job. Inferência é uma chamada de API. Você já conhece esses padrões.
- **A infraestrutura de IA muda algumas coisas** (GPUs em vez de CPUs, InfiniBand em vez de Ethernet, tokens em vez de requisições) **mas mantém os fundamentos** (segurança, rede, IaC, monitoramento, governança de custos).
- **Engenheiros de infraestrutura são criticamente necessários** na IA — data scientists sabem construir modelos, mas enfrentam dificuldades com operações de produção, segurança e gestão de custos.
- **Você não precisa aprender Python ou teoria de ML.** Você precisa aprender o que os workloads de IA exigem da infraestrutura.
- **VMs com GPU vêm em famílias**: NC (compute/treinamento), ND (deep learning distribuído), NV (visualização). Quota deve ser solicitada com antecedência.
- **Caminhos de carreira existem**: Engenheiro de Infraestrutura de IA, Engenheiro de MLOps, Arquiteto de Cloud para IA, Engenheiro de Plataforma de IA — todos se constroem sobre suas habilidades atuais.

---

## O Que Vem a Seguir

Agora que você entende por que a IA precisa das suas habilidades, vamos olhar para o combustível que alimenta tudo — os **dados**. No Capítulo 2, você vai aprender como os dados fluem do storage bruto até o modelo treinado, por que o desempenho de I/O é o gargalo que a maioria dos times descobre tarde demais, e como suas decisões de arquitetura de storage impactam diretamente se um job de treinamento leva 4 horas ou 4 dias.

As decisões de infraestrutura que você toma em relação aos dados — qual tier, qual formato, qual throughput — vão determinar se o time de IA vê você como um executor de pedidos ou como um parceiro estratégico. Vamos garantir que seja a segunda opção.

**Próximo**: [Capítulo 2 — Dados: O Combustível Que Alimenta a IA](02-data.md)

---

## Referências

- [Azure VM sizes overview](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview)
- [GPU-optimized VM sizes — NC family](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nc-family)
- [GPU-optimized VM sizes — ND family](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nd-family)
- [GPU-optimized VM sizes — NV family](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/gpu-accelerated/nv-family)
- [What is Azure Machine Learning?](https://learn.microsoft.com/en-us/azure/machine-learning/overview-what-is-azure-machine-learning)
- [Azure OpenAI Service overview](https://learn.microsoft.com/en-us/azure/ai-services/openai/overview)
- [Provisioned throughput in Azure OpenAI](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/provisioned-throughput)
- [Baseline end-to-end chat with Azure OpenAI architecture](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-openai-e2e-chat)