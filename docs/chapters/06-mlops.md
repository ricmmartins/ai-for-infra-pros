# Capítulo 6 — Ciclo de Vida de Modelos e MLOps sob a Ótica de Infraestrutura

*"Coloca isso em produção."*

---

## O Modelo que Chegou sem Certidão de Nascimento

Um cientista de dados aparece na sua mesa — ou, mais realisticamente, manda uma mensagem no canal do seu time — com um link para uma pasta compartilhada. "Aqui está o modelo. É um checkpoint PyTorch de 15 GB. Precisamos dele em produção até sexta." Você abre a pasta e encontra um único arquivo: `model_final_v2_FIXED.pt`.

Você começa a fazer perguntas. Qual versão é essa? Com quais dados ele foi treinado? Qual é o plano de rollback se as predições saírem erradas? Quais são os SLAs de latência e throughput? Qual framework e versão de CUDA ele exige? As respostas são vagas, no melhor dos casos. "É a versão mais recente. Funciona na minha máquina. É só colocar atrás de uma API."

Você já viu esse filme antes — só com atores diferentes. Desenvolvedores costumavam te entregar um binário compilado e dizer "faz o deploy disso." Esse caos levou a indústria a criar container registries, pipelines de CI/CD, versionamento semântico e rollback automatizado. Modelos não são diferentes. Eles são artefatos — artefatos grandes, versionados e dependentes de ambiente — e merecem o mesmo gerenciamento de ciclo de vida que você passou anos construindo para deploys de aplicações. Este capítulo ensina como aplicar essa disciplina operacional duramente conquistada ao mundo do machine learning.

---

## Modelos São Artefatos — Trate-os Como Tal

Se você já fez pull de uma imagem de um container registry, tagueou um release no Git ou promoveu um build de staging para produção, você já entende os conceitos centrais do gerenciamento de ciclo de vida de modelos. O vocabulário muda, mas os padrões são quase idênticos.

**Tradução Infra ↔ IA**:

| Conceito de Infra | Equivalente em ML |
|---|---|
| Binário compilado / imagem de container | Checkpoint do modelo (arquivo de pesos) |
| Container registry (ACR, Docker Hub) | Model registry (Azure ML, MLflow) |
| Build de CI | Execução de treinamento |
| Pipeline de release de CD | Pipeline de deploy de modelo |
| Manifesto de build (Dockerfile) | Configuração de treinamento (hiperparâmetros, versão dos dados, versão do framework) |
| Assinatura de artefato | Proveniência e linhagem do modelo |
| Deploy blue/green | A/B testing com divisão de tráfego |

A sacada principal é esta: um arquivo de modelo sem metadados é como uma imagem de container sem tag. Você pode fazer o deploy, mas não consegue reproduzi-lo, auditá-lo ou fazer rollback com segurança. O gerenciamento de ciclo de vida de modelos existe para resolver três problemas que todo engenheiro de infraestrutura já conhece.

**Reprodutibilidade.** Se algo der errado em produção, você precisa recriar o modelo exato que está rodando — mesmos pesos, mesmo pré-processamento, mesma versão do framework. Sem linhagem rastreada, "retreinar o modelo" vira adivinhação.

**Conformidade.** Indústrias reguladas exigem trilhas de auditoria. Você precisa provar quais dados treinaram um modelo, quando ele foi implantado e quem aprovou. Isso não é diferente do gerenciamento de mudanças para infraestrutura — apenas aplicado a artefatos de modelo.

**Rollback.** Quando um novo modelo degrada a qualidade das predições ou viola SLAs de latência, você precisa reverter para a última versão estável em minutos, não horas. Isso exige artefatos versionados e pipelines de deploy automatizados — ferramentas que você já sabe construir.

---

## Model Registries

Um model registry é a fonte única de verdade para os modelos treinados da sua organização. Ele armazena artefatos de modelo junto com metadados — números de versão, métricas de treinamento, informações de linhagem e status de deploy. Pense nele como o seu container registry, mas construído especificamente para artefatos de ML.

### Azure Machine Learning Model Registry

