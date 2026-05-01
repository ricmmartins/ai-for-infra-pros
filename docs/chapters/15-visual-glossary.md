# Capítulo 15 — Glossário Visual: Guia de Tradução Infra ↔ IA

> "Você já fala infraestrutura fluentemente. IA não é um idioma estrangeiro — é um dialeto."

## Introdução

Este capítulo é o seu cartão de referência rápida. Cada termo de IA que você encontrará em produção está mapeado para um conceito de infraestrutura que você já conhece — com uma definição de uma linha, uma analogia prática e o contexto de quando esse termo realmente vai importar no seu dia a dia. Seja revisando um diagrama de arquitetura, participando de uma reunião de planejamento com cientistas de dados ou resolvendo problemas em um cluster de GPUs às 2 da manhã, este é o capítulo que você vai manter sempre à mão.

O glossário está organizado em seis categorias — Conceitos Fundamentais de IA, Dados e Armazenamento, Computação e Hardware, Operações de Modelo, Deploy e Serving, e Conceitos Avançados — com os termos listados em ordem alfabética dentro de cada seção para consulta rápida. Cada entrada segue o mesmo formato: o termo de IA, uma analogia de infra entre parênteses, uma definição concisa e uma nota de "quando você vai encontrar isso". No final, você encontrará um cartão de referência resumido com os 20 termos mais essenciais em uma única página. Destaque, salve nos favoritos, fixe no seu monitor — esta é a sua Pedra de Roseta.

---

## Categoria 1: Conceitos Fundamentais de IA

