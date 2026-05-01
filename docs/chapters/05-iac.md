# Capítulo 5 — Infrastructure as Code para IA

*"Se você não consegue destruir e reconstruir todo o seu ambiente de IA com um único comando, você não é dono dele — ele é dono de você."*

---

## O Erro de Digitação de US$ 4.000

Começou como uma vitória. Você provisionou manualmente um cluster GPU em East US 2 para um experimento de ML — um cluster AKS com um node pool Standard_NC6s_v3, rede acelerada, os drivers NVIDIA corretos, taints configurados. Levou quase um dia inteiro, mas funcionou. O job de treinamento rodou, o time ficou feliz e você seguiu em frente.

Três semanas depois, o mesmo time precisa de uma configuração idêntica em West US 3. Sem problema, você pensa. Abre o portal do Azure e começa a clicar. Consulta uma thread no Slack para o SKU da VM, uma página na wiki para a configuração de rede, e a própria memória para o resto. Dois dias depois, está "pronto."

Só que não está. Alguém digitou o SKU da VM errado. Em vez de `Standard_NC6s_v3` (uma VM com GPU a cerca de US$ 3,80/h), o node pool está rodando `Standard_D16s_v5` — uma VM de propósito geral com CPU, sem GPU alguma. O job de treinamento inicia, não encontra nenhum dispositivo CUDA, faz fallback para CPU e avança a uma fração da velocidade esperada. Ninguém percebe por três dias porque o job não falha — ele apenas roda devagar. Quando alguém finalmente verifica, o cluster já consumiu US$ 4.000 em computação numa VM que não consegue fazer a única coisa para a qual foi provisionada.

Essa foi a última vez que provisionei infraestrutura de IA manualmente. A lição não era que pessoas cometem erros de digitação. A lição era que a infraestrutura de IA é cara demais, complexa demais e importante demais para viver na cabeça de alguém. Ela precisa viver em código.

---

## Por Que IaC É Inegociável para IA

Infrastructure as Code não é um "seria legal ter" para workloads de IA. É um mecanismo de sobrevivência. Aplicações web tradicionais são tolerantes — um App Service mal configurado pode custar uns US$ 50/mês a mais. Um cluster GPU mal configurado custa milhares por dia.

### Complexidade

Ambientes de IA têm mais partes móveis do que quase qualquer outro padrão de infraestrutura. Você gerencia cotas de GPU que variam por região e subscription. Lida com versões de driver que precisam corresponder a toolkits CUDA específicos. Configura node pools com taints e tolerations para que workloads GPU caiam no hardware certo. Configura rede acelerada, InfiniBand para treinamento multi-nó, discos NVMe efêmeros para armazenamento de checkpoints, e private endpoints para registries de modelos. Nenhum ser humano consegue manter tudo isso na cabeça de forma confiável.

### Custo

Uma única VM NVIDIA A100 (`Standard_NC24ads_A100_v4`) custa aproximadamente US$ 3,67/h. Um cluster de treinamento com quatro nós custa cerca de US$ 14,68/h — mais de US$ 350/dia. Nessas taxas, cada minuto de configuração incorreta é dinheiro queimando. IaC permite que você provisione exatamente o que precisa, quando precisa, e destrua tudo no momento em que terminar. Essa disciplina é a diferença entre uma conta de GPU gerenciável e uma surpresa que estoura o orçamento.

### Reprodutibilidade

Experimentos de machine learning precisam ser repetíveis. Se um modelo atinge uma acurácia excepcional numa terça-feira, o time precisa saber que consegue recriar exatamente a mesma infraestrutura numa quarta-feira. Mesmo SKU de VM, mesma versão do driver, mesma topologia de rede, mesma configuração de storage. IaC torna isso trivial — você executa o mesmo código e obtém o mesmo ambiente, sempre.

### Conformidade e Auditabilidade