O registry integrado do Azure ML oferece versionamento, tagging e rastreamento de linhagem integrados ao workspace mais amplo do Azure ML. Todo modelo registrado recebe um número de versão imutável, e você pode anexar tags e propriedades arbitrárias para filtragem organizacional.

```bash
# Registrar um modelo a partir de um arquivo local
az ml model create \
  --name sentiment-classifier \
  --version 3 \
  --path ./outputs/model.pt \
  --type custom_model \
  --tags task=sentiment framework=pytorch \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# Listar todas as versões de um modelo
az ml model list \
  --name sentiment-classifier \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws \
  --output table

# Mostrar linhagem — qual execução produziu este modelo
az ml model show \
  --name sentiment-classifier \
  --version 3 \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws \
  --query "jobs"
```

💡 **Dica**: Use as coleções de modelo do Azure ML para agrupar modelos relacionados (por exemplo, todos os modelos de um pipeline de recomendação). Isso facilita promover ou fazer rollback de um ensemble inteiro de modelos em vez de componentes individuais.

### MLflow Model Registry

O MLflow é o padrão open-source para rastreamento de experimentos e gerenciamento de modelos. Ele é agnóstico a framework — encapsula PyTorch, TensorFlow, scikit-learn e dezenas de outros frameworks em um formato de empacotamento comum. O Azure ML integra nativamente com o MLflow, então você pode usar as APIs do MLflow enquanto armazena artefatos no Azure.

```bash
# Iniciar um servidor de rastreamento MLflow local (para dev/test)
mlflow server \
  --backend-store-uri sqlite:///mlflow.db \
  --default-artifact-root ./mlruns \
  --host 0.0.0.0 --port 5000

# Registrar um modelo via CLI do MLflow
mlflow models register \
  --model-uri runs:/<run-id>/model \
  --name sentiment-classifier

# Transicionar um modelo para o estágio de produção
mlflow models transition-stage \
  --name sentiment-classifier \
  --version 3 \
  --stage Production
```

O conceito de `stages` do MLflow (Staging, Production, Archived) mapeia diretamente para o modelo de promoção que engenheiros de infraestrutura usam para deploys de aplicações. Um modelo começa em "None", passa para "Staging" após validação, é promovido para "Production" após aprovação, e vai para "Archived" quando é substituído.

### Container Registries para Servir Modelos

Quando modelos são servidos por meio de servidores de inferência containerizados (como NVIDIA Triton, TorchServe ou um wrapper FastAPI customizado), a imagem de container em si se torna o artefato implantável. Nesse padrão, o Azure Container Registry (ACR) atua tanto como seu model registry quanto como seu container registry.

```bash
# Compilar e enviar um container de model serving
az acr build \
  --registry mlmodelsacr \
  --image sentiment-classifier:v3 \
  --file Dockerfile.serve .

# Verificar a imagem
az acr repository show-tags \
  --name mlmodelsacr \
  --repository sentiment-classifier \
  --output table
```

Essa abordagem funciona bem quando você quer um único artefato (o container) que encapsule pesos do modelo, dependências e código de serving. Ela simplifica o deploy porque suas ferramentas existentes de orquestração de containers (AKS, Container Apps) cuidam de tudo a partir daí.

### Matriz de Decisão: Escolhendo um Model Registry

| Critério | Azure ML Registry | MLflow Registry | ACR (Container) |
|---|---|---|---|
| **Melhor para** | Times de ML nativos Azure | Times multi-cloud / OSS | Serving containerizado |
| **Versionamento** | Integrado, imutável | Integrado com estágios | Tags de imagem |
| **Rastreamento de linhagem** | Profundo (jobs, dados, env) | Nível de execução | Apenas Dockerfile |
| **Tamanho máx. de artefato** | Praticamente ilimitado | Depende do backend | Baseado em camadas |
| **Lock-in de framework** | Nenhum | Nenhum | Nenhum |
| **Overhead de infra** | Gerenciado | Self-hosted ou Azure ML | Gerenciado (ACR) |
| **Quando evitar** | Requisito multi-cloud | Precisa de integração profunda com Azure | Modelos sem containers |