| Termo de IA | Analogia de Infra | Definição | Quando Você Vai Encontrar |
|-------------|-------------------|-----------|---------------------------|
| **Inteligência Artificial** | Disciplina guarda-chuva de automação | O campo amplo que abrange qualquer sistema que executa tarefas que normalmente exigem inteligência humana — de automação baseada em regras a modelos generativos. | Ao definir o escopo de projetos de IA e entender onde ML, deep learning e LLMs se encaixam dentro da disciplina maior. |
| **Batch Size** | Tamanho do bloco de dados | O número de amostras de treinamento processadas antes de o modelo atualizar seus pesos. Lotes maiores usam mais memória de GPU, mas treinam de forma mais eficiente. | Ao ajustar jobs de treinamento e solucionar erros de GPU out-of-memory (OOM) — reduzir o batch size costuma ser a primeira correção. |
| **Deep Learning** | ML multicamadas (como load balancers aninhados) | Um subconjunto de machine learning que usa redes neurais com muitas camadas para aprender padrões complexos a partir de dados brutos (imagens, texto, áudio). | Quando workloads exigem GPUs em vez de CPUs — deep learning é quase sempre o motivo dos pedidos de infraestrutura com GPU. |
| **Epoch** | Ciclo completo de backup | Uma passada completa por todo o dataset de treinamento. Modelos geralmente treinam por dezenas a centenas de epochs. | Ao estimar a duração e o custo de um job de treinamento — mais epochs significam jobs mais longos e contas de computação mais altas. |
| **Fine-tuning** | Customização de configuração | Adaptar um modelo pré-treinado ao seu domínio específico, treinando-o com seus próprios dados e ajustando seus pesos para tarefas especializadas. | Quando equipes precisam de um modelo que entenda terminologia específica da empresa, processos internos ou conhecimento de domínio. |
| **Foundation Model** | Imagem base | Um modelo grande e pré-treinado (como GPT-4, LLaMA ou Mistral) projetado para ser adaptado a diversas tarefas downstream, assim como uma imagem golden de VM usada como ponto de partida. | Ao selecionar qual modelo base usar para deploy ou fine-tuning — este é o artefato inicial na maioria dos projetos de IA. |
| **Inference** | Endpoint de API | Executar um modelo treinado com novos dados para gerar previsões ou respostas. Tempo real, sensível a latência, e a fase operacional da IA. | Toda vez que um usuário ou sistema chama um serviço de IA — inference é o workload de produção que você vai monitorar e escalar. |
| **Large Language Model (LLM)** | Serviço de API especializado (texto entra, texto sai) | Um foundation model treinado especificamente em enormes corpora de texto para entender e gerar linguagem humana. GPT-4, Claude e LLaMA são exemplos. | Ao fazer deploy de endpoints do Azure OpenAI, dimensionar cotas de tokens e planejar capacidade para workloads de chat ou geração de texto. |
| **Machine Learning** | Reconhecimento estatístico de padrões | Um subconjunto de IA onde sistemas aprendem padrões a partir de dados em vez de seguir regras explícitas — como regras de auto-scaling que aprendem limites ideais a partir de métricas históricas. | Ao avaliar se um workload precisa de computação com GPU, armazenamento especializado ou infraestrutura de pipeline de ML. |
| **Model** | Binário compilado | O artefato treinado — a saída de um job de treinamento, empacotado e implantado para servir previsões. Contém os parâmetros aprendidos que definem seu comportamento. | Ao gerenciar deploys, versionar artefatos ou dimensionar armazenamento — modelos variam de megabytes a centenas de gigabytes. |
| **Neural Network** | Pipeline de CI/CD multi-estágio | Uma arquitetura de processamento onde os dados fluem por camadas interconectadas de nós, cada uma transformando a entrada progressivamente — como um pipeline com estágios de build, teste e deploy. | Ao entender por que workloads de IA precisam de computação paralela — cada camada executa operações matriciais que GPUs aceleram. |
| **Parameters** | Valores de configuração | Os valores internos aprendidos durante o treinamento que definem como um modelo processa entradas e gera saídas. O GPT-4 tem mais de um trilhão de parâmetros. | Ao dimensionar infraestrutura — mais parâmetros significam mais memória, mais computação e mais armazenamento para o modelo. |
| **Training** | Batch job | O processo de ensinar um modelo alimentando-o com dados e ajustando seus parâmetros. De longa duração, intensivo em GPU, lê o dataset inteiro repetidamente. | Ao provisionar clusters de GPU, estimar duração de jobs e planejar picos de computação em grande escala. |
| **Transfer Learning** | Reutilização de templates | Usar um modelo pré-treinado em uma tarefa como ponto de partida para uma tarefa diferente, preservando o conhecimento adquirido e reduzindo o tempo de treinamento e a necessidade de dados. | Quando equipes querem obter resultados mais rápido e com menor custo, partindo de um foundation model em vez de treinar do zero. |
| **Weights** | O mesmo que parâmetros | Os valores numéricos reais armazenados dentro de um modelo. "Weights" e "parameters" são frequentemente usados de forma intercambiável — são os números que fazem o modelo funcionar. | Ao gerenciar arquivos de modelo em disco, transferir checkpoints ou calcular requisitos de armazenamento e memória. |

---

## Categoria 2: Dados e Armazenamento

