# FAQ Técnico — Fundamentos de Infraestrutura para IA

Respostas práticas para engenheiros de infraestrutura que trabalham com IA no Azure. Cada resposta referencia o capítulo correspondente para que você possa se aprofundar quando necessário.

---

## 1. Posso executar workloads de IA sem GPU? *(Ch3)*

**Sim, mas conheça os limites.** Modelos clássicos de ML — regressão linear, árvores de decisão, random forests, gradient-boosted trees — rodam eficientemente em CPU. Muitos deles servem predições em menos de 10 ms em uma `Standard_D4s_v5`. Até algumas redes neurais menores (MobileNet, DistilBERT) podem rodar de forma aceitável em CPU se seu orçamento de latência for generoso (200+ ms por requisição).

Porém, tudo que envolve grandes multiplicações de matrizes em escala — inferência de LLM, modelos de difusão, processamento de vídeo, geração de embeddings em larga escala — será 10-100× mais lento em CPU. Um modelo da classe GPT que responde em 200 ms em uma GPU T4 levaria 5-15 segundos em CPU.

**Regra prática**: Se seu modelo tem mais de 100M de parâmetros, você quase certamente precisa de uma GPU. Se tem menos de 10M de parâmetros e usa dados tabulares, CPU provavelmente é suficiente.

**Dica Pro**: Antes de solicitar cota de GPU, faça benchmark do seu modelo em uma `Standard_D8s_v5` (CPU) primeiro. Se a latência atender ao seu SLA, você acabou de economizar 5× em custos de computação.

---

## 2. Qual a diferença entre treinamento e inferência do ponto de vista de infraestrutura? *(Ch3)*

| Aspecto | Treinamento | Inferência |
|---------|-------------|------------|
| **Padrão de computação** | Batch, horas a semanas | Tempo real, milissegundos por requisição |
| **Memória de GPU** | Precisa de pesos + gradientes + otimizador (12× parâmetros) | Precisa de pesos + KV cache apenas (2-4× parâmetros) |
| **Escalabilidade** | Scale up (GPUs maiores, mais nós) | Scale out (mais réplicas) |
| **Disponibilidade** | Tolera interrupções (checkpointing) | Requer alta disponibilidade (SLA) |
| **Rede** | InfiniBand para multi-node (NCCL) | Ethernet padrão é suficiente |
| **Modelo de custo** | Spot VMs viáveis (60-90% de economia) | On-demand ou Reserved (precisa de uptime) |
| **Armazenamento** | Alto throughput para datasets + checkpoints | Baixa latência para carregamento de modelo |

**Analogia de infra**: Treinamento é um enorme job batch de ETL que processa terabytes. Inferência é uma API sensível à latência atrás de um load balancer. Você nunca arquitetaria ambos da mesma forma — e o mesmo se aplica à IA.

---

## 3. Como calcular se meu modelo cabe na memória da GPU? *(Ch4)*

Comece com a contagem de parâmetros e a precisão desejada:

```
FP16 memory = Parameters × 2 bytes
INT8 memory = Parameters × 1 byte  
INT4 memory = Parameters × 0.5 bytes
```

**Para inferência**, adicione o overhead de KV cache:

```
KV cache ≈ 2 × layers × hidden_dim × max_seq_len × batch_size × 2 bytes
```

**Para treinamento** (fine-tuning completo com AdamW):

```
Total ≈ params × 12 bytes + activation memory
```

**Exemplo prático**: Llama 2 13B em FP16 = 26 GB apenas para os pesos. Em uma A100 (80 GB), isso deixa 54 GB para KV cache e activations — confortável para inferência com batch size de até ~32. Mas para fine-tuning completo, você precisaria de 13B × 12 = 156 GB — exigindo pelo menos 2× A100 com sharding ZeRO Stage 3.

⚠️ **Armadilha em Produção**: O alocador de memória CUDA do PyTorch fragmenta a memória ao longo do tempo. Mesmo que seu modelo caiba em 15 GB em uma T4 de 16 GB, ele vai dar OOM após algumas horas sob carga. Deixe no mínimo 20% de margem, ou configure `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`.

---

