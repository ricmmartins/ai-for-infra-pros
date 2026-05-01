# Capítulo 12 — O Guia de Troubleshooting para Produção

*"Tudo funciona em staging. Produção tem opinião própria."*

---

## Mantenha Este Capítulo nos Favoritos

Este capítulo está organizado como uma coleção de cenários reais de falha — aqueles que geram alertas às 2 da manhã, arruínam demos de sprint e fazem você questionar suas escolhas de carreira. Cada cenário segue o mesmo formato:

**Sintomas → Diagnóstico → Causa Raiz → Resolução → Prevenção**

Esses cenários não são hipotéticos. Eles foram destilados de centenas de incidentes de produção em infraestrutura de GPU, workloads de IA no Kubernetes e deployments do Azure OpenAI. Alguns você vai encontrar no primeiro dia. Outros vão te emboscar seis meses depois, justo quando você acha que tudo está estável.

Leia todos uma vez para construir reconhecimento de padrões. Depois mantenha este capítulo nos favoritos — você vai voltar aqui.

---

## Cenário 1: Crash do Driver NVIDIA Após Atualização do Kernel

### Sintomas

Segunda-feira de manhã. O time de ML reporta que todos os workloads de GPU falharam durante o fim de semana. Ninguém fez deploy de nada. Você conecta via SSH na VM e executa:

```bash
$ nvidia-smi
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver.
Make sure that the latest NVIDIA driver is installed and running.
```

Containers de GPU não iniciam. Jobs de treinamento estão mortos. A VM em si está bem — workloads de CPU funcionam normalmente.

### Diagnóstico

Comece pelo ring buffer do kernel:

```bash
$ dmesg | grep -i nvidia
[    4.212] NIST: module nvidia not found in modules.dep

$ uname -r
6.5.0-44-generic

$ dpkg -l | grep nvidia-driver
ii  nvidia-driver-535    535.183.01-0ubuntu1    amd64
```

O driver NVIDIA está instalado para uma versão diferente do kernel. Verifique o que aconteceu:

```bash
$ cat /var/log/apt/history.log | grep -A 5 "linux-image"
Start-Date: 2024-07-13  06:25:11
Commandline: /usr/bin/unattended-upgrade
Install: linux-image-6.5.0-44-generic:amd64 (6.5.0-44.44~22.04.1)
```

### Causa Raiz

O serviço `unattended-upgrades` do Ubuntu instalou automaticamente uma nova versão do kernel. O módulo do kernel NVIDIA é compilado para um kernel específico. Quando a VM reiniciou com o novo kernel, não havia módulo NVIDIA correspondente — o driver quebrou silenciosamente.

### Resolução

**Opção A — Reinstalar a extensão do driver (VMs Azure):**

```bash
az vm extension set \
  --resource-group myRG \
  --vm-name myGPUVM \
  --name NvidiaGpuDriverLinux \
  --publisher Microsoft.HKS \
  --version 1.9
```

Isso recompila o módulo do kernel para o kernel atual.

**Opção B — Fixar a versão do kernel:**

```bash
sudo apt-mark hold linux-image-$(uname -r) linux-headers-$(uname -r)
```

Depois reinstale o driver para o kernel atual:

```bash
sudo apt install --reinstall nvidia-driver-535
sudo reboot
```

### Prevenção

- **Desabilite atualizações automáticas do kernel** em todas as VMs de GPU. Adicione em `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Package-Blacklist {
    "linux-image";
    "linux-headers";
    "linux-modules";
};
```

- **Use a Extensão de Driver GPU NVIDIA do Azure** para gerenciamento do ciclo de vida do driver em vez de instalações manuais. A extensão cuida da compatibilidade com o kernel automaticamente.
- **Fixe versões do kernel** nos seus templates de IaC e trate atualizações de kernel como eventos de manutenção planejada.

⚠️ **Gotcha de Produção**: Essa falha é completamente silenciosa. A VM inicia normalmente, passa nos health checks e responde ao SSH. Somente workloads de GPU falham. Se você não monitorar a saída do `nvidia-smi`, só vai saber quando os usuários reclamarem.

---

## Cenário 2: CUDA Out of Memory Durante Fine-Tuning

### Sintomas

Um job de fine-tuning inicia com sucesso, roda por 10–30 minutos e depois crasha:

```
RuntimeError: CUDA out of memory. Tried to allocate 2.00 GiB
(GPU 0; 79.15 GiB total capacity; 77.42 GiB already allocated;
1.08 GiB free; 78.50 GiB reserved in total by PyTorch)
```

O time está confuso: "Funcionou bem nos primeiros 500 steps."

### Diagnóstico

Monitore a memória da GPU ao longo do tempo:

```bash
# Snapshot
$ nvidia-smi

# Monitoramento contínuo (a cada 1 segundo)
$ watch -n 1 nvidia-smi

# Registrar uso de memória em CSV para análise
$ nvidia-smi --query-gpu=timestamp,memory.used,memory.free,utilization.gpu \
  --format=csv -l 5 > gpu_memory.csv
```

Calcule os requisitos de memória esperados usando a fórmula do Capítulo 4:

```
Memória Total da GPU ≈ Parâmetros + Gradientes + Estados do Otimizador + Ativações
```

Para um modelo de 7B parâmetros com otimizador Adam em FP16/BF16:

| Componente | Memória |
|---|---|
| Parâmetros (BF16) | ~14 GB |
| Gradientes (BF16) | ~14 GB |
| Estados do Otimizador (FP32, Adam) | ~56 GB |
| Ativações (dependente do batch) | Variável |
| **Mínimo total** | **~84 GB + ativações** |

