# Capítulo 11 — Azure OpenAI: Tokens, Throughput e Capacidade Provisionada

> "O modelo é a parte fácil. Mantê-lo rápido, disponível e dentro do orçamento em escala — esse é o desafio de infraestrutura."

---

## O 429 Que Mudou Tudo

Sua equipe lançou um chatbot interno com GPT-4o numa segunda-feira. Primeiro dia: tudo perfeito, mensagens entusiasmadas no Slack, demonstrações para a liderança. Terceiro dia: usuários começam a reclamar que "o bot está lento." Quinto dia: 30% das requisições retornam erros HTTP 429. Você abre o Azure Monitor e descobre que está batendo no teto de cota de 80K TPM. A resposta do time de data science? "É só aumentar o limite."

Mas não é tão simples. Aumentos de cota não são instantâneos, e simplesmente jogar mais TPM no problema não resolve o design subjacente. Algumas requisições estão consumindo 4.000 tokens para uma pergunta que poderia ser respondida em 200. O system prompt sozinho tem 1.800 tokens — copiado de um blog post e nunca enxugado. A lógica de retry está martelando o endpoint sem nenhum backoff, transformando um evento de throttling em uma falha em cascata.

O que você precisa não é de um cano maior. Você precisa entender como o Azure OpenAI mede, limita e cobra pela capacidade — e como arquitetar considerando essas restrições. É isso que este capítulo entrega. Ao final, você vai falar a linguagem de planejamento de capacidade do Azure OpenAI com a mesma fluência com que fala sobre dimensionamento de VMs e largura de banda de rede.

---

## Fundamentos de Tokens

Antes de planejar capacidade para o Azure OpenAI, você precisa entender tokens — a unidade fundamental de trabalho para large language models.

### O Que É um Token?

Um token é um pedaço de uma palavra. Large language models não processam texto caractere por caractere ou palavra por palavra — eles quebram o texto em fragmentos de subpalavras chamados tokens. Em inglês, um token equivale aproximadamente a quatro caracteres ou três quartos de uma palavra. A palavra "infrastructure" se torna três tokens. A palavra "the" é um token. Um trecho de código como `kubectl get pods` pode ter cinco ou seis tokens.

Isso importa porque tudo no Azure OpenAI é medido em tokens: cobrança, limites de throughput, janelas de contexto e rate limiting. Quando você envia uma requisição para a API, a contagem total de tokens é a soma dos tokens de entrada (seu prompt, mensagem de sistema e qualquer contexto) mais os tokens de saída (a resposta do modelo). As duas direções contam.

### Estimando a Contagem de Tokens

Para planejamento de capacidade, use estas regras práticas:

| Tipo de Texto | Tokens Aproximados por 1.000 Caracteres |
|---|---|
| Prosa em inglês | ~250 tokens |
| Código-fonte | ~300–350 tokens |
| Dados estruturados (JSON, XML) | ~350–400 tokens |
| Conteúdo misto (contexto RAG) | ~280 tokens |

Uma fórmula prática para uma única requisição:

```
Total Tokens = System Prompt Tokens + User Input Tokens + Output Tokens
```

Para uma interação típica de chatbot — system prompt de 500 tokens, pergunta do usuário de 300 tokens, resposta de 800 tokens — você está consumindo 1.600 tokens por requisição. Multiplique isso pela sua base de usuários simultâneos e requisições por minuto, e você tem seu requisito de throughput.

### Tamanhos de Janela de Contexto

Cada modelo tem uma janela de contexto máxima — o limite superior de tokens totais em uma única requisição (entrada mais saída combinadas):

| Modelo | Janela de Contexto |
|---|---|
| GPT-4o | 128K tokens |
| GPT-4o-mini | 128K tokens |
| GPT-4 Turbo | 128K tokens |
| GPT-3.5 Turbo | 16K tokens |

Uma janela de contexto grande não significa que você deve preenchê-la. Cada token na janela de contexto conta contra sua cota de TPM. Uma única requisição de 100K tokens com um prompt recheado de RAG consome tanto throughput quanto 62 requisições menores de 1.600 tokens.

