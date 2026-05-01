# Capítulo 10 — Operações de Plataforma de IA em Escala

*Você construiu um ambiente de IA. Agora precisa operar uma plataforma de IA.*

---

## O Canal do Slack Que Engoliu Sua Agenda

Seis meses atrás, você provisionou uma única VM com GPU para o time de ML. Configurou os drivers, montou o storage e seguiu em frente. Parecia qualquer outra solicitação de infraestrutura — um ticket entra, um recurso sai, fecha o ciclo.

Hoje, você tem quatro times, três clusters AKS, dezenas de node pools com GPU e uma coleção crescente de endpoints do Azure OpenAI. Cada time quer seus próprios recursos, suas próprias cotas e seus próprios SLAs. Suas DMs no Slack viraram um help desk. "Pode liberar mais GPUs pra gente?" "Por que meu job de treinamento tá preso em Pending?" "Quem tá usando todas as A100s?" Você gasta mais tempo respondendo perguntas do que realmente fazendo engenharia.

Esse é o ponto de inflexão que toda organização de infraestrutura enfrenta. Você deixou de dar suporte a projetos de IA para se tornar o gargalo de uma plataforma de IA. A solução não é trabalhar mais — é construir os sistemas, políticas e automações que permitem que os times se sirvam sozinhos enquanto você mantém o controle. Este capítulo mostra como.

---

## De Projeto de IA a Plataforma de IA

### A Mentalidade de Platform Engineering

Platform engineering não é novidade. Você já faz isso há anos com aplicações web, bancos de dados e pipelines de CI/CD. A ideia central é simples: construir infraestrutura reutilizável e self-service que os times de produto consomem sem abrir tickets. Uma plataforma interna de desenvolvimento (IDP) oferece golden paths — workflows opinados e bem testados que os times seguem para ir do código à produção.

Infraestrutura de IA segue o mesmo princípio. Em vez de provisionar VMs com GPU de forma ad hoc, você cria templates. Em vez de criar namespaces Kubernetes manualmente, você oferece um portal self-service. Em vez de responder "como faço deploy de um modelo?", você disponibiliza um pipeline que faz isso.

**Infra ↔ IA — Tradução:** Platform engineering é a mesma disciplina que você já conhece — agora aplicada a GPU compute, registries de modelos e endpoints de inferência, em vez de aplicações web e bancos SQL. As camadas de abstração mudam; o raciocínio é o mesmo.

### O Que Automatizar vs. O Que Gerenciar

Nem tudo deve ser self-service. A decisão depende do raio de impacto e do custo.

| Categoria | Self-Service | Gerenciado (Requer Aprovação) |
|---|---|---|
| Namespaces de dev/test | ✅ | |
| Alocações pequenas de GPU (1–2 GPUs) | ✅ | |
| Endpoints de inferência em produção | | ✅ |
| Jobs de treinamento grandes (8+ GPUs) | | ✅ |
| Provisionamento de novos clusters | | ✅ |
| Ambientes Jupyter notebook | ✅ | |
| Criação de endpoints Azure OpenAI | | ✅ |
| Volumes de storage para datasets | ✅ | |

A regra geral: se um erro custa menos do que algumas centenas de dólares e pode ser revertido em minutos, torne self-service. Se envolve recursos caros, tráfego de produção ou impacto entre times, coloque um gate de aprovação.

---

## Multi-Tenancy para Infraestrutura de IA

### Padrões de Isolamento

Multi-tenancy em infraestrutura de IA é sobre equilibrar isolamento e eficiência. Isolamento de menos e o job de treinamento descontrolado de um time vai matar de fome todos os outros. Isolamento demais e você vai gerenciar dezenas de clusters com utilização de GPU péssima.

Existem quatro níveis de isolamento, cada um com tradeoffs diferentes:

### 📊 Matriz de Decisão: Níveis de Isolamento de Times

