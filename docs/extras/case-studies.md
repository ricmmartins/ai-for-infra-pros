# Estudos de Caso Técnicos — IA para Engenheiros de Infraestrutura

Cenários reais mostrando como times de infraestrutura entregam impacto de negócio mensurável com workloads de IA no Azure. Cada estudo de caso mapeia diretamente para os conceitos abordados neste livro, para que você possa rastrear cada decisão até um capítulo específico.

Estas são histórias de produção — não provas de conceito. Toda métrica é fundamentada em dados operacionais realistas, e toda decisão de arquitetura reflete os trade-offs que engenheiros de infraestrutura enfrentam diariamente.

---

## Estudo de Caso 1 — Construção de Cluster GPU para Treinamento de Modelos em Larga Escala

**📖 Capítulos Referenciados:** Cap3 (Compute), Cap4 (GPU Deep Dive), Cap5 (IaC)

### Cenário

Uma empresa de serviços financeiros precisava fazer fine-tuning de um modelo de linguagem com 13 bilhões de parâmetros usando dados proprietários de transações para detecção de fraudes. O time de data science havia validado a abordagem utilizando uma única GPU A100 em ambiente de pesquisa, mas o treinamento completo exigia treinamento distribuído multi-node em 8 nodes — 64 GPUs no total — com uma janela de treinamento de 72 horas para cumprir um prazo regulatório.

O time de infraestrutura tinha vasta experiência com clusters de computação de alta disponibilidade, mas nunca havia provisionado hardware GPU nessa escala. Eles enfrentaram desafios desconhecidos: requisitos de rede InfiniBand, ajuste de comunicação coletiva NCCL e gerenciamento de memória GPU para um modelo que consumia 48 GB de VRAM por GPU antes mesmo de os estados do optimizer serem carregados.

O CTO deu a eles três semanas para sair do zero em infraestrutura GPU até um treinamento em produção — com observabilidade completa e controles de custo implementados desde o primeiro dia.

### Serviços e Configuração do Azure

| Componente | Serviço / SKU | Configuração |
|-----------|--------------|---------------|
| Compute | `Standard_ND96asr_v4` (8× A100 80 GB) | 8 nodes, InfiniBand habilitado, Proximity Placement Group |
| Rede | Accelerated Networking + InfiniBand | Variável de ambiente NCCL `NCCL_IB_HCA=mlx5` configurada |
| Armazenamento | Azure NetApp Files (tier Ultra) | Volume de 100 TiB, throughput de 4.500 MiB/s para I/O de checkpoint |
| IaC | Módulos Bicep | Templates parametrizados para contagem de nodes, SKU e região |
| Monitoramento | Azure Monitor + DCGM Exporter | Dashboards de memória GPU, ocupação de SM, throughput NVLink |
| Controle de custo | Azure Budgets + Logic App de auto-shutdown | Limite de orçamento de $85K com alertas em 80%/90%/100% |

### O que o time de infraestrutura fez

1. **Validação de cota** — Enviaram solicitações de cota para 768 vCPUs A100 em `southcentralus` com duas semanas de antecedência. A primeira solicitação foi negada; eles dividiram entre `southcentralus` (512) e `eastus2` (256) e receberam aprovação em 4 dias úteis.
2. **Topologia de rede** — Implantaram todos os nodes em um único Proximity Placement Group dentro de uma zona de disponibilidade. Configuraram InfiniBand SR-IOV com os adaptadores Mellanox ConnectX-6 integrados do `ND96asr_v4`. Validaram a largura de banda inter-node em 200 Gbps usando `ib_write_bw`.
3. **Design de armazenamento** — Escolheram Azure NetApp Files em vez de Blob Storage após benchmark de escrita de checkpoints. Um único checkpoint de 25 GB em 64 GPUs foi concluído em 11 segundos no ANF versus 4+ minutos no Premium Blob.
4. **Automação com IaC** — Construíram módulos Bicep com um parâmetro `nodeCount` para que o cluster pudesse escalar de 2 a 16 nodes sem alterações no código. O pipeline de CI/CD no Azure DevOps executava `az deployment group what-if` em cada PR.
5. **Planejamento de memória GPU** — Calcularam os requisitos de memória usando a fórmula do Cap4: `Parâmetros do modelo (13B) × 4 bytes (FP32) = 52 GB base`. Com treinamento de precisão mista (BF16) e sharding de optimizer ZeRO Stage 3, o uso real por GPU caiu para 38 GB — dentro do envelope de 80 GB da A100.
6. **Monitoramento desde o primeiro dia** — Implantaram o DCGM Exporter como equivalente a DaemonSet em cada VM, alimentando o Prometheus. Construíram dashboards no Grafana mostrando atividade de SM por GPU, utilização de memória e throughput NVLink. Configuraram alertas para memória GPU > 95% e ocupação de SM < 20% (indicando um rank travado).

