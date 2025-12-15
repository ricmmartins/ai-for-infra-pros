import json
import os
import joblib
import numpy as np

MODEL = None

def init():
    # Azure ML mounts registered model(s) under AZUREML_MODEL_DIR
    global MODEL
    model_dir = os.environ.get("AZUREML_MODEL_DIR", ".")
    model_path = os.path.join(model_dir, "model.pkl")
    MODEL = joblib.load(model_path)

def run(raw_data):
    try:
        payload = json.loads(raw_data)
        data = np.array(payload["data"], dtype=float)
        preds = MODEL.predict(data)
        return preds.tolist()
    except Exception as e:
        return {"error": str(e)}
