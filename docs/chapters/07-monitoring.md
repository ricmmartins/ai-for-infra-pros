# Capítulo 7 — Monitoramento e Observabilidade para Workloads de IA

*"Estava tudo verde no dashboard. E esse era exatamente o problema."*

---

## A Falha Silenciosa

Seu endpoint do Azure OpenAI está retornando 200 OK em todas as requisições. A latência parece normal — o P95 está abaixo de 800ms. A utilização de CPU e memória está bem dentro dos limites. O cluster Kubernetes mostra todos os pods saudáveis, sem restarts, sem evictions. Por cada métrica de infraestrutura em que você sempre confiou, o sistema está perfeitamente bem.

Mas os tickets de suporte continuam chegando. Os usuários estão relatando que o chatbot está "dando respostas piores". As respostas são tecnicamente fluentes, mas factualmente erradas — as alucinações aumentaram, os resumos perdem pontos-chave e as sugestões de código introduzem bugs sutis. Seu product manager está alarmado. O VP de Engenharia quer respostas até o fim do dia.

Você abre sua stack de monitoramento. Azure Monitor: verde. Application Insights: verde. Dashboards do Grafana: todos verdes. Você está olhando para uma parede de métricas saudáveis enquanto o sistema está falhando ativamente com seus usuários.

O problema? **Model drift**. Uma rodada recente de fine-tuning introduziu uma regressão na qualidade das respostas. As saídas do modelo degradaram gradualmente ao longo de duas semanas, mas nenhum alerta disparou — porque você está monitorando métricas de infraestrutura, não métricas de IA. Sua stack de observabilidade foi construída para workloads tradicionais, onde "o servidor está de pé e respondendo" equivale a "o sistema está funcionando." Em IA, um modelo pode estar rodando perfeitamente e ainda assim estar errado.

Esse é o desafio fundamental da observabilidade de IA: **a infraestrutura pode estar saudável enquanto o workload está quebrado**. O monitoramento tradicional responde "Está rodando?" O monitoramento de IA também precisa responder "Está funcionando corretamente?" e "Vale o custo?" Este capítulo ensina você a enxergar todas as seis dimensões da observabilidade de IA — para que você nunca mais confunda um dashboard verde com um sistema saudável.

---

## As Seis Dimensões da Observabilidade de IA

O monitoramento tradicional de infraestrutura cobre computação, rede e armazenamento. Isso é necessário, mas insuficiente para workloads de IA. Você precisa monitorar seis dimensões simultaneamente, porque falhas em qualquer uma delas podem se manifestar como uma experiência degradada para o usuário — e os sintomas frequentemente se sobrepõem de maneiras que tornam a análise de causa raiz complicada.

**Tradução Infra ↔ IA**: Pense da seguinte forma — monitorar um servidor web significa observar CPU, memória, disco e rede. Monitorar um workload de IA é como monitorar um servidor web, um banco de dados, um sistema de billing e um departamento de controle de qualidade simultaneamente. O modelo não está apenas consumindo recursos; ele está produzindo saídas que têm uma dimensão de corretude que a infraestrutura tradicional não possui.

### 1. Computação — Utilização de GPU, Memória, Temperatura

Esta é a dimensão mais próxima do monitoramento tradicional. Você está acompanhando o percentual de utilização da GPU, consumo de memória HBM, temperatura da GPU, consumo de energia e erros de memória ECC (Error Correcting Code). Baixa utilização de GPU durante inferência pode indicar batching ineficiente. Temperaturas altas se aproximando dos limites de thermal throttling (tipicamente 83°C para GPUs de data center) sinalizam problemas de refrigeração ou sobrecarga sustentada. Erros ECC, especialmente os não corrigíveis, indicam degradação de hardware.

### 2. Modelo — Acurácia, Drift, Distribuição de Latência, Taxas de Erro

Esta é a dimensão que captura a falha da nossa história de abertura. Você está acompanhando a acurácia de inferência (quando mensurável), scores de qualidade de saída, comparações de desempenho entre versões do modelo e mudanças na distribuição de respostas. Para LLMs, isso inclui acompanhar taxas de alucinação, taxas de recusa e coerência das respostas. Model drift acontece quando as propriedades estatísticas das entradas ou o desempenho do modelo mudam ao longo do tempo, mesmo que nada na infraestrutura tenha mudado.