### Resultados Quantificados

| Métrica | Resultado |
|--------|--------|
| Tempo de treinamento (modelo 13B, 500K amostras) | 68 horas (dentro do prazo de 72 horas) |
| Utilização de GPU (média em 64 GPUs) | 87% de ocupação de SM |
| Tempo de I/O de checkpoint | 11 segundos por checkpoint (a cada 2 horas) |
| Custo total de infraestrutura | $73.400 (abaixo do orçamento de $85K) |
| Tempo do zero até o primeiro treinamento | 16 dias |

### Lições Aprendidas

- **O tempo de aprovação de cota é o seu caminho crítico** — comece as solicitações de cota de GPU antes de qualquer outro trabalho. *(Cap3)*
- **InfiniBand é inegociável para treinamento multi-node** — Ethernet padrão adicionou 3× de overhead de comunicação nos benchmarks deles. *(Cap4)*
- **A matemática de memória GPU elimina adivinhação** — a fórmula de memória por camada evitou dois incidentes de OOM durante varreduras de hiperparâmetros. *(Cap4)*
- **IaC se paga no primeiro redimensionamento** — quando o time de data science solicitou uma execução com 12 nodes, o time de infra entregou em 20 minutos alterando apenas um parâmetro. *(Cap5)*

---

## Estudo de Caso 2 — Infrastructure as Code para Pipelines de ML Multi-Ambiente

**📖 Capítulos Referenciados:** Cap5 (IaC), Cap6 (MLOps), Cap8 (Segurança)

### Cenário

Uma empresa de analytics de saúde executava seus pipelines de treinamento de ML usando workspaces do Azure ML provisionados manualmente. Cada cientista de dados tinha seu próprio workspace com configurações inconsistentes — SKUs de compute diferentes, sem isolamento de rede e secrets armazenados em arquivos de configuração em texto puro. Quando uma auditoria revelou que PHI (Protected Health Information) estava sendo processada em um workspace sem Private Link, o CISO determinou uma reconstrução completa da infraestrutura com controles de conformidade.

O time de engenharia de plataforma tinha 6 semanas para entregar um stack de infraestrutura repetível e auditável que suportasse três ambientes (dev, staging, prod) com controles de segurança idênticos. Eles também precisavam integrar o ciclo de vida da infraestrutura com os pipelines de treinamento de modelos do time de data science, de forma que o provisionamento de ambientes e o deploy de modelos fizessem parte do mesmo fluxo de CI/CD.

### Serviços e Configuração do Azure

| Componente | Serviço | Configuração |
|-----------|---------|---------------|
| IaC | Terraform (AzureRM provider 3.x) | Módulos para workspace, compute, rede, RBAC |
| Plataforma de ML | Azure Machine Learning | Workspace com Private Link habilitado, VNet gerenciada |
| Rede | VNet + Private Endpoints + NSGs | Topologia hub-spoke, sem endpoints públicos |
| Secrets | Azure Key Vault | Acesso via Managed Identity, sem uso de API key |
| CI/CD | GitHub Actions | `terraform plan` no PR, `terraform apply` no merge para main |
| Política | Azure Policy | Negar endpoints públicos, exigir criptografia, impor tagging |