**Tradução Infra ↔ IA**: Pense nos tokens como o payload do pacote da IA. TPM é o teto de largura de banda — o throughput total de dados que você consegue enviar por minuto. RPM é o seu limite de pacotes por segundo. Assim como em redes, você pode estar limitado por largura de banda (payloads grandes, poucas requisições) ou limitado por PPS (payloads pequenos, muitas requisições). Mesmo raciocínio diagnóstico, unidades diferentes.

---

## Tipos de Deployment — A Decisão Crítica

Quando você cria um deployment no Azure OpenAI, está tomando uma decisão arquitetural que determina seu modelo de custo, garantias de throughput e modos de falha. O Azure OpenAI oferece vários tipos de deployment, e escolher o errado é o erro mais comum de planejamento de capacidade que as equipes cometem.

### Matriz de Decisão: Standard vs Global Standard vs Provisioned (PTU)

| Característica | Standard | Global Standard | Provisioned (PTU) |
|---|---|---|---|
| **Modelo de cobrança** | Pago por token | Pago por token | Custo mensal fixo por PTU |
| **Throughput** | Limitado por cota (TPM/RPM) | Limitado por cota, defaults mais altos | Capacidade reservada garantida |
| **Latência** | Variável (infra compartilhada) | Variável (roteado pela Microsoft) | Previsível, baixa variância |
| **Residência de dados** | Região única | Microsoft seleciona a região | Região única |
| **Throttling** | 429 quando cota excedida | 429 quando cota excedida | Sem throttling dentro da capacidade PTU |
| **Garantia de capacidade** | ❌ Melhor esforço | ❌ Melhor esforço | ✅ Reservada e garantida |
| **Compromisso mínimo** | Nenhum | Nenhum | Tipicamente mensal |
| **Ideal para** | Dev/test, cargas variáveis | Apps globais, limites padrão mais altos | Produção, apps com SLA |

### Deployments Standard

Deployments Standard são pagos por token, com limites de taxa expressos como cotas de TPM (Tokens Per Minute) e RPM (Requests Per Minute). Você define essas cotas ao criar o deployment, consumindo de um pool por assinatura, por região e por modelo. Se sua assinatura tem 300K TPM de cota para GPT-4o em East US, você pode dividir isso entre múltiplos deployments — digamos, 200K para produção e 100K para desenvolvimento.

Standard é a escolha certa quando as cargas de trabalho são imprevisíveis ou com picos. Você paga apenas pelo que consome. A contrapartida: durante picos de demanda, a latência aumenta e erros 429 são possíveis. Não há infraestrutura dedicada por trás do seu deployment — você está compartilhando capacidade com outros clientes do Azure OpenAI naquela região.

### Deployments Global Standard

Global Standard usa o mesmo preço pago por token, mas roteia requisições pela infraestrutura global da Microsoft. Você não escolhe qual região processa uma requisição específica — a Microsoft gerencia o roteamento para disponibilidade ideal. Isso tipicamente resulta em cotas padrão mais altas e melhor disponibilidade durante pressão de capacidade regional.

A contrapartida é a residência de dados. Se seus requisitos de conformidade exigem que os dados permaneçam em uma região específica, Global Standard não é uma opção. Para a maioria das aplicações internas sem restrições regulatórias, é uma excelente escolha padrão.

### Deployments Data Zone

Deployments Data Zone oferecem um meio-termo para residência de dados. O tráfego permanece dentro de um limite geográfico definido (por exemplo, EUA ou Europa), mas pode ser roteado entre regiões dentro desse limite. Isso proporciona alguns dos benefícios de disponibilidade do Global Standard enquanto mantém os dados dentro de uma geografia amigável à conformidade.

### Provisioned Throughput Units (PTU)

Deployments PTU reservam capacidade dedicada de inferência para sua carga de trabalho. Você adquire um número fixo de Provisioned Throughput Units, cada uma representando uma quantidade específica de capacidade de processamento do modelo. O benefício principal: sem throttling. Se sua carga de trabalho cabe dentro da capacidade provisionada, toda requisição é atendida sem erros 429 e com latência consistente e previsível.