### 3. Rede — Throughput, Saúde do InfiniBand, Latência entre Nós

Jobs de treinamento multi-GPU e inferência distribuída dependem fortemente do desempenho de rede. Você precisa monitorar a saúde dos links InfiniBand, throughput de comunicação NCCL, latência entre nós e perda de pacotes. Um único link InfiniBand degradado em um cluster de treinamento multi-nó pode reduzir o throughput em 30-50%, porque o treinamento distribuído exige que todos os nós sincronizem no ritmo do comunicador mais lento.

### 4. Dados — Frescor do Pipeline, Qualidade, Falhas de Ingestão

Workloads de IA consomem dados por meio de pipelines, e falhas de pipeline são uma das principais fontes de incidentes. Monitore a latência de ingestão de dados, erros de validação de schema, valores de features ausentes e obsolescência dos dados de treinamento. Uma aplicação de RAG (Retrieval-Augmented Generation) que para de indexar novos documentos continuará funcionando perfeitamente — ela apenas não saberá sobre nada que aconteceu após o pipeline quebrar.

### 5. Custo — Gastos com GPU, Consumo de Tokens, Custo por Inferência

GPUs e tokens são caros, e os custos podem escalar rapidamente sem visibilidade. Acompanhe GPU-horas consumidas por equipe ou projeto, consumo de tokens por deployment de modelo, custo por requisição de inferência e projeções de gastos versus orçamento. Um prompt não otimizado que envia 4.000 tokens por requisição em vez de 500 pode multiplicar sua conta do Azure OpenAI por 8× de um dia para o outro.

### 6. Segurança — Padrões de Acesso, Prompt Injection, Exfiltração de Dados

Sistemas de IA introduzem requisitos de monitoramento de segurança inéditos. Fique atento a padrões anômalos de acesso à API, tentativas de prompt injection (entradas projetadas para manipular o comportamento do modelo), tentativas de extrair dados de treinamento ou system prompts e picos incomuns de consumo de tokens que podem indicar abuso. Essas são ameaças que logs tradicionais de WAF e NSG não vão capturar.

**Matriz de Decisão — O Que Monitorar Primeiro**

| Prioridade | Dimensão | Por quê |
|------------|----------|---------|
| **P0** | Computação (GPU) | Falhas de hardware causam indisponibilidade imediata |
| **P0** | Custo | Gastos descontrolados podem estourar orçamentos em horas |
| **P1** | Modelo | Degradação de qualidade afeta os usuários silenciosamente |
| **P1** | Segurança | Prompt injection e exfiltração de dados são ameaças ativas |
| **P2** | Rede | Impacta workloads multi-nó significativamente |
| **P2** | Dados | Frescor do pipeline afeta a acurácia downstream |

---

## GPU Monitoring em Profundidade

O monitoramento de GPU é a base da observabilidade de IA. Sem ele, você está voando às cegas no recurso mais caro da sua stack. O ferramental amadureceu significativamente, e o Azure oferece um caminho gerenciado que elimina a maior parte da sobrecarga operacional.

### DCGM Exporter como DaemonSet no AKS

O DCGM Exporter da NVIDIA (Data Center GPU Manager) roda como um DaemonSet — um pod por nó com GPU — e expõe métricas de GPU no formato Prometheus. Essa é a abordagem padrão para monitoramento de GPU em Kubernetes.

```bash
# Adicionar o repositório Helm da NVIDIA
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Instalar o DCGM Exporter como DaemonSet nos nós com GPU
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-monitoring \
  --create-namespace \
  --set nodeSelector."agentpool"="gpu"
```

O DCGM Exporter expõe métricas na porta 9400 por padrão. Uma vez em execução, o Prometheus pode coletar essas métricas automaticamente.

### Azure Managed Prometheus para Métricas de GPU

O Azure Managed Prometheus elimina a necessidade de rodar seu próprio servidor Prometheus. Habilite-o no seu cluster AKS e configure-o para coletar métricas do DCGM:

```bash
# Habilitar o serviço gerenciado Azure Monitor para Prometheus
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-azure-monitor-metrics

# Verificar se o add-on de monitoramento está habilitado
az aks show \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --query "azureMonitorProfile.metrics.enabled"
```