### Causa Raiz

O batch size estava configurado em 8. No início do treinamento, sequências curtas no dataset produziam tensores de ativação pequenos. Conforme o data loader alcançava sequências mais longas, a memória de ativação crescia até exceder a memória restante da GPU. O OOM não aconteceu no step 1 porque os primeiros batches cabiam — as sequências mais longas chegaram depois.

### Resolução

**Correção imediata — reduzir o batch size:**

```python
training_args = TrainingArguments(
    per_device_train_batch_size=2,  # Reduzido de 8
    gradient_accumulation_steps=4,  # Manter o batch size efetivo
)
```

**Correção melhor — habilitar gradient checkpointing:**

```python
model.gradient_checkpointing_enable()
```

Isso troca ~20–30% de velocidade de treinamento por 60–80% de redução na memória de ativação.

**Para modelos maiores — usar fine-tuning eficiente em parâmetros:**

```python
from peft import LoraConfig, get_peft_model

lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "v_proj"],
    lora_dropout=0.05,
)
model = get_peft_model(model, lora_config)
model.print_trainable_parameters()
# trainable params: 6.5M || all params: 6.74B || trainable%: 0.096%
```

LoRA treina <1% dos parâmetros, reduzindo a memória de gradientes e do otimizador em 100×.

### Prevenção

- **Sempre calcule os requisitos de memória antes de começar** usando a fórmula do Capítulo 4. Se a conta diz que não vai caber, não execute.
- **Defina `max_seq_length` explicitamente** para limitar a memória de ativação no comprimento máximo de sequência esperado.
- **Use `gradient_accumulation_steps`** para manter o batch size efetivo enquanto mantém o batch size por GPU pequeno.

💡 **Dica Pro**: Se você vê erros de OOM que acontecem em steps aleatórios (não consistentemente no step N), desconfie de sequências de comprimento variável. Defina `max_seq_length` e faça pad/truncate para eliminar a variância.

---

## Cenário 3: Pods GPU no AKS Presos em Pending

### Sintomas

Um pod de treinamento de GPU está no estado `Pending` há 20 minutos:

```bash
$ kubectl get pods -n ml-team
NAME                        READY   STATUS    RESTARTS   AGE
training-job-7b-xyz         0/1     Pending   0          20m
```

### Diagnóstico

Verifique os eventos:

```bash
$ kubectl describe pod training-job-7b-xyz -n ml-team
Events:
  Type     Reason            Age   Message
  ----     ------            ----  -------
  Warning  FailedScheduling  18m   0/12 nodes are available:
    3 node(s) had untolerated taint {sku=gpu:NoSchedule},
    9 node(s) didn't match Pod's node affinity/selector.
```

A mensagem de taint é a chave. Verifique os taints do node pool de GPU:

```bash
$ kubectl get nodes -l accelerator=nvidia -o custom-columns=\
NAME:.metadata.name,TAINTS:.spec.taints
NAME                                TAINTS
aks-gpunp-12345-vmss000000          [map[effect:NoSchedule key:sku value:gpu]]
```

Agora verifique o spec do pod para tolerations:

```bash
$ kubectl get pod training-job-7b-xyz -n ml-team -o jsonpath='{.spec.tolerations}' | jq .
```

Nenhum toleration de GPU presente.

### Causa Raiz

Node pools de GPU no AKS aplicam o taint `sku=gpu:NoSchedule` por padrão. Pods devem incluir um toleration correspondente para serem agendados nos nós de GPU. O spec do pod estava sem esse toleration — então o scheduler viu os nós de GPU como inelegíveis e não conseguiu encontrar nenhum nó com GPUs e sem taints.

Outras causas comuns incluem:

- **Quota de GPU esgotada**: O cluster autoscaler não consegue provisionar novos nós de GPU porque a subscription atingiu a quota de vCPU de GPU.
- **Node pool no tamanho máximo**: O autoscaler quer escalar para cima, mas o node pool já está no `maxCount`.

Verifique ambos:

```bash
# Verificar quota regional de GPU
$ az vm list-usage --location eastus -o table | grep -i "standard NC\|standard ND"

# Verificar limites de escala do node pool
$ az aks nodepool show --cluster-name myAKS --resource-group myRG \
  --name gpunp --query '{min:minCount, max:maxCount, current:count}'
```

### Resolução

**Corrigir o toleration** — adicione isso ao spec do pod:

```yaml
spec:
  tolerations:
    - key: "sku"
      operator: "Equal"
      value: "gpu"
      effect: "NoSchedule"
  containers:
    - name: training
      resources:
        limits:
          nvidia.com/gpu: 1
```

**Se a quota é o problema:**

```bash
# Solicitar aumento de quota via CLI
az quota create --resource-name "StandardNDSv2Family" \
  --scope "/subscriptions/{sub-id}/providers/Microsoft.Compute/locations/eastus" \
  --limit-object value=48 limit-object-type=LimitValue
```

### Prevenção

- **Padronize todos os specs de pods GPU** com o toleration correto pré-configurado. Use defaults de Helm charts ou políticas OPA/Gatekeeper que injetam tolerations automaticamente.
- **Configure alertas de monitoramento de quota** que disparam a 80% de uso da quota de GPU (veja Capítulo 9).
- **Configure o cluster autoscaler corretamente**: defina `maxCount` com folga para que o autoscaler possa responder à demanda.

⚠️ **Gotcha de Produção**: Um pod preso em Pending não produz logs — não há container para gerar logs. Sempre verifique `kubectl describe pod` para eventos, não `kubectl logs`.