### O que o time de infraestrutura fez

1. **Arquitetura de módulos** — Criaram quatro módulos Terraform: `network` (VNet, subnets, NSGs, zonas de Private DNS), `workspace` (workspace Azure ML, Key Vault vinculado, Storage, ACR), `compute` (clusters de treinamento com auto-scale) e `rbac` (atribuições de role por ambiente). Cada módulo era versionado independentemente em um registry Terraform.
2. **Paridade de ambientes** — Usaram arquivos `tfvars` por ambiente com referências idênticas aos módulos. As únicas diferenças eram os tamanhos de SKU de compute (dev: `Standard_DS3_v2`, prod: `Standard_NC6s_v3`) e contagem de nodes.
3. **Hardening de segurança** — Implantaram atribuições de Azure Policy que negavam a criação de qualquer workspace Azure ML sem Private Link. Adicionaram políticas de acesso ao Key Vault usando apenas Managed Identity — sem secrets de service principal. Habilitaram configurações de diagnóstico em cada recurso, encaminhando para um workspace central de Log Analytics.
4. **Integração com MLOps** — O pipeline de treinamento de modelos (definido em Azure ML YAML) referenciava compute targets pelo nome. Como o Terraform criava compute targets com nomes determinísticos (`train-cpu-dev`, `train-gpu-prod`), o YAML do pipeline do time de data science funcionava em todos os ambientes sem modificação.
5. **Detecção de drift** — Configuraram um workflow noturno no GitHub Actions que executava `terraform plan` contra cada ambiente e abria uma issue se drift fosse detectado. No primeiro mês, capturou 3 alterações manuais feitas pelo portal.

### Resultados Quantificados

| Métrica | Resultado |
|--------|--------|
| Tempo de provisionamento de ambiente | 22 minutos (eram 2-3 dias manualmente) |
| Achados de auditoria de segurança | 0 críticos (eram 14) |
| Incidentes de drift de configuração (mensal) | 3 detectados e remediados automaticamente |
| Tempo de onboarding de desenvolvedor (novo cientista de dados) | 4 horas (eram 2 dias) |
| Módulos Terraform reutilizados entre times | 3 times adotaram os mesmos módulos em 2 meses |

### Lições Aprendidas

- **IaC é um controle de segurança, não apenas automação** — a auditoria passou porque a infraestrutura era revisada via code review, não por causa de um checklist. *(Cap5)*
- **MLOps e IaC devem compartilhar um contrato de nomenclatura** — quando os nomes dos compute targets são determinísticos, o YAML do pipeline se torna agnóstico ao ambiente. *(Cap6)*
- **Private Link adiciona 15-20 minutos ao provisionamento** — planeje isso nos timeouts de CI/CD e comunique o trade-off aos stakeholders. *(Cap8)*

💡 **Dica Pro**: Execute `terraform plan` no pipeline do seu PR e publique a saída como comentário no PR. Revisores capturam configurações incorretas antes que cheguem a qualquer ambiente.

---

## Estudo de Caso 3 — Plataforma de Observabilidade para Inferência Acelerada por GPU

**📖 Capítulos Referenciados:** Cap7 (Monitoramento), Cap4 (GPU Deep Dive), Cap12 (Troubleshooting)

### Cenário

Uma empresa de mídia operava um sistema de moderação de conteúdo em tempo real alimentado por um modelo vision transformer implantado no AKS com node pools de GPU. O sistema processava 15.000 imagens por minuto durante horários de pico. O time de operações tinha monitoramento básico de Kubernetes (CPU, memória, reinícios de pod), mas nenhuma telemetria específica de GPU. Quando picos de latência ocorriam durante surtos de tráfego, eles não tinham como distinguir entre saturação de GPU, ineficiência do modelo e gargalos de I/O de armazenamento.

