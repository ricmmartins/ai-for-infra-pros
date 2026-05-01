# Guias Rápidos — Referência Rápida para Engenheiros de Infraestrutura de IA

Uma referência condensada e visual cobrindo todos os capítulos do livro. Imprima, salve nos favoritos, fixe no seu monitor — estes são os números, comandos e checklists que você vai consultar diariamente.

---

## Comparação de VMs GPU no Azure *(Cap. 3, Cap. 4)*

| SKU da VM | GPU | VRAM | Ideal Para | Inferência | Treinamento | ~Custo/hr |
|-----------|-----|------|------------|------------|-------------|-----------|
| `Standard_NC4as_T4_v3` | 1× T4 | 16 GB | Inferência com bom custo-benefício | ✅✅ | ❌ | ~$0,53 |
| `Standard_NC6s_v3` | 1× V100 | 16 GB | Cargas de trabalho de IA em geral | ✅ | ⚠️ | ~$0,90 |
| `Standard_NC24ads_A100_v4` | 1× A100 | 80 GB | Treinamento/inferência com GPU única | ✅✅ | ✅✅ | ~$3,67 |
| `Standard_NV36ads_A10_v5` | 1× A10 | 24 GB | Visualização + IA leve | ✅ | ❌ | ~$1,80 |
| `Standard_ND96asr_v4` | 8× A100 | 640 GB total | Treinamento de LLM com múltiplas GPUs | ✅✅✅ | ✅✅✅ | ~$27,20 |
| `Standard_ND96isr_H100_v5` | 8× H100 | 640 GB total | Treinamento de modelos de fronteira | ✅✅✅ | ✅✅✅ | ~$40+ |

💡 **Dica Pro**: Para inferência, comece com T4 (`NC4as_T4_v3`). Só migre para A10 ou A100 quando comprovar que o modelo não cabe em 16 GB de VRAM ou precisa de maior throughput.

---

## Referência Rápida: CPU vs GPU *(Cap. 3)*

| Atributo | CPU | GPU |
|----------|-----|-----|
| Número de núcleos | 8–128 | 2.560–16.896 núcleos CUDA |
| Arquitetura | Otimizada para lógica serial/ramificada | Otimizada para operações SIMD paralelas |
| Memória | RAM compartilhada do sistema (até TBs) | VRAM dedicada (16–80 GB por GPU) |
| Melhor para | Aplicações web, ETL, ML clássico, pré-processamento | Deep learning, embeddings, álgebra matricial |
| Famílias Azure | Dv5, Ev5, Fv2 | NCas_T4, NC_A100, ND_H100 |
| Perfil de custo | 💲 | 💲💲💲 |

⚠️ **Armadilha em Produção**: Não coloque pré-processamento (redimensionamento de imagens, tokenização) em GPUs. Use nodes de CPU para preparação de dados e reserve a GPU exclusivamente para computação de modelos.

---

## Matemática de Memória GPU *(Cap. 4)*

Use estas fórmulas para calcular se o seu modelo cabe na VRAM da GPU antes de provisionar.

### Memória de Parâmetros do Modelo

| Precisão | Fórmula | Modelo 7B | Modelo 13B | Modelo 70B |
|----------|---------|-----------|------------|------------|
| FP32 | `params × 4 bytes` | 28 GB | 52 GB | 280 GB |
| FP16 / BF16 | `params × 2 bytes` | 14 GB | 26 GB | 140 GB |
| INT8 | `params × 1 byte` | 7 GB | 13 GB | 70 GB |
| INT4 (GPTQ/AWQ) | `params × 0.5 bytes` | 3,5 GB | 6,5 GB | 35 GB |

### Memória para Treinamento (Fine-Tuning Completo)

```
VRAM Total ≈ Pesos do modelo + Gradientes + Estados do otimizador + Ativações
           ≈ (params × 2) + (params × 2) + (params × 8) + ativações
           ≈ params × 12 bytes (AdamW, precisão mista FP16) + ativações
```

**Exemplo**: Modelo 7B com AdamW → `7B × 12 = 84 GB` mínimo → requer 2× A100-80GB ou gradient checkpointing.

### Memória para Inferência (Estimativa Rápida)

```
VRAM ≈ Pesos do modelo + KV cache
KV cache por token ≈ 2 × num_layers × hidden_dim × 2 bytes (FP16)
```

💡 **Dica Pro**: Quando um modelo *mal cabe* na VRAM, você vai ter OOM sob carga porque o KV cache cresce com o comprimento da sequência e o tamanho do batch. Deixe 20% de margem de VRAM.