---

## Cenário 4: Tempestade de 429 no Azure OpenAI

### Sintomas

O dashboard da sua aplicação mostra 30%+ das requisições ao Azure OpenAI retornando HTTP 429. Usuários reportam respostas lentas ou timeouts. O payload de erro é assim:

```json
{
  "error": {
    "code": "429",
    "message": "Requests to the ChatCompletions_Create Operation under Azure OpenAI API have exceeded the token rate limit of your current deployment. Please retry after 6 seconds."
  }
}
```

### Diagnóstico

Verifique o uso de TPM e RPM do seu deployment no Azure Monitor:

```bash
# Verificar métricas atuais do deployment
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}" \
  --metric "TokenTransaction" \
  --interval PT1M \
  --aggregation Total \
  --filter "ModelDeploymentName eq 'gpt-4o-prod'"
```

Observe os valores do header `Retry-After` nas respostas 429 — eles indicam o quanto você está acima da quota. Um `Retry-After: 1` significa que você mal excedeu o limite. Um `Retry-After: 30` significa que você está dramaticamente acima.

Verifique o TPM provisionado do deployment:

```bash
az cognitiveservices account deployment show \
  --name my-openai-account \
  --resource-group myRG \
  --deployment-name gpt-4o-prod \
  --query "properties.rateLimits"
```

### Causa Raiz

O deployment Standard (pay-as-you-go) foi provisionado com 80K TPM. Um lançamento de produto gerou um pico de tráfego que chegou a 200K+ TPM. Deployments Standard aplicam rate limits rígidos — uma vez que você excede o TPM ou RPM provisionado, cada requisição adicional recebe um 429.

### Resolução

**Imediato — implementar exponential backoff com jitter:**

```python
import time
import random

def call_with_backoff(client, messages, max_retries=5):
    for attempt in range(max_retries):
        try:
            return client.chat.completions.create(
                model="gpt-4o",
                messages=messages
            )
        except openai.RateLimitError as e:
            if attempt == max_retries - 1:
                raise
            retry_after = int(e.response.headers.get("Retry-After", 1))
            wait = retry_after + random.uniform(0, 1)
            time.sleep(wait)
```

**Curto prazo — adicionar um deployment secundário para overflow:**

Crie um segundo deployment em uma região diferente e direcione o tráfego excedente para ele usando o Azure API Management ou lógica no nível da aplicação.

**Longo prazo — avaliar Provisioned Throughput Units (PTU):**

Para workloads previsíveis e de alto volume, PTU fornece throughput garantido sem rate limiting. Sem 429s — você paga por capacidade reservada independentemente do uso (veja Capítulo 9 para a análise de custos).

### Prevenção

- **Arquitetura multi-deployment**: Use o Azure API Management com políticas de load balancing entre 2–3 deployments em regiões diferentes.
- **Alerte a 80% da quota**: Configure alertas no Azure Monitor que disparam quando o uso de TPM atinge 80% da capacidade provisionada.
- **Implemente uma fila com consciência de tokens**: Estime a contagem de tokens antes de enviar requisições e faça throttling no lado do cliente ao se aproximar dos limites.
- **Use rastreamento de uso**: Registre a contagem de tokens por requisição para prever necessidades de capacidade antes de lançamentos.

💡 **Dica Pro**: O erro mais comum é fazer retry de 429s imediatamente em um loop apertado. Isso piora a tempestade. Sempre respeite o header `Retry-After` e adicione jitter aleatório para evitar thundering herd.

---

## Cenário 5: Pico de Latência na Inferência

### Sintomas

A latência P99 do seu endpoint de inferência do modelo pula de 200 ms para 3 segundos. Nenhum deploy foi feito. Nenhuma mudança de configuração. Usuários começam a reportar "a IA está lenta."

### Diagnóstico

Verifique a camada de infraestrutura, nível por nível:

```bash
# Utilização da GPU — a GPU está realmente ocupada?
$ nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu \
  --format=csv -l 2

# Restarts de container — o container de serving crashou?
$ kubectl get pods -n inference -w
$ kubectl describe pod model-serve-abc -n inference | grep -A 5 "Last State"

# Verificar cold starts — o container foi criado recentemente?
$ kubectl get pods -n inference -o custom-columns=\
NAME:.metadata.name,START:.status.startTime,READY:.status.conditions[0].lastTransitionTime
```

Verifique se o carregamento do modelo é o gargalo:

```bash
# Verificar logs de startup do container para tempo de carregamento do modelo
$ kubectl logs model-serve-abc -n inference | grep -i "model loaded\|loading model\|startup"
[2024-07-15 08:12:03] Loading model from /models/llama-7b...
[2024-07-15 08:14:47] Model loaded in 164.2 seconds
```

Um tempo de carregamento de modelo de 164 segundos significa que cada restart de container cria um buraco de latência de quase 3 minutos.

### Causa Raiz

Três causas comuns, frequentemente sobrepostas:

1. **Cold start do container**: O pod de inferência foi despejado (OOM, node drain, reivindicação de nó spot) e reiniciou. Os pesos do modelo são carregados do Azure Blob Storage na inicialização — baixar 14+ GB pela rede leva minutos.
2. **Thermal throttling da GPU**: Utilização sustentada de 100% da GPU elevou a temperatura acima do limiar de throttling (tipicamente 83°C), causando redução automática do clock.
3. **Vizinho barulhento**: Outro pod no mesmo nó está consumindo CPU, memória ou banda de rede necessários para pré-processamento ou pós-processamento.