## 4. O que causa erros de OOM na GPU e como corrigi-los? *(Ch4, Ch12)*

**Causas mais comuns** (em ordem de frequência):

1. **Batch size muito grande** — Cada amostra em um batch consome memória de GPU. Reduza o batch size em 50% e teste.
2. **Sequência muito longa** — O KV cache cresce linearmente com o tamanho da sequência. Defina `max_tokens` ou `max_seq_len` para o mínimo que sua aplicação precisa.
3. **Modelo grande demais para a GPU** — Calcule a memória necessária (veja Q3). Quantize para INT8/INT4, ou use uma GPU maior.
4. **Vazamento de memória no pré-processamento** — Tensores criados na GPU durante o pré-processamento que não são liberados. Sempre faça o pré-processamento na CPU.
5. **Fragmentação de memória** — Servidores de inferência de longa duração fragmentam a memória da GPU. Reinicie o processo periodicamente, ou use `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`.

**Comandos de depuração:**

```bash
# Verificar uso atual de memória da GPU
nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# Dentro do Python, obter detalhamento de alocação
python -c "import torch; print(torch.cuda.memory_summary())"
```

**Checklist de correção rápida:**
- [ ] Reduzir batch size
- [ ] Reduzir tamanho máximo de sequência
- [ ] Habilitar gradient checkpointing (treinamento)
- [ ] Quantizar o modelo (INT8 com bitsandbytes, INT4 com GPTQ/AWQ)
- [ ] Migrar para uma GPU com mais VRAM
- [ ] Habilitar tensor parallelism em múltiplas GPUs

---

## 5. Como devo configurar auto-scaling para inferência com GPU? *(Ch3, Ch7)*

**Sinais de escalabilidade recomendados** (em ordem de prioridade):

1. **Latência de inferência P95** — Scale out quando a latência se aproximar do limite do seu SLA. Esta é a métrica mais visível para o usuário.
2. **Utilização de GPU** — Scale out quando sustentada acima de 80%. Scale in quando abaixo de 30% por mais de 15 minutos.
3. **Profundidade da fila de requisições** — Se seu servidor de inferência enfileira requisições, escale quando a profundidade da fila exceder 2× o seu batch size.
4. **Utilização de memória de GPU** — Scale out quando acima de 85% (pressão de KV cache).

**Implementações no Azure:**

| Plataforma | Mecanismo de Escalabilidade | Fonte de Métricas de GPU |
|------------|----------------------------|--------------------------|
| AKS | HPA + Cluster Autoscaler | DCGM Exporter → Prometheus → HPA custom metrics |
| Azure ML | `min_instances`/`max_instances` | Autoscaler integrado (baseado em latência de requisição) |
| VMSS | Regras de Autoscale | Métricas customizadas do Azure Monitor via DCGM |

**Configurações críticas:**
- **Cooldown de scale-out**: 3-5 minutos (nós com GPU levam tempo para inicializar)
- **Cooldown de scale-in**: 15-20 minutos (evita oscilação durante quedas de tráfego)
- **Réplicas mínimas**: Nunca defina como 0 em produção (cold start para workloads com GPU é de 2-5 minutos para carregamento do modelo)

💡 **Dica Pro**: Para AKS, defina `min_count: 1` no seu node pool de GPU mesmo fora do horário de pico. O custo de uma T4 ociosa (~$380/mês) é muito menor que o impacto para o usuário de um cold start de 5 minutos.

---

## 6. O que é um model registry e por que engenheiros de infraestrutura devem se importar? *(Ch6)*

Um model registry é um armazém versionado de artefatos para modelos de ML — pense nele como um container registry (ACR), mas para arquivos de modelo em vez de imagens Docker. O model registry do Azure ML armazena pesos do modelo, metadados (métricas de acurácia, parâmetros de treinamento) e linhagem (qual dataset e código produziram esta versão).

**Por que é importante para infraestrutura:**