### Calculadora de Número de GPUs

```
GPUs mínimas necessárias = Memória total do modelo ÷ VRAM por GPU × 1,2 (margem de segurança)
```

| Modelo | Precisão | VRAM Mín. | Cabe Em |
|--------|----------|-----------|---------|
| Llama 2 7B | FP16 | 14 GB | 1× T4 (apertado) ou 1× A10 |
| Llama 2 13B | FP16 | 26 GB | 1× A100-80GB |
| Llama 2 70B | FP16 | 140 GB | 2× A100-80GB |
| Llama 2 70B | INT4 | 35 GB | 1× A100-80GB |

⚠️ **Armadilha em Produção**: Esses valores são *apenas para os pesos*. O KV cache para um contexto de 4K com batch size 32 pode adicionar 8-12 GB. Sempre faça benchmark de memória real sob carga realista.

---

## Checklist de Segurança para Cargas de IA *(Cap. 8)*

| # | Controle | Descrição | Prioridade |
|---|----------|-----------|------------|
| 1 | Managed Identity para todos os serviços | Sem secrets de service principal; use `SystemAssigned` ou `UserAssigned` | 🔴 Crítico |
| 2 | Private Endpoints em todos os lugares | Azure ML, Storage, ACR, Key Vault, OpenAI — sem endpoints públicos | 🔴 Crítico |
| 3 | Key Vault para todos os secrets | Chaves de API, connection strings, certificados — nunca no código ou variáveis de ambiente | 🔴 Crítico |
| 4 | Segmentação de rede | Hub-spoke VNet, NSGs restringindo tráfego leste-oeste | 🔴 Crítico |
| 5 | Logs de diagnóstico habilitados | Todos os recursos → workspace central do Log Analytics | 🟡 Alto |
| 6 | RBAC com privilégio mínimo | `Cognitive Services User` e não `Contributor`; escopo no recurso, não no RG | 🟡 Alto |
| 7 | Testes de prompt injection | Validação de entrada, filtragem de conteúdo habilitada no Azure OpenAI | 🟡 Alto |
| 8 | Criptografia de dados | TLS 1.2+ em trânsito, SSE com CMK em repouso para dados sensíveis | 🟡 Alto |
| 9 | Controle de saída (egress) | NSG/Firewall restringindo tráfego de saída dos nodes de inferência | 🟡 Alto |
| 10 | Varredura de imagens de contêiner | Apenas imagens assinadas do ACR privado; bloquear tag `latest` | 🟠 Médio |
| 11 | Limitação de taxa da API | Azure API Management ou Application Gateway WAF | 🟠 Médio |
| 12 | Integridade de artefatos de modelo | Validação de checksum em arquivos de modelo baixados do storage | 🟠 Médio |

---

## Monitoramento e Observabilidade *(Cap. 7)*

### Os Sinais de Ouro da GPU

| Sinal | Métrica | Fonte | Limite para Alerta |
|-------|---------|-------|--------------------|
| **Utilização** | `DCGM_FI_DEV_GPU_UTIL` | DCGM Exporter | < 20% (desperdício) ou > 95% (saturação) |
| **Memória** | `DCGM_FI_DEV_FB_USED` / `FB_FREE` | DCGM Exporter | > 90% usado (risco de OOM) |
| **Temperatura** | `DCGM_FI_DEV_GPU_TEMP` | DCGM Exporter | > 83°C (thermal throttling) |
| **Erros** | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | DCGM Exporter | > 0 (falha de hardware) |

### Métricas no Nível da Aplicação

| Métrica | O Que Indica | Ferramenta |
|---------|-------------|------------|
| Latência de inferência P50/P95/P99 | Experiência do usuário e conformidade com SLA | Application Insights |
| Requisições por segundo (RPS) | Pressão de carga e planejamento de capacidade | Application Insights |
| Taxa de erros (4xx, 5xx) | Uso incorreto pelo cliente vs. problemas no servidor | Application Insights |
| Throughput de tokens (TPM) | Taxa de consumo do Azure OpenAI | Azure Monitor |
| Taxa de 429 | Frequência de throttling | Azure Monitor / Log Analytics |
| Profundidade da fila | Contrapressão em pipelines assíncronos | Prometheus / métrica customizada |

### Consultas KQL Essenciais