💡 **Dica Profissional**: O Azure Managed Prometheus descobre e coleta automaticamente os pods do DCGM Exporter por meio do service discovery do Kubernetes. Você não precisa configurar manualmente os targets de coleta — basta implantar o DaemonSet do DCGM Exporter e a instância do Managed Prometheus o encontrará. Se você precisar de configurações customizadas de coleta, use o ConfigMap `ama-metrics-settings-configmap`.

### Métricas-Chave de GPU e Limites de Alertas

| Métrica | Nome DCGM | Aviso | Crítico | O Que Significa |
|---------|-----------|-------|---------|-----------------|
| Utilização de GPU | `DCGM_FI_DEV_GPU_UTIL` | < 30% sustentado | < 10% sustentado | Subutilização — desperdiçando gastos com GPU |
| Memória de GPU Usada | `DCGM_FI_DEV_FB_USED` | > 85% | > 95% | Risco de OOM para novos workloads |
| Temperatura da GPU | `DCGM_FI_DEV_GPU_TEMP` | > 78°C | > 83°C | Thermal throttling iminente |
| Erros ECC (Não Corrigíveis) | `DCGM_FI_DEV_ECC_DBE_VOL_TOTAL` | > 0 | > 0 | Degradação de hardware — substituir GPU |
| Throttle de Clock de Memória | `DCGM_FI_DEV_CLOCK_THROTTLE_REASONS` | Thermal | HW Slowdown | Desempenho limitado por temperatura ou energia |

⚠️ **Cuidado em Produção**: Baixa utilização de GPU nem sempre é um problema. Alguns workloads de inferência são sensíveis à latência e intencionalmente mantêm a utilização de GPU baixa para manter tempos de resposta rápidos. Antes de alertar sobre baixa utilização, verifique se o workload é otimizado para throughput (treinamento — alta utilização esperada) ou latência (inferência — utilização moderada aceitável).

### nvidia-smi para Debugging Ad-Hoc

Quando você precisa investigar um nó específico, `nvidia-smi` é sua ferramenta principal (veja o Capítulo 4 para diagnósticos aprofundados de GPU). Use-o para obter um snapshot em tempo real:

```bash
# Status básico da GPU
nvidia-smi

# Monitoramento contínuo em intervalos de 1 segundo
nvidia-smi dmon -s pucvmet -d 1

# Verificar topologia da GPU e status do NVLink
nvidia-smi topo -m
```

---

## Monitoramento do Azure OpenAI

O Azure OpenAI possui seus próprios requisitos de monitoramento, distintos da infraestrutura de modelos auto-hospedados. As métricas-chave giram em torno de consumo de tokens, rate limiting e latência percebida.

### Métricas-Chave

**TPM (Tokens Per Minute)** mede seu consumo de throughput em relação à capacidade alocada. Quando você atinge o limite de TPM, o Azure throttlea suas requisições com respostas HTTP 429. Monitore o quão perto você está do seu limite — uso sustentado acima de 80% da sua alocação de TPM significa que você precisa planejar mais capacidade.

**RPM (Requests Per Minute)** limita o número de chamadas individuais à API, independentemente da contagem de tokens. Uma enxurrada de requisições pequenas pode atingir os limites de RPM mesmo quando o TPM ainda tem folga. Isso frequentemente pega as equipes de surpresa quando mudam de poucas requisições grandes para muitas requisições pequenas.

**TTFT (Time to First Token)** mede a latência percebida para respostas em streaming. Os usuários percebem a latência com base em quando o primeiro token aparece, não quando a resposta completa termina. Um TTFT acima de 2 segundos parece lento para os usuários, mesmo que o tempo total de geração seja aceitável.

**Taxa de HTTP 429** é o sinal de throttling. Qualquer taxa sustentada de 429 acima de 1% merece investigação. Picos durante horários de pico podem indicar que você precisa implementar enfileiramento de requisições, implantar em múltiplas regiões ou migrar de pay-as-you-go para Provisioned Throughput Units (PTUs).

### Monitorando Throttling na Prática

Configure diagnostic settings no seu recurso do Azure OpenAI para enviar logs a um workspace do Log Analytics. Uma vez habilitado, cada chamada à API é registrada com status code, latência, contagem de tokens e nome do deployment. Esta é a base de dados para cada consulta KQL mais adiante neste capítulo.

