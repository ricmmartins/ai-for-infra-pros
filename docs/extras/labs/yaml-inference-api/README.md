# Lab: Deploying an inference API using Azure Machine Learning (YAML-based)

## Objective
This lab walks you through deploying a **machine learning model as an inference endpoint** using **Azure Machine Learning (AML)** via a YAML configuration file.

You’ll deploy a simple example model (such as scikit-learn diabetes regression) and expose it securely as an HTTPS endpoint.

## Prerequisites
Before starting, make sure you have:

- ✅ [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- ✅ Azure CLI ML extension installed:
  ```bash
  az extension add -n ml -y
  ```
- ✅ An **Azure Machine Learning Workspace**
- ✅ A registered model in the workspace (you can use the sample `sklearn-diabetes`)
- ✅ Python 3.9+ and the `azureml` SDK if testing locally
- ✅ Proper RBAC permissions for AML deployments

## Folder structure
```
yaml-inference-api/
├── endpoint.yml
├── score.py
├── requirements.txt
└── README.md
```

## 1. endpoint.yml — YAML Configuration for the endpoint

```yaml
name: infer-demo
auth_mode: key
traffic:
  blue: 100
deployments:
  - name: blue
    model: azureml:sklearn-diabetes:1
    instance_type: Standard_DS2_v2
    code_configuration:
      code: ./src
      scoring_script: score.py
```

**Explanation**
| Field | Description |
|--------|-------------|
| `name` | The name of your endpoint (unique per workspace) |
| `auth_mode` | Authentication mode (`key` or `aml_token`) |
| `deployments` | List of model versions and configurations |
| `model` | Reference to a registered model in your AML workspace |
| `instance_type` | VM SKU used to run the endpoint |
| `scoring_script` | The Python file that defines the inference logic |


## 2. score.py — Inference logic

Example `score.py`:

```python
import json
import joblib
import numpy as np
from azureml.core.model import Model

def init():
    global model
    model_path = Model.get_model_path("sklearn-diabetes")
    model = joblib.load(model_path)

def run(raw_data):
    try:
        data = np.array(json.loads(raw_data)["data"])
        result = model.predict(data)
        return result.tolist()
    except Exception as e:
        return json.dumps({"error": str(e)})
```

## 3. requirements.txt — Dependencies

```text
numpy
scikit-learn
joblib
azureml-core
```

## Deployment steps

### Step 1: Log in and set workspace
```bash
az login
az account set --subscription "<your-subscription-id>"
az configure --defaults group=<your-rg> workspace=<your-workspace>
```

### Step 2: Create the online endpoint
```bash
az ml online-endpoint create --name infer-demo --file endpoint.yml
```

### Step 3: Test the endpoint
Once the deployment finishes, you can test the API with:

```bash
az ml online-endpoint invoke \
  --name infer-demo \
  --request-file sample.json
```

Example `sample.json`:

```json
{
  "data": [[0.038075906, 0.05068012, 0.06169621, 0.02187235, -0.0442235, -0.03482076, -0.04340085, -0.00259226, 0.01990749, -0.01764613]]
}
```

✅ **Expected output:**  
A JSON response with numeric predictions.

## Security options
- Use `auth_mode: aml_token` to integrate with Azure Active Directory  
- Add **Private Endpoint** for network isolation  
- Configure **Managed Identity** for secure access to other services (like Blob Storage)

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Endpoint fails to start | Check model dependencies in `requirements.txt` |
| `HTTP 401 Unauthorized` | Verify endpoint `auth_mode` and key/token |
| Slow inference | Try using a GPU-based SKU like `Standard_NC6s_v3` |
| Endpoint timeout | Increase timeout in AML or optimize model loading |

## Cleanup
To remove the endpoint and resources:
```bash
az ml online-endpoint delete --name infer-demo --yes
```

## References
- [Azure ML Online Endpoints Documentation](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-deploy-online-endpoints)
- [YAML Schema Reference](https://learn.microsoft.com/en-us/azure/machine-learning/reference-yaml-endpoint)
- [Azure ML CLI v2](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-configure-cli)