### Resolução

**Para cold starts — pré-carregar modelos e cachear localmente:**

```yaml
# Usar um init container para baixar pesos do modelo para NVMe local
initContainers:
  - name: model-loader
    image: mcr.microsoft.com/azure-cli:latest
    command: ["sh", "-c"]
    args:
      - |
        az storage blob download-batch \
          --source models --destination /local-cache/models \
          --account-name mystorageaccount --auth-mode login
    volumeMounts:
      - name: local-nvme
        mountPath: /local-cache
```

**Para cold starts — configurar readiness probes corretamente:**

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 180  # Dar tempo para o modelo carregar
  periodSeconds: 10
  failureThreshold: 3
```

Isso impede que o Kubernetes direcione tráfego para um pod que ainda está carregando o modelo.

**Para thermal throttling:**

```bash
# Verificar temperatura da GPU
$ nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader
82

# Se consistentemente acima de 80°C, reduza requisições concorrentes ou adicione refrigeração
```

**Para vizinhos barulhentos — isolar pods de inferência GPU:**

```yaml
resources:
  requests:
    cpu: "8"
    memory: "32Gi"
    nvidia.com/gpu: 1
  limits:
    cpu: "8"
    memory: "32Gi"
    nvidia.com/gpu: 1  # GPUs são sempre exclusivas por container
```

Defina `requests = limits` tanto para CPU quanto para memória para obter a classe de QoS Guaranteed, que previne eviction e contenção de CPU por vizinhos barulhentos.

### Prevenção

- **Defina `minReplicas` > 0** no seu Horizontal Pod Autoscaler para evitar escalar para zero.
- **Use cache NVMe local** em VMs ND/NC-series para pesos do modelo. Carregar do SSD local leva segundos; carregar do Blob Storage leva minutos.
- **Configure liveness e readiness probes** com `initialDelaySeconds` adequado para o carregamento do modelo.
- **Monitore a temperatura da GPU** e configure alertas a 80°C.

⚠️ **Gotcha de Produção**: Readiness probes com `initialDelaySeconds` padrão (0) vão marcar um pod de model serving como "ready" antes do modelo estar de fato carregado. O Kubernetes direciona tráfego para ele, requisições atingem um modelo não inicializado, e os usuários veem erros. Sempre defina `initialDelaySeconds` para pelo menos o tempo de carregamento do seu modelo.

---

## Cenário 6: Treinamento Distribuído Trava na Sincronização de Gradientes

### Sintomas

Um job de treinamento multi-nó para de progredir. O terminal não mostra nova saída de log. A utilização da GPU cai para 0% em todos os nós. Nenhuma mensagem de erro aparece. O job simplesmente... trava.

```bash
$ nvidia-smi  # Em qualquer nó
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                GPU Memory  |
|  0     N/A  N/A     12345    C   python                          78000MiB  |
+-----------------------------------------------------------------------------+
# Memória da GPU alocada mas utilização em 0%
```

### Diagnóstico

Habilite o debug logging do NCCL e reinicie:

```bash
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL
export NCCL_SOCKET_IFNAME=eth0
torchrun --nproc_per_node=8 --nnodes=4 --node_rank=0 train.py
```

Verifique o status do InfiniBand em cada nó:

```bash
$ ibstat
CA 'mlx5_0'
    CA type: MT4123
    Number of ports: 1
    Port 1:
        State: Down          # <-- Problema! Deveria ser "Active"
        Physical state: Disabled
        Rate: 0
```

Compare com um nó saudável:

```bash
$ ibstat
CA 'mlx5_0'
    CA type: MT4123
    Number of ports: 1
    Port 1:
        State: Active
        Physical state: LinkUp
        Rate: 200             # 200 Gb/s HDR InfiniBand
```

### Causa Raiz

Um nó no cluster de treinamento de 4 nós perdeu conectividade InfiniBand. A operação `all-reduce` do NCCL requer que todos os participantes completem antes que qualquer nó possa prosseguir. Um único nó com falha bloqueia o job inteiro indefinidamente — o NCCL espera para sempre por padrão.

Isso é particularmente traiçoeiro porque:
- O job não crasha — ele trava silenciosamente
- Os outros 3 nós (24 GPUs) ficam ociosos, queimando dinheiro
- Nenhum erro aparece nos logs padrão de treinamento

### Resolução

**Identificar e substituir o nó com falha:**

```bash
# Executar em todos os nós para encontrar qual tem InfiniBand down
for node in node-0 node-1 node-2 node-3; do
    echo "=== $node ==="
    ssh $node "ibstat | grep -A 2 'Port 1'"
done
```

**Configurar timeout do NCCL para que jobs falhem rápido em vez de travar:**

```python
import datetime
import torch.distributed as dist

dist.init_process_group(
    backend="nccl",
    timeout=datetime.timedelta(minutes=10)  # Falhar após 10 min, não para sempre
)
```

**Remover o nó com falha e reiniciar do checkpoint:**

```bash
# Reiniciar com 3 nós, carregando do último checkpoint
torchrun --nproc_per_node=8 --nnodes=3 --node_rank=0 \
  train.py --resume_from_checkpoint ./checkpoints/step-15000/
```

### Prevenção

- **Execute health checks de InfiniBand pré-job** antes de iniciar treinamento multi-nó:

```bash
#!/bin/bash
# ib-health-check.sh — Executar em cada nó antes do treinamento
IB_STATE=$(ibstat | grep "State:" | head -1 | awk '{print $2}')
if [ "$IB_STATE" != "Active" ]; then
    echo "FAIL: InfiniBand not active on $(hostname)"
    exit 1