| Nível de Isolamento | Eficiência de Custo | Fronteira de Segurança | Overhead Operacional | Melhor Para |
|---|---|---|---|---|
| **Namespace** | ⭐⭐⭐⭐⭐ | Baixa | Baixo | Times confiáveis compartilhando um cluster |
| **Node pool** | ⭐⭐⭐⭐ | Média | Médio | Times que precisam de tipos de GPU dedicados |
| **Cluster** | ⭐⭐⭐ | Alta | Alto | Times com necessidades de compliance diferentes |
| **Subscription** | ⭐⭐ | Muito Alta | Muito Alto | Workloads regulados, billing separado |

A maioria das organizações adota um modelo híbrido: um ou dois clusters compartilhados com namespaces por time e node pools de GPU dedicados, além de clusters separados para inferência em produção e workloads regulados.

### RBAC com Escopo para Acesso Multi-Time a GPUs

No AKS, o RBAC deve limitar cada time ao seu próprio namespace. Use grupos do Microsoft Entra ID mapeados para ClusterRoles do Kubernetes para controle de acesso consistente.

```yaml
# team-data-science-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: team-data-science
  name: gpu-workload-role
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "persistentvolumeclaims"]
    verbs: ["get", "list", "create", "delete", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "create", "update", "delete"]
```

Vincule essa role ao grupo do Microsoft Entra ID do time. Eles podem fazer deploy de workloads no namespace deles, mas não conseguem tocar nos recursos de outros times nem em objetos no nível do cluster.

### Enforcement de Resource Quotas

Sem cotas, um time inevitavelmente vai consumir todas as GPUs disponíveis. ResourceQuotas do Kubernetes impõem limites rígidos por namespace.

```yaml
# team-data-science-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  namespace: team-data-science
  name: gpu-quota
spec:
  hard:
    requests.cpu: "64"
    requests.memory: 256Gi
    requests.nvidia.com/gpu: "8"
    limits.cpu: "128"
    limits.memory: 512Gi
    limits.nvidia.com/gpu: "8"
    pods: "50"
```

Isso limita o time de data science a 8 GPUs, 64 cores de CPU e 256 GiB de memória. Eles podem distribuir esse orçamento entre qualquer número de pods — um job com 8 GPUs ou oito jobs com 1 GPU cada — mas não podem exceder o total.

⚠️ **Cuidado em Produção:** ResourceQuotas só são aplicadas no momento do scheduling. Se você reduzir uma cota abaixo do uso atual, os pods existentes não serão despejados — mas novos pods serão rejeitados. Planeje mudanças de cota durante janelas de manutenção, quando os times podem reagendar seus workloads.

### Isolamento de Rede

Network policies impedem tráfego lateral entre namespaces de times diferentes. Isso é especialmente importante quando os times lidam com classificações de dados distintas.

```yaml
# deny-cross-namespace.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  namespace: team-data-science
  name: deny-other-namespaces
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
```

Essa policy permite que pods dentro do namespace `team-data-science` se comuniquem entre si, mas bloqueia todo tráfego de entrada de outros namespaces. Você precisará adicionar regras explícitas para serviços compartilhados, como registries de modelos ou endpoints de monitoramento.

---

## GPU Scheduling e Gerenciamento de Filas

### O Problema Fundamental

Recursos de GPU são finitos e caros. Um único nó A100 custa aproximadamente US$ 3 por hora no Azure. Quando você tem 20 nós e 4 times, o scheduling padrão do Kubernetes — primeiro a chegar, primeiro a ser servido — gera atrito constante. Jobs de treinamento monopolizam GPUs por horas. Workloads de inferência ficam sem recursos. Data scientists submetem 10 jobs de uma vez e ficam se perguntando por que só 2 estão rodando.

Você precisa de scheduling que entenda prioridades, fairness e as características únicas de workloads de IA.

### Scheduling Nativo do Kubernetes

Comece pelo básico. Todo workload de GPU deve especificar requests e limits de recursos. Sem eles, o Kubernetes não consegue tomar decisões de scheduling inteligentes.