```bash
# Habilitar logging de diagnóstico para Azure OpenAI
az monitor diagnostic-settings create \
  --resource "/subscriptions/<sub-id>/resourceGroups/myRG/providers/Microsoft.CognitiveServices/accounts/myAOAI" \
  --name "aoai-diagnostics" \
  --workspace "/subscriptions/<sub-id>/resourceGroups/myRG/providers/Microsoft.OperationalInsights/workspaces/myWorkspace" \
  --logs '[{"category":"RequestResponse","enabled":true},{"category":"Audit","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

⚠️ **Cuidado em Produção**: Os logs de diagnóstico do Azure OpenAI podem gerar um volume significativo em deployments movimentados. Um deployment atendendo 1.000 RPM produz aproximadamente 1,4 milhão de registros de log por dia. Defina políticas de retenção apropriadas no seu workspace do Log Analytics — 30 dias é suficiente para debugging operacional, enquanto requisitos de compliance podem exigir retenção mais longa.

### Consumo de Tokens para Atribuição de Custos

Acompanhe o uso de tokens por deployment, aplicação e equipe para entender os direcionadores de custo:

```python
from opentelemetry import metrics

meter = metrics.get_meter("azure-openai-tracking")
token_counter = meter.create_counter(
    "aoai.tokens.consumed",
    description="Tokens consumed per request",
    unit="tokens"
)

# Após cada chamada à API, registrar uso de tokens com labels de atribuição
token_counter.add(
    response.usage.total_tokens,
    attributes={
        "deployment": deployment_name,
        "model": model_name,
        "application": app_name,
        "team": team_tag,
        "token_type": "total"
    }
)
```

**Tradução Infra ↔ IA**: Pense nos limites de TPM como throttling de banda e nos limites de RPM como limitação de taxa de conexão. Você gerencia ambos em redes há anos — os mesmos padrões se aplicam. Orçamentos de tokens são o equivalente em IA das cotas de transferência de dados.

---

## Observabilidade em Nível de Aplicação

Métricas de infraestrutura dizem se o sistema está saudável. A observabilidade em nível de aplicação diz se ele está funcionando corretamente e de forma eficiente.

### OpenTelemetry para Distributed Tracing

Aplicações modernas de IA envolvem múltiplos serviços: API gateways, etapas de pré-processamento, geração de embeddings, busca vetorial, inferência LLM e pós-processamento. O OpenTelemetry fornece o padrão de distributed tracing que permite acompanhar uma única requisição por todo esse pipeline.

```python
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace

# Configurar o exportador do Azure Monitor
# Requer a variável de ambiente APPLICATIONINSIGHTS_CONNECTION_STRING
configure_azure_monitor()

tracer = trace.get_tracer("inference-pipeline")

def process_request(user_query):
    with tracer.start_as_current_span("inference-pipeline") as span:
        # Passo 1: Gerar embedding da query
        with tracer.start_as_current_span("generate-embedding"):
            embedding = embed(user_query)

        # Passo 2: Recuperar contexto do vector store
        with tracer.start_as_current_span("vector-search"):
            context = search(embedding, top_k=5)

        # Passo 3: Gerar resposta via LLM
        with tracer.start_as_current_span("llm-inference") as llm_span:
            response = generate(user_query, context)
            llm_span.set_attribute("tokens.prompt", response.usage.prompt_tokens)
            llm_span.set_attribute("tokens.completion", response.usage.completion_tokens)

        return response
```

### Métricas Customizadas para Workloads de IA

Além dos traces, instrumente sua aplicação com métricas que capturam o comportamento específico de IA:

- **Percentis de latência de inferência** — P50, P95 e P99. O P50 mostra a experiência típica; P95/P99 revelam a latência de cauda que afeta seus usuários com pior atendimento.
- **Tokens por segundo** — medida de throughput para inferência LLM. Queda no TPS pode indicar pressão de memória na GPU ou degradação do modelo.
- **Profundidade da fila** — quantas requisições estão aguardando recursos de GPU. Profundidade de fila crescente com throughput estável sinaliza que você precisa escalar horizontalmente.
- **Taxa de cache hit** — para camadas de semantic caching. Altas taxas de cache hit reduzem tanto latência quanto custo.

### Logging Estruturado para Pipelines de ML

Logs padrão de aplicação são texto não estruturado difícil de consultar. Para workloads de IA, use logging estruturado que capture os campos que você precisará durante a investigação de incidentes:

```python
import logging
import json

class StructuredFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "message": record.getMessage(),
            "service": getattr(record, "service", "inference-api"),
            "model_version": getattr(record, "model_version", "unknown"),
            "deployment": getattr(record, "deployment", "unknown"),
            "request_id": getattr(record, "request_id", None),
            "tokens_used": getattr(record, "tokens_used", None),
            "latency_ms": getattr(record, "latency_ms", None),
        }
        return json.dumps(log_entry)
```

Logs estruturados permitem filtrar por versão do modelo, correlacionar por request ID e agregar por deployment — tudo crítico durante um incidente. Sem logging estruturado, você estará fazendo grep em texto livre às 3 da manhã.

💡 **Dica Profissional**: Sempre registre a versão do modelo e o nome do deployment em cada trace e métrica. Quando você implanta uma nova versão do modelo e a latência aumenta 40%, você precisa correlacionar a mudança de desempenho com o evento de deploy. Sem versionamento nos tags, você perderá horas investigando infraestrutura quando o próprio modelo é a causa.

---

## Consultas KQL para Troubleshooting de IA

Essas consultas KQL prontas para produção rodam no Application Insights (Log Analytics) e cobrem os cenários mais comuns de troubleshooting de IA. Todas as consultas usam a tabela `AppRequests` com os nomes de coluna atuais.

### 1. Requisições de Inferência com Alta Latência

Identifique requisições de inferência que excedem seu SLO de latência. Ajuste o limite para corresponder ao seu objetivo — 2000ms é um SLO P95 comum para inferência em tempo real.

```kusto
AppRequests
| where TimeGenerated > ago(24h)
| where DurationMs > 2000
| summarize
    Count = count(),
    AvgLatencyMs = avg(DurationMs),
    P95LatencyMs = percentile(DurationMs, 95),
    P99LatencyMs = percentile(DurationMs, 99)
    by bin(TimeGenerated, 15m), AppRoleName
| order by P99LatencyMs desc
```

### 2. Taxa de Throttling HTTP 429 ao Longo do Tempo

Acompanhe eventos de throttling para entender quando você está atingindo limites de capacidade e se o throttling correlaciona com janelas de tempo específicas.

```kusto
AppRequests
| where TimeGenerated > ago(7d)
| summarize
    TotalRequests = count(),
    ThrottledRequests = countif(ResultCode == "429"),
    ThrottleRate = round(100.0 * countif(ResultCode == "429") / count(), 2)
    by bin(TimeGenerated, 1h), AppRoleName
| where ThrottledRequests > 0
| order by TimeGenerated desc
```

### 3. Correlação de Utilização de GPU com Throughput de Requisições

Correlacione taxas de requisição da aplicação com a utilização de GPU para identificar se é necessário escalar. Esta consulta junta métricas de nível de aplicação com métricas customizadas de GPU, caso você esteja enviando-as para o mesmo workspace.

```kusto
AppRequests
| where TimeGenerated > ago(6h)
| summarize
    RequestsPerMin = count(),
    AvgLatencyMs = avg(DurationMs),
    ErrorRate = round(100.0 * countif(toint(ResultCode) >= 500) / count(), 2)
    by bin(TimeGenerated, 5m), AppRoleName
| order by TimeGenerated asc
```

### 4. Consumo de Tokens por Deployment e Modelo

Acompanhe o uso de tokens entre deployments usando custom dimensions. Isso requer que sua aplicação registre contagens de tokens como propriedades customizadas (veja a seção de instrumentação com OpenTelemetry acima).

```kusto
AppRequests
| where TimeGenerated > ago(24h)
| extend TokensUsed = tolong(Properties["tokens.total"])
| extend Deployment = tostring(Properties["deployment"])
| where isnotempty(TokensUsed)
| summarize
    TotalTokens = sum(TokensUsed),
    AvgTokensPerRequest = avg(TokensUsed),
    RequestCount = count()
    by Deployment, AppRoleName