```kusto
// Desempenho da VM GPU nas últimas 24 horas
InsightsMetrics
| where Name == "dcgm_gpu_utilization"
| where TimeGenerated > ago(24h)
| summarize avg(Val), max(Val), percentile(Val, 95) by bin(TimeGenerated, 5m), Computer
| render timechart

// Erros 429 do Azure OpenAI por deployment
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultType == "429"
| summarize count() by bin(TimeGenerated, 1h), _ResourceId
| render barchart
```

---

## Comandos de MLOps *(Cap. 6)*

### Essenciais do Azure ML CLI v2

```bash
# Registrar um modelo a partir de arquivos locais
az ml model create --name fraud-detector --version 1 \
  --path ./model/ --type custom_model

# Criar um endpoint online gerenciado
az ml online-endpoint create --name fraud-api \
  --auth-mode aml_token

# Fazer deploy de um modelo no endpoint
az ml online-deployment create --name blue \
  --endpoint-name fraud-api \
  --model azureml:fraud-detector:1 \
  --instance-type Standard_NC4as_T4_v3 \
  --instance-count 2 \
  --file deployment.yml

# Divisão de tráfego blue-green
az ml online-endpoint update --name fraud-api \
  --traffic "blue=80 green=20"

# Testar o endpoint
az ml online-endpoint invoke --name fraud-api \
  --request-file sample-request.json
```

### Comandos de Ciclo de Vida do Modelo

```bash
# Listar versões do modelo
az ml model list --name fraud-detector --output table

# Arquivar versão antiga do modelo (exclusão suave)
az ml model archive --name fraud-detector --version 1

# Baixar artefatos do modelo para inspeção
az ml model download --name fraud-detector --version 2 \
  --download-path ./local-model/
```

### Trigger de Pipeline MLOps

```bash
# Submeter uma execução de pipeline de treinamento
az ml job create --file pipeline.yml \
  --set inputs.training_data.path=azureml:transactions:latest

# Monitorar um job em execução
az ml job show --name <job-name> --output table

# Acompanhar logs do job em tempo real
az ml job stream --name <job-name>
```

💡 **Dica Pro**: Sempre versione seus modelos com versionamento semântico no registro de modelos. Quando um endpoint de inferência degradar, você precisa fazer rollback para `fraud-detector:3`, não para "o que quer que estivesse em produção na terça passada."

---

## Comandos Rápidos de Deploy de Infraestrutura *(Cap. 5)*

### Criar uma VM GPU

```bash
az vm create \
  --resource-group rg-ai-lab \
  --name vm-gpu-inference \
  --image Ubuntu2204 \
  --size Standard_NC4as_T4_v3 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --priority Spot \
  --max-price 0.35 \
  --eviction-policy Deallocate
```

⚠️ **Armadilha em Produção**: Sempre verifique a cota de GPU *antes* de fazer deploy: `az vm list-usage --location eastus -o table | grep -i "NC"`. Solicitações de cota levam de 1 a 5 dias úteis.

### Node Pool GPU no AKS (Terraform)

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpuinfer"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_NC4as_T4_v3"
  mode                  = "User"
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = 6

  node_labels = {
    "hardware" = "gpu"
    "gpu-type" = "t4"
  }

  node_taints = ["nvidia.com/gpu=present:NoSchedule"]

  tags = {
    Environment  = "production"
    WorkloadType = "inference"
    CostCenter   = "ai-platform"
  }
}
```

### Manifesto de Pod GPU no Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: inference-server
spec:
  tolerations:
  - key: "nvidia.com/gpu"
    operator: "Equal"
    value: "present"
    effect: "NoSchedule"
  nodeSelector:
    hardware: gpu
  containers:
  - name: model
    image: myacr.azurecr.io/inference:v2.1
    resources:
      limits:
        nvidia.com/gpu: 1
      requests:
        nvidia.com/gpu: 1
        memory: "8Gi"
        cpu: "4"
```

---

## Referência Rápida de Engenharia de Custos *(Cap. 9)*

### Alavancas de Otimização de Custos

| Alavanca | Faixa de Economia | Risco | Melhor Para |
|----------|-------------------|-------|-------------|
| **Spot VMs** | 60-90% | Evicção (apenas batch) | Treinamento, inferência em lote |
| **Instâncias Reservadas (1 ano)** | 20-35% | Compromisso | Inferência em estado estável |
| **Instâncias Reservadas (3 anos)** | 40-55% | Compromisso longo | Cargas permanentes |
| **Agendamento de VMs** | 30-50% | Latência de cold start | Cargas em horário comercial |
| **Right-sizing** | 15-40% | Requer testes de performance | Clusters superprovisionados |
| **PTU vs Standard (OpenAI)** | 20-50% | Compromisso de capacidade | Uso sustentado >100K TPM |
| **Quantização (INT8/INT4)** | 50-75% de redução de GPU | Leve perda de acurácia | Inferência (não treinamento) |