fi
echo "PASS: InfiniBand active on $(hostname)"
```

- **Configure `NCCL_TIMEOUT`** para um valor razoável (5–10 minutos) para que jobs travados falhem com erros acionáveis em vez de bloquear silenciosamente.
- **Faça checkpoint frequentemente** — a cada 15–30 minutos para jobs grandes. O custo de escrever um checkpoint é negligível comparado a perder horas de treinamento.
- **Use Azure CycleCloud ou job schedulers do AKS** que podem detectar nós não responsivos e reiniciar jobs automaticamente.

💡 **Dica Pro**: Se `ibstat` mostra `Active` mas o treinamento ainda trava, execute `ib_write_bw` entre pares de nós para testar a largura de banda real do InfiniBand. Um link pode estar "Active" mas degradado.

---

## Cenário 7: Container de Model Serving em Crash Loop

### Sintomas

Seu pod de inferência reinicia a cada 2–3 minutos:

```bash
$ kubectl get pods -n inference
NAME                        READY   STATUS             RESTARTS   AGE
model-serve-abc-12345       0/1     CrashLoopBackOff   7          14m
```

### Diagnóstico

Verifique o motivo da última terminação:

```bash
$ kubectl describe pod model-serve-abc-12345 -n inference | grep -A 10 "Last State"
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Mon, 15 Jul 2024 08:10:03 +0000
      Finished:     Mon, 15 Jul 2024 08:12:47 +0000
```

`OOMKilled` com exit code 137 significa que o OOM killer do kernel Linux terminou o processo porque ele excedeu o limite de memória do container.

Verifique o limite de memória do container vs. necessidades reais:

```bash
$ kubectl get pod model-serve-abc-12345 -n inference \
  -o jsonpath='{.spec.containers[0].resources}' | jq .
{
  "limits": {
    "memory": "16Gi",
    "nvidia.com/gpu": "1"
  },
  "requests": {
    "memory": "8Gi",
    "nvidia.com/gpu": "1"
  }
}
```

Um modelo de 7B parâmetros em FP16 tem ~14 GB em disco. Mas carregá-lo requer RAM de CPU primeiro — os pesos do modelo são lidos na memória de CPU antes de serem transferidos para a memória da GPU. Com um limite de 16 GB, não há margem.

### Causa Raiz

Três causas comuns para crash loops de model serving:

1. **Limite de memória muito baixo**: O carregamento do modelo usa RAM de CPU como área de staging. Um modelo de 14 GB precisa de ~28 GB de RAM de CPU durante o carregamento (leitura do arquivo + desserialização dos tensores). O limite de 16 GB dispara o OOMKilled.
2. **Arquivo de modelo corrompido**: Um download incompleto do Blob Storage produz um arquivo de modelo truncado. O código de carregamento crasha com um erro de desserialização.
3. **Dependências Python faltando**: A imagem do container está sem uma biblioteca que o modelo necessita (comum com arquiteturas de modelo customizadas).

Verifique os logs antes do OOMKilled:

```bash
$ kubectl logs model-serve-abc-12345 -n inference --previous
Loading model weights...
Loaded 48/64 shards [==========>          ] 75%
Killed
```

Carregamento em 75% confirma o OOMKilled — a RAM de CPU acabou antes de todos os shards serem carregados.

### Resolução

**Aumentar limites de memória** — defina pelo menos 2× o tamanho do arquivo de pesos do modelo:

```yaml
resources:
  requests:
    memory: "32Gi"        # Tamanho do modelo × 2 para overhead de carregamento
    nvidia.com/gpu: 1
  limits:
    memory: "32Gi"        # Definir igual ao requests para QoS Guaranteed
    nvidia.com/gpu: 1
```

**Para arquivos de modelo corrompidos:**

```bash
# Verificar integridade do arquivo do modelo
$ md5sum /models/model-7b.safetensors
$ az storage blob show --container-name models --name model-7b.safetensors \
  --account-name mystorageaccount --query "properties.contentMd5"
```

**Para dependências faltando:**

```bash
$ kubectl logs model-serve-abc-12345 -n inference --previous | tail -20
# Procure por ImportError, ModuleNotFoundError
```

### Prevenção

- **Defina `requests = limits`** para memória em todos os pods de inferência GPU. Isso garante a classe de QoS Guaranteed e impede que o kubelet defina um limite baixo de memória do cgroup.
- **Regra prática**: Limite de memória de CPU = tamanho do arquivo de pesos do modelo × 2. Isso contabiliza o overhead de carregamento onde os pesos existem tanto no buffer de arquivo quanto em formato tensor simultaneamente.
- **Teste containers localmente** com `docker run --memory=32g` antes de fazer deploy no Kubernetes.
- **Use o formato `safetensors`** em vez de formatos baseados em pickle. Safetensors suporta carregamento com memory-mapped, o que reduz drasticamente o pico de uso de RAM de CPU.

---

## Cenário 8: Esgotamento de Quota de GPU

### Sintomas

Seu deployment Terraform falha:

```
Error: creating Virtual Machine: compute.VirtualMachinesClient#CreateOrUpdate:
StatusCode=409 -- Original Error: Code="OperationNotAllowed"
Message="Operation could not be completed as it results in exceeding
approved Standard NDSv2 Family vCPUs Quota. Current usage: 96,
Additional Required: 40, (Effective) Limit: 96."
```

Ou via Azure CLI:

```bash
$ az vm create --resource-group myRG --name gpu-vm --image UbuntuLTS \
  --size Standard_ND40rs_v2