| order by TotalTokens desc
```

### 5. Detecção de Picos na Taxa de Erros

Detecte aumentos repentinos nas taxas de erro comparando a hora atual com a baseline histórica. Um pico acima de 2× a baseline justifica investigação.

```kusto
let baseline = AppRequests
    | where TimeGenerated between (ago(7d) .. ago(1d))
    | summarize BaselineErrorRate = round(100.0 * countif(toint(ResultCode) >= 500) / count(), 2)
        by AppRoleName;
AppRequests
| where TimeGenerated > ago(1h)
| summarize
    CurrentErrorRate = round(100.0 * countif(toint(ResultCode) >= 500) / count(), 2),
    TotalRequests = count()
    by AppRoleName
| join kind=inner baseline on AppRoleName
| extend SpikeRatio = iff(BaselineErrorRate > 0, CurrentErrorRate / BaselineErrorRate, 0.0)
| where SpikeRatio > 2.0
| project AppRoleName, CurrentErrorRate, BaselineErrorRate, SpikeRatio, TotalRequests
```

### 6. Distribuição de Latência por Faixas de Percentil

Entenda a distribuição completa de latência, não apenas as médias. Médias escondem a dor dos seus usuários de cauda de latência.

```kusto
AppRequests
| where TimeGenerated > ago(4h)
| summarize
    P50 = percentile(DurationMs, 50),
    P75 = percentile(DurationMs, 75),
    P90 = percentile(DurationMs, 90),
    P95 = percentile(DurationMs, 95),
    P99 = percentile(DurationMs, 99),
    Max = max(DurationMs),
    Count = count()
    by AppRoleName
| order by P99 desc
```

⚠️ **Cuidado em Produção**: A função `percentile()` do KQL é aproximada para datasets grandes. Para percentis exatos em relatórios críticos de SLO, use `percentile_tdigest()` ou exporte os dados para análise offline. Para dashboards operacionais, a aproximação padrão é precisa o suficiente.

---

## Estratégia de Alerting

O objetivo do alerting é notificar a pessoa certa, no momento certo, com contexto suficiente para agir. Em workloads de IA, o excesso de alertas é um perigo real — picos de utilização de GPU, flutuações de consumo de tokens e variação de latência são todos comportamentos normais que podem disparar alarmes falsos se você definir limites muito agressivos.

### O Que Alertar (e O Que Não Alertar)

**Alerte sobre estes — eles exigem ação humana:**
- Erros ECC não corrigíveis de GPU (falha de hardware iminente)
- Taxa de HTTP 429 excedendo 5% por mais de 10 minutos
- Latência de inferência P99 excedendo o SLO por 15+ minutos
- Temperatura da GPU acima de 83°C de forma sustentada
- Gastos excedendo o orçamento diário em 20%+
- Zero requisições bem-sucedidas para qualquer deployment (indisponibilidade total)

**Não alerte sobre estes — são informativos:**
- Flutuações de utilização de GPU durante operação normal
- Respostas 429 isoladas (throttling transitório é esperado)
- Picos curtos de latência durante cold starts do modelo
- Consumo de tokens dentro de 80% do orçamento (registre, não acorde ninguém)

### Alerting em Camadas

| Camada | Tempo de Resposta | Canal | Exemplo de Gatilho |
|--------|-------------------|-------|---------------------|
| **P1 — Crítico** | 5 minutos | PagerDuty / telefone | Indisponibilidade total, falha de hardware de GPU, custos descontrolados |
| **P2 — Aviso** | 30 minutos | Slack / Teams | Throttling sustentado, violação de SLO de latência, alta taxa de erros |
| **P3 — Informativo** | Próximo dia útil | E-mail / ticket | Aproximação de limites de cota, custo tendendo acima da previsão |

### Ações de Auto-Remediação

Para modos de falha previsíveis, configure respostas automatizadas:

```text
Gatilho: Taxa de HTTP 429 > 5% por 10 minutos
  → Ação: Escalar para deployment adicional do Azure OpenAI (failover de load balancer)

Gatilho: Memória de GPU > 95% nos pods de inferência
  → Ação: Disparar HPA para adicionar réplicas de inferência

Gatilho: Profundidade da fila de requisições > 100 por 5 minutos
  → Ação: Escalar node pool do AKS, notificar engenheiro de plantão

Gatilho: Temperatura da GPU > 83°C
  → Ação: Reduzir batch size via atualização de ConfigMap, alertar equipe de infraestrutura