PTU faz sentido quando você precisa de garantias no nível de SLA — copilots voltados ao cliente, aplicações que geram receita ou cargas de trabalho onde um erro 429 tem impacto direto no negócio. Também faz sentido em escala: quando seu consumo Standard é alto o suficiente, PTU se torna mais custo-efetivo porque você paga uma taxa fixa independente do uso.

⚠️ **Cuidado em Produção**: O throughput do PTU varia por modelo, tamanho do prompt e tamanho da geração. Um PTU configurado para GPT-4o não entrega um número fixo de TPM — o throughput depende do mix de tokens de entrada e saída da sua carga real. Nunca fixe no código proporções de TPM por PTU tiradas da documentação. Use a [calculadora de capacidade do Azure OpenAI](https://oai.azure.com/portal/calculator) com seus padrões reais de tráfego para estimar requisitos de PTU, e valide com testes de carga antes de se comprometer.

### Escolhendo o Tipo de Deployment Correto

Use este fluxo de decisão:

1. **Carga variável, baixo volume ou experimental?** → Standard ou Global Standard
2. **Precisa de cotas padrão mais altas, sem restrições de residência de dados?** → Global Standard
3. **Residência de dados dentro de uma geografia (EUA, UE)?** → Data Zone
4. **Carga de produção com requisitos de SLA, ou volume consistentemente alto?** → Provisioned (PTU)
5. **Produção crítica com necessidade de capacidade de overflow?** → PTU primário + Standard como overflow (veja Arquitetura de Alta Disponibilidade)

💡 **Dica Pro**: Muitas arquiteturas de produção combinam tipos de deployment. Roteie o tráfego base para PTU com latência garantida e o tráfego de overflow para Standard ou Global Standard durante picos. O API Management torna esse roteamento simples — vamos cobrir o padrão mais adiante neste capítulo.

---

## Entendendo Throttling

Throttling é o primeiro problema de capacidade que você vai encontrar no Azure OpenAI, e é o mais mal compreendido. Dois limites independentes controlam seu throughput, e atingir qualquer um deles dispara o throttling.

### TPM — Tokens Per Minute

TPM é o teto de throughput total. Ele limita o número agregado de tokens — entrada e saída combinados — que seu deployment pode processar por minuto. Se seu deployment tem uma cota de 80K TPM e você envia requisições totalizando 85K tokens em uma janela de um minuto, as requisições que ultrapassam os 80K são rejeitadas com HTTP 429.

### RPM — Requests Per Minute

RPM limita o número de chamadas individuais à API por minuto, independentemente de quantos tokens cada requisição contém. O Azure OpenAI define um RPM padrão derivado da sua alocação de TPM (tipicamente TPM ÷ 6 para modelos de chat), mas o limite efetivo depende do perfil da sua carga de trabalho.

### Por Que Você Atinge Um Antes do Outro

Entender qual limite você atingirá primeiro é crítico para diagnósticos:

- **Muitas requisições pequenas** (autocomplete, classificação, Q&A curto): Você atinge RPM antes de TPM. Cada requisição usa poucos tokens, mas o volume de chamadas excede o limite de contagem de requisições.
- **Poucas requisições grandes** (RAG com contexto grande, sumarização de documentos): Você atinge TPM antes de RPM. Cada requisição é pesada em tokens, então você esgota o orçamento de tokens muito antes de atingir o teto de contagem de requisições.

Essa distinção importa porque a solução é diferente. Cargas limitadas por RPM se beneficiam de agrupamento ou consolidação de requisições. Cargas limitadas por TPM se beneficiam de prompts mais curtos, janelas de contexto menores ou simplesmente mais cota de TPM.

### A Resposta 429

Quando ocorre throttling, o Azure OpenAI retorna um HTTP 429 com um header `Retry-After` indicando quantos segundos esperar antes de tentar novamente. Um cliente bem projetado respeita esse header. Um cliente mal projetado o ignora, tenta novamente imediatamente e amplifica o problema — cada retry rejeitado também conta contra sua janela de cota.

### Estratégia de Retry: Exponential Backoff com Jitter

O padrão correto de retry para respostas 429:

```
wait_time = min(base_delay × 2^attempt + random_jitter, max_delay)
```

| Tentativa | Base Delay | Backoff | Jitter (exemplo) | Espera Total |
|---|---|---|---|---|
| 1 | 1s | 2s | +0.3s | ~2.3s |
| 2 | 1s | 4s | +0.7s | ~4.7s |
| 3 | 1s | 8s | +0.1s | ~8.1s |
| 4 | 1s | 16s | +0.5s | ~16.5s |

O jitter previne o problema de "thundering herd", onde múltiplos clientes tentam novamente simultaneamente, criando outro pico. Se o valor do header `Retry-After` for maior que o seu backoff calculado, sempre use o `Retry-After`.

⚠️ **Cuidado em Produção**: Retries agressivos em deployments Standard podem criar um ciclo de retroalimentação. Os próprios retries consomem cota, o que significa que cada ciclo de retry torna o próximo mais propenso a falhar. Limite sua contagem de retries (máximo de 3–5 tentativas), e se o header `Retry-After` exceder 60 segundos, roteie a requisição para um deployment de fallback em outra região em vez de esperar.

---

## Planejamento de Capacidade

O planejamento de capacidade para Azure OpenAI segue os mesmos princípios de qualquer exercício de dimensionamento de infraestrutura: estimar a demanda, planejar para picos e reservar margem. As unidades é que são diferentes.

### Estimando Requisitos de TPM

A fórmula central:

```
Required TPM = Concurrent Users × Requests per Minute per User × Avg Tokens per Request
```

### Exemplo Prático

Suponha que você está implantando um chatbot de atendimento ao cliente com estas características:

| Parâmetro | Valor |
|---|---|
| Usuários simultâneos | 500 |
| Requisições por minuto por usuário | 2 |
| Tokens médios por requisição (entrada + saída) | 1.500 |

```
Required TPM = 500 × 2 × 1.500 = 1.500.000 TPM (1,5M)
```

Isso está bem acima da cota padrão para a maioria dos modelos. Você precisará solicitar um aumento de cota, dividir o tráfego entre múltiplos deployments ou regiões, ou considerar PTU.

### Planejando para Picos vs Média

TPM médio é útil para modelagem de custos. TPM de pico é o que determina se os usuários verão erros 429. Cargas de produção tipicamente apresentam 2–5× a média durante períodos de pico (segundas de manhã, final de trimestre, lançamentos de produto). Dimensione sua cota para o pico, não para a média.

| Meta de Planejamento | Fórmula | Uso |
|---|---|---|
| TPM Médio | Usuários × RPM × Tokens/Requisição | Estimativa de custos, dimensionamento de PTU |
| TPM de Pico | TPM Médio × Multiplicador de pico (2–5×) | Alocação de cota, dimensionamento de deployment Standard |
| TPM de Burst | TPM de Pico + 30% de margem | Margem de segurança para produção |

### Aumentos de Cota

Cotas padrão são pontos de partida, não tetos fixos. Você pode solicitar aumentos de cota pelo Portal do Azure em seu recurso Azure OpenAI → Quotas. Os aumentos estão sujeitos à disponibilidade de capacidade regional — modelos populares em regiões populares (GPT-4o em East US) podem ter tempos de espera mais longos. Planeje com antecedência e solicite aumentos antes de precisar deles, não durante uma indisponibilidade.

### Balanceamento de Carga Multi-Deployment

Quando a cota de um único deployment não é suficiente, distribua o tráfego entre múltiplos deployments. Você pode implantar o mesmo modelo várias vezes dentro de uma região (cada um consumindo do pool de cota da região) ou entre regiões. O Azure API Management é a porta de entrada natural para esse padrão — ele pode fazer round-robin de requisições, rotear com base em prioridade e automaticamente fazer failover em respostas 429.

💡 **Dica Pro**: Ao solicitar cota para planejamento de capacidade, documente seu uso de pico esperado e caso de uso. Revisores de cota aprovam aumentos mais rápido quando entendem a carga de trabalho. "Precisamos de 2M TPM para um chatbot de suporte interno para 500 usuários com padrões de pico documentados" é aprovado mais rápido do que "por favor, aumente nossa cota."

---

## Arquitetura de Alta Disponibilidade

Um deployment Azure OpenAI em produção precisa dos mesmos padrões de resiliência de qualquer serviço crítico: redundância, failover e roteamento inteligente. A diferença é que seu modo de falha frequentemente é throttling em vez de crashes — e a lógica de roteamento precisa ser consciente de tokens.

### Padrão de Deployment Multi-Região

Implante o mesmo modelo em pelo menos duas regiões do Azure. Se sua região primária atingir limites de capacidade ou sofrer uma indisponibilidade, o tráfego é roteado para a secundária. Com Global Standard, a Microsoft lida com parte desse roteamento automaticamente. Com Standard ou PTU, você gerencia através da sua própria camada de balanceamento de carga.

### API Management como Roteador Inteligente

O Azure API Management (APIM) fica entre sua aplicação e o Azure OpenAI, fornecendo:

- **Retry em 429**: Quando um deployment backend retorna 429, o APIM automaticamente tenta novamente em um deployment alternativo
- **Balanceamento de carga**: Distribui requisições entre múltiplos deployments usando round-robin ou roteamento ponderado
- **Roteamento por prioridade**: Envia requisições críticas para PTU (capacidade garantida), overflow para Standard
- **Rate limiting**: Aplica cotas por cliente ou por aplicação sobre as cotas do Azure OpenAI
- **Rastreamento de tokens**: Registra o consumo de tokens por cliente para chargeback e alocação de custos

### Roteamento Baseado em Prioridade (PTU + Standard)

O padrão de produção mais comum combina deployments PTU e Standard:

```
┌─────────────────┐
│    Aplicação    │
└────────┬────────┘
         │
┌────────▼─────────┐
│  API Management  │
│ (Roteador Intel.)│
└───┬─────────┬────┘
    │         │
    ▼         ▼
┌───────┐ ┌──────────┐
│  PTU  │ │ Standard │
│Primár.│ │ Overflow │
└───────┘ └──────────┘
```

Todo o tráfego é roteado para o deployment PTU primeiro. Se o deployment PTU não conseguir lidar com a carga (ou estiver em manutenção), o APIM roteia o overflow para um deployment Standard. Isso proporciona latência previsível para seu tráfego base e capacidade elástica para picos — sem pagar preço de PTU pela capacidade de burst.

### Padrão Circuit Breaker

Quando um deployment está consistentemente retornando erros, pare de enviar tráfego para ele temporariamente em vez de martelá-lo com retries. Implemente um circuit breaker na sua política do APIM:

- **Closed** (normal): Todas as requisições são roteadas para o deployment
- **Open** (disparado): Após N falhas consecutivas, pare de rotear para este deployment por um período de cooldown
- **Half-Open** (testando): Após o cooldown, envie uma única requisição de teste. Se tiver sucesso, feche o circuito; se falhar, reabra

Isso evita que um deployment com falhas consuma seu orçamento de retries e degrade a experiência de todos os usuários.

💡 **Dica Pro**: Marque suas políticas do APIM com o tipo de deployment. Quando o circuit breaker dispara em um deployment Standard devido à pressão de capacidade regional, ele deve fazer failover para um deployment Standard de outra região — não para o seu deployment PTU, que deve ser reservado para tráfego prioritário.

---

## Monitorando o Azure OpenAI

Você não pode otimizar o que não pode medir. O Azure OpenAI expõe métricas chave através do Azure Monitor, e logs de diagnóstico fluem para o Log Analytics para análise aprofundada.

### Métricas Chave para Acompanhar

| Métrica | O Que Ela Informa | Limite para Alerta |
|---|---|---|
| Azure OpenAI Requests | Contagem total de requisições por deployment | Baseline + 50% |
| Generated Completion Tokens | Tokens de saída consumidos | Tendência em direção à cota |
| Processed Prompt Tokens | Tokens de entrada consumidos | Tendência em direção à cota |
| Provisioned-managed Utilization (PTU) | Percentual de capacidade PTU em uso | > 80% |
| Contagem de HTTP 429 | Requisições com throttling | > 0 em produção |
| Time to First Token (TTFT) | Latência antes da resposta começar o streaming | > 2s para cargas de chat |

### Queries KQL para Diagnósticos do Azure OpenAI

Após habilitar o log de diagnósticos no seu recurso Azure OpenAI, os dados de requisições fluem para a tabela `AppRequests` no Log Analytics. Aqui estão queries que você vai usar repetidamente.

**Taxa de throttling ao longo do tempo (erros 429):**

```kql
AppRequests
| where TimeGenerated > ago(24h)
| where Url contains "openai"
| summarize
    TotalRequests = count(),
    ThrottledRequests = countif(ResultCode == "429"),
    ThrottleRate = round(100.0 * countif(ResultCode == "429") / count(), 2)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**Consumo de tokens por deployment:**

```kql
AppRequests
| where TimeGenerated > ago(24h)
| where Url contains "openai"
| extend
    PromptTokens = toint(Properties["promptTokens"]),
    CompletionTokens = toint(Properties["completionTokens"])
| summarize
    TotalPromptTokens = sum(PromptTokens),
    TotalCompletionTokens = sum(CompletionTokens),
    TotalTokens = sum(PromptTokens) + sum(CompletionTokens),
    RequestCount = count()
    by tostring(Properties["deploymentId"])
```

**Percentis de latência (P50, P95, P99):**

```kql
AppRequests
| where TimeGenerated > ago(1h)
| where Url contains "openai"
| where ResultCode == "200"
| summarize
    P50 = percentile(DurationMs, 50),
    P95 = percentile(DurationMs, 95),
    P99 = percentile(DurationMs, 99),
    AvgDuration = avg(DurationMs)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Estratégia de Alertas

Configure alertas antes de precisar deles:

- **Utilização de tokens > 80%**: Aviso — você está se aproximando do teto de cota. Comece a planejar um aumento de cota ou deployments adicionais.
- **Taxa de 429 > 1%**: Crítico — usuários estão experimentando falhas. Investigue imediatamente.
- **Latência P95 > 5 segundos**: Aviso — a experiência do usuário está se degradando, mesmo que as requisições estejam tendo sucesso.
- **Utilização de PTU > 90%**: Crítico — sua capacidade reservada está quase saturada. O tráfego de overflow precisará de um caminho de fallback.

⚠️ **Cuidado em Produção**: As métricas do Azure OpenAI no Azure Monitor têm um atraso de reporte de 1–3 minutos. Não confie em dashboards em tempo real para resposta a incidentes de throttling. Em vez disso, instrumente sua camada de aplicação (Application Insights, OpenTelemetry) para visibilidade sub-minuto nas taxas de 429 e latência.

---

## Técnicas de Otimização

Uma vez que seu deployment Azure OpenAI esteja instrumentado e monitorado, a otimização se torna um exercício orientado por dados. Cada token que você economiza reduz custos e libera throughput para requisições adicionais.

### Cache de Prompt

O Azure OpenAI suporta cache de prompt para prefixos repetidos. Se o seu system prompt é idêntico entre requisições (e geralmente deveria ser), o serviço armazena a representação processada em cache e pula a recomputação em chamadas subsequentes. Isso reduz tanto a latência quanto o consumo efetivo de tokens para a porção em cache. O cache de prompt funciona automaticamente quando o início do seu prompt corresponde a uma requisição anterior — sem necessidade de configuração.

### System Prompts Mais Curtos

Cada token no seu system prompt conta contra o TPM em toda requisição. Um system prompt de 1.800 tokens copiado de um tutorial consome 1.800 tokens mesmo quando a pergunta real do usuário é de 50 tokens. Enxugue sem piedade. A maioria dos system prompts de produção pode ser reduzida para 200–400 tokens sem perder efetividade. Isso é uma redução potencial de 80% na sobrecarga por requisição.

### Limites de Tamanho da Resposta

Defina o parâmetro `max_tokens` para limitar o tamanho da saída. Sem ele, o modelo gera até atingir seu ponto de parada natural — que pode ser 2.000 tokens quando sua UI exibe apenas os primeiros 500. Para tarefas de classificação (sentimento, categoria, sim/não), defina `max_tokens` entre 10–50. Para resumos, 200–500. Só deixe sem limite quando você genuinamente precisa de geração aberta.

### Roteamento de Modelos — Dimensione Corretamente Cada Requisição

Nem toda requisição precisa do GPT-4o. Construa uma camada de roteamento que corresponda a complexidade da requisição à capacidade do modelo:

| Tipo de Requisição | Modelo Recomendado | Por Quê |
|---|---|---|
| Classificação, tagging, extração | GPT-4o-mini | Rápido, barato, preciso para tarefas estruturadas |
| Q&A curto, consulta de FAQ | GPT-4o-mini | Qualidade suficiente a ~20× menos custo |
| Raciocínio complexo, geração de código | GPT-4o | Maior precisão justifica o custo mais alto |
| Sumarização de documentos, análise | GPT-4o | Melhor em tarefas nuançadas e de contexto longo |

Um classificador simples baseado em palavras-chave ou ML no API gateway pode rotear 60–70% das requisições para GPT-4o-mini, reduzindo significativamente os custos totais de tokens.

### Batch API para Cargas Não Tempo-Real

A Batch API do Azure OpenAI processa requisições de forma assíncrona com 50% de desconto em relação ao preço padrão. Se sua carga de trabalho não precisa de respostas em tempo real — geração de relatórios noturnos, processamento em massa de documentos, classificação em lote — use a Batch API. Você envia um arquivo de requisições e recupera os resultados depois (tipicamente dentro de 24 horas).

### Streaming para Melhor Latência Percebida

Streaming não reduz o consumo total de tokens nem o custo, mas melhora dramaticamente a latência percebida. Em vez de esperar a resposta inteira ser gerada antes de exibir qualquer coisa, o cliente recebe tokens conforme são produzidos. O Time to First Token (TTFT) cai de segundos para milissegundos. Para aplicações interativas, sempre habilite streaming.

**Tradução Infra ↔ IA**: Roteamento de modelos é o equivalente de IA ao armazenamento em camadas. Você não armazena todos os arquivos em NVMe premium — você distribui em camadas com base nos padrões de acesso e requisitos de desempenho. Da mesma forma, você não roteia todo prompt para GPT-4o. Requisições quentes (complexas, voltadas ao usuário) recebem o modelo premium. Requisições mornas (simples, em segundo plano) recebem o modelo custo-efetivo.

---

## Checklist do Capítulo

Antes de seguir em frente, verifique se você abordou estes fundamentos de planejamento de capacidade:

- **Estimativa de tokens**: Você consegue estimar tokens por requisição para sua carga de trabalho (system prompt + entrada + saída)
- **Tipo de deployment selecionado**: Standard, Global Standard ou PTU — escolhido com base na previsibilidade da carga e requisitos de SLA
- **Cotas TPM/RPM dimensionadas**: Calculadas para o pico, não para a média, com margem
- **Throttling compreendido**: Você sabe se sua carga é limitada por TPM ou por RPM, e tem lógica de retry com exponential backoff e jitter
- **Plano de capacidade documentado**: Usuários simultâneos × requisições/min × tokens/requisição = TPM necessário, com multiplicador de pico aplicado
- **Failover multi-região configurado**: Pelo menos dois deployments em regiões diferentes com roteamento via API Management
- **Monitoramento habilitado**: Logs de diagnóstico fluindo para o Log Analytics, alertas sobre taxa de 429, latência e utilização de tokens
- **Otimização aplicada**: System prompts enxugados, max_tokens definido, roteamento de modelos implementado para seleção de modelo com custo adequado
- **Batch API avaliada**: Cargas não tempo-real movidas para Batch API com 50% de economia
- **Dimensionamento de PTU validado**: Se usando PTU, throughput testado com padrões reais de tráfego — nunca confiando em proporções fixas de TPM por PTU

---

## Próximos Passos

Agora você entende a linguagem de planejamento de capacidade do Azure OpenAI — tokens, modelos de throughput, tipos de deployment e os padrões arquiteturais que mantêm cargas de produção rápidas e resilientes. Mas o que acontece quando as coisas dão errado — não apenas throttling, mas crashes de driver de GPU, falhas de agendamento de pods e picos de latência de inferência? O Capítulo 12 é o playbook de troubleshooting que você vai deixar nos favoritos.

**Próximo: [Capítulo 12 — Troubleshooting de Infraestrutura de IA](12-troubleshooting.md)**