- **Capacidade de rollback** — Quando um novo modelo degrada a inferência em produção, você precisa reimplantar a versão N-1 em minutos, não horas. O registry oferece `az ml model download --name fraud-detector --version 3`.
- **Automação de deployment** — Pipelines de CI/CD referenciam `model-name:version` para deploy determinístico. Chega de "qual arquivo de modelo está atualmente no blob container?"
- **Gerenciamento de armazenamento** — Arquivos de modelo são grandes (modelo 7B = 14 GB em FP16). O registry cuida de deduplicação e ciclo de vida.
- **Trilha de auditoria** — Setores regulamentados exigem comprovação de qual versão do modelo serviu quais predições. O registry fornece isso.

**MLOps mínimo viável para equipes de infraestrutura:**

```bash
# Registrar modelo
az ml model create --name fraud-detector --version 4 --path ./model/

# Fazer deploy de versão específica
az ml online-deployment create --endpoint-name prod-api \
  --model azureml:fraud-detector:4 --file deployment.yml

# Rollback (trocar tráfego)
az ml online-endpoint update --name prod-api --traffic "v3=100 v4=0"
```

⚠️ **Armadilha em Produção**: Arquivos de modelo na conta de armazenamento padrão do Azure ML podem se acumular rapidamente. Configure políticas de ciclo de vida para arquivar versões com mais de 90 dias — um único time pode gerar mais de 500 GB de artefatos de modelo por trimestre.

---

## 7. Como monitorar workloads de GPU de forma eficaz? *(Ch7)*

**Os quatro sinais de ouro para GPU** (análogos aos quatro sinais de ouro do Google para serviços):

1. **Utilização de GPU** (`DCGM_FI_DEV_GPU_UTIL`) — Os núcleos CUDA estão ocupados? < 20% significa desperdício; > 95% significa saturação.
2. **Memória de GPU** (`DCGM_FI_DEV_FB_USED`) — Quanta VRAM está consumida? > 90% significa risco de OOM.
3. **Temperatura da GPU** (`DCGM_FI_DEV_GPU_TEMP`) — Acima de 83°C, GPUs NVIDIA entram em thermal-throttle, reduzindo silenciosamente o desempenho.
4. **Erros de GPU** (`DCGM_FI_DEV_ECC_DBE_VOL_TOTAL`) — Erros ECC de bit duplo indicam falha de hardware. Alerte imediatamente.

**Stack de monitoramento recomendado:**

```
DCGM Exporter (DaemonSet) → Prometheus (scrape) → Grafana (dashboards)
                                                 → Alertmanager (alertas)
Application Insights SDK → Azure Monitor → Action Groups (PagerDuty/Teams)
```

**Três alertas que todo deployment com GPU precisa:**

| Alerta | Condição | Severidade |
|--------|----------|------------|
| OOM de GPU iminente | Memória > 90% por 5 min | P1 (chamada urgente) |
| Desperdício de GPU | Utilização < 20% por 60 min | P3 (relatório diário) |
| Thermal throttling | Temperatura > 83°C por 10 min | P2 (Teams) |

💡 **Dica Pro**: `nvidia-smi` serve para uma verificação rápida, mas faz uma amostragem por invocação. O DCGM Exporter fornece métricas contínuas com resolução de 1 segundo — a diferença importa ao depurar picos intermitentes de latência.

---

## 8. Como proteger endpoints de inferência de IA? *(Ch8)*

Siga os mesmos princípios de zero-trust que você aplicaria a qualquer API de produção, além de controles específicos para IA:

**Camada de rede:**
- Implante inferência atrás de **Private Endpoints** — sem IP público
- Use **regras de NSG** para restringir entrada apenas a clientes conhecidos
- Para Azure OpenAI, habilite **integração com VNet** e desabilite acesso público

**Camada de identidade:**
- **Managed Identity** para autenticação serviço-a-serviço (Azure ML, pods AKS, Functions)
- **Microsoft Entra ID** para aplicações voltadas ao usuário
- API keys como último recurso — rotacione a cada 90 dias, armazene no **Key Vault**

**Controles específicos para IA:**
- Habilite **content filtering** nos deployments do Azure OpenAI
- Implemente **validação de entrada** — rejeite prompts que excedam os limites máximos de tokens
- Registre todos os prompts e completions no **Log Analytics** para auditoria (em conformidade com políticas de privacidade)
- Aplique rate-limit por cliente para prevenir tentativas de brute-force de prompt injection