```

💡 **Dica Profissional**: Comece apenas com alerting — sem auto-remediação. Uma vez que você tenha validado que um alerta consistentemente representa um problema real (não um alarme falso), então automatize a resposta. Auto-remediação sobre um sinal falso pode causar mais dano do que o problema original.

---

## Dashboards Que Contam uma História

Um dashboard deve responder a uma pergunta específica para um público específico. Três dashboards cobrem a maioria das necessidades de infraestrutura de IA.

### Dashboard Executivo — "Como está o desempenho da plataforma de IA?"

Este dashboard vai para a liderança e finanças. Mantenha-o em alto nível e orientado ao negócio.

- **Disponibilidade**: Percentual de conformidade com SLA (meta: 99,9%)
- **Custo**: Gastos diários e mensais com GPU e tokens, tendência versus orçamento
- **Uso**: Total de requisições atendidas, deployments ativos, contagem de usuários
- **Incidentes**: Alertas P1/P2 abertos, tempo médio de resolução (MTTR)

### Dashboard de Engenharia — "O que precisa da minha atenção?"

Este é o painel do dia a dia para a equipe de infraestrutura e plataforma de ML.

- **Utilização de GPU**: Heatmap de utilização por nó, pressão de memória
- **Percentis de Latência**: P50/P95/P99 por deployment, com linhas de referência de SLO
- **Taxas de Erro**: 4xx e 5xx por endpoint, com anotações de picos
- **Throughput**: Requisições por segundo e tokens por segundo, por modelo
- **Profundidade da Fila**: Requisições pendentes aguardando recursos de GPU

### Dashboard de Capacidade — "Quando precisamos escalar?"

Este dashboard apoia decisões de planejamento de capacidade e aquisição.

- **Uso de Cota**: Consumo atual de cota de GPU versus limites, por região
- **Folga para Escalar**: Quantos pods/nós adicionais podem ser adicionados antes de atingir limites
- **Projeção de Crescimento**: Linha de tendência do volume de requisições com previsão de 30/60/90 dias
- **Taxa de Consumo do Orçamento de Tokens**: Dias restantes na taxa de consumo atual

**Matriz de Decisão — Design de Dashboard**

| Público | Taxa de Atualização | Retenção de Dados | Perguntas-Chave |
|---------|---------------------|-------------------|-----------------|
| **Executivos** | Por hora | 90 dias | "Estamos dentro do orçamento? Os usuários estão satisfeitos?" |
| **Engenheiros** | Tempo real (30s) | 30 dias | "O que está quebrado? O que está degradando?" |
| **Planejadores de capacidade** | Diária | 180 dias | "Quando ficamos sem folga?" |

---

## Mão na Massa: Configurando GPU Monitoring com Prometheus e Grafana

Este passo a passo leva você de um cluster AKS bare com nós GPU a uma stack de monitoramento totalmente instrumentada. Tempo estimado: 20 minutos.

### Pré-requisitos

- Cluster AKS com node pool de GPU (veja o Capítulo 3)
- `kubectl` e `helm` configurados
- Azure CLI autenticado

### Passo 1: Habilitar Azure Managed Prometheus e Grafana

```bash
# Criar um workspace do Azure Monitor
az monitor account create \
  --name ai-monitor-workspace \
  --resource-group myResourceGroup \
  --location eastus

# Criar uma instância de Azure Managed Grafana
az grafana create \
  --name ai-grafana \
  --resource-group myResourceGroup \
  --location eastus

# Habilitar Managed Prometheus no seu cluster AKS
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id \
    "/subscriptions/<sub-id>/resourceGroups/myResourceGroup/providers/Microsoft.Monitor/accounts/ai-monitor-workspace" \
  --grafana-resource-id \
    "/subscriptions/<sub-id>/resourceGroups/myResourceGroup/providers/Microsoft.Dashboard/grafana/ai-grafana"
```

### Passo 2: Implantar o DCGM Exporter

```bash
# Adicionar o repositório Helm da NVIDIA
helm repo add nvidia https://nvidia.github.io/dcgm-exporter/helm-charts
helm repo update

# Instalar o DCGM Exporter direcionado aos nós com GPU
helm install dcgm-exporter nvidia/dcgm-exporter \
  --namespace gpu-monitoring \
  --create-namespace \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.interval=15s

