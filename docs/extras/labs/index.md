# 🧪 Laboratórios de infraestrutura para IA

Bem-vindo à seção de **laboratórios práticos** do livro _AI for Infra Pros — The Practical Handbook for Infrastructure Engineers_.  
Cada laboratório demonstra como aplicar os conceitos de infraestrutura do livro em ambientes reais no Azure.

## Escopo e expectativas dos laboratórios

Estes laboratórios são **focados em infraestrutura** e projetados para:

- Provisionar ambientes com GPU  
- Fazer deploy de workloads prontos para inferência  
- Validar desempenho, acesso e observabilidade  

Eles **não** cobrem:

- Treinamento ou fine-tuning de modelos  
- Experimentação em ciência de dados  
- Pipelines avançados de MLOps  

O objetivo é ajudar engenheiros de infraestrutura a **executar workloads de IA** com confiança, não a construir modelos do zero.

## Índice dos laboratórios

| Laboratório | Descrição | Tecnologias |
|-----|--------------|---------------|
| [**Lab 1 — Bicep VM com GPU**](./bicep-vm-gpu/index.md) | Fazer deploy de uma VM com GPU usando Azure Bicep para hospedar workloads de inferência de IA. | Bicep, Azure CLI, NVIDIA Drivers |
| [**Lab 2 — Terraform AKS GPU Cluster**](./terraform-aks-gpu/index.md) | Provisionar um cluster Azure Kubernetes Service com um node pool dedicado com GPU para workloads de IA. | Terraform, AKS, GPU, IaC |
| [**Lab 3 — YAML Inference API (Azure ML)**](./yaml-inference-api/index.md) | Publicar um modelo treinado como endpoint de inferência usando Azure Machine Learning e configuração YAML. | Azure ML, YAML, CLI, REST API |

## Pré-requisitos

Antes de executar qualquer laboratório:

- Ter uma **Assinatura do Azure** ativa
- Instalar a versão mais recente do **Azure CLI**
- Instalar **Terraform** e/ou **Bicep** dependendo do laboratório
- Garantir que as cotas de GPU estejam disponíveis na região desejada  
  - SKUs comuns:
    - `Standard_NC4as_T4_v3` (T4 inferência)
    - `Standard_NC6s_v3` (V100)
  - Verifique as cotas com:
    ```bash
    az vm list-usage --location <your-target-region> --output table
    ```
- Instalar e atualizar a extensão Azure ML CLI:
  ```bash
  az extension add -n ml
  az extension update -n ml
  ```
  Testado com Azure CLI `>= 2.55.0`
- Autenticar-se no Azure:
  ```bash
  az login
  ```
- Ter permissões suficientes (**Owner** ou **Contributor** no Resource Group de destino)

## ⚠️ Aviso sobre custos

Estes laboratórios podem criar **recursos com GPU**, que podem gerar custos significativos se deixados em execução.

Sempre:

- Use o menor SKU de GPU possível  
- Conclua as etapas de validação rapidamente  
- Exclua os resource groups após finalizar  

Recursos com GPU podem custar **$0,90–$30+/hora** dependendo do SKU.

## Fluxo de trabalho dos laboratórios

Todos os laboratórios seguem uma estrutura similar:

1. **Provisionar** a infraestrutura (VM, AKS ou workspace AML)  
2. **Configurar** acesso, segurança e monitoramento  
3. **Fazer deploy** de modelos ou containers para inferência  
4. **Validar** desempenho e conectividade  
5. **Limpar** os recursos para evitar custos desnecessários  

## Recomendações

- Prefira **West US 3** ou **West Europe** — historicamente oferecem maior disponibilidade de SKUs de GPU, mas as cotas ainda se aplicam  
- Sempre **aplique tags** nos recursos com nomes de projeto e responsável  
- Armazene os logs de deploy para auditoria e rollback  
- Para deploys em nível de produção, adicione **Private Endpoints** e validação com **Azure Policy**  

## Lembrete de limpeza

Após finalizar um laboratório, lembre-se de excluir os recursos criados para evitar surpresas na cobrança:

```bash
az group delete --name <your-resource-group> --yes --no-wait
```

## Referências

- [Documentação do Azure Machine Learning](https://learn.microsoft.com/en-us/azure/machine-learning/)
- [Terraform no Azure](https://learn.microsoft.com/en-us/azure/developer/terraform/)
- [Referência da Linguagem Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Visão Geral da Infraestrutura de IA no Azure](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/overview)

> "Você não escala IA com PowerPoint — você escala com Infrastructure as Code."