Setores regulados precisam saber quem mudou o quê, quando e por quê. Quando sua infraestrutura é definida em código e armazenada no Git, você ganha essa trilha de auditoria de graça. Cada mudança é um pull request. Cada pull request tem um revisor. Cada deploy é rastreável até um commit hash. Tente conseguir isso a partir de uma sessão no portal.

**Infra ↔ IA — Tradução**: Quando um engenheiro de ML diz "preciso do mesmo ambiente do experimento da semana passada", ele está pedindo reprodutibilidade de infraestrutura. Quando um auditor de conformidade diz "me mostre o que mudou", ele está pedindo uma trilha de auditoria. IaC responde a ambas as perguntas com o mesmo artefato: um arquivo de configuração versionado.

---

## O Panorama de IaC para IA

Nem toda ferramenta é ideal para todo trabalho. O espaço de infraestrutura de IA tem quatro abordagens principais, cada uma com pontos fortes distintos.

**Matriz de Decisão: Escolhendo Sua Ferramenta de IaC**

| Critério | Terraform | Bicep | Azure CLI | Pulumi |
|----------|-----------|-------|-----------|--------|
| **Paradigma** | Declarativo | Declarativo | Imperativo | Declarativo (código) |
| **Multi-cloud** | ✅ Sim | ❌ Somente Azure | ❌ Somente Azure | ✅ Sim |
| **Gerenciamento de estado** | Arquivo de state remoto | Nenhum (ARM gerencia) | Nenhum | Arquivo de state remoto |
| **Linguagem** | HCL | Bicep DSL | Bash/PowerShell | Python, TypeScript, Go, C# |
| **Curva de aprendizado** | Moderada | Baixa (usuários Azure) | Baixa | Moderada–Alta |
| **Ecossistema de módulos** | Massivo (Registry) | Em crescimento (módulos) | N/A | Em crescimento |
| **Suporte a IA/GPU** | Excelente | Excelente | Bom | Bom |
| **Melhor para** | Plataformas multi-cloud | Times Azure-native | Automação rápida | Times developer-first |

### Terraform

Terraform é o padrão da indústria para infraestrutura multi-cloud. Seu ecossistema de providers abrange Azure, AWS, GCP, Kubernetes, Helm e centenas de serviços SaaS. O gerenciamento de estado (quem é dono do quê) é explícito, o que é tanto um ponto forte quanto uma responsabilidade. Para organizações que executam workloads de IA em múltiplas nuvens — treinamento em GPUs Azure, serving em endpoints AWS — Terraform é a escolha natural.

### Bicep

Bicep é a linguagem de IaC nativa do Azure. Ela compila para ARM templates, não requer arquivo de state (o Azure Resource Manager rastreia o estado nativamente) e tem suporte de primeira classe para todo tipo de recurso Azure desde o primeiro dia de GA. Se sua infraestrutura de IA é 100% Azure, Bicep oferece a sintaxe mais limpa e a integração mais estreita. Sem arquivo de state significa sem dores de cabeça com state locking, sem storage account para gerenciar e sem risco de corrupção de estado.

### Azure CLI

O Azure CLI é imperativo — você diz exatamente o que fazer, passo a passo. É excelente para automação rápida, scripts ad-hoc e código de integração entre ferramentas declarativas. Não é a escolha certa para gerenciar infraestrutura complexa e com estado, mas é indispensável para tarefas como verificar cota de GPU, registrar features em preview ou executar deploys pontuais durante o desenvolvimento.

### Quando Usar Cada Uma

Use **Terraform** quando precisar de suporte multi-cloud, tiver um time de platform engineering ou estiver gerenciando infraestrutura em escala com múltiplos ambientes. Use **Bicep** quando for Azure-native e quiser o caminho mais simples para infraestrutura production-grade com o menor overhead operacional. Use **Azure CLI** como cola de automação, prototipagem e tarefas operacionais. Use **Pulumi** quando seu time preferir escrever infraestrutura na mesma linguagem do código da aplicação.