| Termo de IA | Analogia de Infra | Definição | Quando Você Vai Encontrar |
|-------------|-------------------|-----------|---------------------------|
| **Data Augmentation** | Geração de dados sintéticos | Criar cópias modificadas de dados de treinamento existentes (rotações, ruído, paráfrases) para aumentar o tamanho do dataset e melhorar a robustez do modelo. | Quando cientistas de dados solicitam armazenamento adicional para datasets expandidos ou quando pipelines de treinamento incluem estágios de pré-processamento. |
| **Data Drift** | Mudança de schema / desvio na distribuição de entrada | Quando as propriedades estatísticas dos dados de entrada em produção divergem dos dados com que o modelo foi treinado, causando degradação de acurácia ao longo do tempo. | Quando o desempenho do modelo degrada em produção sem mudanças no código — data drift é o assassino silencioso da acurácia em ML. |
| **Dataset** | Fonte de dados / volume de armazenamento | Os dados estruturados ou não estruturados usados para treinar, validar ou testar um modelo. Podem variar de gigabytes a petabytes. | Ao provisionar armazenamento, planejar pipelines de dados e gerenciar controles de acesso para dados de treinamento. |
| **Embedding** | Hash / chave de índice | Uma representação vetorial numérica de texto, imagens ou outros dados que captura significado semântico, permitindo busca e comparação por similaridade. | Ao fazer deploy de arquiteturas RAG, construir sistemas de busca ou dimensionar bancos de dados vetoriais para recuperação semântica. |
| **Feature** | Coluna em um banco de dados / variável de entrada | Uma propriedade mensurável individual dos dados usada como entrada para um modelo — como utilização de CPU, contagem de requisições ou idade do usuário. | Quando engenheiros de dados constroem pipelines de dados e você provisiona a computação e o armazenamento para jobs de extração de features. |
| **Feature Store** | Camada de cache para entradas de ML | Um repositório centralizado que armazena, gerencia e serve features pré-calculadas tanto para treinamento quanto para inference, garantindo consistência. | Ao arquitetar plataformas de ML que precisam de acesso de baixa latência a features processadas no momento da inference. |
| **Tokenization** | Serialização | O processo de quebrar texto em unidades menores (tokens) que um modelo pode processar — similar a como a serialização converte objetos em formatos transmissíveis. | Ao calcular custos (você paga por token), estimar uso da context window e otimizar o tamanho do prompt. |
| **Vector Database** | Índice de busca | Um banco de dados especializado que armazena embeddings e os recupera usando busca por similaridade (vizinho mais próximo) em vez de consultas por correspondência exata. | Ao fazer deploy de soluções RAG, construir busca semântica ou provisionar o Azure AI Search com capacidades vetoriais. |

---

## Categoria 3: Computação e Hardware

| Termo de IA | Analogia de Infra | Definição | Quando Você Vai Encontrar |
|-------------|-------------------|-----------|---------------------------|
| **CUDA** | Conjunto de instruções / SDK da GPU | A plataforma de computação paralela e API da NVIDIA que permite aos desenvolvedores escrever código executado em GPUs. A base da maioria da computação de IA. | Ao instalar drivers de GPU, configurar containers para workloads com GPU ou solucionar erros de "CUDA out of memory". |
| **GPU** | Coprocessador | Um processador projetado para computação paralela massiva, descarregando operações matriciais da CPU da mesma forma que uma NIC descarrega o processamento de rede. Essencial para treinamento e inference. | Em todos os lugares na infraestrutura de IA — desde provisionar SKUs de VM (séries NC, ND) até monitorar utilização e gerenciar custos. |
| **HBM (High Bandwidth Memory)** | RAM da GPU | Memória especializada de alta velocidade empilhada diretamente no die da GPU, fornecendo a largura de banda necessária para operações de modelos grandes. A A100 tem 80 GB de HBM2e. | Ao selecionar SKUs de GPU — a capacidade de HBM determina o tamanho máximo de modelo que uma única GPU consegue manter em memória. |
| **InfiniBand** | Rede de alta velocidade nó a nó | Interconexão de ultra-baixa latência e alta largura de banda usada para treinamento distribuído entre múltiplos nós, muito mais rápida que Ethernet padrão. | Ao provisionar clusters multi-nó de GPU (VMs da série ND) para jobs de treinamento em larga escala que abrangem múltiplas máquinas. |
| **NCCL** | Biblioteca de comunicação multi-GPU | A Biblioteca de Comunicações Coletivas da NVIDIA — gerencia a troca de dados entre GPUs durante treinamento distribuído (all-reduce, broadcast, etc.). | Ao solucionar falhas de treinamento distribuído, timeouts de rede entre GPUs ou problemas de escalabilidade multi-nó. |
| **NVLink** | Interconexão GPU a GPU | Um link de alta velocidade conectando GPUs dentro de um único nó, fornecendo ~10× a largura de banda do PCIe para transferência de dados entre GPUs. | Ao dimensionar VMs multi-GPU — GPUs conectadas por NVLink podem compartilhar dados rápido o suficiente para atuar como um pool de memória unificado. |
| **Tensor Core** | Unidade especializada em operações matriciais | Unidades de hardware dedicadas dentro das GPUs NVIDIA otimizadas para operações de multiplicação e acumulação de matrizes que dominam os workloads de IA. | Ao avaliar gerações de GPU — os Tensor Cores são o motivo pelo qual uma A100 é dramaticamente mais rápida para IA do que uma GPU gamer com specs similares. |
| **TPU (Tensor Processing Unit)** | Chip de IA customizado do Google | ASIC construído pelo Google especificamente para acelerar workloads de machine learning, disponível através do Google Cloud. | Ao avaliar estratégias multi-cloud de IA ou comparar a infraestrutura de IA do Google Cloud com as ofertas de GPU do Azure. |