```yaml
# training-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: bert-fine-tuning
  namespace: team-nlp
spec:
  template:
    spec:
      containers:
        - name: trainer
          image: myregistry.azurecr.io/bert-trainer:v2.1
          resources:
            requests:
              cpu: "8"
              memory: 32Gi
              nvidia.com/gpu: "4"
            limits:
              cpu: "16"
              memory: 64Gi
              nvidia.com/gpu: "4"
      restartPolicy: Never
      tolerations:
        - key: "sku"
          operator: "Equal"
          value: "gpu"
          effect: "NoSchedule"
      nodeSelector:
        accelerator: nvidia-a100
```

💡 **Dica:** Sempre defina GPU requests iguais aos GPU limits. Diferentemente de CPU e memória, GPUs não podem ser overcommitted. Um pod que solicita 1 GPU vai ser dono exclusivo daquela GPU independentemente do valor do limit, então valores diferentes só geram confusão.

### Priority Classes

Priority classes dizem ao scheduler quais workloads são mais importantes. Defina uma hierarquia clara que reflita as necessidades do negócio.

```yaml
# priority-classes.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-inference
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Production model-serving workloads — never preempted by training."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: scheduled-training
value: 100000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Scheduled training jobs with deadlines."
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: exploratory
value: 1000
globalDefault: true
preemptionPolicy: Never
description: "Interactive notebooks, experiments — can be preempted."
```

Com essa hierarquia, um pod de inferência em produção vai fazer preemption de um job de treinamento se GPUs estiverem escassas, e jobs de treinamento vão fazer preemption de notebooks exploratórios. Mas workloads exploratórios nunca fazem preemption de nada — eles esperam.

💡 **Dica:** Use `preemptionPolicy: Never` para workloads exploratórios. Isso evita uma debandada onde 50 pods de notebook tentam fazer preemption uns dos outros em um ambiente de GPU limitado.

### Kueue: Fair Scheduling para Workloads Batch de IA

O Kubernetes não entende nativamente enfileiramento de jobs. Se você submeter 100 jobs de treinamento e tiver capacidade para 10, o Kubernetes vai criar 100 pods pendentes. O Kueue resolve isso adicionando uma camada de filas que admite jobs com base na capacidade disponível e em políticas de fair-share.

```yaml
# cluster-queue.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: gpu-cluster-queue
spec:
  namespaceSelector: {}
  resourceGroups:
    - coveredResources: ["cpu", "memory", "nvidia.com/gpu"]
      flavors:
        - name: a100-spot
          resources:
            - name: "cpu"
              nominalQuota: 128
            - name: "memory"
              nominalQuota: 512Gi
            - name: "nvidia.com/gpu"
              nominalQuota: 16
        - name: a100-ondemand
          resources:
            - name: "cpu"
              nominalQuota: 64
            - name: "memory"
              nominalQuota: 256Gi
            - name: "nvidia.com/gpu"
              nominalQuota: 8
  preemption:
    withinClusterQueue: LowerPriority
---
# local-queue.yaml
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  namespace: team-nlp
  name: team-nlp-queue
spec:
  clusterQueue: gpu-cluster-queue
```

O Kueue mantém jobs na fila até que recursos estejam disponíveis e então os admite em ordem de prioridade. Os times submetem jobs para sua LocalQueue; a ClusterQueue controla a capacidade global. Isso elimina o problema dos "100 pods pendentes" — os jobs ficam enfileirados, não agendados, até que haja espaço.

### Volcano: Gang Scheduling para Treinamento Distribuído

Jobs de treinamento distribuído precisam de múltiplas GPUs em múltiplos nós iniciando simultaneamente. O scheduling padrão do Kubernetes não garante isso — ele pode agendar 3 de 4 pods necessários, deixando os três ociosos enquanto esperam pelo quarto.