**Validação rápida:**

```bash
# Verificar se não há endpoints públicos no Azure OpenAI
az cognitiveservices account show --name aoai-prod --resource-group rg-ai \
  --query "properties.publicNetworkAccess"
# Deve retornar: "Disabled"
```

---

## 9. O que são Spot VMs e quando devo usá-las para IA? *(Ch9)*

**Spot VMs** oferecem capacidade ociosa do Azure com 60-90% de desconto, mas podem ser despejadas com 30 segundos de aviso quando o Azure precisa da capacidade de volta.

**Seguro para:**
- Treinamento de modelo (com checkpointing a cada 15-30 minutos)
- Inferência em batch (processa itens enfileirados, reenfileira em caso de despejo)
- Sweeps de hiperparâmetros (embaraçosamente paralelo — despejo perde uma tentativa, não todas)
- Workloads de GPU para dev/test

**Não é seguro para:**
- Inferência em tempo real em produção (despejo = downtime)
- Workloads que não suportam checkpoint (você perde todo o progresso)
- Qualquer coisa com SLA

**Padrão de implementação para treinamento:**

```bash
az vm create --name train-gpu --size Standard_NC24ads_A100_v4 \
  --priority Spot --max-price 0.60 --eviction-policy Deallocate \
  --resource-group rg-training --image Ubuntu2204 --generate-ssh-keys
```

**Estratégia de checkpoint:**
```python
# Salvar checkpoint a cada 30 minutos
if step % checkpoint_interval == 0:
    torch.save({
        'step': step,
        'model_state': model.state_dict(),
        'optimizer_state': optimizer.state_dict(),
    }, f"azureml://checkpoint-{step}.pt")  # Salvar no Azure Blob
```