---

## Categoria 4: Operações de Modelo

| Termo de IA | Analogia de Infra | Definição | Quando Você Vai Encontrar |
|-------------|-------------------|-----------|---------------------------|
| **Backpropagation** | Loop de feedback | O algoritmo que calcula como cada peso contribuiu para o erro do modelo, propagando sinais de erro de volta pela rede para atualizar os pesos. | Ao entender por que o treinamento é computacionalmente intensivo — backpropagation requer uma passada reversa completa por todas as camadas. |
| **Checkpoint** | Snapshot / backup | Uma cópia salva do estado do modelo durante o treinamento — pesos, estado do optimizer e progresso do treinamento — permitindo retomada após falhas. | Ao gerenciar armazenamento para jobs de treinamento (checkpoints podem ter dezenas de GB cada) e projetar pipelines de treinamento tolerantes a falhas. |
| **Gradient** | Sinal de erro | Um valor matemático que indica a direção e a magnitude dos ajustes de peso necessários para reduzir o erro do modelo. | Ao solucionar instabilidade no treinamento — "exploding gradients" e "vanishing gradients" são modos de falha comuns. |
| **Hyperparameter** | Valor de configuração ajustável | Um valor definido antes do início do treinamento que controla o próprio processo de treinamento — learning rate, batch size, número de camadas — como contagem de threads ou tamanho do pool de conexões. | Quando cientistas de dados solicitam múltiplas execuções de treinamento com configurações diferentes — cada combinação é um job de computação separado. |
| **Loss Function** | Métrica de erro | Uma função matemática que mede o quão distantes as previsões do modelo estão das respostas corretas. O treinamento busca minimizar esse valor. | Ao monitorar o progresso do treinamento — a curva de loss deve ter tendência de queda. Um loss estável ou subindo indica problemas. |
| **MLOps** | DevOps para modelos | A disciplina de aplicar práticas de DevOps — CI/CD, versionamento, monitoramento, automação — ao ciclo de vida de machine learning. | Ao construir plataformas de ML, projetar pipelines de deploy de modelos e implementar monitoramento e governança de modelos. |
| **Model Registry** | Container registry para modelos | Um repositório versionado para armazenar, catalogar e gerenciar artefatos de modelos treinados — como o Azure Container Registry, mas para modelos. | Ao implementar pipelines de MLOps que precisam versionar, promover e fazer rollback de deploys de modelos entre ambientes. |
| **Optimizer** | Controlador de learning rate | O algoritmo que determina como os pesos do modelo são atualizados durante o treinamento (Adam, SGD, AdamW). Controla a velocidade e a estabilidade do aprendizado. | Ao ajustar a performance do treinamento — a escolha do optimizer e a learning rate são os hyperparameters de maior impacto. |

---

## Categoria 5: Deploy e Serving