💡 **Dica**: Muitos times de produção usam mais de uma ferramenta. Um padrão comum é Terraform ou Bicep para provisionamento de infraestrutura, scripts Azure CLI para tarefas operacionais (verificação de cotas, registro de features) e GitHub Actions para orquestrar tudo.

---

## Terraform para Infraestrutura de IA

A força do Terraform é sua explicitude. Cada recurso, cada dependência, cada valor de configuração é visível no código. Para infraestrutura de IA — onde um único SKU errado pode custar milhares — essa explicitude é uma vantagem, não um peso.

### Configuração do Provider

Comece pelo bloco do provider. A versão `~> 4.0` do provider `azurerm` é a release major atual. Fixe-a para evitar surpresas.

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

### Variáveis

Parametrize tudo que muda entre ambientes. SKUs de GPU, regiões, contagem de nós — nada disso deve ser hardcoded.

```hcl
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus2"
}

variable "gpu_vm_size" {
  description = "VM SKU for GPU node pool"
  type        = string
  default     = "Standard_NC6s_v3"

  validation {
    condition     = can(regex("^Standard_N", var.gpu_vm_size))
    error_message = "GPU VM size must be an N-series SKU (e.g., Standard_NC6s_v3, Standard_NC24ads_A100_v4)."
  }
}

variable "gpu_max_nodes" {
  description = "Maximum number of GPU nodes for autoscaling"
  type        = number
  default     = 5
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}
```

💡 **Dica**: Aquele bloco `validation` em `gpu_vm_size` não é decorativo. Ele previne exatamente o erro da história de abertura — alguém especificando acidentalmente uma VM da série D ou E para um workload GPU. Pegue o erro no `terraform plan`, não na sua fatura da nuvem.

### Cluster AKS com Node Pool GPU

Esta é uma configuração AKS pronta para produção para workloads de IA. Inclui um node pool de sistema para serviços do cluster, um node pool GPU com autoscaling, taints adequados para evitar que workloads não-GPU caiam em nós caros, e labels para direcionamento de workloads.

```hcl
resource "azurerm_resource_group" "ai" {
  name     = "rg-ai-${var.environment}"
  location = var.location

  tags = {
    environment  = var.environment
    project      = "ai-platform"
    managed-by   = "terraform"
    cost-center  = "ml-engineering"
  }
}

resource "azurerm_kubernetes_cluster" "ai" {
  name                = "aks-ai-${var.environment}"
  location            = azurerm_resource_group.ai.location
  resource_group_name = azurerm_resource_group.ai.name
  dns_prefix          = "aks-ai-${var.environment}"
  kubernetes_version  = "1.30"

  default_node_pool {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    node_count          = 2
    os_disk_size_gb     = 128
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  tags = azurerm_resource_group.ai.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.ai.id
  vm_size               = var.gpu_vm_size
  mode                  = "User"
  os_disk_size_gb       = 256
  auto_scaling_enabled  = true
  min_count             = 0
  max_count             = var.gpu_max_nodes

  node_taints = [
    "sku=gpu:NoSchedule"
  ]

  node_labels = {
    "hardware"    = "gpu"
    "gpu-type"    = "nvidia"
    "workload"    = "ai"
  }

  tags = azurerm_resource_group.ai.tags
}
```

⚠️ **Atenção em Produção**: O taint `sku=gpu:NoSchedule` é crítico. Sem ele, o Kubernetes vai alocar tranquilamente seus DaemonSets de monitoramento, coletores de logs e outros workloads não-GPU nos seus nós GPU de US$ 3,80/h. O taint garante que apenas pods com uma toleration correspondente caiam no hardware GPU. Todo pod GPU no seu cluster deve incluir `tolerations: [{key: "sku", operator: "Equal", value: "gpu", effect: "NoSchedule"}]` na sua spec.

### Outputs