⚠️ **Armadilha em Produção**: Taxas de despejo de Spot variam por região e tamanho de VM. `Standard_NC24ads_A100_v4` em `eastus` pode ter taxa de despejo de 2%, enquanto `westus2` tem 15%. Verifique os [dados de despejo de Spot VMs do Azure](https://learn.microsoft.com/azure/virtual-machines/spot-vms) antes de se comprometer.

---

## 10. Como estimar e controlar custos do Azure OpenAI? *(Ch9, Ch11)*

**Passo 1: Meça seu consumo de tokens**

```bash
# Consultar uso real de tokens nos últimos 7 dias
az monitor metrics list \
  --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{name} \
  --metric "ProcessedPromptTokens" "GeneratedCompletionTokens" \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1H --output table
```

**Passo 2: Calcule o custo mensal**

```
Custo mensal = (Média de tokens de prompt/requisição × preço de prompt por 1K)
             + (Média de tokens de completion/requisição × preço de completion por 1K)
             × Requisições por mês

Exemplo (GPT-4o):
  800 tokens de prompt × $0.0025/1K = $0.002
  400 tokens de completion × $0.01/1K = $0.004
  Por requisição = $0.006
  100K requisições/mês = $600/mês
```

**Passo 3: Avalie PTU vs Standard**

| Fator | Standard (PayGo) | Provisionado (PTU) |
|-------|-------------------|---------------------|
| Ideal quando | < 100K TPM sustentado | > 100K TPM sustentado por 8+ hrs/dia |
| Modelo de custo | Por token | Fixo por hora por PTU |
| Risco de 429 | Sim (limitado por cota) | Não (capacidade provisionada) |
| Ponto de equilíbrio | Abaixo do ponto de cruzamento | Acima do ponto de cruzamento |

**Passo 4: Estabeleça guardrails**

- Alerta de Budget do Azure a 80% do gasto mensal esperado
- Limites de TPM/RPM por deployment para prevenir custos descontrolados
- Registre o uso de tokens por chamador para chargeback

💡 **Dica Pro**: Retries são amplificadores ocultos de custo. Se 10% das requisições recebem 429 e fazem retry 3 vezes, seu consumo real de tokens é 1,3× o que os logs da sua aplicação mostram. Sempre meça no nível do recurso Azure, não no nível da aplicação.

---

## 11. Qual a diferença entre deployments PTU e Standard? *(Ch11)*

| Atributo | Standard (PayGo) | Provisionado (PTU) |
|----------|-------------------|---------------------|
| **Cobrança** | Por 1K tokens (entrada + saída cobrados separadamente) | Por hora por PTU (custo fixo independente do uso) |
| **Latência** | Melhor esforço, variável | Menor e mais consistente (capacidade dedicada) |
| **Throttling** | Limites de TPM/RPM, respostas 429 quando excedidos | Capacidade provisionada, 429s mínimos |
| **Compromisso** | Nenhum | Reserva mínima de 1 mês |
| **Ideal para** | Dev/test, workloads com picos, baixo volume | Produção, tráfego constante, apps sensíveis à latência |
| **Escalabilidade** | Automática (dentro da cota) | Manual (adicionar/remover PTUs) |

**Quando migrar para PTU:**
1. A taxa de 429 do seu deployment standard excede 5%
2. Você tem tráfego sustentado acima de 100K TPM por 8+ horas/dia
3. Consistência de latência importa (ex.: chat voltado ao usuário)
4. Você pode se comprometer com 1+ mês de capacidade

**Cálculo de dimensionamento de PTU:**

```
TPM sustentado necessário: 180.000
Capacidade aproximada por PTU (GPT-4o): ~3.600 TPM por PTU
PTUs base: 180.000 ÷ 3.600 = 50 PTUs
Com 25% de margem para picos: 63 PTUs
```

⚠️ **Armadilha em Produção**: PTUs são específicos por região e sujeitos à disponibilidade. Se você precisa de 100+ PTUs de um modelo específico, verifique a capacidade regional com seu time de contas Microsoft *antes* de planejar a migração. Regiões populares esgotam rapidamente.

---

## 12. Como implementar multi-tenancy para workloads de IA no AKS? *(Ch10)*

**Três níveis de isolamento, do mais leve ao mais restrito:**

| Nível | Mecanismo | Isolamento de GPU | Quando Usar |
|-------|-----------|-------------------|-------------|
| Namespace + ResourceQuota | Namespaces do Kubernetes | Time-slicing (compartilhado) | Dev/test, times confiáveis |
| Namespace + NetworkPolicy + nós dedicados | Node pool por tenant | GPU dedicada por pod | Produção, compliance |
| Clusters separados | Cluster por tenant | Isolamento total | Setores regulamentados, tenants não confiáveis |

**Multi-tenancy mínimo viável (nível de namespace):**

1. Um namespace por time com `ResourceQuota` limitando requisições de GPU
2. `NetworkPolicy` negando tráfego entre namespaces
3. `LimitRange` impedindo que um único pod consuma todos os recursos
4. Políticas OPA Gatekeeper aplicando fontes de imagem e limites de recursos
5. Kubecost para atribuição de custo por namespace

**Considerações específicas para GPU:**
- **ResourceQuotas** limitam o *número* de GPUs que um namespace pode solicitar, mas não a *memória* de GPU — um pod ainda pode consumir toda a VRAM de uma GPU compartilhada
- **NVIDIA GPU time-slicing** permite que 2-4 workloads compartilhem uma GPU, mas oferece zero isolamento de memória
- **NVIDIA MPS (Multi-Process Service)** oferece compartilhamento um pouco melhor, mas ainda sem limites rígidos de memória
- Para multi-tenancy em produção, use **nós de GPU dedicados** por time via node selectors e taints

💡 **Dica Pro**: Rotule seus nós de GPU com `gpu-type: t4` ou `gpu-type: a100` e use `nodeSelector` nos deployments. Isso evita que um workload de desenvolvimento caia acidentalmente em um nó A100 caro.

---

## 13. Como solucionar problemas de driver de GPU em VMs do Azure? *(Ch12)*

**Sintoma: `nvidia-smi` retorna "command not found" ou "driver not loaded"**

```bash
# Passo 1: Verificar se a extensão de driver NVIDIA está instalada
az vm extension list --resource-group <rg> --vm-name <vm> --output table

# Passo 2: Se estiver faltando, instalar
az vm extension set \
  --resource-group <rg> --vm-name <vm> \
  --name NvidiaGpuDriverLinux \
  --publisher Microsoft.HCPCompute \
  --version 1.9

# Passo 3: Reiniciar e verificar
az vm restart --resource-group <rg> --name <vm>
# Após reiniciar, conecte via SSH e execute:
nvidia-smi
```

**Sintoma: Driver instalado mas erros de CUDA na sua aplicação**

Isso quase sempre é incompatibilidade de versão do CUDA toolkit. Verifique a compatibilidade:

```bash
# Verificar versão do driver
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# Exemplo de saída: 535.129.03

# Verificar a versão de CUDA que o driver suporta
nvidia-smi | head -3
# Procure por "CUDA Version: 12.2"

# Verificar se o CUDA toolkit do seu container é compatível
docker inspect <image> | grep CUDA
```

O CUDA toolkit no seu container deve ser ≤ a versão de CUDA suportada pelo driver. Se seu container usa CUDA 12.3, mas o driver suporta 12.2, ele falhará silenciosamente ou lançará `CUDA error: no kernel image is available`.

⚠️ **Armadilha em Produção**: A extensão de driver NVIDIA do Azure atualiza automaticamente por padrão. Fixe a versão em produção para evitar que uma atualização automática quebre a compatibilidade CUDA: `--version 1.9 --settings '{"driverVersion":"535.129.03"}'`.

---

## 14. Como lidar com erros 429 (throttling) do Azure OpenAI? *(Ch11, Ch12)*

**Entendendo o 429:**
O Azure OpenAI retorna HTTP 429 quando suas requisições excedem a cota de TPM (Tokens Por Minuto) ou RPM (Requisições Por Minuto) do deployment. A resposta inclui um header `Retry-After` indicando quanto tempo esperar.

**Mitigações imediatas (sem mudanças de infraestrutura):**

1. **Backoff exponencial com jitter** — Não faça retry imediatamente. Espere `min(2^tentativa × 100ms + random(0-100ms), 60s)`.
2. **Reduza o tamanho do prompt** — System prompts mais curtos consomem menos tokens. Cada token economizado aumenta o throughput efetivo.
3. **Limite max_tokens** — Defina para o mínimo que sua aplicação precisa, não o máximo do modelo.

**Mitigações de infraestrutura:**

1. **Aumente a cota** — Solicite limites maiores de TPM/RPM pelo portal do Azure (pode levar 1-3 dias úteis).
2. **Adicione deployments** — Faça deploy do mesmo modelo em uma segunda região e balanceie a carga com Azure API Management ou um roteador customizado.
3. **Migre para PTU** — Capacidade provisionada elimina completamente o throttling baseado em cota.
4. **Implemente um orçamento de tokens** — Rastreie o TPM acumulado por chamador e rejeite requisições na camada da aplicação antes que cheguem ao Azure OpenAI.

**Consulta de monitoramento (KQL):**

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultType == "429"
| summarize ThrottledRequests = count() by bin(TimeGenerated, 5m)
| render timechart
```

---

## 15. Qual backend de armazenamento devo usar para arquivos de modelo e dados de treinamento? *(Ch3, Ch6)*

| Tipo de Armazenamento | Throughput | Latência | Ideal Para | Custo |
|----------------------|-----------|----------|------------|-------|
| **Azure Blob (Hot)** | 60 Gbps (por conta) | ~10-20 ms | Armazenamento de artefatos de modelo, arquivo de dados de treinamento | 💲 |
| **Azure Blob (Premium)** | IOPS mais alto | ~2-5 ms | Datasets de treinamento ativos | 💲💲 |
| **Azure NetApp Files** | 4.500 MiB/s (Ultra) | ~1 ms | Checkpoints de treinamento multi-node, dados compartilhados | 💲💲💲 |
| **NVMe (SSD local)** | 7+ GB/s | ~0,1 ms | Cache de carregamento de modelo, espaço temporário | Incluso na VM |
| **Azure Managed Lustre** | 500+ MB/s por cliente | ~1 ms | Datasets de treinamento em escala HPC | 💲💲💲 |

**Padrão recomendado:**
- Armazene artefatos de modelo no **Blob Storage (Hot)** → faça download para NVMe local ao iniciar o pod/VM
- Datasets de treinamento no **Blob (Premium)** ou **ANF** dependendo dos requisitos de I/O
- Checkpoints no **ANF** ou **Blob** (ANF se frequência de checkpoint < 5 min; Blob caso contrário)

💡 **Dica Pro**: Para pods de inferência no AKS, use um init container que copia o modelo do Blob para o SSD local do nó (`emptyDir`). Isso elimina a latência do Blob em cada reload do modelo e sobrevive a reinicializações do pod no mesmo nó.

---

## 16. Como implementar deployments blue-green para modelos de ML? *(Ch6, Ch10)*

**Azure ML Managed Endpoints** suportam divisão de tráfego nativamente:

```bash
# Fazer deploy da nova versão do modelo como "green"
az ml online-deployment create --name green \
  --endpoint-name prod-api \
  --model azureml:fraud-detector:5 \
  --instance-type Standard_NC4as_T4_v3 \
  --instance-count 2

# Direcionar 10% do tráfego para green (canary)
az ml online-endpoint update --name prod-api \
  --traffic "blue=90 green=10"

# Monitorar por 1 hora, depois promover
az ml online-endpoint update --name prod-api \
  --traffic "blue=0 green=100"

# Deletar deployment antigo
az ml online-deployment delete --name blue --endpoint-name prod-api --yes
```

**No AKS**, use estratégias nativas do Kubernetes:

1. Faça deploy da nova versão do modelo como um Deployment separado com um label diferente (`model-version: v5`)
2. Use um **Istio VirtualService** ou roteamento ponderado do **NGINX ingress** para dividir o tráfego
3. Monitore latência P95 e taxa de erro entre as versões
4. Promova ou faça rollback ajustando os pesos do tráfego

⚠️ **Armadilha em Produção**: Blue-green de modelos de ML é mais caro que blue-green de aplicações porque cada deployment mantém uma cópia completa do modelo na memória da GPU. Durante a transição, você está pagando por 2× a capacidade de GPU. Mantenha a janela de transição curta (horas, não dias).

---

## 17. Como dimensionar corretamente VMs de GPU para inferência? *(Ch3, Ch9)*

**Passo 1: Profile os requisitos de memória e computação do seu modelo**

```bash
# Executar benchmark com entrada realista
python benchmark.py --model ./model --batch-size 1 --num-requests 1000
# Saída: Avg latency 45ms, P95 72ms, GPU util 34%, VRAM used 11.2GB
```

**Passo 2: Escolha a menor GPU que atende**

| Se a VRAM necessária é... | E a latência alvo é... | Use... |
|---------------------------|------------------------|--------|
| < 14 GB | < 100 ms | `Standard_NC4as_T4_v3` (T4, 16 GB) |
| 14-22 GB | < 50 ms | `Standard_NV36ads_A10_v5` (A10, 24 GB) |
| 22-75 GB | < 30 ms | `Standard_NC24ads_A100_v4` (A100, 80 GB) |
| > 80 GB | Qualquer | Multi-GPU (série ND96) |

**Passo 3: Valide com teste de carga**

Execute um teste de carga realista por 30+ minutos e verifique:
- A memória da GPU não cresce ao longo do tempo (sem vazamento)
- A latência P95 permanece dentro do SLA no pico de QPS
- A utilização de GPU está entre 40-80% no tráfego esperado (margem para picos)

💡 **Dica Pro**: Comece com a menor GPU que comporte seu modelo e escale *horizontalmente* (mais réplicas) em vez de *verticalmente* (GPU maior). Duas réplicas T4 frequentemente custam menos que uma A100 e oferecem melhor disponibilidade.

---

## 18. O que devo incluir em um runbook de workload de IA? *(Ch7, Ch12)*

**Todo serviço de inferência com GPU deve ter um runbook cobrindo:**

1. **Visão geral do serviço** — Nome/versão do modelo, URL do endpoint, QPS esperado, metas de SLA
2. **Diagrama de arquitetura** — Computação (VM/AKS), armazenamento, rede, dependências
3. **Comandos de health check:**
   ```bash
   curl -s https://inference.internal/health | jq .status
   kubectl get pods -n ml-prod -l app=inference -o wide
   nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv
   ```
4. **Cenários comuns de falha e correções:**
   - OOM → Reduzir batch size ou reiniciar pod
   - Alta latência → Verificar utilização de GPU, scale out se > 80%
   - Erros 5xx → Verificar carregamento do modelo, validar integridade do arquivo de modelo
   - Pod CrashLoopBackOff → Verificar compatibilidade de driver de GPU, revisar logs do container
5. **Caminho de escalação** — L1 (reiniciar pod), L2 (escalar cluster), L3 (time de engenharia de ML)
6. **Procedimento de rollback** — Passos para reverter para a versão anterior do modelo

---

## 19. Como lidar com limitações de cota de GPU no Azure? *(Ch3, Ch4)*

**O desafio da cota**: VMs de GPU (série N) possuem cotas de vCPU por assinatura, por região, que são padrão 0 na maioria das regiões. Você deve solicitar aumentos antes de fazer deploy.

**Verificar cotas atuais:**

```bash
az vm list-usage --location eastus --output table | grep -i "NC\|ND\|NV"
```

**Solicitar um aumento:**
1. Portal do Azure → Assinaturas → Uso + Cotas → Solicitar aumento
2. Ou use a CLI: `az quota create` (requer registro do provider `Microsoft.Quota`)

**Estratégias para cota limitada:**

- **Deployment multi-região** — Distribua workloads entre 2-3 regiões (ex.: 50% eastus, 50% westus2)
- **Dimensione corretamente primeiro** — Não solicite cota de A100 se T4 atende seu SLA de latência
- **Spot VMs para dev/test** — A cota de Spot é separada da on-demand e frequentemente mais disponível
- **Divisão de assinaturas** — Times enterprise às vezes usam assinaturas separadas por workload para obter cotas independentes

⚠️ **Armadilha em Produção**: A aprovação de cota não é instantânea. Planeje 3-5 dias úteis para solicitações padrão, 1-2 semanas para solicitações grandes de A100/H100. Inicie o processo de cota no momento em que começar o planejamento de capacidade — não quando estiver pronto para fazer deploy.

---

## 20. Qual é o caminho de aprendizado recomendado para engenheiros de infraestrutura entrando em IA? *(Ch1, Ch15)*

**Fase 1 — Fundamentos (Semanas 1-2):**
- Leia os Ch1-4 deste livro (por que IA importa, fundamentos de dados, computação, deep dive em GPU)
- Obtenha a certificação **AI-900: Azure AI Fundamentals**
- Faça deploy de uma VM com GPU e execute `nvidia-smi` — entenda o que você está vendo

**Fase 2 — Mão na Massa (Semanas 3-4):**
- Complete os labs nos extras deste livro
- Faça deploy de um modelo no AKS com um node pool de GPU
- Configure monitoramento com DCGM Exporter + Prometheus + Grafana
- Faça deploy de uma instância do Azure OpenAI e execute um teste de carga

**Fase 3 — Habilidades de Produção (Semanas 5-8):**
- Implemente IaC para um workspace de ML (Bicep ou Terraform)
- Construa um dashboard de custos para workloads de GPU
- Pratique troubleshooting: simule OOM, throttling 429, problemas de driver
- Leia Ch7-12 e aplique monitoramento, segurança, engenharia de custos e operações de plataforma

**Fase 4 — Liderança (Contínuo):**
- Construa uma plataforma interna de IA para sua organização (Ch10)
- Apresente resultados de otimização de custos para a liderança (Ch9)
- Crie runbooks e documentação operacional (Ch12)
- Seja mentor de outros engenheiros de infraestrutura em preparação para IA (Ch14)

💡 **Dica Pro**: Você não precisa entender backpropagation ou funções de perda. Seu trabalho é fazer a IA *funcionar* — de forma confiável, segura e custo-eficiente. Foque na camada de infraestrutura e colabore com cientistas de dados na camada de modelo.

---

> Infraestrutura não compete com IA — ela torna a IA confiável, segura e escalável.