(OperationNotAllowed) Operation could not be completed as it results in
exceeding approved quota.
```

### Diagnóstico

Verifique o uso atual de quota de GPU:

```bash
$ az vm list-usage --location eastus -o table | grep -i "standard ND"
Name                          CurrentValue    Limit
----------------------------  --------------  ------
Standard NDSv2 Family vCPUs   96              96
Standard NDAMSv5 Family vCPUs 0               0

# Ver o que está consumindo a quota
$ az vm list -g myRG -o table --query "[?contains(hardwareProfile.vmSize,'ND')]"
Name          ResourceGroup    Location    VmSize
-----------   ---------------  ----------  ----------------------
train-node-0  myRG             eastus      Standard_ND40rs_v2
train-node-1  myRG             eastus      Standard_ND40rs_v2
dev-gpu-01    myRG             eastus      Standard_ND40rs_v2
```

Três VMs ND40rs_v2 × 40 vCPUs = 120 solicitadas, mas a quota é 96 — então duas estão rodando (80 vCPUs) e uma parcialmente alocada. A terceira VM e quaisquer novas vão falhar.

### Causa Raiz

Quotas de GPU no Azure são por subscription, por região, por família de VM. Quotas padrão para famílias de GPU são tipicamente **0** — você deve solicitar aumentos explicitamente. Razões comuns para esgotamento:

- VMs rodando que deveriam ter sido desalocadas (VMs de dev/test esquecidas)
- Múltiplos times fazendo deploy na mesma subscription sem coordenação
- Solicitando uma família de VM que você nunca usou antes (quota = 0)

### Resolução

**Imediato — desalocar VMs de GPU não utilizadas:**

```bash
# Encontrar VMs paradas-mas-ainda-alocadas (estas consomem quota!)
$ az vm list -g myRG --show-details -o table \
  --query "[?powerState!='VM deallocated' && contains(hardwareProfile.vmSize,'ND')]"

# Desalocar (não apenas parar)
$ az vm deallocate --resource-group myRG --name dev-gpu-01
```

⚠️ **Gotcha de Produção**: `az vm stop` mantém a VM alocada — ela ainda consome quota e você ainda paga pelo compute. Somente `az vm deallocate` libera os recursos.

**Solicitar aumento de quota:**

```bash
az quota create \
  --resource-name "StandardNDSv2Family" \
  --scope "/subscriptions/{sub-id}/providers/Microsoft.Compute/locations/eastus" \
  --limit-object value=192 limit-object-type=LimitValue \
  --resource-type "dedicated"
```

Aumentos de quota para VMs de GPU podem levar de 1 a 5 dias úteis. Planeje com antecedência.

**Tente uma região diferente** se você precisa de capacidade imediatamente:

```bash
$ az vm list-skus --location westus2 --size Standard_ND40rs_v2 \
  --query "[].{Name:name, Restrictions:restrictions}" -o table
```

### Prevenção

- **Construa um dashboard de monitoramento de quota de GPU** no Azure Monitor. Acompanhe a razão `CurrentValue / Limit` por família de VM por região.
- **Configure alertas a 80% de uso da quota** para ter tempo de solicitar aumentos antes de bater no limite.
- **Adicione verificações de quota pré-deploy nos pipelines de IaC**:

```bash
#!/bin/bash
# pre-deploy-check.sh
REQUIRED_VCPUS=40
CURRENT=$(az vm list-usage -l eastus --query \
  "[?name.value=='standardNDSv2Family'].currentValue" -o tsv)
LIMIT=$(az vm list-usage -l eastus --query \
  "[?name.value=='standardNDSv2Family'].limit" -o tsv)
AVAILABLE=$((LIMIT - CURRENT))

if [ "$AVAILABLE" -lt "$REQUIRED_VCPUS" ]; then
    echo "FAIL: Need $REQUIRED_VCPUS vCPUs, only $AVAILABLE available"
    exit 1
fi
echo "PASS: $AVAILABLE vCPUs available"
```

- **Marque VMs de GPU com datas de expiração** e automatize a desalocação de recursos expirados.

---

## Cenário 9: Falhas na Montagem do BlobFuse2

### Sintomas

Um job de treinamento inicia mas não encontra seu dataset:

```
FileNotFoundError: [Errno 2] No such file or directory: '/mnt/data/training/dataset.parquet'
```

O ponto de montagem existe mas está vazio:

```bash
$ ls /mnt/data/
# (vazio)

$ mount | grep blobfuse
# (sem saída — a montagem falhou silenciosamente)
```

### Diagnóstico

Verifique os logs do BlobFuse2:

```bash
$ journalctl -u blobfuse2-mount.service --since "1 hour ago"
blobfuse2[1234]: Error: Failed to authenticate. StatusCode=403
AuthorizationFailure. This request is not authorized to perform
this operation using this permission.

# Ou verifique diretamente se executou manualmente
$ blobfuse2 mount /mnt/data --config-file=/etc/blobfuse2/config.yaml 2>&1
Error: authorization failure: identity not authorized
```

Verifique a atribuição de managed identity:

```bash
$ az vm identity show --resource-group myRG --name gpu-vm-01
{
  "type": "UserAssigned",
  "userAssignedIdentities": {
    "/subscriptions/.../my-ml-identity": { ... }
  }
}

# Verificar RBAC na conta de armazenamento
$ az role assignment list --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/mldatastorage" \
  --query "[?principalName=='my-ml-identity'].{Role:roleDefinitionName}" -o table