| Termo de IA | Analogia de Infra | Definição | Quando Você Vai Encontrar |
|-------------|-------------------|-----------|---------------------------|
| **Completion** | Corpo da resposta da API | A saída gerada pelo modelo em resposta a um prompt. Em APIs de chat, é a resposta do assistente retornada ao chamador. | Ao parsear respostas de API, calcular custos de tokens de saída e monitorar qualidade e latência das respostas. |
| **Context Window** | Tamanho máximo do payload da requisição | O número máximo de tokens que um modelo pode processar em uma única requisição (prompt + completion combinados). O GPT-4o suporta 128K tokens. | Ao projetar prompts e sistemas RAG — exceder a context window trunca a entrada ou causa erros. |
| **Inference Endpoint** | Endpoint de API servindo previsões | Um modelo implantado exposto como uma API HTTP que aceita entradas e retorna previsões ou texto gerado em tempo real. | Ao provisionar, escalar e monitorar o serviço de IA voltado para produção — esta é sua principal superfície operacional. |
| **Prompt** | Corpo da requisição da API | A entrada de texto enviada a um modelo para guiar sua saída — instruções, contexto, exemplos e a pergunta ou tarefa propriamente dita. | Toda interação com um LLM — o design do prompt impacta diretamente a qualidade da saída, o consumo de tokens e o custo. |
| **Provisioned Throughput (PTU)** | Capacidade reservada (como instâncias reservadas de VM) | Capacidade computacional pré-alocada e garantida para modelos do Azure OpenAI, fornecendo latência e throughput consistentes independente da carga da plataforma. | Quando workloads precisam de performance previsível — PTU elimina throttling a um custo fixo, como instâncias reservadas para IA. |
| **RAG (Retrieval-Augmented Generation)** | Enriquecimento dinâmico do prompt com dados externos | Um padrão que recupera documentos relevantes de uma base de conhecimento e os injeta no prompt antes de o modelo gerar uma resposta. | Ao construir soluções empresariais de IA que precisam responder perguntas usando dados específicos e atualizados da empresa. |
| **Requests Per Minute (RPM)** | Limite de taxa de requisições | O número máximo de chamadas de API permitidas por minuto para um deploy de modelo, aplicado no nível do endpoint. | Ao planejar capacidade e solucionar erros HTTP 429 — os limites de RPM são independentes das cotas de tokens. |
| **Tokens Per Minute (TPM)** | Cota de largura de banda / throughput | O número máximo de tokens (entrada + saída) processados por minuto para um deploy de modelo. A principal métrica de throughput para endpoints de LLM. | Ao dimensionar deploys, estimar custos e diagnosticar throttling — TPM é a restrição de capacidade mais comum. |

---

## Categoria 6: Conceitos Avançados

| Termo de IA | Analogia de Infra | Definição | Quando Você Vai Encontrar |
|-------------|-------------------|-----------|---------------------------|
| **Data Parallelism** | Sharding de dados entre GPUs | Uma estratégia de treinamento distribuído onde o dataset é dividido entre GPUs, cada uma processando um batch diferente com uma cópia completa do modelo. | Ao escalar treinamento para múltiplas GPUs — data parallelism é a abordagem de treinamento distribuído padrão e mais simples. |
| **LoRA (Low-Rank Adaptation)** | Fine-tuning leve | Uma técnica que faz fine-tuning de uma pequena camada adaptadora (~1-2% dos parâmetros) em vez do modelo completo, reduzindo drasticamente os requisitos de computação e memória. | Quando equipes querem customizar um foundation model sem o custo do fine-tuning completo — LoRA torna a customização acessível. |
| **Mixed Precision** | Otimização com tipos de dados variáveis | Treinar com uma combinação de tipos de dados FP32 e BF16/FP16 — usando menor precisão onde possível para reduzir uso de memória e aumentar throughput sem perder acurácia. | Ao otimizar jobs de treinamento para velocidade e custo — mixed precision pode quase dobrar o throughput em GPUs modernas. |
| **Model Parallelism** | Sharding do modelo entre GPUs | Dividir um único modelo entre múltiplas GPUs quando ele é grande demais para caber na memória de uma GPU, com cada GPU mantendo uma porção das camadas. | Ao fazer deploy de modelos muito grandes (70B+ parâmetros) que excedem a capacidade de HBM de uma única GPU. |
| **Pipeline Parallelism** | Linha de montagem entre GPUs | Uma abordagem de treinamento distribuído onde as camadas do modelo são distribuídas entre GPUs em sequência, com micro-batches fluindo como uma linha de montagem. | Ao treinar modelos muito grandes em muitas GPUs — pipeline parallelism reduz o requisito de memória por GPU. |
| **Prompt Injection** | SQL injection para IA | Um ataque onde entrada não confiável é elaborada para substituir ou manipular as instruções de sistema de um modelo, causando comportamento indesejado ou vazamento de dados. | Ao proteger endpoints de IA expostos a entrada de usuários — prompt injection é a preocupação de segurança nº 1 para aplicações LLM. |
| **Quantization** | Compressão | Reduzir a precisão do modelo (ex.: FP32 → INT8 ou INT4) para diminuir o tamanho do modelo e acelerar inference, trocando uma pequena perda de acurácia por ganhos significativos de eficiência. | Ao fazer deploy de modelos em produção com restrições de custo ou latência — quantization pode reduzir o uso de memória em 4× ou mais. |
| **ZeRO (Zero Redundancy Optimizer)** | Otimização de memória para treinamento distribuído | Uma família de técnicas que particiona estados do optimizer, gradients e parâmetros entre GPUs para eliminar uso redundante de memória durante treinamento distribuído. | Ao treinar modelos grandes que não cabem na memória da GPU mesmo com data parallelism — ZeRO é a solução padrão no DeepSpeed. |