O Volcano oferece gang scheduling: todos os pods de um job iniciam juntos, ou nenhum inicia. Isso previne deadlocks e desperdício de recursos.

```yaml
# distributed-training-volcano.yaml
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata:
  name: distributed-llm-training
  namespace: team-nlp
spec:
  minAvailable: 4
  schedulerName: volcano
  plugins:
    svc: ["--publish-not-ready-addresses"]
  tasks:
    - replicas: 4
      name: worker
      template:
        spec:
          containers:
            - name: trainer
              image: myregistry.azurecr.io/llm-trainer:v1.0
              resources:
                requests:
                  nvidia.com/gpu: "4"
                limits:
                  nvidia.com/gpu: "4"
              env:
                - name: WORLD_SIZE
                  value: "4"
          restartPolicy: OnFailure
```

O campo `minAvailable: 4` diz ao Volcano: não agende nenhum worker a menos que consiga agendar todos os quatro. Isso previne alocação parcial — a fonte mais comum de horas de GPU desperdiçadas em treinamento distribuído.

---

## Gerenciamento de Cotas e Capacidade

### A Pilha de Cotas

A capacidade de GPU é gerenciada em múltiplas camadas. Pule qualquer uma delas e você vai bater em um muro.

| Camada | Mecanismo | Quem Gerencia |
|---|---|---|
| **Azure subscription** | Cotas regionais de vCPU | Admin de cloud (portal ou solicitação de suporte) |
| **Cluster AKS** | Limites de scaling de node pools | Time de plataforma |
| **Namespace Kubernetes** | Objetos ResourceQuota | Time de plataforma |
| **Kueue** | Cotas nominais de ClusterQueue | Time de plataforma |
| **Nível do time** | Admissão via LocalQueue | Self-service dentro dos limites |

### Reserva de Capacidade

Para workloads de inferência em produção que não toleram atrasos de scheduling, use Azure Capacity Reservations. Isso garante que tamanhos específicos de VM estejam disponíveis na sua região quando você precisar.

```bash
# Reserve 4x Standard_NC24ads_A100_v4 in East US
az capacity reservation group create \
  --resource-group rg-ai-platform \
  --name crg-inference-prod \
  --location eastus

az capacity reservation create \
  --resource-group rg-ai-platform \
  --capacity-reservation-group crg-inference-prod \
  --name cr-a100-inference \
  --sku Standard_NC24ads_A100_v4 \
  --capacity 4
```

Você paga pela capacidade reservada usando ou não — mas tem a garantia de que as VMs estarão lá. Para inferência em produção atendendo tráfego em tempo real, esse tradeoff quase sempre vale a pena.

### Workflows de Solicitação e Aprovação

Para alocações de GPU acima do limite self-service, construa um workflow leve de aprovação. Não precisa ser complexo — um template de issue no GitHub ou um formulário no Teams que aciona um Azure Logic App funciona bem.

O workflow deve capturar: qual time está solicitando, quantas GPUs, por quanto tempo, qual tipo de workload (treinamento vs. inferência) e uma justificativa de negócio. Direcione aprovações para o líder do time de plataforma em solicitações padrão e para a liderança de engenharia em alocações grandes. Aprove automaticamente solicitações dentro de orçamentos pré-aprovados e escale todo o resto.

O objetivo não é burocracia — é visibilidade. Você quer saber sobre alocações grandes de GPU antes que aconteçam, não depois que sua cota estiver esgotada.

### Monitoramento de Uso de Cotas

Construa um dashboard que mostre o consumo de cotas em todas as camadas. A Azure CLI dá visibilidade no nível da subscription:

```bash
# Check GPU quota usage in East US
az vm list-usage --location eastus \
  --query "[?contains(name.value, 'NC') || contains(name.value, 'ND')].{Name:name.localizedValue, Current:currentValue, Limit:limit}" \
  --output table
```

Configure alertas quando qualquer cota ultrapassar 80% de utilização. Com 80%, você ainda tem tempo de solicitar um aumento. Com 95%, você está a um job de treinamento de uma parada total.