Após uma interrupção de 45 minutos onde a latência P95 excedeu 8 segundos (o SLA era de 500 ms), o VP de Engenharia determinou uma reformulação completa da observabilidade. O time de infraestrutura precisava construir um stack de monitoramento que pudesse identificar a causa raiz da degradação de latência em até 2 minutos — rápido o suficiente para que o engenheiro de plantão agisse antes que os usuários percebessem.

### Serviços e Configuração do Azure

| Componente | Serviço | Configuração |
|-----------|---------|---------------|
| Compute | AKS com node pool `Standard_NC16as_T4_v3` | 6 nodes, cluster autoscaler (mín 4, máx 12) |
| Métricas de GPU | DCGM Exporter (DaemonSet) | Exportados: `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`, `DCGM_FI_DEV_SM_CLOCK` |
| Pipeline de métricas | Prometheus (Azure Managed) + Grafana | Intervalo de scrape de 15 segundos, retenção de 30 dias |
| Telemetria de aplicação | Application Insights (SDK instrumentado) | Métricas customizadas: `inference_latency_ms`, `batch_size`, `model_version` |
| Alertas | Azure Monitor Action Groups | Integração PagerDuty para P1, webhook do Teams para P2/P3 |
| Agregação de logs | Container Insights + Log Analytics | Queries KQL para correlação em nível de pod |

### O que o time de infraestrutura fez

1. **Pipeline de telemetria de GPU** — Implantaram o DCGM Exporter como DaemonSet com tolerations para o taint do node pool de GPU. Configuraram o Prometheus para coletar métricas de GPU em intervalos de 15 segundos. Construíram dashboards no Grafana com quatro painéis: utilização de GPU (%), uso de memória GPU (MB), frequência de clock SM (MHz) e throughput PCIe (GB/s).
2. **Instrumentação em nível de aplicação** — Trabalharam com o time de engenharia de ML para adicionar métricas customizadas do Application Insights ao serviço de inferência. Cada requisição registrava: `inference_latency_ms`, `preprocessing_time_ms`, `postprocessing_time_ms`, `batch_size` e `model_version`. Isso separou o tempo de computação do modelo do overhead de I/O.
3. **Dashboards de correlação** — Construíram um dashboard no Grafana que sobrepunha utilização de GPU, latência P95 de inferência e contagem de pods no mesmo eixo temporal. Isso revelou imediatamente um padrão: os picos de latência correlacionavam com memória GPU > 90%, não com utilização de compute GPU. O gargalo era pressão de memória causada por batch sizes grandes, não insuficiência de cores GPU.
4. **Hierarquia de alertas** — Definiram três níveis de alerta:
   - **P1** (PagerDuty, imediato): latência P95 > 2 segundos por 3 minutos consecutivos
   - **P2** (Teams, resposta em 15 min): memória GPU > 85% sustentada por 10 minutos
   - **P3** (Resumo diário): utilização de GPU < 30% por 1 hora (detecção de desperdício)
5. **Automação de runbook** — Criaram um runbook do Azure Automation acionado por alertas P2 que reduzia automaticamente o batch size de inferência de 32 para 16, dando ao time tempo para investigar sem impacto aos usuários.

### Resultados Quantificados

| Métrica | Antes | Depois |
|--------|--------|-------|
| Tempo médio de detecção (MTTD) | 12 minutos | 90 segundos |
| Tempo médio de resolução (MTTR) | 45 minutos | 8 minutos |
| Latência P95 (horários de pico) | 1.200 ms (com picos de 8s) | 380 ms (estável) |
| Alertas falso-positivos (mensal) | 47 | 6 |
| Desperdício de GPU identificado (economia mensal) | — | $2.800 com right-sizing de batch sizes |

### Lições Aprendidas