---

## Cartão de Referência Rápida — Top 20 Termos

*Fixe esta página. Tire um screenshot. Imprima.*

| # | Termo de IA | Tradução para Infra |
|---|-------------|---------------------|
| 1 | **Model** | Um binário compilado — a saída implantável do treinamento |
| 2 | **Training** | Um batch job de longa duração que produz um modelo |
| 3 | **Inference** | Uma chamada de API — requisição/resposta em tempo real contra um modelo implantado |
| 4 | **GPU** | Um coprocessador que descarrega operações matriciais, como uma NIC descarrega rede |
| 5 | **LLM** | Um serviço de API texto-entra/texto-sai construído sobre um modelo treinado massivo |
| 6 | **Prompt** | O corpo da requisição da API — instruções e contexto enviados ao modelo |
| 7 | **Completion** | O corpo da resposta da API — o que o modelo retorna |
| 8 | **Token** | A menor unidade de processamento — você paga por token assim como paga por byte transferido |
| 9 | **Context Window** | Tamanho máximo do payload da requisição — o limite do buffer de entrada do modelo |
| 10 | **Fine-tuning** | Customizar uma imagem base — adaptar um modelo pré-treinado com seus dados |
| 11 | **RAG** | Enriquecimento dinâmico do prompt — injetar dados recuperados antes da geração |
| 12 | **Embedding** | Uma hash/chave de índice — representação numérica para busca por similaridade |
| 13 | **Vector Database** | Um índice de busca otimizado para consultas de similaridade por vizinho mais próximo |
| 14 | **TPM** | Cota de largura de banda — tokens por minuto, o principal limite de throughput |
| 15 | **PTU** | Capacidade reservada — throughput garantido como instâncias reservadas de VM |
| 16 | **MLOps** | DevOps para modelos — CI/CD, versionamento, monitoramento para ML |
| 17 | **Checkpoint** | Um snapshot/backup — estado salvo do modelo para tolerância a falhas |
| 18 | **Parameters** | Valores de configuração — os números aprendidos que definem o comportamento do modelo |
| 19 | **Data Drift** | Mudança de schema — quando a entrada em produção diverge dos dados de treinamento |
| 20 | **Prompt Injection** | SQL injection para IA — entrada não confiável manipulando o comportamento do modelo |

---

## Como Usar Este Glossário

Este capítulo foi projetado para ser uma referência viva. Aqui estão três formas de aproveitá-lo ao máximo:

1. **Durante revisões de arquitetura** — Consulte termos desconhecidos antes de reuniões com equipes de ciência de dados. As analogias de infra dão a você modelos mentais instantâneos.
2. **Ao solucionar problemas** — Falhas de IA frequentemente mapeiam para problemas de infraestrutura que você já resolveu antes. "GPU OOM" é apenas um problema de pressão de memória. "Token limit exceeded" é um erro de tamanho de payload. A tradução ajuda você a fazer triagem mais rápido.
3. **Para planejamento de capacidade** — Termos como TPM, RPM, PTU, context window e batch size impactam diretamente as decisões de dimensionamento. Entender o que eles significam em termos de infra ajuda você a planejar com precisão.

> "De VMs a inference, de logs a tokens, de pipelines a redes neurais — você já tinha os modelos mentais. Agora você tem o vocabulário."