💡 **Dica:** Aumentos de cota no Azure podem levar dias para SKUs de GPU em regiões populares. Solicite o aumento bem antes de precisar — idealmente quando atingir 60% de utilização, não 90%.

---

## Design de SLA/SLO para Endpoints de Inferência

### Definindo o Que "Bom" Significa

Todo endpoint de inferência precisa de service-level objectives claros. Sem eles, cada pico de latência vira um incêndio e o workload de cada time é igualmente "crítico."

### Matriz de Decisão: Tiers de SLO para Serviços de IA

| Tier | Latência (P99) | Disponibilidade | Throughput | Exemplos de Uso |
|---|---|---|---|---|
| **Real-time** | < 200ms | 99,95% | > 1000 req/s | Chat voltado ao cliente, ranking de busca |
| **Near-real-time** | < 2s | 99,9% | > 100 req/s | Moderação de conteúdo, recomendações |
| **Batch** | < 1 hora | 99,5% | N/A (baseado em jobs) | Processamento de documentos, geração de embeddings |

Defina esses tiers cedo e atribua cada workload a um deles. Isso direciona decisões de arquitetura — endpoints real-time precisam de autoscaling e reservas de capacidade; workloads batch podem usar instâncias spot e scheduling preemptível.

### Error Budgets para Serviços de IA

Error budgets quantificam quanta instabilidade você pode tolerar. Um SLO de disponibilidade de 99,9% dá a você 43 minutos de downtime por mês. Gaste esse orçamento com sabedoria.

Acompanhe o consumo do error budget em tempo real. Quando o orçamento está queimando rápido — digamos que você consumiu 50% na primeira semana — congele mudanças e foque em confiabilidade. Quando o orçamento está saudável, você tem espaço para deploys e experimentos.

### Health Probes para Model Serving

Containers de modelo falham de maneiras que health checks tradicionais não detectam. Um container pode estar rodando, mas o modelo ainda não carregou, ou a GPU está em estado ruim, ou a inferência está retornando lixo. Projete health probes que verifiquem a funcionalidade real do modelo.

```yaml
# inference-deployment.yaml (partial)
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
  failureThreshold: 2
startupProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30
```

⚠️ **Cuidado em Produção:** Modelos grandes podem levar de 5 a 10 minutos para carregar na memória da GPU. Defina `startupProbe.failureThreshold` alto o suficiente para cobrir o tempo de carregamento do seu maior modelo, ou o Kubernetes vai matar o container em um loop de restart antes que o modelo esteja pronto.

### Degradação Graciosa

Quando seu modelo principal está sobrecarregado ou fora do ar, não retorne erros — degrade graciosamente. Padrões comuns:

- **Modelos de fallback:** Redirecione para um modelo menor e mais rápido quando a latência do modelo principal excede os thresholds do SLO.
- **Respostas em cache:** Retorne resultados em cache para consultas comuns enquanto o modelo se recupera.
- **Buffering baseado em fila:** Aceite requisições em uma fila e processe-as quando a capacidade retornar, devolvendo um status "processando" ao cliente.
- **Circuit breakers:** Pare de enviar tráfego para um endpoint que está falhando após um limite de erros, dando tempo para ele se recuperar.

---

## Fleet Management

### A Realidade Multi-Cluster

Em escala, você não vai ter um cluster — vai ter vários. Inferência em produção no East US e West Europe. Clusters de treinamento com node pools spot. Um cluster de dev/test com SKUs de GPU mais baratos. Gerenciar tudo isso de forma consistente é a diferença entre uma plataforma e uma coleção de snowflakes.

Um layout típico de fleet para uma organização de IA de médio porte é assim:

