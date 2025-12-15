# Lab: Deploying an inference API using Azure Machine Learning (YAML-based)

## Objective
Deploy a **scikit-learn** model as a **Managed Online Endpoint** in **Azure Machine Learning (AML)** using **YAML + Azure ML CLI v2**.

You will:
1. Create or reuse an Azure ML workspace
2. Train a tiny model locally (diabetes regression), producing `model.pkl`
3. Register the model in Azure ML
4. Create a managed online endpoint
5. Create a deployment from YAML and send all traffic to it
6. Invoke the endpoint and validate results
7. Clean up

This lab is intentionally written step-by-step and assumes you are new to AML endpoints.

---

## Prerequisites
- Azure CLI installed
- Azure ML CLI extension installed:
  ```bash
  az extension add -n ml -y
  az extension update -n ml
  ```
- `kubectl` is not required
- Python 3.9+ locally
- RBAC: Contributor on the resource group, plus permissions for AML operations

References:
- Online endpoint YAML schema: https://learn.microsoft.com/azure/machine-learning/reference-yaml-endpoint-online?view=azureml-api-2 citeturn0search1
- Managed online deployment YAML schema: https://learn.microsoft.com/azure/machine-learning/reference-yaml-deployment-managed-online?view=azureml-api-2 citeturn0search0
- Azure ML inference server guidance: https://learn.microsoft.com/azure/machine-learning/how-to-inference-server-http?view=azureml-api-2 citeturn0search2

---

## Folder structure
```text
yaml-inference-api/
├── README.md
├── endpoint.yml
├── deployment.yml
├── environment.yml
├── score.py
├── requirements.txt
├── sample-request.json
└── train_model.py
```

---

## Step 0: Set defaults (subscription, RG, workspace)

```bash
az login
az account set --subscription "<your-subscription-id>"
```

Set defaults so you can omit `--resource-group` and `--workspace-name` later:
```bash
az configure --defaults group="<your-rg>" workspace="<your-aml-workspace>"
```

Quick sanity check:
```bash
az ml workspace show --query "{name:name,location:location}" -o json
```

---

## Step 1: Train a tiny sample model locally

Install deps:
```bash
python -m pip install -r requirements.txt
```

Train:
```bash
python train_model.py
```

Expected:
- `./model/model.pkl` is created

---

## Step 2: Register the model in Azure ML

```bash
az ml model create \
  --name sklearn-diabetes \
  --path ./model \
  --type custom_model \
  --description "Sklearn diabetes regression sample model for online endpoint lab"
```

Confirm:
```bash
az ml model list --query "[?name=='sklearn-diabetes'] | [0].{name:name,version:version}" -o table
```

---

## Step 3: Create the online endpoint

The endpoint YAML contains only endpoint-level settings (name, auth, identity). Deployments are created separately.

```bash
az ml online-endpoint create -f endpoint.yml
```

Wait until provisioning completes:
```bash
az ml online-endpoint show -n infer-demo --query "{name:name,provisioning:provisioning_state,auth:auth_mode}" -o table
```

---

## Step 4: Create the deployment and route traffic

```bash
az ml online-deployment create -f deployment.yml --all-traffic
```

Check status:
```bash
az ml online-deployment show \
  --name blue \
  --endpoint-name infer-demo \
  --query "{name:name,state:provisioning_state,instance_type:instance_type}" -o table
```

If it fails, get logs:
```bash
az ml online-deployment get-logs --name blue --endpoint-name infer-demo --lines 200
```

---

## Step 5: Invoke the endpoint

Get the scoring URI:
```bash
az ml online-endpoint show -n infer-demo --query scoring_uri -o tsv
```

Invoke via CLI (recommended for first test):
```bash
az ml online-endpoint invoke -n infer-demo --request-file sample-request.json
```

Expected output:
- JSON list of numeric predictions

---

## Step 6: Optional hardening (quick pointers)
- Switch to Entra-based auth (`aad_token`) for enterprise use cases (instead of `key`). citeturn0search10
- Add Private Link for private endpoints and lock down public access for production (not covered in this lab)
- Use managed identity for downstream access (Storage, Key Vault). citeturn0search17

---

## Cleanup

Delete deployment first (optional):
```bash
az ml online-deployment delete --name blue --endpoint-name infer-demo --yes
```

Delete endpoint:
```bash
az ml online-endpoint delete --name infer-demo --yes
```

Optionally delete the resource group:
```bash
az group delete --name <your-rg> --yes --no-wait
```

---

## Troubleshooting quick guide

### Endpoint created but deployment is stuck
- Check logs:
  ```bash
  az ml online-deployment get-logs --name blue --endpoint-name infer-demo --lines 200
  ```

### 401 Unauthorized
- If using `auth_mode: key`, fetch keys:
  ```bash
  az ml online-endpoint get-credentials -n infer-demo
  ```

### Import errors in scoring
- Ensure `environment.yml` and `requirements.txt` include your needed packages
- Prefer minimal requirements. Large environments slow down deployment startup. citeturn0search2