Exponha os valores que consumidores downstream precisam — configuração do kubectl, identidade do cluster e nome do resource group.

```hcl
output "kube_config" {
  value     = azurerm_kubernetes_cluster.ai.kube_config_raw
  sensitive = true
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.ai.name
}

output "cluster_identity" {
  value = azurerm_kubernetes_cluster.ai.identity[0].principal_id
}

output "resource_group_name" {
  value = azurerm_resource_group.ai.name
}
```

### State Remoto no Azure Storage

Nunca armazene o state do Terraform localmente para infraestrutura de IA. Um arquivo de state corrompido ou perdido para um cluster GPU significa que o Terraform não consegue rastrear — nem destruir — recursos que custam dinheiro real a cada hora que ficam rodando. Use Azure Storage com locking habilitado.

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "ai-platform.terraform.tfstate"
  }
}
```

```bash
# Criar o storage para state (configuração única)
az group create --name rg-terraform-state --location eastus2

az storage account create \
  --name stterraformstate \
  --resource-group rg-terraform-state \
  --sku Standard_LRS \
  --encryption-services blob

az storage container create \
  --name tfstate \
  --account-name stterraformstate
```

⚠️ **Atenção em Produção**: O state do Terraform para recursos GPU é uma preocupação de raio de explosão. Se dois engenheiros executam `terraform apply` simultaneamente contra o mesmo state, você pode acabar com nós GPU órfãos que nenhum arquivo de state conhece. O Azure Storage oferece leasing nativo de blob para state locking, mas você também deve impor disciplina de escritor único via CI/CD — apenas seu pipeline deve executar `apply`, nunca um humano diretamente.

---

## Bicep para Infraestrutura de IA

A vantagem do Bicep é a simplicidade. Sem arquivo de state para gerenciar, sem backend para configurar, sem locking para se preocupar. O Azure Resource Manager cuida de tudo. Para times que são 100% Azure, Bicep elimina uma categoria inteira de complexidade operacional.

### VM GPU com Extensão de Driver NVIDIA

Este template Bicep provisiona uma VM GPU e instala automaticamente os drivers NVIDIA via extensão de VM. Sem necessidade de SSH para configuração de drivers.

```bicep
@description('Name of the GPU virtual machine')
param vmName string = 'vm-gpu-ai'

@description('Azure region for deployment')
param location string = resourceGroup().location

@allowed([
  'Standard_NC6s_v3'
  'Standard_NC12s_v3'
  'Standard_NC24s_v3'
  'Standard_NC24ads_A100_v4'
  'Standard_NC48ads_A100_v4'
  'Standard_NC96ads_A100_v4'
])
@description('GPU VM size — must be an N-series SKU')
param vmSize string = 'Standard_NC6s_v3'

@description('Administrator username')
param adminUsername string = 'azureuser'

@secure()
@description('SSH public key for authentication')
param sshPublicKey string

var vnetName = '${vmName}-vnet'
var subnetName = '${vmName}-subnet'
var nsgName = '${vmName}-nsg'
var nicName = '${vmName}-nic'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.10.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 256
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
  tags: {
    environment: 'ai'
    'managed-by': 'bicep'
  }
}

resource nvidiaExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'NvidiaGpuDriverLinux'
  location: location
  properties: {
    publisher: 'Microsoft.HpcCompute'
    type: 'NvidiaGpuDriverLinux'
    typeHandlerVersion: '1.9'
    autoUpgradeMinorVersion: true
  }
}

output vmId string = vm.id
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
```

💡 **Dica**: O decorator `@allowed` em `vmSize` tem o mesmo propósito que o bloco `validation` do Terraform — ele impede que SKUs não-GPU sejam implantados. A extensão de driver NVIDIA (`Microsoft.HpcCompute/NvidiaGpuDriverLinux`) elimina a necessidade de acessar via SSH e instalar drivers manualmente, que era uma das etapas mais propensas a erros no antigo processo manual.

### Cluster AKS com Node Pool GPU (Bicep)

```bicep
@description('Name of the AKS cluster')
param clusterName string = 'aks-ai'