- **Utilização de GPU isoladamente é enganosa** — alta utilização parece saudável, mas se a memória GPU está saturada, a latência ainda degrada. Monitore sempre ambos. *(Cap4, Cap7)*
- **Métricas em nível de aplicação são inegociáveis** — sem `inference_latency_ms` detalhada por fase, o time teria culpado a GPU quando o verdadeiro gargalo era o pré-processamento de imagem na CPU. *(Cap7)*
- **Níveis estruturados de alerta previnem fadiga de alertas** — o sistema antigo tinha 47 falsos positivos por mês. A nova abordagem em camadas reduziu o ruído em 87%. *(Cap7, Cap12)*

⚠️ **Armadilha em Produção**: O conjunto de métricas padrão do DCGM Exporter é enorme. Exporte apenas as 8-10 métricas que você realmente usa nos dashboards — caso contrário, os custos de armazenamento do Prometheus vão te surpreender.

---

## Estudo de Caso 4 — Engenharia de Custos para uma Frota de Inferência Mista GPU/CPU

**📖 Capítulos Referenciados:** Cap9 (Engenharia de Custos), Cap3 (Compute), Cap11 (Azure OpenAI)

### Cenário

Uma empresa SaaS B2B operava três funcionalidades alimentadas por IA: sumarização de documentos (Azure OpenAI GPT-4o), classificação de imagens (modelo de visão customizado em VMs GPU) e detecção de anomalias (ML clássico em CPU). O gasto mensal com IA no Azure havia crescido de $18K para $67K em 6 meses sem aumento correspondente no uso pelos clientes. O CFO exigiu uma redução de 35% nos custos sem degradar a qualidade do serviço.

O time de infraestrutura descobriu diversos fatores de custo: VMs GPU rodando 24/7 para um workload que tinha pico apenas 10 horas por dia, deployments standard do Azure OpenAI com 40% das requisições atingindo throttling 429 (gerando retentativas caras) e nenhuma visibilidade de chargeback — três times de produto consumiam recursos GPU mas os custos eram alocados em uma única linha orçamentária "Infraestrutura de IA".

### O que o time de infraestrutura fez

1. **Análise de uso** — Exportaram 90 dias de dados do Azure Cost Management e correlacionaram com métricas de utilização de GPU do Prometheus. Descobriram que as VMs GPU tinham em média 22% de utilização durante horários fora de pico (22h – 8h) e 78% durante horário comercial.
2. **Agendamento de GPU** — Implementaram runbooks do Azure Automation para desalocar as VMs de classificação de imagens das 22h às 7h diariamente. Adicionaram um buffer de aquecimento de 30 minutos com health checks antes de rotear a primeira requisição. Economizaram 37% em compute GPU.
3. **Migração do Azure OpenAI para PTU** — Analisaram padrões de consumo de tokens: a funcionalidade de sumarização de documentos consumia um fluxo estável de 180K TPM durante horário comercial. Migraram do standard (pay-per-token) para 300 PTU, que fornecia 200K+ TPM a uma taxa horária fixa. Isso eliminou erros 429 e reduziu o custo por token em 42%.
4. **Spot VMs para workloads batch** — Moveram o job noturno de retreinamento de modelo (detecção de anomalias) para VMs spot `Standard_NC4as_T4_v3` com preço máximo de 60% do on-demand. Implementaram checkpointing a cada 30 minutos, de modo que evictions só perdiam 30 minutos de trabalho. A taxa de eviction de spot teve média de 3% ao longo de 90 dias.
5. **Tagging de chargeback** — Implementaram tags obrigatórias nos recursos (`CostCenter`, `Product`, `WorkloadType`) impostas por Azure Policy. Construíram um dashboard no Power BI mostrando custo por time de produto por funcionalidade de IA. Em um mês, o time de classificação de imagens reduziu voluntariamente seu batch size após ver o custo por requisição.
6. **Reserved Instances** — Compraram reservas de 1 ano para as 4 VMs GPU que rodavam durante horário comercial, economizando 21% adicionais versus pay-as-you-go.