# Verificar se os pods estão rodando nos nós com GPU
kubectl get pods -n gpu-monitoring -o wide
```

### Passo 3: Configurar Custom Scrape para Métricas DCGM

Crie um ConfigMap para garantir que o Azure Managed Prometheus colete os endpoints do DCGM Exporter:

```yaml
# dcgm-scrape-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ama-metrics-prometheus-config
  namespace: kube-system
data:
  prometheus-config: |
    scrape_configs:
    - job_name: dcgm-exporter
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: dcgm-exporter
        action: keep
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
```

```bash
kubectl apply -f dcgm-scrape-config.yaml
```

### Passo 4: Importar Dashboard de GPU no Grafana

```bash
# Obter URL do endpoint do Grafana
az grafana show \
  --name ai-grafana \
  --resource-group myResourceGroup \
  --query "properties.endpoint" -o tsv
```

Navegue até a URL do Grafana e importe o dashboard NVIDIA DCGM:

1. Vá em **Dashboards → Import**
2. Insira o dashboard ID **12239** (dashboard da comunidade NVIDIA DCGM Exporter)
3. Selecione sua fonte de dados Azure Managed Prometheus
4. Clique em **Import**

Agora você deve ver painéis de utilização de GPU, uso de memória, temperatura, consumo de energia e erros ECC sendo atualizados em tempo real.

### Passo 5: Verificar se as Métricas Estão Fluindo

```bash
# Consultar o Prometheus para métricas DCGM via kubectl
kubectl run prom-test --rm -it --image=curlimages/curl -- \
  curl -s "http://dcgm-exporter.gpu-monitoring:9400/metrics" | head -20
```

Você deve ver linhas de métricas como `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED` e `DCGM_FI_DEV_GPU_TEMP` com valores atuais.

⚠️ **Cuidado em Produção**: O DCGM Exporter requer que o driver de GPU NVIDIA e as bibliotecas DCGM estejam presentes no host. No AKS, o driver de GPU é instalado automaticamente via o DaemonSet do NVIDIA device plugin quando você provisiona node pools de GPU. Se os pods do DCGM Exporter estiverem crashando, verifique a instalação do driver de GPU com `kubectl logs -n gpu-resources -l name=nvidia-device-plugin-ds`.

---

## Checklist do Capítulo

Antes de seguir em frente, verifique se você tem essas capacidades implementadas:

- **Métricas de GPU fluindo** — DCGM Exporter implantado, Prometheus coletando, Grafana visualizando
- **Monitoramento do Azure OpenAI** — TPM/RPM acompanhados, alerting de 429 configurado, TTFT medido
- **Distributed tracing** — OpenTelemetry instrumentado em todo o seu pipeline de inferência
- **Consultas KQL salvas** — Consultas de throttling, latência, taxa de erros e consumo de tokens favoritas
- **Alerting em camadas** — Alertas P1/P2/P3 definidos com canais e tempos de resposta apropriados
- **Visibilidade de custos** — Consumo de tokens e gastos com GPU rastreados por equipe/projeto/deployment
- **Três dashboards** — Executivo (custo/SLA), Engenharia (latência/erros), Capacidade (cotas/escala)
- **Monitoramento de segurança** — Padrões de acesso e uso anômalo rastreados
- **Auto-remediação** — Pelo menos uma resposta automatizada para um modo de falha validado
- **Sem fadiga de alertas** — Limites de alertas ajustados para minimizar alarmes falsos

---

## Próximos Passos

Agora você pode ver tudo o que está acontecendo na sua infraestrutura de IA. Cada GPU, cada token, cada pico de latência, cada anomalia de custo — você tem a visibilidade para detectar problemas antes que se tornem indisponibilidades e os dashboards para comunicar a saúde da plataforma a qualquer público.

Mas enxergar não é suficiente — você precisa proteger. Sistemas de IA introduzem superfícies de ataque que a infraestrutura tradicional nunca teve: prompt injection, extração de modelo, envenenamento de dados de treinamento e entradas adversárias que burlam seus filtros de segurança. O Capítulo 8 cobre segurança em ambientes de IA — as novas ameaças que a IA traz e os controles de infraestrutura que as detêm.