@description('Azure region')
param location string = resourceGroup().location

@description('GPU VM size for the AI node pool')
param gpuVmSize string = 'Standard_NC6s_v3'

@description('Maximum GPU nodes for autoscaling')
param gpuMaxCount int = 5

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-06-02-preview' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: '1.30'
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        vmSize: 'Standard_D4s_v5'
        count: 2
        osDiskSizeGB: 128
        osType: 'Linux'
      }
      {
        name: 'gpu'
        mode: 'User'
        vmSize: gpuVmSize
        minCount: 0
        maxCount: gpuMaxCount
        enableAutoScaling: true
        osDiskSizeGB: 256
        osType: 'Linux'
        nodeTaints: [
          'sku=gpu:NoSchedule'
        ]
        nodeLabels: {
          hardware: 'gpu'
          'gpu-type': 'nvidia'
        }
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
    }
  }
  tags: {
    environment: 'ai'
    'managed-by': 'bicep'
    'cost-center': 'ml-engineering'
  }
}

output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
```

### Padrão de Módulos para Infraestrutura de IA Reutilizável

Times de produção não escrevem arquivos Bicep monolíticos. Eles usam módulos — blocos de construção autocontidos e parametrizados que impõem padrões em toda a organização.

```
infra/
├── main.bicep              # Orquestrador
├── modules/
│   ├── network.bicep       # VNet, subnets, NSGs, private endpoints
│   ├── aks.bicep            # Cluster AKS com node pool GPU
│   ├── storage.bicep        # Storage account para modelos e dados
│   ├── monitoring.bicep     # Log Analytics, alertas, dashboards
│   └── keyvault.bicep       # Key Vault para secrets e certificados
└── parameters/
    ├── dev.bicepparam
    ├── staging.bicepparam
    └── prod.bicepparam
```

O arquivo orquestrador (`main.bicep`) conecta os módulos:

```bicep
targetScope = 'resourceGroup'

param environment string
param location string = resourceGroup().location