### Resultados Quantificados

| Alavanca de Custo | Economia Mensal | Percentual |
|------------|----------------|------------|
| Agendamento de VM GPU (desalocação fora de horário) | $8.900 | 37% do compute GPU |
| Migração para PTU do Azure OpenAI | $6.200 | 42% de redução no custo por token |
| VMs spot para treinamento batch | $1.800 | 58% vs. on-demand |
| Reserved Instances (1 ano) | $4.100 | 21% dos custos de VM reservada |
| **Economia mensal total** | **$21.000** | **31% do gasto total com IA** |

*Gasto mensal pós-otimização: $46.000 (reduzido de $67.000).*

### Lições Aprendidas

- **Dados de utilização de GPU são a base da engenharia de custos** — sem métricas do Prometheus, o time teria adivinhado as janelas de agendamento. *(Cap9)*
- **PTU é quase sempre mais barato para workloads sustentados** — o ponto de break-even foi aproximadamente 120K TPM sustentados por 8+ horas/dia. *(Cap11)*
- **Chargeback muda o comportamento** — times otimizam quando veem seus próprios custos. Imposição de tags é um controle de custo. *(Cap9)*

💡 **Dica Pro**: Antes de se comprometer com PTU, faça uma análise de 2 semanas do consumo real de TPM do seu deployment standard. As métricas do Azure OpenAI no Azure Monitor fornecem os números exatos para calcular o break-even.

---

## Estudo de Caso 5 — Operações de Plataforma Multi-Time para Workloads de IA

**📖 Capítulos Referenciados:** Cap10 (Platform Ops), Cap5 (IaC), Cap8 (Segurança)

### Cenário

Uma empresa de tecnologia com mais de 200 engenheiros tinha quatro times de produto executando workloads de IA no Azure — cada um com seus próprios clusters AKS, storage accounts e configurações de rede. O resultado era expansão descontrolada de infraestrutura: 14 clusters AKS, 23 storage accounts, políticas de segurança inconsistentes e nenhuma capacidade GPU compartilhada. Quando um time precisou de GPUs A100 para um sprint de treinamento, esperaram 3 semanas pela aprovação de cota enquanto os nodes A100 de outro time ficavam ociosos com 12% de utilização.

O CTO encarregou o time de engenharia de plataforma de construir uma plataforma de IA compartilhada que oferecesse capacidades de self-service mantendo guardrails de segurança, visibilidade de custos e utilização eficiente de GPU entre todos os times.

### Serviços e Configuração do Azure

| Componente | Serviço | Configuração |
|-----------|---------|---------------|
| Plataforma de compute | AKS (3 clusters: dev, staging, prod) | Node pools GPU compartilhados com isolamento por namespace |
| Multi-tenancy | Kubernetes namespaces + NetworkPolicy | Namespaces por time, resource quotas, limit ranges |
| Compartilhamento de GPU | NVIDIA MPS + time-slicing | 2× time-slicing em nodes T4 para dev, dedicado para prod |
| IaC | Terraform + Atlantis | Workflow baseado em PR, revisão obrigatória do plan |
| Self-service | Portal de desenvolvedor Backstage | Templates para provisionamento de "novo projeto ML" |
| Alocação de custos | Kubecost + Azure Cost Management | Atribuição de custo por namespace com relatórios diários |
| Segurança | Azure Policy + OPA Gatekeeper | Impor registries privados, bloquear containers privilegiados |

### O que o time de infraestrutura fez