# (vazio — sem atribuição de role!)
```

### Causa Raiz

Duas causas principais:

1. **RBAC faltando**: A managed identity da VM não recebeu a role `Storage Blob Data Reader` na conta de armazenamento. A identidade existe, mas não tem permissões para ler blobs.
2. **Firewall do storage bloqueando**: As regras de rede da conta de armazenamento estão definidas como "Redes selecionadas" e a VNet/subnet da VM não está na lista de permitidos.

Verifique o firewall:

```bash
$ az storage account show --name mldatastorage --resource-group myRG \
  --query "networkRuleSet.defaultAction"
"Deny"

$ az storage account network-rule list --account-name mldatastorage \
  --query "virtualNetworkRules[].virtualNetworkResourceId" -o table
# Subnet da VM não listada
```

### Resolução

**Corrigir RBAC:**

```bash
# Obter o principal ID da managed identity
PRINCIPAL_ID=$(az identity show --name my-ml-identity --resource-group myRG \
  --query principalId -o tsv)

# Atribuir Storage Blob Data Reader
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/mldatastorage"
```

**Corrigir firewall do storage:**

```bash
az storage account network-rule add \
  --account-name mldatastorage \
  --resource-group myRG \
  --vnet-name ml-vnet \
  --subnet gpu-subnet
```

Depois remonte:

```bash
$ blobfuse2 mount /mnt/data --config-file=/etc/blobfuse2/config.yaml
$ ls /mnt/data/training/
dataset.parquet  validation.parquet
```

### Prevenção

- **Provisione storage + RBAC juntos no IaC.** Nunca crie uma conta de armazenamento sem também criar a atribuição de role no mesmo template:

```hcl
# Exemplo Terraform — storage + RBAC em um módulo
resource "azurerm_role_assignment" "ml_storage_reader" {
  scope                = azurerm_storage_account.ml_data.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.ml_identity.principal_id
}
```

- **Inclua regras de VNet no Terraform** para que as regras de firewall do storage estejam sempre sincronizadas com a topologia de rede.
- **Teste montagens no CI** — adicione uma etapa no pipeline que monta o storage e verifica o acesso aos arquivos antes de fazer deploy de jobs de treinamento.

💡 **Dica Pro**: Atribuições de role RBAC podem levar até 10 minutos para propagar. Se você acabou de criar a atribuição e a montagem ainda falha, espere e tente novamente. Não comece a adicionar storage keys como workaround.

---

## Cenário 10: Degradação da Qualidade do Modelo em Produção

### Sintomas

Nenhum alarme de infraestrutura disparou. Nenhum deploy aconteceu. Mas o time de produto reporta que a qualidade das saídas de IA degradou visivelmente:

- Scores de satisfação do cliente caíram 15% ao longo de duas semanas
- Revisões internas de qualidade mostram o modelo produzindo respostas menos relevantes
- Taxas de erro não mudaram — o modelo responde, só responde mal

### Diagnóstico

Este é o cenário mais difícil porque as métricas de infraestrutura parecem perfeitamente normais. Você precisa trabalhar com o time de ML para rastrear o problema:

**Passo 1 — Verificar a versão do modelo:**

```bash
# Verificar qual versão do modelo está realmente servindo
$ kubectl get deployment model-serve -n inference \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
myregistry.azurecr.io/llm-serve:v2.3.1

# Comparar com a versão esperada
$ az acr repository show-tags --name myregistry --repository llm-serve --top 5 -o table
```

**Passo 2 — Verificar o pipeline de dados:**

```bash
# Quando o dataset de treinamento foi atualizado pela última vez?
$ az storage blob show --container-name datasets --name training-data.parquet \
  --account-name mldatastorage \
  --query "properties.lastModified"