module network 'modules/network.bicep' = {
  name: 'network-${environment}'
  params: {
    location: location
    environment: environment
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks-${environment}'
  params: {
    location: location
    subnetId: network.outputs.aksSubnetId
    environment: environment
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-${environment}'
  params: {
    location: location
    environment: environment
  }
}
```

Esse padrão faz com que um novo time consiga criar um ambiente de IA completo e em conformidade apenas criando um único arquivo de parâmetros. Sem reinventar a roda. Sem esquecer o taint de GPU. Sem pular a configuração de monitoramento.

---

## Pipelines CI/CD para Infraestrutura de IA

Mudanças de infraestrutura em ambientes de IA nunca devem ser aplicadas a partir de um laptop. O risco é alto demais. Um pipeline CI/CD oferece portões de revisão, validação automatizada e uma trilha de auditoria para cada mudança.

### GitHub Actions com Autenticação OIDC

CI/CD moderno para Azure usa OpenID Connect (OIDC) — sem client secrets armazenados no GitHub. O workflow troca um token de curta duração com o Microsoft Entra ID em tempo de execução. Esta é a melhor prática atual.

```yaml
name: "AI Infrastructure — Plan & Apply"

on:
  push:
    branches: [main]
    paths: ["infra/**"]
  pull_request:
    branches: [main]
    paths: ["infra/**"]

permissions:
  id-token: write
  contents: read
  pull-requests: write

env:
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  TF_VERSION: "1.9.0"

jobs:
  plan:
    name: "Terraform Plan"
    runs-on: ubuntu-latest
    environment: ai-infrastructure
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        working-directory: infra
        run: terraform init

      - name: Terraform Plan
        working-directory: infra
        run: terraform plan -out=tfplan -input=false

      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: infra/tfplan

  apply:
    name: "Terraform Apply"
    runs-on: ubuntu-latest
    needs: plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment:
      name: ai-infrastructure-prod
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: infra

      - name: Terraform Init
        working-directory: infra
        run: terraform init

      - name: Terraform Apply
        working-directory: infra
        run: terraform apply -auto-approve tfplan
```

### O Padrão Plan → Approve → Apply

Este workflow implementa um padrão de segurança crítico para infraestrutura de IA:

1. **No pull request**: O Terraform executa apenas o `plan`. A saída do plan mostra exatamente o que vai mudar — novos nós GPU, regras de rede modificadas, recursos destruídos. Os revisores podem ver as implicações de custo antes que qualquer coisa aconteça.
2. **No merge para main**: O job de `apply` é executado, mas somente após passar por uma **regra de proteção de ambiente**. Este é um portão de aprovação nativo do GitHub onde revisores designados precisam aprovar explicitamente o deploy.
3. **Transferência de artefato**: O plan é salvo como artefato e consumido pelo job de apply. Isso garante que o plano exato que foi revisado é o plano que será aplicado — sem drift entre revisão e execução.

⚠️ **Atenção em Produção**: Sempre fixe as versões das suas actions. Use `actions/checkout@v4`, `hashicorp/setup-terraform@v3`, `azure/login@v2` e `actions/upload-artifact@v4`. Usar `@latest` ou `@main` em pipelines de produção significa que uma mudança upstream com breaking change pode derrubar seu deploy de infraestrutura no pior momento possível — como quando você precisa escalar nós GPU para um prazo apertado.

### Regras de Proteção de Ambiente

No GitHub, navegue até **Settings → Environments** e crie um ambiente chamado `ai-infrastructure-prod`. Configure-o com:

- **Revisores obrigatórios**: Pelo menos um engenheiro de infraestrutura deve aprovar
- **Timer de espera**: Atraso opcional (ex: 5 minutos) para revisão de última hora
- **Branches de deploy**: Restrinja apenas à `main` — sem deploys de feature branches para produção

Isso transforma seu pipeline CI/CD em um processo de deploy controlado, em vez de um script que dispara e esquece.

---

## Governança e Guardrails

Infraestrutura de IA sem guardrails é um centro de custos esperando para explodir. Governança garante que cada deploy atenda aos padrões organizacionais de nomenclatura, tagging, segurança e controle de custos.

### Azure Policy para Governança de GPU

O Azure Policy pode impor regras no nível de subscription ou management group. Para infraestrutura de IA, as políticas mais impactantes previnem estouros de custo e garantem conformidade.

```json
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Compute/virtualMachines"
        },
        {
          "field": "Microsoft.Compute/virtualMachines/sku.name",
          "in": [
            "Standard_NC24ads_A100_v4",
            "Standard_NC48ads_A100_v4",
            "Standard_NC96ads_A100_v4",
            "Standard_ND96asr_v4",
            "Standard_ND96amsr_A100_v4"
          ]
        },
        {
          "field": "tags['cost-center']",
          "exists": "false"
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  },
  "parameters": {}
}
```

Esta política nega a criação de VMs GPU de alto desempenho (A100, série ND) a menos que elas carreguem a tag `cost-center`. Sem tag, sem GPU. É uma regra simples que impede que clusters GPU "sombra" apareçam na sua fatura.

### Convenções de Nomenclatura para Recursos de IA

Nomenclatura consistente torna os recursos descobríveis, filtráveis e gerenciáveis em escala. Adote um padrão que codifique propósito, ambiente e região.

| Tipo de Recurso | Padrão | Exemplo |
|-----------------|--------|---------|
| Resource Group | `rg-{projeto}-{env}` | `rg-ai-platform-prod` |
| Cluster AKS | `aks-{projeto}-{env}` | `aks-ai-platform-prod` |
| Node Pool GPU | `gpu{workload}` | `gputraining` |
| Storage Account | `st{projeto}{env}{regiao}` | `staiprodeus2` |
| Key Vault | `kv-{projeto}-{env}` | `kv-ai-platform-prod` |
| Log Analytics | `log-{projeto}-{env}` | `log-ai-platform-prod` |

### Estratégia de Tagging

Todo recurso de IA deve carregar um conjunto mínimo de tags. Essas tags direcionam relatórios de custos, controle de acesso e gerenciamento de ciclo de vida.

```hcl
locals {
  required_tags = {
    environment  = var.environment          # dev, staging, prod
    project      = var.project_name         # ai-platform, ml-training
    team         = var.team_name            # ml-engineering, data-science
    cost-center  = var.cost_center          # rastreamento financeiro
    experiment   = var.experiment_id        # vincula infra ao experimento de ML
    managed-by   = "terraform"             # como este recurso foi criado
    created-date = formatdate("YYYY-MM-DD", timestamp())
  }
}
```

**Infra ↔ IA — Tradução**: A tag `experiment` faz a ponte entre infraestrutura e workflows de ML. Quando um cientista de dados pergunta "quanto custou o experimento X?", você consegue responder com uma única consulta no Azure Cost Management filtrada por essa tag. Sem ela, você fica correlacionando timestamps e resource groups manualmente.

### Registries de Módulos

Para organizações com múltiplos times fazendo deploy de infraestrutura de IA, um registry de módulos previne a proliferação de configurações. O Terraform suporta registries privados (Terraform Cloud, hospedado no Azure), e módulos Bicep podem ser publicados no Azure Container Registry.

```bash
# Publicar um módulo Bicep no Azure Container Registry
az bicep publish \
  --file modules/aks-gpu.bicep \
  --target br:myregistry.azurecr.io/bicep/modules/aks-gpu:v1.2.0