| Cluster | Região | Finalidade | SKUs de GPU | Scaling de Nós |
|---|---|---|---|---|
| prod-inference-eastus | East US | Serving em tempo real | A100, A10G | Capacidade reservada |
| prod-inference-westeu | West Europe | Serving em tempo real (DR) | A100, A10G | Capacidade reservada |
| training-eastus | East US | Treinamento, fine-tuning | A100, H100 | Spot + on-demand |
| dev-eastus | East US | Dev/test, notebooks | T4, A10G | Somente spot |

Cada cluster tem uma finalidade distinta, e essa finalidade direciona sua configuração — tolerância a spot, seleção de SKU de GPU, comportamento de scaling e cadência de upgrades. Não tente fazer um cluster servir para tudo. O overhead operacional de gerenciar quatro clusters focados é menor do que gerenciar um cluster que tenta atender todos os padrões de workload.

### GitOps para Infraestrutura de GPU

Use Flux ou ArgoCD para gerenciar a configuração dos clusters de forma declarativa. Cada cluster puxa sua configuração de um repositório Git. Mudanças passam por pull requests, são revisadas e são implantadas automaticamente.

```text
fleet-config/
├── base/
│   ├── namespaces/
│   ├── rbac/
│   ├── resource-quotas/
│   ├── network-policies/
│   ├── priority-classes/
│   └── kueue/
├── clusters/
│   ├── prod-eastus/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   ├── prod-westeurope/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   └── dev-eastus/
│       ├── kustomization.yaml
│       └── patches/
```

O diretório `base/` contém a configuração compartilhada — namespaces, RBAC, cotas, priority classes. Cada diretório de cluster aplica patches específicos do ambiente por cima. Precisa adicionar um novo time? Crie o namespace e a cota em `base/`, e todos os clusters pegam na próxima sincronização.

### Rolling Upgrades na Fleet

Além dos drivers de GPU, você vai precisar coordenar versões do CUDA toolkit, atualizações do container runtime e upgrades de versão do Kubernetes em toda a sua fleet. Divergências de versão entre clusters são uma fonte constante de bugs do tipo "funciona no dev mas não na prod."

Mantenha uma matriz de compatibilidade da fleet que rastreie as versões exatas de cada componente em cada cluster. Atualize-a a cada mudança. Quando um data scientist reportar que o job de treinamento dele falha no cluster de produção mas funciona no dev, a primeira coisa que você verifica é essa matriz.

```text
Fleet Compatibility Matrix (2024-Q4)
─────────────────────────────────────────────────────────────
Component          prod-eastus    prod-westeu    training    dev
─────────────────────────────────────────────────────────────
Kubernetes         1.29.4         1.29.4         1.29.4      1.30.1
GPU Driver         550.54.15      550.54.15      550.54.15   550.90.07
CUDA Toolkit       12.4           12.4           12.4        12.6
cuDNN              9.1.0          9.1.0          9.1.0       9.3.0
Container Runtime  containerd 1.7 containerd 1.7 containerd 1.7 containerd 1.7
─────────────────────────────────────────────────────────────
```

💡 **Dica:** Mantenha os clusters de produção em versões idênticas. Deixe o cluster de dev rodar uma versão à frente como seu sistema de alerta antecipado. Quando uma nova versão do CUDA quebrar um framework de treinamento popular, você quer descobrir isso no dev — não no meio de um treinamento de duas semanas em produção.

### Upgrades de Driver de GPU

Upgrades de driver de GPU são a operação mais perigosa na sua fleet. Um driver ruim pode causar corrupção silenciosa de dados no treinamento de modelos, kernel panics ou falha total da GPU. Trate upgrades de driver com o mesmo cuidado que um upgrade de kernel.

⚠️ **Cuidado em Produção:** Nunca faça upgrade de drivers de GPU em todos os clusters simultaneamente. Use uma estratégia de deploy canário: faça upgrade no cluster de dev primeiro, rode workloads de validação por 48 horas, depois avance para um cluster de produção. Espere mais 48 horas antes de avançar para o restante da fleet. Erros silenciosos de GPU podem levar dias para aparecer nas curvas de loss de treinamento.

