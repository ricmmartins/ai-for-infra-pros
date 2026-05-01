# Capítulo 9 — Engenharia de Custos para Cargas de Trabalho de IA

> "A nuvem não tem um problema de gastos. Ela tem um problema de visibilidade."

---

## A Segunda-Feira de $127.000

É segunda-feira de manhã. Você está no meio do seu café quando chega um e-mail do financeiro com o assunto: **"URGENTE: fatura do Azure — $127.000 — favor explicar."** A previsão do mês passado era $42.000. Você abre o Azure Cost Management e começa a investigar. Duas VMs ND96isr_H100_v5 saltam na tela — provisionadas há três semanas para um "experimento rápido" e nunca foram desligadas. A aproximadamente $98/hora cada, rodando 24/7 por três semanas, isso dá cerca de $33.000 em tempo ocioso de GPU. Ninguém estava usando. Ninguém sequer lembrava que elas estavam ligadas.

Isso não é hipotético. Variações dessa história acontecem em organizações todo mês. O engenheiro de ML que provisionou essas VMs não estava sendo descuidado — ele estava iterando rápido, que é exatamente o que você quer da sua equipe de data science. A falha não foi humana; foi sistêmica. Sem política de desligamento automático, sem alertas de orçamento, sem tags para rastrear as VMs até um projeto ou responsável.

Este capítulo oferece os frameworks, fórmulas e práticas operacionais para garantir que esse e-mail nunca chegue à sua caixa de entrada. Não desacelerando a experimentação, mas construindo guardrails que tornam a consciência de custos automática.

---

## Por Que a Engenharia de Custos de IA É Diferente

Se você já gerenciou custos de nuvem para cargas de trabalho tradicionais, já conhece os fundamentos: dimensionar VMs corretamente, usar reserved instances, desligar ambientes de dev/test à noite. Cargas de trabalho de IA seguem os mesmos princípios — mas os valores em jogo são dramaticamente maiores e os padrões de gasto são muito menos previsíveis.

### VMs com GPU Custam 10–100× Mais que VMs de Uso Geral

Uma Standard_D4s_v5 (4 vCPUs, 16 GB RAM) custa aproximadamente $0,19/hora. Uma ND96isr_H100_v5 (8× H100 GPUs) custa aproximadamente $98/hora. Isso é uma diferença de 500×. Uma VM de uso geral mal configurada rodando ociosa no fim de semana custa $9. Uma VM com GPU mal configurada rodando ociosa no fim de semana custa $4.700. A margem para erro diminui drasticamente.

### Treinamento É Intermitente

Cargas de trabalho tradicionais tendem a padrões de estado estacionário — servidores web lidam com tráfego previsível, bancos de dados atendem consultas consistentes. O treinamento de IA é fundamentalmente diferente. Uma equipe pode consumir zero horas de GPU por duas semanas enquanto prepara dados, depois disparar para 64 GPUs durante cinco dias de treinamento, e voltar a zero. Esse padrão intermitente dificulta previsões e torna compromissos de capacidade reservada arriscados sem planejamento cuidadoso.

### Precificação Baseada em Tokens Adiciona uma Camada Variável

Quando suas equipes consomem serviços do Azure OpenAI, os custos escalam com o uso de uma forma mais difícil de prever do que horas de VM. Um chatbot que atende 1.000 consultas por dia com prompts curtos custa uma fração de um que processa 1.000 documentos jurídicos com contextos de 100K tokens. Ambos são "a mesma aplicação" do ponto de vista de infraestrutura, mas os perfis de custo são completamente diferentes.

### Cultura de Experimentação Entra em Conflito com Disciplina Orçamentária

Data scientists precisam experimentar — é assim que modelos melhoram. Mas experimentação significa provisionar recursos com pouca antecedência, testar diferentes configurações e às vezes abandonar abordagens no meio do caminho. Dizer à equipe de ML "envie uma ordem de compra antes de provisionar qualquer GPU" mata a velocidade. A solução não é menos experimentação; é melhores guardrails ao redor da experimentação.

**Infra ↔ IA — Tradução**: Tempo ocioso de GPU é como deixar todas as luzes de um estádio ligadas depois que o jogo termina. A conta de energia por hora é enorme, ninguém está se beneficiando, e a solução é um simples timer — mas alguém precisa instalar o timer antes do primeiro jogo.

---

## Modelagem de Custos de GPU