### Estimativa Rápida de Custos

```
Custo mensal de GPU = (Taxa por hora × Horas/dia × 30) × Número de VMs
                    = ($0,53 × 12 × 30) × 4 = $763/mês (T4, 12h/dia)

Economia anual com RI = Custo mensal × 12 × 0,30 (desconto médio de 1 ano)
                      = $763 × 12 × 0,30 = $2.747/ano
```

### Comandos de Gerenciamento de Custos do Azure

```bash
# Gastos do mês atual por grupo de recursos
az consumption usage list \
  --start-date $(date -d "$(date +%Y-%m-01)" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName,'gpu')].{Name:instanceName,Cost:pretaxCost}" \
  --output table

# Criar um orçamento com alertas
az consumption budget create \
  --budget-name ai-gpu-budget \
  --amount 5000 \
  --category cost \
  --time-grain monthly \
  --start-date 2025-01-01 \
  --end-date 2025-12-31
```

### Tagueamento para Chargeback (Azure Policy)

```json
{
  "if": {
    "allOf": [
      { "field": "type", "equals": "Microsoft.Compute/virtualMachines" },
      { "field": "Microsoft.Compute/virtualMachines/vmSize", "like": "Standard_N*" },
      { "field": "tags['CostCenter']", "exists": false }
    ]
  },
  "then": { "effect": "deny" }
}
```

💡 **Dica Pro**: Configure um alerta semanal de anomalia de custos a 120% da sua média das últimas 4 semanas. Custos de GPU podem disparar rapidamente quando alguém esquece de desalocar uma VM de treinamento.

---

## Comandos de Operações de Plataforma *(Cap. 10)*

### Isolamento de Namespace para Multi-Tenancy

```yaml
# Cota de recursos por namespace da equipe
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.nvidia.com/gpu: "4"
    requests.cpu: "32"
    requests.memory: "128Gi"
    pods: "50"
---
# Limite de faixa para evitar que um único pod monopolize recursos
apiVersion: v1
kind: LimitRange
metadata:
  name: gpu-limits
  namespace: team-alpha
spec:
  limits:
  - type: Container
    max:
      nvidia.com/gpu: "2"
      memory: "64Gi"
    default:
      cpu: "2"
      memory: "8Gi"
```

### Network Policy para Isolamento de Namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: team-alpha
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: team-alpha
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: team-alpha
  - to:  # Permitir DNS
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
```

### Configuração de GPU Time-Slicing

```yaml
# ConfigMap do NVIDIA device plugin para time-slicing
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin
  namespace: kube-system
data:
  config: |
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 2
```

⚠️ **Armadilha em Produção**: GPU time-slicing não oferece isolamento de memória. Se o Pod A alocar 14 GB em uma T4 de 16 GB, o Pod B vai sofrer OOM mesmo que o Kubernetes mostre a GPU como "disponível." Use time-slicing apenas em dev/teste.

---

## Referência de Throughput do Azure OpenAI *(Cap. 11)*

### Comparação de Tipos de Deployment

| Atributo | Standard (PayGo) | Provisionado (PTU) | Global Standard |
|----------|-------------------|---------------------|-----------------|
| Cobrança | Por 1K tokens | Por hora (por PTU) | Por 1K tokens |
| Garantia de latência | Nenhuma (melhor esforço) | Com SLA | Nenhuma |
| Throttling | Limites de TPM/RPM | Capacidade provisionada | Limites mais altos |
| Melhor para | Dev/teste, uso intermitente | Produção, uso constante | Roteamento global |
| Compromisso mínimo | Nenhum | 1 mês | Nenhum |
| Escala | Automática (com limites) | Provisionada fixa | Automática |

### Estimador de Dimensionamento de PTU

```
Passo 1: Medir a média de tokens por requisição
         Média de tokens de entrada:  800
         Média de tokens de saída: 400
         Total por requisição: 1.200

Passo 2: Calcular TPM sustentado
         Requisições por minuto: 150
         TPM sustentado = 150 × 1.200 = 180.000 TPM

Passo 3: Usar a calculadora de capacidade do Azure ou:
         ~1 PTU ≈ 3.600 TPM (GPT-4o, aproximado)
         PTUs necessários ≈ 180.000 ÷ 3.600 = 50 PTUs