Construa imagens de VM padronizadas com drivers de GPU pré-instalados usando Azure Image Builder ou Packer. Isso garante que cada nó em cada cluster rode versões idênticas de driver. Nunca dependa da instalação de driver no boot — é lento, frágil e adiciona latência imprevisível de inicialização aos seus node pools.

---

## Observabilidade em Escala

### Monitoramento Centralizado

Quando você tem múltiplos clusters, precisa de uma visão unificada. O Azure Monitor com Container Insights pode agregar métricas entre clusters, mas para observabilidade específica de GPU, o DCGM Exporter alimentando uma instância centralizada de Prometheus (ou Azure Monitor Managed Prometheus) dá a granularidade que você precisa.

Métricas-chave para centralizar:

| Métrica | Fonte | Threshold de Alerta |
|---|---|---|
| Utilização de GPU | DCGM Exporter | < 20% por 1h (desperdício) |
| Memória de GPU usada | DCGM Exporter | > 95% (risco de OOM) |
| Temperatura da GPU | DCGM Exporter | > 83°C |
| Latência de inferência P99 | Métricas da aplicação | > threshold do SLO |
| Profundidade da fila | Métricas do Kueue | > 50 jobs pendentes |
| Utilização do node pool | Métricas do AKS | > 85% |
| Consumo de cota | Azure Monitor | > 80% |

### Dashboards Cross-Cluster

Construa dashboards no Grafana que mostrem a saúde da fleet inteira em uma olhada. O dashboard de nível superior deve responder três perguntas em menos de 10 segundos:

1. **Algo está quebrado?** Status vermelho/verde para cada endpoint de inferência em todos os clusters.
2. **Algo está sendo desperdiçado?** Mapa de calor de utilização de GPU mostrando capacidade subutilizada.
3. **Algo está em risco?** Consumo de cotas e tendências de capacidade que preveem quando você vai ficar sem recursos.

Dashboards de drill-down devem permitir ir de "utilização de GPU está baixa no cluster prod-eastus" até "o namespace do team-nlp tem 4 GPUs ociosas alocadas a um job concluído que nunca foi limpo."

### Atribuição de Custos

Quando quatro times compartilham um cluster de GPU, alguém vai perguntar "quanto cada time está gastando?" Construa a atribuição de custos desde o primeiro dia — é muito mais difícil implementar depois.

Tagueie cada recurso com o time proprietário. Use labels do Kubernetes de forma consistente:

```yaml
metadata:
  labels:
    team: data-science
    project: recommendation-engine
    cost-center: cc-4521
    environment: production
```

Alimente essas labels na sua ferramenta de monitoramento de custos — seja Azure Cost Management, Kubecost ou OpenCost. Reporte custos por time e projeto mensalmente. Times que enxergam seu gasto com GPU são times que limpam recursos ociosos.

### Planejamento de Capacidade

Colete dados históricos de utilização e use-os para prever demanda. Uma regressão linear simples sobre tendências semanais de utilização de GPU vai dizer quando você vai esgotar a capacidade atual. Considere projetos futuros conhecidos — se o time de NLP vai começar um treinamento de large language model no próximo trimestre, contabilize esse pico agora.

Planeje capacidade de GPU com 8 a 12 semanas de antecedência. Isso contempla os tempos de espera para aumento de cotas no Azure, ciclos de aquisição de instâncias reservadas e o tempo necessário para provisionar e configurar novos node pools.

---

## Padrões de Self-Service

### Onboarding de Times

O onboarding de novos times deve ser um pull request, não um ticket. Construa módulos Terraform ou templates Backstage que criam tudo o que um time precisa de uma só vez.

Um módulo de onboarding de time deve provisionar:

- Namespace Kubernetes com resource quotas
- Bindings de RBAC para o grupo do Microsoft Entra ID do time
- Network policies
- LocalQueue do Kueue vinculada à cluster queue
- Acesso ao Azure Container Registry
- Storage class padrão e persistent volume claims
- Dashboards de monitoramento pré-filtrados para o namespace do time