⚠️ **Armadilha de Produção**: Não use sistemas de arquivos compartilhados ou blob storage como seu "registry." Sem versões imutáveis, uploads atômicos e APIs de metadados, você acaba com `model_final_v2_FIXED_actually_final.pt` — exatamente o caos que este capítulo existe para evitar.

---

## CI/CD para Modelos

Deploy de modelo não é um processo manual. É um pipeline — com estágios, gates e mecanismos de rollback — assim como o seu CI/CD de aplicações. A diferença é que a validação de modelos envolve testes estatísticos (acurácia, latência, fairness) além dos testes funcionais com os quais você já está acostumado.

### O Pipeline de Promoção de Modelo

Um pipeline de modelos de nível produção tem três estágios, cada um com requisitos de infraestrutura distintos e gates de validação.

```
┌─────────┐     ┌─────────────┐     ┌──────────────┐
│   DEV   │────▶│   STAGING   │────▶│  PRODUCTION  │
│         │     │             │     │              │
│ Treinar │     │ Validar     │     │ Servir       │
│ Rastrear│     │ Benchmark   │     │ Monitorar    │
│ Versionar│    │ Segurança   │     │ Auto-rollback│
└─────────┘     └─────────────┘     └──────────────┘
     │               │                    │
  GPU Compute    Infra de Inferência  Load Balanced
  Blob Storage   Acesso a Dados      Multi-réplica
  Rastreamento   de Teste            Rede de Prod
  de Experimentos Rede Isolada       Vinculado a SLA
```

**Dev**: Cientistas de dados treinam modelos usando GPU compute. Sua responsabilidade é fornecer o ambiente de computação (VMs com GPU ou node pools GPU no AKS), storage para dados de treinamento e checkpoints, e infraestrutura de rastreamento de experimentos. Modelos que passam na avaliação inicial são registrados no model registry.

**Staging**: Modelos registrados são implantados em um ambiente de staging que espelha a infraestrutura de produção — mesmos SKUs de VM, mesma configuração de rede, mesmo servidor de inferência. Testes automatizados validam a acurácia contra um dataset holdout, medem a latência sob carga e executam scans de segurança. É neste estágio que a maioria dos modelos falha, e isso é proposital.

**Production**: Modelos que passam em todos os gates de staging são implantados em produção com gerenciamento de tráfego (canary ou blue/green). O monitoramento detecta degradação e dispara rollback automatizado. Sua infraestrutura precisa suportar a execução de múltiplas versões do modelo simultaneamente durante transições.

### Gates de Validação Automatizados

Toda transição de estágio exige a passagem por gates automatizados. Aqui está o que validar e qual infraestrutura cada gate requer:

| Gate | O que Verifica | Infra Necessária |
|---|---|---|
| **Threshold de acurácia** | Métricas do modelo ≥ baseline (ex.: F1 > 0.92) | Storage de dataset de teste, compute para avaliação |
| **Benchmark de latência** | Latência P95 ≤ SLA (ex.: < 200ms) | Infraestrutura de teste de carga |
| **Teste de throughput** | Requisições/seg ≥ meta sob carga | Gerador de carga (k6, Locust) |
| **Scan de segurança** | Sem dependências vulneráveis, artefato assinado | Scanning de container (Triton, Defender) |
| **Validação de dados** | Schema de entrada corresponde ao formato esperado | Schema registry ou serviço de validação |
| **Estimativa de custo** | Custo projetado de serving dentro do orçamento | Modelagem de custo baseada no SKU de compute |

### Workflow do GitHub Actions para Deploy de Modelo

Aqui está um workflow prático de CI/CD que engenheiros de infraestrutura podem assumir. Ele é acionado quando uma nova versão de modelo é registrada, executa validação e promove para produção.