Passo 4: Adicionar 25% de margem para picos
         Recomendado: 63 PTUs
```

### Regras Práticas para Estimativa de Tokens

| Tipo de Conteúdo | Tokens Aproximados |
|------------------|--------------------|
| 1 palavra em inglês | ~1,3 tokens |
| 1 página de texto (~500 palavras) | ~650 tokens |
| 1 linha de código | ~10-15 tokens |
| Um arquivo de código com 100 linhas | ~1.200 tokens |
| Payload JSON (1 KB) | ~300 tokens |

### Comandos de Monitoramento do Azure OpenAI

```bash
# Verificar deployments atuais e seus limites de TPM
az cognitiveservices account deployment list \
  --resource-group rg-ai-prod \
  --name aoai-prod \
  --output table

# Consultar eventos de throttling 429 (últimas 24h)
az monitor metrics list \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{name} \
  --metric "AzureOpenAIRequests" \
  --dimension StatusCode \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1H \
  --output table
```

💡 **Dica Pro**: Se sua taxa de 429 exceder 5%, você está deixando performance na mesa. Aumente sua cota de TPM, migre para PTU ou implemente backoff exponencial no lado do cliente com jitter.

---

## Árvore de Decisão para Troubleshooting *(Cap. 12)*

### GPU Não Detectada

```
GPU não está visível para a carga de trabalho?
├── Verificar SKU da VM → É uma VM da série N?
│   └── Não → SKU errado. Reimplante com série NC/ND/NV.
├── nvidia-smi retorna erro?
│   ├── Driver não instalado → Instale a extensão de driver NVIDIA:
│   │   az vm extension set --name NvidiaGpuDriverLinux \
│   │     --publisher Microsoft.HCPCompute --version 1.9 \
│   │     --vm-name <vm> --resource-group <rg>
│   └── Versão do driver incompatível → Verifique a matriz de compatibilidade CUDA
├── No pod AKS, `nvidia-smi` não encontrado?
│   ├── GPU device plugin ausente → Faça deploy do DaemonSet do NVIDIA device plugin
│   ├── Pod sem solicitação de recurso → Adicione `nvidia.com/gpu: 1` aos limits
│   └── Pod não agendado em node GPU → Verifique tolerations e nodeSelector
└── nvidia-smi mostra a GPU, mas CUDA falha?
    └── Versão do CUDA toolkit não é compatível com o driver → Reconstrua o contêiner com CUDA compatível
```

### Picos de Latência na Inferência

```
Latência P95 excedendo o SLA?
├── Verificar utilização da GPU
│   ├── > 95% → GPU saturada. Escale horizontalmente (mais réplicas) ou otimize o batch size.
│   └── < 50% → GPU não é o gargalo. Verifique abaixo.
├── Verificar memória da GPU
│   ├── > 90% → Pressão no KV cache. Reduza o comprimento máximo de sequência ou batch size.
│   └── Normal → Não é limitação de memória. Verifique abaixo.
├── Verificar utilização da CPU
│   ├── > 80% → Gargalo no pré-processamento. Mova para pods de CPU dedicados.
│   └── Normal → Verifique abaixo.
├── Verificar rede / armazenamento
│   ├── Carregamento do modelo lento → Faça cache do modelo em NVMe local, não no Blob Storage.
│   └── Alta latência de rede → Verifique o roteamento do Private Endpoint.
└── Verificar código da aplicação
    ├── Sem batching de requisições → Implemente batching dinâmico (batch size 8-32).
    └── Pré-processamento síncrono → Mude para pipeline assíncrono.
```

### Throttling 429 do Azure OpenAI

```
Recebendo respostas HTTP 429?
├── Verificar valor do header Retry-After
│   ├── < 10 segundos → Implemente backoff exponencial com jitter
│   └── > 60 segundos → Você atingiu um limite rígido de cota
├── Verificar limites de TPM/RPM do deployment
│   ├── Próximo do limite → Solicite aumento de cota ou adicione segundo deployment
│   └── Bem abaixo do limite → Verifique se tempestades de retry estão amplificando o TPM real
├── Múltiplos consumidores compartilhando um deployment?
│   └── Sim → Separe deployments por consumidor com cotas dedicadas
└── Uso sustentado alto?
    └── Avalie migração para PTU (veja Dimensionamento de PTU acima)