```bash
# Team onboarding via Terraform
terraform apply -var="team_name=robotics" \
  -var="gpu_quota=4" \
  -var="cpu_quota=32" \
  -var="memory_quota=128Gi" \
  -var="aad_group_id=<group-object-id>" \
  -target=module.team_onboarding
```

Um comando. Cinco minutos. O time tem tudo o que precisa para começar a fazer deploy de workloads. Sem tickets, sem espera, sem mensagens no Slack.

### Ambientes Pré-Configurados

Data scientists não querem construir imagens Docker nem escrever manifestos Kubernetes. Eles querem um notebook com GPUs. Encontre-os onde eles estão.

- **JupyterHub no AKS:** Faça deploy do JupyterHub com perfis de servidor habilitados para GPU. Os cientistas escolhem um perfil ("2x A100, PyTorch 2.1, CUDA 12.1"), clicam em iniciar e recebem um notebook com GPUs conectadas. O time de plataforma mantém os perfis.
- **VS Code Dev Containers:** Forneça configurações `.devcontainer` com passthrough de GPU. Data scientists clonam um repositório e recebem um ambiente de desenvolvimento totalmente configurado.
- **Templates de jobs de treinamento:** Ofereça uma CLI simples ou formulário web: "Quero fazer fine-tuning de um modelo. Aqui está meu script, aqui está meu dataset, aqui está quantas GPUs eu preciso." O template gera o manifesto de Kubernetes Job, submete pelo Kueue e envia ao cientista um link para os logs.

**Infra ↔ IA — Tradução:** Esse é o mesmo padrão de abstração que você usa há anos. VMs viraram containers. Containers viraram funções serverless. Agora, acesso a GPU vira um dropdown de perfil. Toda geração de infraestrutura passa por esse arco do manual ao self-service.

---

## Checklist do Capítulo

- Definiu fronteiras de isolamento para cada time (namespace, node pool, cluster ou subscription)
- Implementou ResourceQuotas para limitar GPU, CPU e memória por namespace
- Configurou RBAC com escopo usando grupos do Microsoft Entra ID mapeados para roles do Kubernetes
- Aplicou network policies para impedir tráfego entre namespaces
- Criou priority classes separando inferência em produção, treinamento e workloads exploratórios
- Fez deploy do Kueue para enfileiramento de jobs e fair-share scheduling
- Avaliou o Volcano para treinamento distribuído com gang scheduling
- Configurou Azure capacity reservations para VMs de GPU de inferência em produção
- Configurou alertas de uso de cota no threshold de 80%
- Definiu tiers de SLO (real-time, near-real-time, batch) para endpoints de inferência
- Implementou health probes com timeouts de startup probe que cobrem o tempo de carregamento do modelo
- Construiu uma estrutura de repositório GitOps para fleet management multi-cluster
- Estabeleceu uma estratégia canário para upgrades de driver de GPU
- Centralizou observabilidade com dashboards de monitoramento de GPU cross-cluster
- Implementou atribuição de custos com labels Kubernetes consistentes
- Automatizou onboarding de times via módulos Terraform ou templates de plataforma
- Forneceu ambientes self-service (JupyterHub, templates de treinamento) para data scientists

---

## Próximos Passos

Sua plataforma de IA está operando em escala — multi-tenant, com scheduling bem definido e observável. Os times conseguem fazer onboarding sozinhos, submeter jobs de treinamento por filas e fazer deploy de endpoints de inferência com SLOs claros. Você saiu de responder mensagens no Slack para engenheirar sistemas.

Agora vamos mergulhar no serviço que está gerando mais conversas sobre IA do que qualquer outro: Azure OpenAI. O Capítulo 11 cobre tokens, throughput e provisioned capacity — o capítulo de planejamento de capacidade que todo deploy de Azure OpenAI precisa.