1. **Consolidação de clusters** — Reduziram 14 clusters AKS para 3 (dev, staging, prod). Cada cluster utilizava isolamento em nível de namespace com Kubernetes ResourceQuotas limitando requisições de GPU por time (`requests.nvidia.com/gpu`). NetworkPolicies impunham isolamento namespace-a-namespace — os times não podiam acessar os endpoints de inferência uns dos outros.
2. **Estratégia de compartilhamento de GPU** — Implementaram NVIDIA GPU time-slicing nos nodes T4 de dev, permitindo que 2 workloads compartilhassem uma única GPU. Workloads de produção em nodes A100 tinham acesso dedicado à GPU — sem time-slicing. Isso aumentou a utilização de GPU em dev de 12% para 64% sem comprar hardware adicional.
3. **Provisionamento self-service** — Construíram templates no Backstage que permitiam aos cientistas de dados provisionar um novo namespace de projeto ML com: uma resource quota de GPU, um scope dedicado no Azure Container Registry, acesso ao Key Vault para secrets e um Prometheus ServiceMonitor pré-configurado. O tempo de provisionamento caiu de um ticket de 3 semanas para 15 minutos.
4. **Workflow GitOps** — Todas as mudanças de infraestrutura passavam por PRs de Terraform revisados pelo time de plataforma via Atlantis. Nenhum `kubectl apply` era permitido em produção — ArgoCD sincronizava manifests a partir do Git. Isso criou uma trilha completa de auditoria de cada mudança de infraestrutura.
5. **Atribuição de custos** — Implantaram Kubecost com integração ao Azure Cost Management. Os custos de compute, armazenamento e rede de cada namespace eram atribuídos ao centro de custo do time proprietário. Relatórios mensais eram gerados automaticamente e enviados aos líderes dos times. O tempo ocioso de GPU era sinalizado separadamente, mostrando o custo de horas de GPU reservadas mas não utilizadas.
6. **Guardrails via política** — Políticas do OPA Gatekeeper impunham: sem tags de imagem `latest`, resource limits obrigatórios em todos os pods, requisições de GPU devem incluir limits correspondentes (prevenindo sobrealocação), e todas as imagens devem vir do ACR interno. Azure Policy impunha controles em nível de rede — sem load balancers públicos, Private Link obrigatório para acesso ao armazenamento.

### Resultados Quantificados

| Métrica | Antes | Depois |
|--------|--------|-------|
| Clusters AKS | 14 | 3 |
| Utilização de GPU (dev) | 12% | 64% |
| Utilização de GPU (prod) | 41% | 78% |
| Tempo de provisionamento de novo projeto | 3 semanas | 15 minutos |
| Gasto mensal com compute GPU | $89.000 | $52.000 (redução de 42%) |
| Violações de política de segurança (mensal) | Desconhecido | 0 (imposto pelo Gatekeeper) |
| Headcount do time de infra para AI ops | 6 FTEs em 4 times | 2 FTEs no time de plataforma |

### Lições Aprendidas

- **Plataformas compartilhadas são um multiplicador de economia** — consolidar 14 clusters para 3 economizou mais do que a otimização de agendamento de GPU. *(Cap10)*
- **GPU time-slicing é seguro para dev, perigoso para prod** — em produção, um vizinho barulhento em uma GPU compartilhada causou um pico de 3× na latência durante a primeira semana. Eles reverteram para GPUs dedicadas em prod imediatamente. *(Cap10, Cap4)*
- **Self-service sem guardrails é caos; guardrails sem self-service são gargalos** — a combinação Backstage + Gatekeeper deu aos times velocidade com segurança. *(Cap10, Cap8)*
- **Visibilidade de custos impulsiona otimização orgânica** — dois times reduziram voluntariamente suas cotas de GPU após ver os relatórios do Kubecost, liberando capacidade para o time que realmente precisava. *(Cap9)*

⚠️ **Armadilha em Produção**: Kubernetes ResourceQuotas limitam o número de GPUs que um namespace pode *solicitar*, mas não impedem que um único pod consuma toda a memória GPU. Sempre combine ResourceQuotas com imposição de `resources.limits` em nível de container via OPA Gatekeeper.

---

> "A melhor infraestrutura de IA não é aquela com mais GPUs — é aquela onde cada GPU-hora produz valor de negócio."