```

```bicep
// Consumir um módulo publicado
module aksGpu 'br:myregistry.azurecr.io/bicep/modules/aks-gpu:v1.2.0' = {
  name: 'aks-gpu-deployment'
  params: {
    location: location
    environment: environment
    gpuVmSize: 'Standard_NC6s_v3'
  }
}
```

Os times consomem módulos aprovados, testados e com versão fixada em vez de escrever os próprios. Isso garante que cada cluster GPU na organização tenha os taints corretos, as tags corretas, o monitoramento correto e a configuração de segurança correta.

---

## Mão na Massa: Deploy de um Cluster AKS GPU com Terraform

Esta seção percorre um deploy completo, de ponta a ponta. Cada comando é válido para produção. Cada arquivo é autocontido.

### Pré-requisitos

- Azure CLI instalado e autenticado (`az login`)
- Terraform >= 1.5 instalado
- Uma subscription Azure com cota de GPU na região desejada
- Um resource group para o state do Terraform (veja a seção State Remoto acima)

### Passo 1 — Verificar Cota de GPU

Antes de escrever uma única linha de Terraform, verifique se você tem cota de GPU. Nada é mais frustrante do que um plan perfeito que falha no apply.

```bash
az vm list-usage --location eastus2 \
  --query "[?contains(name.value, 'StandardNCSv3Family')]" \
  --output table