```yaml
# .github/workflows/model-deploy.yml
name: Model Deployment Pipeline

on:
  workflow_dispatch:
    inputs:
      model_name:
        description: 'Model name in registry'
        required: true
      model_version:
        description: 'Model version to deploy'
        required: true

env:
  AZURE_RG: ml-prod-rg
  AZURE_ML_WS: ml-prod-ws
  ACR_NAME: mlmodelsacr
  AKS_CLUSTER: ml-inference-aks

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Download model from registry
        run: |
          az ml model download \
            --name ${{ inputs.model_name }} \
            --version ${{ inputs.model_version }} \
            --download-path ./model \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}

      - name: Run accuracy validation
        run: |
          python scripts/validate_model.py \
            --model-path ./model \
            --test-data ./data/holdout.csv \
            --min-accuracy 0.92

      - name: Run latency benchmark
        run: |
          python scripts/benchmark_latency.py \
            --model-path ./model \
            --max-p95-ms 200 \
            --num-requests 1000

  deploy-staging:
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging endpoint
        run: |
          az ml online-deployment create \
            --name staging-${{ inputs.model_version }} \
            --endpoint-name sentiment-staging \
            --model azureml:${{ inputs.model_name }}:${{ inputs.model_version }} \
            --instance-type Standard_NC4as_T4_v3 \
            --instance-count 1 \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}

      - name: Smoke test staging
        run: |
          python scripts/smoke_test.py \
            --endpoint sentiment-staging \
            --expected-status 200

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval
    steps:
      - name: Deploy canary (10% traffic)
        run: |
          az ml online-deployment create \
            --name prod-${{ inputs.model_version }} \
            --endpoint-name sentiment-prod \
            --model azureml:${{ inputs.model_name }}:${{ inputs.model_version }} \
            --instance-type Standard_NC4as_T4_v3 \
            --instance-count 2 \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}

          az ml online-endpoint update \
            --name sentiment-prod \
            --traffic "prod-stable=90 prod-${{ inputs.model_version }}=10" \
            --resource-group ${{ env.AZURE_RG }} \
            --workspace-name ${{ env.AZURE_ML_WS }}
```

**Tradução Infra ↔ IA**: Esse é o seu pipeline de deploy blue/green, mas para pesos de modelo em vez de imagens de container. O flag `--traffic` funciona exatamente como roteamento ponderado no Azure Front Door ou Application Gateway — você está desviando uma porcentagem das requisições de produção para a nova versão do modelo enquanto a versão antiga continua servindo.

### Responsabilidades de Infraestrutura em Cada Estágio

Como engenheiro de infraestrutura, sua responsabilidade abrange todo o pipeline:

- **Provisionamento de compute**: Node pools GPU para treinamento (Dev), VMs de inferência para validação (Staging), clusters GPU com auto-scaling para serving (Production).
- **Rede**: VNets isoladas para staging, private endpoints para acesso ao model registry, configuração de load balancer para divisão de tráfego.
- **Storage**: Blob storage de alto throughput para dados de treinamento, storage de baixa latência para artefatos de modelo, políticas de retenção para versões antigas de modelos.
- **Gerenciamento de secrets**: Integração com Key Vault para API keys, managed identity para autenticação do pipeline, RBAC para acesso ao model registry.
- **Monitoramento**: Dashboards de saúde do deploy, alertas de latência, gatilhos de rollback automatizado.

---

## A/B Testing e Deploys Canary para Modelos

Fazer deploy de um modelo em produção não é um evento binário. Você não aperta um botão e torce pelo melhor. Em vez disso, você gradualmente desvia tráfego para a nova versão do modelo enquanto monitora o desempenho — os mesmos padrões canary e blue/green que você usa para deploys de aplicações.

### Padrões de Divisão de Tráfego

Três padrões dominam os deploys de modelo, cada um com requisitos de infraestrutura diferentes:

**Canary (90/10 → 70/30 → 0/100).** Roteie uma pequena porcentagem do tráfego para a nova versão do modelo. Se as métricas se mantiverem, aumente a porcentagem. Se degradarem, faça rollback. Este é o padrão mais seguro e o mais comum. Os managed endpoints do Azure ML suportam isso nativamente com o parâmetro `--traffic`.