"2024-05-15T08:00:00+00:00"   # 2 meses desatualizado
```

**Passo 3 — Comparar saídas atuais vs. baseline:**

Execute os mesmos prompts de avaliação no modelo de produção e compare contra respostas de baseline conhecidas como boas. Use métricas de avaliação automatizadas (BLEU, ROUGE, ou LLM-as-judge) para quantificar a diferença.

### Causa Raiz

Três causas comuns:

1. **Data drift**: Consultas em produção mudaram em tópico, estilo ou complexidade desde que o modelo foi treinado. Os dados de treinamento do modelo não representam mais o que os usuários realmente perguntam.
2. **Versão errada do modelo**: Um rollback ou pipeline de CI/CD mal configurado fez deploy de uma versão mais antiga e menos capaz do modelo.
3. **Mudança na API upstream**: Para arquiteturas RAG (retrieval-augmented generation), a API de busca ou o modelo de embedding mudou seu formato de resposta, quebrando o pipeline de recuperação silenciosamente.

### Resolução

- **Data drift**: Retreine ou faça fine-tune em um dataset atualizado que inclua consultas recentes de produção (com controles de privacidade apropriados).
- **Versão errada do modelo**: Corrija o manifesto de deployment e faça redeploy da versão correta.
- **Mudança na API upstream**: Audite todo o pipeline de inferência — modelo de embedding, índice de busca, template de prompt e modelo de serving — para incompatibilidades de versão.

### Prevenção

- **Monitoramento automatizado de qualidade do modelo**: Execute um conjunto de prompts de avaliação em um cronograma (diário ou semanal) e alerte quando os scores caírem abaixo de um limiar.
- **Testes A/B para atualizações de modelo**: Nunca substitua um modelo de produção por completo. Direcione 5–10% do tráfego para a nova versão e compare métricas antes da troca completa.
- **Detecção de data drift**: Monitore a distribuição estatística das consultas recebidas vs. dados de treinamento. Ferramentas como o monitor de data drift do Azure Machine Learning podem automatizar isso.
- **Fixação de versão nos manifestos de deployment**: Use tags de imagem imutáveis (nunca `latest`) e rastreie versões do modelo no seu pipeline de deployment.

⚠️ **Gotcha de Produção**: Degradação de qualidade é o único problema de produção nesta lista onde todas as métricas de infraestrutura estão verdes. Utilização de GPU está normal. Latência está normal. Taxas de erro estão normais. O modelo está apenas produzindo saídas ruins com confiança. É por isso que monitoramento de qualidade do modelo é separado do monitoramento de infraestrutura — e igualmente importante.

---

## Referência Rápida: Cheatsheet de Comandos de Diagnóstico

### Diagnósticos de GPU

| Comando | O que Mostra |
|---|---|
| `nvidia-smi` | Utilização da GPU, memória, temperatura, processos em execução |
| `nvidia-smi -l 2` | Monitoramento contínuo da GPU (a cada 2 segundos) |
| `nvidia-smi topo -m` | Topologia de interconexão GPU-para-GPU (NVLink vs. PCIe) |
| `nvidia-smi --query-gpu=timestamp,memory.used,memory.free,utilization.gpu,temperature.gpu --format=csv -l 5` | Saída de métricas estruturadas para logging |
| `dmesg \| grep -i nvidia` | Mensagens do kernel sobre carregamento do driver NVIDIA |
| `ibstat` | Estado da porta InfiniBand, velocidade do link, status físico |
| `ib_write_bw` | Teste de largura de banda InfiniBand entre pares de nós |
| `dcgmi diag -r 3` | Diagnóstico completo do NVIDIA DCGM (stress test + health check) |

### Diagnósticos de GPU no Kubernetes

| Comando | O que Mostra |
|---|---|
| `kubectl get pods -o wide` | Status do pod, posicionamento no nó, restarts |
| `kubectl describe pod <name>` | Eventos, falhas de agendamento, motivos de OOMKilled |
| `kubectl logs <pod> --previous` | Logs do último container que crashou |
| `kubectl get nodes -l accelerator=nvidia` | Nós com capacidade de GPU |
| `kubectl top nodes` | Utilização de CPU/memória dos nós |
| `kubectl get events --sort-by=.lastTimestamp` | Eventos recentes do cluster |
| `kubectl describe node <name> \| grep nvidia.com/gpu` | Capacidade e alocável de GPU em um nó |

### Diagnósticos de Recursos Azure

| Comando | O que Mostra |
|---|---|
| `az vm list-usage --location <region> -o table` | Uso de quota de vCPU por família de VM |
| `az vm get-instance-view --name <vm> -g <rg>` | Estado de energia da VM, status das extensões |
| `az aks nodepool show --cluster-name <aks> -g <rg> -n <pool>` | Tamanho do node pool, configuração do autoscaler |
| `az monitor metrics list --resource <id> --metric <name>` | Métricas do Azure Monitor para qualquer recurso |
| `az storage account show --name <acct> --query networkRuleSet` | Configuração de firewall do storage |
| `az cognitiveservices account deployment show --name <acct> -g <rg> --deployment-name <dep>` | Configuração do deployment OpenAI e rate limits |

### Storage e Conectividade

| Comando | O que Mostra |
|---|---|
| `blobfuse2 mount <path> --config-file=<cfg>` | Montar Azure Blob Storage |
| `journalctl -u blobfuse2-mount.service` | Logs do serviço de montagem BlobFuse2 |
| `az role assignment list --scope <resource-id>` | Roles RBAC em um recurso |
| `az storage account network-rule list --account-name <acct>` | Regras de VNet do firewall do storage |

---

## Checklist do Capítulo

Antes de fechar este capítulo, certifique-se de que você tem:

- **Monitoramento de driver GPU** ativo — alertas em falhas do `nvidia-smi`, não apenas utilização de GPU
- **Fixação de kernel** configurada em VMs de GPU para prevenir quebras por atualizações automáticas
- **Cálculos de memória** feitos antes de jobs de treinamento começarem — use a fórmula do Capítulo 4
- **Templates de pods GPU** com tolerations `sku=gpu:NoSchedule` corretos como padrão
- **Exponential backoff com jitter** implementado em todo código cliente do Azure OpenAI
- **Readiness probes** com `initialDelaySeconds` adequado em containers de model serving
- **Timeout do NCCL** configurado para jobs de treinamento distribuído (não deixe travamentos rodarem para sempre)
- **Limites de memória de container** definidos como 2× o tamanho dos pesos do modelo para pods de inferência
- **Monitoramento de quota de GPU** com alertas a 80% de uso por família de VM por região
- **RBAC de storage e regras de firewall** provisionados junto com contas de armazenamento no IaC
- **Monitoramento de qualidade do modelo** separado do monitoramento de infraestrutura
- **Frequência de checkpoint** definida para treinamento distribuído (mínimo a cada 15–30 minutos)

---

## Próximos Passos

Esses cenários cobrem as falhas de produção mais comuns em infraestrutura de IA. Mas troubleshooting é reativo — você está corrigindo coisas depois que elas quebram. E quanto à IA proativa?

O Capítulo 13 mostra como você pode aplicar IA ao seu próprio trabalho de infraestrutura: detecção preditiva de falhas, análise de anomalias em logs e copilots de operações que ajudam a diagnosticar problemas antes que os usuários percebam. As mesmas capacidades de IA para as quais você vem construindo infraestrutura? Elas podem trabalhar *para* você também.