Antes de otimizar custos, você precisa modelá-los. Cargas de trabalho de IA têm dois perfis de custo fundamentalmente diferentes: **treinamento** (executar seus próprios modelos em VMs com GPU) e **inferência** (consumir uma API de modelo como o Azure OpenAI). Vamos construir as fórmulas para cada um.

### Preços de VMs com GPU por Família

A tabela abaixo apresenta custos aproximados de pay-as-you-go para SKUs de VMs com GPU comuns no Azure. Esses preços mudam frequentemente — sempre verifique na [Calculadora de Preços do Azure](https://azure.microsoft.com/pricing/calculator/) para valores atualizados.

| SKU da VM | GPU | Qtd. de GPUs | Memória GPU | Custo Aprox./Hora (Pay-as-you-go) | Caso de Uso Principal |
|---|---|---|---|---|---|
| NC4as_T4_v3 | NVIDIA T4 | 1 | 16 GB | ~$0,53 | Inferência, fine-tuning leve |
| NC24ads_A100_v4 | NVIDIA A100 | 1 | 80 GB | ~$3,67 | Treinamento, inferência |
| NC48ads_A100_v4 | NVIDIA A100 | 2 | 160 GB | ~$7,35 | Treinamento multi-GPU |
| ND96asr_v4 | NVIDIA A100 | 8 | 320 GB | ~$27,20 | Treinamento em larga escala |
| ND96isr_H100_v5 | NVIDIA H100 | 8 | 640 GB | ~$98,00 | Treinamento de modelos de fronteira |

> **Nota**: Os preços são aproximados, em USD, e variam por região. East US e West US 2 tendem a ter maior disponibilidade para SKUs com GPU.

### Fórmula de Custo de Treinamento

Para cargas de trabalho de treinamento executadas em VMs com GPU, a fórmula base é:

```
Training Cost = (GPU count × Hours × Price/GPU-hour) + Storage + Networking
```

**Exemplo prático — fine-tuning de um modelo de 7B parâmetros:**

| Componente | Cálculo | Custo |
|---|---|---|
| Computação | 2× A100 GPUs × 18 horas × $3,67/hr | $132,12 |
| Armazenamento | 500 GB Premium SSD × 18 horas | ~$2,50 |
| Rede | Desprezível (VM única) | ~$0 |
| **Total** | | **~$135** |

**Exemplo prático — pré-treinamento de um modelo de 70B parâmetros:**

| Componente | Cálculo | Custo |
|---|---|---|
| Computação | 64× H100 GPUs (8 VMs) × 72 horas × $98/hr por VM | $56.448 |
| Armazenamento | 10 TB entre nós × 72 horas | ~$85 |
| Rede | InfiniBand entre nós (incluído no SKU ND) | $0 |
| **Total** | | **~$56.533** |

A diferença entre esses exemplos ilustra por que o dimensionamento correto importa. Provisionar H100s para um trabalho que roda bem em A100s não apenas desperdiça dinheiro — desperdiça 3–4× o dinheiro.

### Fórmula de Custo de Inferência (Azure OpenAI)

Para consumo do Azure OpenAI, os custos são baseados em tokens:

```
Inference Cost = Requests × Avg Tokens/Request × Price per 1K Tokens
```

**Exemplo prático — chatbot de suporte ao cliente (GPT-4o):**

| Componente | Cálculo | Custo |
|---|---|---|
| Tokens de entrada | 10.000 requests/dia × 800 tokens × $0,0025/1K | $20,00/dia |
| Tokens de saída | 10.000 requests/dia × 400 tokens × $0,01/1K | $40,00/dia |
| **Total diário** | | **$60/dia** |
| **Total mensal** | $60 × 30 | **~$1.800/mês** |

**Exemplo prático — mesmo chatbot usando GPT-4o-mini:**

| Componente | Cálculo | Custo |
|---|---|---|
| Tokens de entrada | 10.000 requests/dia × 800 tokens × $0,00015/1K | $1,20/dia |
| Tokens de saída | 10.000 requests/dia × 400 tokens × $0,0006/1K | $2,40/dia |
| **Total diário** | | **$3,60/dia** |
| **Total mensal** | $3,60 × 30 | **~$108/mês** |

Isso é uma redução de 94% nos custos para consultas onde o GPT-4o-mini entrega qualidade aceitável — e para muitos cenários de suporte ao cliente, ele entrega.

> **Nota**: Os preços de tokens mostrados são aproximados e sujeitos a alteração. Sempre verifique os preços atuais na [página de preços do Azure OpenAI](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/).

### Matriz de Decisão: Modelos de Compra de Computação

| Fator | Pay-as-you-go | Reserved 1 Ano | Reserved 3 Anos | Spot VMs |
|---|---|---|---|---|
| **Desconto** | 0% (base) | ~30–40% | ~50–60% | ~60–90% |
| **Compromisso** | Nenhum | 1 ano | 3 anos | Nenhum |
| **Risco de evicção** | Nenhum | Nenhum | Nenhum | Alto |
| **Ideal para** | Experimentação, cargas imprevisíveis | Inferência em estado estacionário | Clusters de treinamento de longo prazo | Treinamento tolerante a falhas |
| **Previsibilidade orçamentária** | Baixa | Alta | Alta | Baixa |
| **Flexibilidade** | Máxima | Moderada (permite troca) | Baixa | Máxima |

💡 **Dica**: Não se comprometa com reserved instances até ter pelo menos 2–3 meses de dados de utilização. Muitas organizações reservam cedo demais e acabam pagando por GPUs que não usam. Comece com pay-as-you-go, meça o consumo real e reserve apenas a base que você tem confiança de que vai sustentar.

---

## Spot VMs e VMs de Baixa Prioridade para Treinamento

As Spot VMs do Azure oferecem o mesmo hardware de GPU com 60–90% de desconto — mas o Azure pode recuperá-las com apenas 30 segundos de aviso quando a capacidade é necessária. Para as cargas de trabalho certas, essa é a maior alavanca de redução de custos disponível.

### Quando Spot É Seguro

Spot VMs funcionam bem quando seu framework de treinamento suporta **checkpoint-and-resume**. Isso significa que o job de treinamento salva periodicamente seu estado (pesos do modelo, estado do otimizador, learning rate schedule, epoch atual) em armazenamento durável. Se a VM for despejada, uma nova Spot VM retoma do último checkpoint em vez de recomeçar do zero.

Frameworks que suportam isso bem:

- **PyTorch Lightning**: Checkpointing nativo com callback `ModelCheckpoint`
- **DeepSpeed**: Checkpointing automático integrado com o otimizador ZeRO
- **Hugging Face Transformers**: Parâmetros `save_steps` e `resume_from_checkpoint`
- **Azure ML**: Checkpointing gerenciado para jobs de treinamento

### Quando Spot NÃO É Seguro

Não use Spot VMs quando:

- **Prazos são inegociáveis**: Se um modelo precisa estar treinado até sexta-feira, evicções repetidas podem empurrar você além do prazo
- **Checkpointing não está implementado**: Sem checkpointing, cada evicção reinicia o treinamento do zero — potencialmente custando mais que pay-as-you-go
- **Jobs são muito curtos** (menos de 1 hora): O overhead de checkpoint/resume supera a economia
- **Você está rodando inferência em produção**: Endpoints de produção precisam de garantias de disponibilidade que Spot não pode oferecer

### Implementando Checkpoint-and-Resume

O padrão é direto:

1. **Salve checkpoints no Azure Blob Storage ou Azure Files** — não no SSD local (que é perdido na evicção)
2. **Defina a frequência de checkpoint** com base no custo do trabalho perdido. Se o treinamento custa $50/hora, faça checkpoint a cada 15 minutos para limitar o retrabalho a $12,50 por evicção
3. **Construa seu script de inicialização** para verificar checkpoints existentes e retomar se encontrar
4. **Use Azure VM Scale Sets com Spot** para substituir automaticamente VMs despejadas

⚠️ **Cuidado em Produção**: Spot VMs podem ser despejadas com apenas 30 segundos de aviso. Seu checkpoint precisa gravar em armazenamento durável, não em disco local. Se seu checkpoint leva 5 minutos para gravar 20 GB de estado do modelo, você vai perdê-lo na evicção. Ou faça checkpoint com mais frequência e estado menor, ou use armazenamento mais rápido (Premium SSD ou Azure NetApp Files como camada intermediária antes do Blob).

### Exemplo de Economia com Spot

| Cenário | Pay-as-you-go | Spot (70% de desconto) | Economia |
|---|---|---|---|
| 8× A100 treinamento, 72 horas | $1.958 | $587 | $1.371 |
| 8× H100 treinamento, 72 horas | $7.056 | $2.117 | $4.939 |
| 4× T4 teste de inferência, 40 horas | $85 | $25 | $60 |

Mesmo contabilizando evicções ocasionais e retrabalho, Spot VMs tipicamente entregam 50–80% de economia líquida em cargas de treinamento tolerantes a falhas.

---

## Estratégias de Dimensionamento Correto

A GPU mais cara é aquela que não está fazendo nada — ou fazendo trabalho que uma GPU mais barata faria igualmente bem. Dimensionar corretamente cargas de trabalho de IA exige combinar a GPU com a tarefa, não usar o hardware mais poderoso disponível por padrão.

### Não Use H100s Quando T4s Resolvem

Este é o erro de custo mais comum em infraestrutura de IA. Uma equipe solicita H100s "porque queremos o melhor desempenho", mas a carga de trabalho real é rodar inferência em um modelo de 7B parâmetros que cabe confortavelmente nos 16 GB de memória de uma T4. A H100 é 185× mais cara por hora do que uma única T4. A menos que estejam treinando um modelo de fronteira ou precisem das capacidades específicas da H100 (FP8 Tensor Cores, maior largura de banda de memória), estão queimando dinheiro.

**Diretrizes gerais de dimensionamento:**

| Carga de Trabalho | SKU Inicial Recomendado | Por Quê |
|---|---|---|
| Inferência (modelos ≤13B) | NC-series T4 | 16 GB de memória, custo-benefício |
| Inferência (modelos 13B–70B) | NC-series A100 | 80 GB de memória, bom throughput |
| Fine-tuning (modelos ≤13B) | NC-series A100 (1–2 GPUs) | Memória suficiente com LoRA/QLoRA |
| Fine-tuning (modelos 70B+) | ND-series A100 (8 GPUs) | Necessita multi-GPU + NVLink |
| Pré-treinamento | ND-series H100 | Throughput máximo, NVLink + InfiniBand |

### Benchmarking de Utilização de GPU

Antes de escalar para cima, meça o que você está realmente usando. Execute `nvidia-smi` ou use as métricas de GPU do Azure Monitor para verificar:

- **Utilização de Computação da GPU (%)**: Se consistentemente abaixo de 30%, a GPU está superdimensionada para a carga de trabalho ou o pipeline de dados é o gargalo
- **Utilização de Memória da GPU (%)**: Se abaixo de 50%, uma GPU menor pode funcionar. Se acima de 90%, você pode precisar de mais memória ou habilitar gradient checkpointing
- **Memória de GPU Usada (GB)**: Compare com a memória total da GPU para entender a folga

**Infra ↔ IA — Tradução**: Dimensionar GPUs corretamente é exatamente como dimensionar VMs em infraestrutura tradicional. Você não rodaria um site estático em uma VM de 64 cores. Mesmo princípio — mas o custo de errar é 100× maior porque VMs com GPU são 100× mais caras.

### Políticas de Desligamento Automático para Dev/Test

Toda VM com GPU provisionada para desenvolvimento, experimentação ou teste deve ter uma **política de desligamento automático**. O Azure suporta isso nativamente através de dois mecanismos:

- **Auto-shutdown do Azure DevTest Labs**: Defina um horário de desligamento diário em VMs individuais
- **Runbooks do Azure Automation**: Agende o desligamento por resource groups ou por tag
- **Azure Policy**: Exija que todas as VMs com GPU em assinaturas de dev/test tenham auto-shutdown habilitado

💡 **Dica**: Defina o horário padrão de auto-shutdown para 19:00 no horário local para todas as VMs com GPU de dev/test. Engenheiros que precisam da VM rodando à noite podem estender manualmente — mas o padrão deve ser "desligado". Uma única ND96isr_H100_v5 deixada ligada da sexta à noite até segunda de manhã custa aproximadamente $4.700. O auto-shutdown elimina isso completamente.

### Reduzindo Recursos Após Experimentos

Estabeleça um processo — não apenas uma esperança — para descomissionar recursos de experimentos:

1. **Tagueie todo recurso de GPU** com `experiment-name`, `owner` e `expected-end-date`
2. **Execute um relatório semanal** listando VMs com GPU mais antigas que a data de término esperada
3. **Notifique automaticamente os responsáveis** 48 horas antes de desalocar
4. **Desaloque** se não houver resposta — os dados estão em armazenamento persistente, a VM pode ser recriada

---

## Otimização de Custos do Azure OpenAI

A precificação do Azure OpenAI se divide em dois modelos: **Standard (pay-per-token)** e **Provisioned Throughput Units (PTU)**. Escolher o errado — ou não escolher — é uma das fontes mais comuns de gastos inesperados com IA.

### Standard (Pay-per-Token)

O deployment Standard cobra por 1.000 tokens consumidos. É simples, não exige compromisso e escala a zero quando não utilizado. É a escolha certa para:

- Aplicações em desenvolvimento ou produção inicial
- Cargas de trabalho com tráfego imprevisível ou variável
- Casos de uso de baixo volume (menos de algumas centenas de milhares de tokens por dia)

O risco é que os custos escalam linearmente com o uso. Se sua aplicação viralizar ou uma equipe upstream começar a enviar volumes maiores, sua fatura cresce proporcionalmente sem teto.

### Provisioned Throughput Units (PTU)

Deployments com PTU reservam capacidade dedicada de modelo, medida em Provisioned Throughput Units. Você paga uma taxa fixa por hora ou mensal independentemente de quantos tokens consumir. O throughput por PTU varia por modelo, versão e região, então você deve sempre usar a [calculadora de capacidade do Azure OpenAI](https://oai.azure.com/portal/calculator) para estimar os requisitos de PTU para sua carga de trabalho específica.

PTU faz sentido quando:

- Você tem **tráfego sustentado e previsível** com alta utilização
- Você precisa de **latência garantida** que deployments compartilhados (standard) não podem oferecer
- Seu volume de tokens é alto o suficiente para que o **custo por token sob PTU seja menor** que o preço standard

### Quando o PTU Se Paga

O ponto de equilíbrio depende do seu modelo, região e padrão de tráfego, mas como diretriz geral: se seu deployment standard está consistentemente utilizado a **60–70% ou acima** do que uma alocação de PTU proporcionaria, o PTU tipicamente se torna mais barato. Abaixo dessa utilização, você está pagando por capacidade reservada que não está usando.

### Matriz de Decisão: Standard vs PTU

| Fator | Standard (Pay-per-Token) | Provisioned Throughput (PTU) |
|---|---|---|
| **Modelo de precificação** | Por 1K tokens consumidos | Taxa fixa por hora/mês |
| **Compromisso** | Nenhum | Mensal ou anual |
| **Ideal para** | Tráfego variável/imprevisível | Tráfego estável e de alto volume |
| **Latência** | Capacidade compartilhada (variável) | Capacidade dedicada (consistente) |
| **Custo em baixo volume** | Menor | Maior (pagando por capacidade ociosa) |
| **Custo em alto volume** | Maior (escala linear) | Menor (amortizado entre tokens) |
| **Escala a zero** | Sim | Não (compromisso mínimo de PTU) |

> **Nota**: Preços de PTU, proporções de throughput por unidade e compromissos mínimos variam por modelo, versão e região. Sempre use a calculadora de capacidade do Azure OpenAI para dimensionamento preciso.

### Estratégias de Otimização de Tokens

Independentemente de usar Standard ou PTU, reduzir o consumo de tokens reduz diretamente o custo:

**Cache de prompts**: O Azure OpenAI suporta cache automático de prompts para prefixos repetidos. Se seu system prompt tem 2.000 tokens e é idêntico em todas as requisições, tokens em cache são cobrados com tarifa reduzida. Estruture seus prompts com a parte estática primeiro.

**System prompts mais curtos**: Um system prompt de 3.000 tokens que poderia ter 800 desperdiça 2.200 tokens por requisição. A 10.000 requisições por dia com GPT-4o, isso são 22 milhões de tokens de entrada desperdiçados — aproximadamente $55/dia ou $1.650/mês em gastos desnecessários.

**Limites de tamanho de resposta**: Use o parâmetro `max_tokens` para limitar o tamanho da resposta. Se sua aplicação precisa apenas de respostas de 200 palavras, não permita respostas de 2.000 tokens. Isso é tanto uma otimização de custo quanto de latência.

**Roteamento multi-modelo**: Nem toda requisição precisa do seu modelo mais capaz (e mais caro). Roteie consultas simples de classificação, extração ou FAQ para o GPT-4o-mini e reserve o GPT-4o para raciocínio complexo, análise em múltiplas etapas ou tarefas onde a qualidade piora mensuravelmente com o modelo menor. Uma camada de roteamento bem implementada pode reduzir custos de inferência em 50–80%.

💡 **Dica**: Monte um harness de avaliação simples que execute as mesmas 200 consultas representativas no GPT-4o e no GPT-4o-mini, e peça a um especialista do domínio para pontuar as saídas. Se o GPT-4o-mini pontuar dentro de 5% em 70%+ das consultas, você identificou uma enorme oportunidade de economia com impacto mínimo na qualidade.

---

## Práticas de FinOps para IA

FinOps — a prática de trazer responsabilidade financeira aos gastos com nuvem — é crítica para cargas de trabalho de IA porque o custo de errar é muito maior. Uma equipe que superdimensiona VMs de CPU pode desperdiçar centenas de dólares. Uma equipe que superdimensiona VMs com GPU desperdiça dezenas de milhares.

### Atribuição de Custos: Tags

Todo recurso de IA deve ser tageado com no mínimo:

| Tag | Finalidade | Exemplo |
|---|---|---|
| `cost-center` | Atribuição financeira | `CC-4521-ML` |
| `project` | Qual iniciativa | `customer-churn-model` |
| `team` | Quem é responsável | `data-science-west` |
| `environment` | Dev, test, prod | `dev` |
| `expected-end-date` | Quando revisar/excluir | `2025-03-15` |

Use **Azure Policy** para exigir que SKUs de VMs com GPU (NC*, ND*) não possam ser criadas sem essas tags. Este é um controle de governança inegociável.

⚠️ **Cuidado em Produção**: Tags só são úteis se forem exigidas no momento do provisionamento. Se você permitir recursos sem tags e tentar tagear retroativamente, estará sempre correndo atrás. Implemente uma Azure Policy com efeito `deny` que bloqueie a criação de VMs com GPU sem as tags obrigatórias. As equipes vão resistir — mantenha a posição.

### Orçamentos e Alertas

O Azure Cost Management suporta orçamentos com alertas acionáveis. Para cargas de trabalho de IA, configure uma estratégia de alertas em três níveis:

| Limite do Alerta | Ação | Finalidade |
|---|---|---|
| 50% do orçamento mensal | Notificação por e-mail para líderes da equipe | Visibilidade antecipada |
| 75% do orçamento mensal | E-mail + notificação no Teams para equipe + financeiro | Escalação |
| 90% do orçamento mensal | E-mail + ação automatizada (ex.: parar VMs de não-produção) | Prevenção |

Crie orçamentos separados para computação com GPU, Azure OpenAI e armazenamento — não junte tudo em um orçamento só onde um pico de gasto com GPU se esconde atrás da folga no armazenamento.

### Chargeback e Showback

Para organizações com clusters de GPU compartilhados, decida entre:

- **Showback**: As equipes veem o que consomem mas não são cobradas diretamente. Menor atrito, mas incentivo mais fraco para otimizar
- **Chargeback**: As equipes são cobradas pelo consumo do próprio orçamento. Incentivo mais forte, mas exige medição precisa e pode criar incentivos perversos (equipes acumulam capacidade reservada)

A maioria das organizações começa com showback e migra para chargeback conforme a prática de IA amadurece e as ferramentas de atribuição de custos se tornam confiáveis.

### Governança de Cotas de GPU

As cotas de GPU do Azure são sua primeira linha de defesa contra provisionamento descontrolado. Por padrão, a maioria das assinaturas tem cota zero para VMs da série ND — você precisa solicitar explicitamente. Use isso a seu favor:

1. **Centralize as solicitações de cota** através de uma equipe de plataforma ou FinOps
2. **Aprove cotas por projeto**, não por indivíduo
3. **Defina cotas no nível da assinatura** que limitem o número máximo de VMs com GPU que qualquer equipe individual pode provisionar
4. **Revise alocações de cota trimestralmente** e recupere cotas não utilizadas

### Revisões Regulares de Custos

Agende uma **revisão mensal de custos de IA** que reúna stakeholders de infraestrutura, data science e financeiro. Revise:

- Gasto total com GPU vs orçamento
- Taxas de utilização de GPU em todas as VMs
- Tendências de consumo de tokens do Azure OpenAI
- Top 5 drivers de custo e oportunidades de otimização
- Recursos mais antigos que sua data de término esperada

Essa reunião é onde você pega o problema dos "$33.000 em GPU ociosa" antes que ele se torne o problema do "e-mail de $127.000 do financeiro".

---

## Atribuição de Custos em Clusters Compartilhados (AKS)

Quando múltiplas equipes compartilham um cluster AKS com node pools de GPU, a atribuição de custos se torna mais complexa que simples tags em VMs. Você precisa de visibilidade no nível de namespace sobre quem está consumindo o quê.

### Rastreamento de Custos por Namespace

Em um cluster AKS compartilhado, cada equipe ou projeto deve ter seu próprio namespace Kubernetes. Isso oferece uma fronteira natural para atribuição de custos:

- **Azure Cost Analysis** pode decompor custos do AKS por namespace quando o add-on de análise de custos do AKS está habilitado
- **OpenCost** (projeto CNCF) fornece alocação de custos em tempo real por namespace, pod e label
- **Kubecost** oferece funcionalidade similar com recomendações adicionais de otimização

### Resource Quotas por Namespace

**ResourceQuotas** do Kubernetes impedem que qualquer namespace individual consuma mais do que sua parcela dos recursos do cluster. Para cargas de trabalho com GPU, isso é essencial:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
  namespace: team-nlp
spec:
  hard:
    requests.nvidia.com/gpu: "4"
    limits.nvidia.com/gpu: "4"
```

Isso limita o namespace `team-nlp` a 4 GPUs, independentemente de quantos pods eles tentem agendar. Sem isso, um job de treinamento descontrolado de uma única equipe poderia consumir todas as GPUs do cluster.

### Autoscaler Proporcional do Cluster

Use o **cluster autoscaler** para escalar node pools de GPU a zero quando não há pods de GPU pendentes. Isso garante que você não pague por nós de GPU ociosos fora do horário. Configure o autoscaler com:

- **Atraso para redução de escala**: Quanto tempo um nó deve ficar ocioso antes de ser removido (ex.: 10 minutos para clusters de dev, 30 minutos para produção)
- **Limite de utilização para redução**: Remover nós abaixo de um limite de utilização de GPU
- **Contagem máxima de nós**: Limite rígido de quantos nós de GPU o autoscaler pode provisionar

### Comparação de Ferramentas

| Ferramenta | Custo | Atribuição por Namespace | Suporte a GPU | Recomendações de Otimização |
|---|---|---|---|---|
| Azure Cost Analysis | Incluído | Sim (com add-on) | Sim | Básicas |
| OpenCost | Gratuito (open-source) | Sim | Sim | Limitadas |
| Kubecost | Tier gratuito + pago | Sim | Sim | Detalhadas |

💡 **Dica**: Habilite o add-on de análise de custos do AKS (`az aks update --enable-cost-analysis`) antes de precisar dele. Ele requer tempo para acumular dados antes de se tornar útil. Se você habilitá-lo após um incidente de custos, não terá dados históricos para analisar.

---

## Checklist do Capítulo

Antes de seguir em frente, confirme que você tem estas práticas de engenharia de custos implementadas:

- **Modelo de custos documentado** tanto para cargas de treinamento (GPU-hours) quanto de inferência (tokens)
- **Política de tags exigida** via Azure Policy — todos os recursos de GPU tageados com cost-center, project, team e environment
- **Alertas de orçamento configurados** nos limites de 50%, 75% e 90% com ações escalonadas
- **Auto-shutdown habilitado** em todas as VMs com GPU de dev/test
- **Spot VMs avaliadas** para cargas de treinamento tolerantes a falhas com checkpointing implementado
- **Dimensionamento correto validado** — utilização de GPU benchmarkada antes de provisionar SKUs maiores
- **Modelo de precificação do Azure OpenAI selecionado** — Standard vs PTU avaliado com base em dados de utilização
- **Otimização de tokens implementada** — cache de prompts, redução de system prompts, limites de tamanho de resposta, roteamento multi-modelo
- **Governança de cotas de GPU** centralizada com workflow de aprovação
- **Reunião mensal de revisão de custos** agendada com stakeholders de infra, data science e financeiro
- **Rastreamento de custos por namespace** habilitado para clusters AKS compartilhados
- **Relatório semanal de recursos ociosos** em execução para detectar experimentos esquecidos

---

## Próximos Passos

Os custos estão sob controle. Mas conforme sua plataforma de IA cresce de uma equipe para dez, você precisa de padrões operacionais que escalem: gerenciamento de frota, multi-tenancy, agendamento e design de SLAs. O Capítulo 10 leva você de rodar projetos de IA para rodar uma plataforma de IA.