**Blue/Green.** Execute dois ambientes de produção completos simultaneamente. Roteie todo o tráfego para "blue" (atual) enquanto valida "green" (novo). Quando estiver pronto, mude o DNS ou load balancer para green. O rollback é instantâneo — basta voltar. Esse padrão dobra o custo de infraestrutura durante o deploy, mas elimina riscos de tráfego parcial.

**Shadow (Dark Launch).** Roteie 100% do tráfego para o modelo atual, mas também envie uma cópia de cada requisição para o novo modelo. Compare as respostas offline sem afetar os usuários. Isso é ideal para deploys de alto risco onde até 10% de tráfego é inaceitável. O trade-off é o dobro de compute de inferência durante o período de shadow.

```bash
# Azure ML: Desviar tráfego gradualmente
# Começar com 10% para o novo deployment
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "stable=90 canary-v4=10" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# Após o monitoramento confirmar paridade, aumentar para 50%
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "stable=50 canary-v4=50" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# Cutover completo
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "canary-v4=100" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws
```

### Monitorando o Desempenho do Modelo Durante A/B Tests

Durante um deploy canary, você está comparando duas versões do modelo frente a frente. Seu monitoramento precisa responder: o novo modelo é pelo menos tão bom quanto o antigo? Aqui está o que rastrear:

| Métrica | Por que Importa | Threshold de Alerta |
|---|---|---|
| **Latência de predição (P50/P95/P99)** | Experiência do usuário e conformidade com SLA | P95 > 1.2× baseline |
| **Taxa de erro** | Falhas do modelo, timeout, OOM | > 0.5% |
| **Distribuição de predições** | Detectar drift do modelo ou mudança de viés | Divergência de distribuição > threshold |
| **Utilização de GPU** | Eficiência e impacto no custo | Sustentada < 30% ou > 95% |
| **Throughput de requisições** | Validação de capacidade | Cai abaixo do RPS esperado |

### Gatilhos de Rollback Automatizado

Não dependa de humanos para detectar degradação às 3 da manhã. Configure regras de rollback automatizado que revertem o tráfego quando as métricas ultrapassam thresholds. Os managed endpoints do Azure ML suportam monitoramento de saúde de deployment, e você pode construir lógica de rollback customizada usando alertas do Azure Monitor com Logic Apps ou webhooks do GitHub Actions.

```bash
# Rollback de emergência — desviar todo o tráfego de volta para stable
az ml online-endpoint update \
  --name sentiment-prod \
  --traffic "stable=100" \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws

# Em seguida, excluir o deployment que falhou
az ml online-deployment delete \
  --name canary-v4 \
  --endpoint-name sentiment-prod \
  --resource-group ml-prod-rg \
  --workspace-name ml-prod-ws \
  --yes
```

💡 **Dica**: Defina seus critérios de rollback antes do deploy, não depois. Escreva-os na configuração do seu pipeline. Gatilhos comuns: latência P95 excede 2× o baseline por 5 minutos, taxa de erro excede 1% por 3 minutos, ou a distribuição de confiança das predições diverge além de um threshold estatístico.

---

## Segurança da Cadeia de Suprimentos de Modelos

Você não faria pull de uma imagem de container não assinada de um registry desconhecido para rodar em produção. A mesma disciplina precisa se aplicar a artefatos de modelo. Arquivos de modelo são código executável — especialmente quando serializados com o formato `pickle` do Python — e o ecossistema de ML ainda está amadurecendo suas práticas de segurança.

### Assinatura e Proveniência de Modelos

Estabeleça uma cadeia de custódia para cada artefato de modelo. No mínimo, rastreie:

- **Quem** iniciou a execução de treinamento (identidade e autorização)
- **O que** foi usado: código, dados e hiperparâmetros (reprodutibilidade)
- **Quando** o modelo foi treinado e registrado (auditabilidade)
- **Onde** o treinamento foi executado (ambiente de compute, região)

O Azure ML captura automaticamente a linhagem de jobs de treinamento. Para assinatura adicional, considere usar o Notary v2 (notation) para assinar containers de modelo armazenados no ACR:

```bash
# Assinar uma imagem de container de modelo com notation
notation sign \
  mlmodelsacr.azurecr.io/sentiment-classifier:v3 \
  --key mySigningKey

# Verificar antes do deploy
notation verify \
  mlmodelsacr.azurecr.io/sentiment-classifier:v3
```

### Segurança de Imagens de Container para Model Serving

Containers de model serving herdam todas as preocupações de segurança de qualquer container de produção — além de riscos adicionais vindos das dependências de frameworks de ML. Seu pipeline de scanning de containers deve incluir:

```bash
# Escanear a imagem de model serving com o Defender for Containers
az acr task run \
  --registry mlmodelsacr \
  --name scan-sentiment-v3 \
  --file scan-task.yaml

# Verificar vulnerabilidades conhecidas nas dependências de frameworks de ML
# (PyTorch, TensorFlow, ONNX Runtime, etc.)
az acr repository show \
  --name mlmodelsacr \
  --image sentiment-classifier:v3 \
  --query "changeableAttributes"
```

⚠️ **Armadilha de Produção**: Arquivos de modelo baixados de hubs públicos como o Hugging Face podem conter código malicioso. A serialização padrão do PyTorch usa `pickle` do Python, que pode executar código arbitrário durante a desserialização. Um arquivo de modelo chamado `pytorch_model.bin` pode conter um payload de reverse shell que é ativado quando seu servidor de inferência carrega os pesos. **Sempre** escaneie arquivos de modelo de fontes não confiáveis, prefira o formato SafeTensors ao pickle e execute o carregamento de modelos em ambientes sandboxed antes de promovê-los ao seu registry. Trate arquivos de modelo com a mesma desconfiança que você daria a uma imagem de container não assinada do Docker Hub.

### Protegendo o Pipeline de Modelos

Aplique os mesmos princípios de cadeia de suprimentos que você usa para código de aplicação:

- **Apenas registries privados**: Armazene modelos em registries do Azure ML ou instâncias privadas do ACR — nunca em pastas compartilhadas ou storage público.
- **Managed identity para acesso**: Use Azure Managed Identity para autenticação do pipeline nos model registries. Nada de secrets de service principal em variáveis de CI/CD.
- **Isolamento de rede**: Model registries devem ser acessíveis apenas via private endpoints. Compute de treinamento e inferência deve fazer pull de artefatos pela sua VNet.
- **Versões imutáveis**: Uma vez que uma versão de modelo é registrada, ela não deve ser sobrescrita. Trate versões de modelo como digests de imagem de container — apenas adicione, nunca mude.

---

## Ambientes de Treinamento Reprodutíveis

Quando um modelo precisa de retreinamento — porque os dados mudam, os requisitos se alteram ou um bug é descoberto — você precisa recriar o ambiente exato que produziu a versão atual. "Funciona na minha máquina" é ainda mais perigoso em ML porque os resultados do treinamento dependem de versões de framework, drivers CUDA, seeds aleatórias e até da geração do hardware da GPU.

### O que Fixar

Um ambiente de treinamento reprodutível trava quatro categorias:

| Categoria | O que Fixar | Exemplo |
|---|---|---|
| **Framework** | Versão da biblioteca de ML | `pytorch==2.2.1`, `transformers==4.38.0` |
| **Runtime** | CUDA, cuDNN, Python | `CUDA 12.1`, `cuDNN 8.9.7`, `Python 3.11.8` |
| **Dados** | Versão ou snapshot do dataset | `dataset-v2.3`, snapshot de blob com timestamp |
| **Hardware** | SKU e quantidade de GPUs | `Standard_NC24ads_A100_v4`, 4x A100 80GB |

```dockerfile
# Exemplo: Ambiente de treinamento com versões fixas
FROM mcr.microsoft.com/aifx/acpt/stable-ubuntu2204-cu121-py311-torch221:latest

WORKDIR /training

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY configs/ ./configs/

# Fixar a seed aleatória para reprodutibilidade
ENV PYTHONHASHSEED=42
ENV CUBLAS_WORKSPACE_CONFIG=:4096:8

ENTRYPOINT ["python", "src/train.py"]
```