```

### Erros de OOM (Out of Memory)

```
Erro CUDA out of memory?
├── Calcular requisito de memória do modelo (veja Matemática de Memória GPU acima)
│   ├── Modelo grande demais para a GPU → Quantize (INT8/INT4) ou use GPU maior
│   └── Modelo cabe → Batch size ou comprimento de sequência muito alto
├── Reduza o batch size em 50%, tente novamente
│   ├── Funciona → Aumente gradualmente para encontrar o ponto ideal
│   └── Ainda OOM → Habilite gradient checkpointing (treinamento) ou reduza max_seq_len
├── Múltiplas GPUs disponíveis?
│   └── Habilite tensor parallelism (inferência) ou ZeRO Stage 3 (treinamento)
└── Ainda falhando?
    └── Faça profiling com `torch.cuda.memory_summary()` para encontrar o pico de alocação
```

---

## Fórmulas de Performance e Throughput *(Cap. 3, Cap. 11)*

| Métrica | Fórmula | Exemplo |
|---------|---------|---------|
| **TPM** | `Média de tokens/requisição × RPM` | 1.200 × 150 = 180K TPM |
| **QPS** | `RPM ÷ 60` | 300 RPM = 5 QPS |
| **VRAM do Modelo (FP16)** | `Parâmetros × 2 bytes` | 7B × 2 = 14 GB |
| **VRAM para Treinamento (AdamW)** | `Parâmetros × 12 bytes + ativações` | 7B × 12 = 84 GB + ativações |
| **Eficiência de utilização da GPU** | `Tempo de computação ativo ÷ Tempo total alocado` | 80% = saudável |
| **Custo por 1K inferências** | `(VM $/hr ÷ inferências/hr) × 1000` | ($0,53 ÷ 3600) × 1000 = $0,15 |
| **TPM de break-even do PTU** | `Custo por hora do PTU ÷ Custo por token Standard` | Varia por modelo e região |

---

## Onde Executar Seu Modelo — Fluxo de Decisão *(Cap. 3, Cap. 10)*

```
É um modelo proprietário/customizado?
├── Sim → Você precisa treiná-lo?
│   ├── Sim → Azure ML Compute Clusters (gerenciado) ou GPU VMs (controle total)
│   └── Não (apenas inferência) → Qual o volume de tráfego?
│       ├── < 10 QPS → Azure ML Managed Endpoint ou GPU VM única
│       ├── 10-100 QPS → AKS com node pool GPU + HPA
│       └── > 100 QPS → AKS com pool GPU multi-node + cluster autoscaler
└── Não (usando um modelo de fundação) → Azure OpenAI Service
    ├── Dev/teste ou uso intermitente → Deployment Standard (PayGo)
    ├── Produção sustentada → Deployment Provisionado (PTU)
    └── Precisa de distribuição global → Deployment Global Standard
```

---

## Convenção de Tagueamento de Recursos *(Cap. 9, Cap. 10)*

| Tag | Exemplo | Finalidade | Exigida Por |
|-----|---------|------------|-------------|
| `Environment` | `dev`, `staging`, `prod` | Estágio do ciclo de vida | Azure Policy |
| `CostCenter` | `CC-4521` | Chargeback e orçamento | Azure Policy |
| `Team` | `ml-platform` | Responsabilidade e escalonamento | Convenção |
| `WorkloadType` | `training`, `inference`, `batch` | Análise de custos e agendamento | Convenção |
| `Model` | `fraud-detector-v2`, `gpt-4o` | Correlacionar com métricas do modelo | Convenção |
| `DataClassification` | `public`, `confidential`, `restricted` | Controles de segurança | Azure Policy |
| `AutoShutdown` | `true`, `business-hours` | Gatilhos de automação de custos | Automation Runbook |

---

## Links de Referência

- [Tamanhos de VMs GPU no Azure](https://learn.microsoft.com/azure/virtual-machines/sizes/overview#gpu-accelerated)
- [Cotas e limites do Azure OpenAI](https://learn.microsoft.com/azure/ai-services/openai/quotas-limits)
- [Agendamento de GPU no AKS](https://learn.microsoft.com/azure/aks/gpu-cluster)
- [Referência do Azure ML CLI v2](https://learn.microsoft.com/cli/azure/ml)
- [Gerenciamento de Custos do Azure](https://learn.microsoft.com/azure/cost-management-billing/)
- [Métricas do DCGM Exporter](https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/latest/dcgm-exporter.html)
- [GPU time-slicing da NVIDIA](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-sharing.html)
- [Azure Monitor container insights](https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-overview)