```

Se `CurrentValue` for igual a `Limit`, você precisa solicitar um aumento de cota antes de prosseguir.

### Passo 2 — Inicializar o Terraform

```bash
mkdir ai-gpu-cluster && cd ai-gpu-cluster
```

Crie o `main.tf` com as configurações de provider, resource group, cluster AKS e node pool GPU da seção Terraform acima. Em seguida, inicialize:

```bash
terraform init
```

Você deve ver `Terraform has been successfully initialized!` junto com a versão do provider sendo baixada.

### Passo 3 — Plan

```bash
terraform plan -out=tfplan
```

Revise a saída do plan com atenção. Você deve ver:

- 1 resource group
- 1 cluster AKS com um node pool de sistema
- 1 node pool GPU com autoscaling (0–5 nós), taint `sku=gpu:NoSchedule`

Verifique o SKU da VM na saída do plan. Esta é sua última chance de pegar um SKU errado antes que dinheiro real comece a ser gasto.

### Passo 4 — Apply

```bash
terraform apply tfplan
```

O provisionamento do AKS normalmente leva de 5 a 10 minutos. O node pool GPU pode levar de 2 a 3 minutos adicionais se estiver escalando a partir do zero.

### Passo 5 — Verificar

```bash
# Obter credenciais do cluster
az aks get-credentials \
  --resource-group rg-ai-dev \
  --name aks-ai-dev

# Verificar node pools
kubectl get nodes -L hardware

# Verificar taint de GPU
kubectl describe node <gpu-node-name> | grep Taints

# Verificar disponibilidade de GPU
kubectl get nodes -l hardware=gpu \
  -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'
```

Você deve ver o taint `sku=gpu:NoSchedule` nos nós GPU, e o recurso `nvidia.com/gpu` disponível nos recursos alocáveis do nó.

### Passo 6 — Limpeza

Quando o experimento terminar, destrua tudo. Este é um dos superpoderes do IaC — a destruição é tão controlada e repetível quanto a criação.

```bash
terraform destroy
```

Digite `yes` quando solicitado. O Terraform removerá todos os recursos em ordem reversa de dependência. Sem NICs órfãs, sem discos esquecidos, sem faturas surpresa no mês seguinte.

💡 **Dica**: Para ambientes de treinamento efêmeros, considere executar `terraform destroy` de forma agendada. Um workflow do GitHub Actions disparado por `schedule` (cron) pode destruir clusters GPU de desenvolvimento toda sexta-feira às 18h e recriá-los na segunda-feira às 8h. Só isso já pode reduzir custos de GPU em 65%.

---

## Checklist do Capítulo

Antes de seguir em frente, verifique se você pode responder "sim" a cada item:

- Toda a infraestrutura de IA está definida em código (Terraform ou Bicep) — sem recursos criados apenas pelo portal
- SKUs de VM GPU são validados nas definições de variáveis para evitar deploys sem GPU
- Node pools GPU do AKS usam o taint `sku=gpu:NoSchedule`
- O state do Terraform é armazenado remotamente no Azure Storage com locking habilitado
- Pipelines CI/CD usam autenticação OIDC — sem client secrets no GitHub
- O padrão plan → approve → apply é imposto com regras de proteção de ambiente
- O Azure Policy bloqueia VMs GPU sem as tags obrigatórias
- Todos os recursos seguem uma convenção de nomenclatura consistente
- Cada recurso carrega tags de environment, project, team, cost-center e experiment
- Módulos reutilizáveis são publicados em um registry para consumo entre times
- A cota de GPU é verificada antes do deploy
- A destruição é automatizada e testada — você consegue executar `terraform destroy` com confiança

---

## Próximos Passos

Sua infraestrutura agora é código — versionada, reprodutível e auditável. Cada cluster GPU, cada regra de rede, cada atribuição de RBAC vive em um repositório Git com histórico completo e trilhas de revisão. Você pode criar um ambiente idêntico em qualquer região com um único comando, e destruí-lo com a mesma facilidade.

Mas a infraestrutura é apenas a fundação. E os modelos que rodam em cima dela? Um cluster AKS perfeitamente provisionado não significa nada se o processo de deploy de modelos for manual, as imagens de container não forem escaneadas e não houver plano de rollback quando uma nova versão de modelo degradar a acurácia. O **Capítulo 6** cobre o ciclo de vida do modelo sob a perspectiva de infraestrutura: container registries, CI/CD para deploys de modelos, testes A/B na camada de infraestrutura e segurança da cadeia de suprimentos para os artefatos que rodam na sua plataforma cuidadosamente codificada.