💡 **Dica**: Use ambientes curados do Azure ML ou imagens base ACPT (Azure Container for PyTorch) da Microsoft. Essas são combinações pré-validadas de CUDA, cuDNN e versões de framework testadas contra SKUs de GPU do Azure. Construir sua própria stack CUDA do zero é um risco de confiabilidade que você não precisa correr.

### Arquitetura de Storage para Artefatos de Treinamento

O treinamento produz um volume surpreendente de artefatos além do modelo final. Sua arquitetura de storage precisa lidar com:

- **Checkpoints**: Snapshots intermediários do modelo salvos a cada N passos. Uma única execução de treinamento em um modelo grande pode produzir centenas de gigabytes de checkpoints. Use Azure Blob Storage com camada hot para execuções ativas, depois políticas de lifecycle para mover checkpoints mais antigos para a camada cool ou archive.
- **Logs e métricas**: Métricas de treinamento por passo (loss, learning rate, normas de gradiente) registradas no rastreamento de experimentos (MLflow ou Azure ML). Elas são pequenas mas numerosas — milhares de pontos de métrica por execução.
- **Datasets**: Snapshots versionados dos dados de treinamento. Use Azure Data Lake Storage Gen2 com hierarchical namespace para acesso eficiente a datasets grandes. Habilite versionamento ou storage imutável para conformidade.
- **Configuração**: Hiperparâmetros, definições de ambiente e configurações de pipeline. Armazene-os no Git junto com seu código de treinamento.

```bash
# Criar uma conta de storage otimizada para artefatos de treinamento
az storage account create \
  --name mltrainingartifacts \
  --resource-group ml-prod-rg \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hns true

# Definir política de lifecycle para arquivar checkpoints antigos
az storage account management-policy create \
  --account-name mltrainingartifacts \
  --resource-group ml-prod-rg \
  --policy @lifecycle-policy.json
```

---

## Feature Stores — A Visão de Infra

Em algum momento, seus times de ML vão pedir uma "feature store." Se o termo é novo, não se preocupe — da perspectiva de infraestrutura, é uma camada de cache e serving de dados que você já sabe construir.

### O que São Feature Stores e Por que Existem

Uma feature é um dado transformado usado como entrada para um modelo. Por exemplo, um log bruto de transações pode conter timestamps e valores em dólares. Features derivadas desses dados podem incluir "valor médio de transação nos últimos 7 dias" ou "número de transações na última hora." Computar essas features é caro, e modelos diferentes frequentemente precisam das mesmas features. Uma feature store computa features uma vez e as serve para qualquer modelo que precisar delas.

Da sua perspectiva, uma feature store é um sistema com dois caminhos de dados e um requisito de consistência entre eles.

### Stores Online vs. Offline

| Componente | Finalidade | Latência | Storage | Tecnologia Exemplo |
|---|---|---|---|---|
| **Offline store** | Recuperação de dados em lote para treinamento | Segundos a minutos | Terabytes a petabytes | Azure Data Lake, Synapse, Delta Lake |
| **Online store** | Serving de inferência em tempo real | Milissegundos de um dígito | Gigabytes a terabytes | Azure Cache for Redis, Cosmos DB |

**Offline stores** atendem pipelines de treinamento. Cientistas de dados consultam valores históricos de features para construir datasets de treinamento. Os requisitos de desempenho são orientados a throughput — escanear grandes volumes de dados de forma eficiente. Isso mapeia para sua arquitetura de data lake existente.

**Online stores** atendem endpoints de inferência. Quando um modelo recebe uma requisição de predição, ele precisa dos valores mais recentes das features com latência abaixo de 10ms. Esse é um padrão de lookup chave-valor — exatamente como as camadas de cache que você já construiu para aplicações web.

### Componentes de Infraestrutura

Um deploy de feature store normalmente inclui:

```
┌─────────────────────────────────────────────┐
│              Feature Store                  │
│                                             │
│  ┌──────────┐    Sync    ┌──────────────┐   │
│  │ Offline  │ ─────────▶ │   Online     │  │
│  │ Store    │            │   Store      │   │
│  │ (ADLS)   │            │ (Redis/      │   │
│  │          │            │  Cosmos DB)  │   │
│  └──────────┘            └──────────────┘   │
│       ▲                        │            │
│       │                        ▼            │
│  Pipelines de              Endpoints de     │
│  Treinamento               Inferência       │
└─────────────────────────────────────────────┘
```

- **Azure Data Lake Storage Gen2** para o offline store — acesso em lote, evolução de schema e storage com custo-benefício para dados históricos de features.
- **Azure Cache for Redis** ou **Cosmos DB** para o online store — leituras sub-milissegundo para serving em tempo real. Escolha Redis para padrões simples de chave-valor com latência extremamente baixa. Escolha Cosmos DB quando precisar de replicação multi-região, padrões de consulta mais ricos ou disponibilidade com SLA garantido.
- **Um pipeline de sincronização** (Azure Data Factory, Spark ou customizado) que materializa features do offline store para o online store em uma agenda ou acionado por novos dados.

💡 **Dica**: Trate a online feature store como qualquer outra camada de cache. Aplique as mesmas práticas operacionais — monitore taxas de acerto, defina políticas de evicção, planeje capacidade para picos de carga e teste cenários de falha. Se o Redis cair, seus endpoints de inferência perdem acesso às features e as predições falham. Essa é uma dependência no caminho crítico.

---

## Checklist do Capítulo

Antes de seguir para o Capítulo 7, verifique se o gerenciamento de ciclo de vida dos seus modelos cobre estes itens essenciais:

- [ ] **Model registry implementado** — Todos os modelos de produção estão registrados com versões imutáveis, metadados e rastreamento de linhagem (Azure ML, MLflow ou ACR).
- [ ] **Pipeline de CI/CD para modelos** — Pipeline automatizado com estágios Dev → Staging → Production e gates de validação em cada transição.
- [ ] **Gates de validação definidos** — Thresholds de acurácia, benchmarks de latência, testes de throughput e scans de segurança rodam automaticamente antes de qualquer modelo chegar à produção.
- [ ] **Gerenciamento de tráfego configurado** — Capacidade de deploy canary ou blue/green com divisão de tráfego baseada em porcentagem para rollouts seguros de modelos.
- [ ] **Rollback automatizado** — Alertas de monitoramento disparam reversão automática de tráfego quando o desempenho do modelo degrada além dos thresholds definidos.
- [ ] **Cadeia de suprimentos de modelos protegida** — Artefatos de modelo são assinados, escaneados, armazenados em registries privados e acessados via managed identity e private endpoints.
- [ ] **Ambientes de treinamento reprodutíveis** — Versões de framework, CUDA, Python e dados estão fixadas. Treinamento roda em ambientes containerizados com configurações determinísticas.
- [ ] **Arquitetura de storage planejada** — Blob storage para checkpoints com políticas de lifecycle, rastreamento de experimentos para métricas, data lake versionado para datasets.
- [ ] **Infraestrutura de feature store dimensionada** — Se necessário, offline store (ADLS), online store (Redis/Cosmos DB) e pipeline de sincronização estão provisionados e monitorados.
- [ ] **Rollback testado** — Você realmente testou fazer rollback de uma versão de modelo em um ambiente que não é de produção. Não espere por um incidente às 2 da manhã para descobrir que seu processo de rollback tem falhas.

---

## Ponte para o Capítulo 7

Seus modelos agora têm um ciclo de vida — versionados, testados e implantáveis por meio de pipelines automatizados com capacidade de rollback. Mas o deploy é apenas o começo da vida de um modelo em produção. Como você sabe que o modelo está performando bem depois que o período de canary termina? Como você detecta quando a qualidade das predições degrada porque o mundo real mudou? Como você cria alertas sobre padrões de utilização de GPU que indicam desperdício de gastos?

O Capítulo 7 cobre monitoramento e observabilidade para workloads de IA: o que medir, como alertar e por que métricas de GPU são apenas o começo.