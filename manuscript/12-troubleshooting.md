# Chapter 12 — The Production Troubleshooting Playbook

*"Everything works in staging. Production has opinions."*

---

## Keep This Chapter Bookmarked

This chapter is organized as a collection of real-world failure scenarios — the ones that generate 2 AM pages, derail sprint demos, and make you question your career choices. Each scenario follows the same format:

**Symptoms → Diagnosis → Root Cause → Resolution → Prevention**

These aren't hypothetical. They're distilled from hundreds of production incidents across GPU infrastructure, Kubernetes AI workloads, and Azure OpenAI deployments. Some you'll hit on your first day. Others will ambush you six months in, right when you think everything is stable.

Read through them once to build pattern recognition. Then keep this chapter bookmarked — you'll come back to it.

---

## Scenario 1: NVIDIA Driver Crash After Kernel Update

### Symptoms

Monday morning. The ML team reports that all GPU workloads failed over the weekend. Nobody deployed anything. You SSH into the VM and run:

```bash
$ nvidia-smi
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver.
Make sure that the latest NVIDIA driver is installed and running.
```

GPU containers won't start. Training jobs are dead. The VM itself is fine — CPU workloads run normally.

### Diagnosis

Start with the kernel ring buffer:

```bash
$ dmesg | grep -i nvidia
[    4.212] NIST: module nvidia not found in modules.dep

$ uname -r
6.5.0-44-generic

$ dpkg -l | grep nvidia-driver
ii  nvidia-driver-535    535.183.01-0ubuntu1    amd64
```

The NVIDIA driver is installed for a different kernel version. Check what happened:

```bash
$ cat /var/log/apt/history.log | grep -A 5 "linux-image"
Start-Date: 2024-07-13  06:25:11
Commandline: /usr/bin/unattended-upgrade
Install: linux-image-6.5.0-44-generic:amd64 (6.5.0-44.44~22.04.1)
```

### Root Cause

Ubuntu's `unattended-upgrades` service automatically installed a new kernel version. The NVIDIA kernel module is compiled against a specific kernel. When the VM rebooted into the new kernel, there was no matching NVIDIA module — the driver silently broke.

### Resolution

**Option A — Reinstall the driver extension (Azure VMs):**

```bash
az vm extension set \
  --resource-group myRG \
  --vm-name myGPUVM \
  --name NvidiaGpuDriverLinux \
  --publisher Microsoft.HKS \
  --version 1.9
```

This rebuilds the kernel module against the current kernel.

**Option B — Pin the kernel version:**

```bash
sudo apt-mark hold linux-image-$(uname -r) linux-headers-$(uname -r)
```

Then reinstall the driver for the current kernel:

```bash
sudo apt install --reinstall nvidia-driver-535
sudo reboot
```

### Prevention

- **Disable unattended kernel upgrades** on all GPU VMs. Add to `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Package-Blacklist {
    "linux-image";
    "linux-headers";
    "linux-modules";
};
```

- **Use the Azure NVIDIA GPU Driver Extension** for driver lifecycle management instead of manual installs. The extension handles kernel compatibility automatically.
- **Pin kernel versions** in your IaC templates and treat kernel upgrades as planned maintenance events.

**Production Gotcha**: This failure is completely silent. The VM boots normally, passes health checks, and responds to SSH. Only GPU workloads fail. If you don't monitor `nvidia-smi` output, you won't know until users complain.

---

## Scenario 2: CUDA Out of Memory During Fine-Tuning

### Symptoms

A fine-tuning job starts successfully, runs for 10–30 minutes, then crashes:

```
RuntimeError: CUDA out of memory. Tried to allocate 2.00 GiB
(GPU 0; 79.15 GiB total capacity; 77.42 GiB already allocated;
1.08 GiB free; 78.50 GiB reserved in total by PyTorch)
```

The team is confused: "It worked fine for the first 500 steps."

### Diagnosis

Monitor GPU memory over time:

```bash
# Snapshot
$ nvidia-smi

# Continuous monitoring (every 1 second)
$ watch -n 1 nvidia-smi

# Log memory usage to CSV for analysis
$ nvidia-smi --query-gpu=timestamp,memory.used,memory.free,utilization.gpu \
  --format=csv -l 5 > gpu_memory.csv
```

Calculate expected memory requirements using the formula from Chapter 4:

```
Total GPU Memory ≈ Parameters + Gradients + Optimizer States + Activations
```

For a 7B parameter model with Adam optimizer in FP16/BF16:

| Component | Memory |
|---|---|
| Parameters (BF16) | ~14 GB |
| Gradients (BF16) | ~14 GB |
| Optimizer States (FP32, Adam) | ~56 GB |
| Activations (batch-dependent) | Variable |
| **Minimum total** | **~84 GB + activations** |

### Root Cause

The batch size was set to 8. At the start of training, short sequences in the dataset produced small activation tensors. As the data loader reached longer sequences, activation memory grew until it exceeded the remaining GPU memory. The OOM didn't happen at step 1 because the first batches fit — the longest sequences arrived later.

### Resolution

**Immediate fix — reduce batch size:**

```python
training_args = TrainingArguments(
    per_device_train_batch_size=2,  # Reduced from 8
    gradient_accumulation_steps=4,  # Maintain effective batch size
)
```

**Better fix — enable gradient checkpointing:**

```python
model.gradient_checkpointing_enable()
```

This trades ~20–30% slower training for 60–80% reduction in activation memory.

**For larger models — use parameter-efficient fine-tuning:**

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

LoRA trains <1% of parameters, slashing gradient and optimizer memory by 100×.

### Prevention

- **Always calculate memory requirements before starting** using the formula from Chapter 4. If the math says it won't fit, don't run it.
- **Set `max_seq_length` explicitly** to cap activation memory at the longest sequence you expect.
- **Use `gradient_accumulation_steps`** to maintain effective batch size while keeping per-GPU batch size small.

**Pro Tip**: If you see OOM errors that happen at random steps (not consistently at step N), suspect variable-length sequences. Set `max_seq_length` and pad/truncate to eliminate the variance.

---

## Scenario 3: AKS GPU Pods Stuck in Pending

### Symptoms

A GPU training pod has been in `Pending` state for 20 minutes:

```bash
$ kubectl get pods -n ml-team
NAME                        READY   STATUS    RESTARTS   AGE
training-job-7b-xyz         0/1     Pending   0          20m
```

### Diagnosis

Check the events:

```bash
$ kubectl describe pod training-job-7b-xyz -n ml-team
Events:
  Type     Reason            Age   Message
  ----     ------            ----  -------
  Warning  FailedScheduling  18m   0/12 nodes are available:
    3 node(s) had untolerated taint {sku=gpu:NoSchedule},
    9 node(s) didn't match Pod's node affinity/selector.
```

The taint message is the key. Check the GPU node pool taints:

```bash
$ kubectl get nodes -l accelerator=nvidia -o custom-columns=\
NAME:.metadata.name,TAINTS:.spec.taints
NAME                                TAINTS
aks-gpunp-12345-vmss000000          [map[effect:NoSchedule key:sku value:gpu]]
```

Now check the pod spec for tolerations:

```bash
$ kubectl get pod training-job-7b-xyz -n ml-team -o jsonpath='{.spec.tolerations}' | jq .
```

No GPU toleration present.

### Root Cause

AKS GPU node pools apply the taint `sku=gpu:NoSchedule` by default. Pods must include a matching toleration to be scheduled on GPU nodes. The pod spec was missing this toleration — so the scheduler saw GPU nodes as ineligible and couldn't find any node with GPUs and without taints.

Other common causes include:

- **GPU quota exhausted**: The cluster autoscaler can't provision new GPU nodes because the subscription hit its GPU vCPU quota.
- **Node pool at max size**: The autoscaler wants to scale up but the node pool is already at `maxCount`.

Check both:

```bash
# Check regional GPU quota
$ az vm list-usage --location eastus -o table | grep -i "standard NC\|standard ND"

# Check node pool scaling limits
$ az aks nodepool show --cluster-name myAKS --resource-group myRG \
  --name gpunp --query '{min:minCount, max:maxCount, current:count}'
```

### Resolution

**Fix the toleration** — add this to the pod spec:

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

**If quota is the issue:**

```bash
# Request a quota increase via CLI
az quota create --resource-name "StandardNDSv2Family" \
  --scope "/subscriptions/{sub-id}/providers/Microsoft.Compute/locations/eastus" \
  --limit-object value=48 limit-object-type=LimitValue
```

### Prevention

- **Template all GPU pod specs** with the correct toleration pre-configured. Use Helm chart defaults or OPA/Gatekeeper policies that inject tolerations automatically.
- **Set up quota monitoring alerts** that fire at 80% GPU quota usage (see Chapter 9).
- **Configure cluster autoscaler correctly**: set `maxCount` with headroom so the autoscaler can respond to demand.

**Production Gotcha**: A pod stuck in Pending produces no logs — there's no container to log from. Always check `kubectl describe pod` for events, not `kubectl logs`.

---

## Scenario 4: Azure OpenAI 429 Storm

### Symptoms

Your application dashboard shows 30%+ of Azure OpenAI requests returning HTTP 429. Users report slow responses or timeouts. The error payload looks like:

```json
{
  "error": {
    "code": "429",
    "message": "Requests to the ChatCompletions_Create Operation under Azure OpenAI API have exceeded the token rate limit of your current deployment. Please retry after 6 seconds."
  }
}
```

### Diagnosis

Check your deployment's TPM and RPM usage in Azure Monitor:

```bash
# Check current deployment metrics
az monitor metrics list \
  --resource "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.CognitiveServices/accounts/{account}" \
  --metric "TokenTransaction" \
  --interval PT1M \
  --aggregation Total \
  --filter "ModelDeploymentName eq 'gpt-4o-prod'"
```

Look at the `Retry-After` header values in the 429 responses — they tell you how far over quota you are. A `Retry-After: 1` means you barely exceeded the limit. A `Retry-After: 30` means you're dramatically over.

Check the deployment's provisioned TPM:

```bash
az cognitiveservices account deployment show \
  --name my-openai-account \
  --resource-group myRG \
  --deployment-name gpt-4o-prod \
  --query "properties.rateLimits"
```

### Root Cause

The Standard (pay-as-you-go) deployment was provisioned with 80K TPM. A product launch drove a burst of traffic that peaked at 200K+ TPM. Standard deployments enforce hard rate limits — once you exceed the provisioned TPM or RPM, every additional request gets a 429.

### Resolution

**Immediate — implement exponential backoff with jitter:**

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

**Short-term — add a secondary deployment for overflow:**

Create a second deployment in a different region and route overflow traffic to it using Azure API Management or application-level logic.

**Long-term — evaluate Provisioned Throughput Units (PTU):**

For predictable, high-volume workloads, PTU provides guaranteed throughput without rate limiting. No 429s — you pay for reserved capacity regardless of usage (see Chapter 9 for the cost analysis).

### Prevention

- **Multi-deployment architecture**: Use Azure API Management with load-balancing policies across 2–3 deployments in different regions.
- **Alert at 80% quota**: Set up Azure Monitor alerts that fire when TPM usage reaches 80% of provisioned capacity.
- **Implement a token-aware queue**: Estimate token count before sending requests and throttle client-side when approaching limits.
- **Use usage tracking**: Log token counts per request to forecast capacity needs before launches.

**Pro Tip**: The most common mistake is retrying 429s immediately in a tight loop. This makes the storm worse. Always respect the `Retry-After` header and add random jitter to prevent thundering herd.

---

## Scenario 5: Inference Latency Spike

### Symptoms

P99 latency for your model inference endpoint jumps from 200 ms to 3 seconds. No deployments were made. No configuration changes. Users start reporting "the AI is slow."

### Diagnosis

Check the infrastructure layer by layer:

```bash
# GPU utilization — is the GPU actually busy?
$ nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu \
  --format=csv -l 2

# Container restarts — did the serving container crash?
$ kubectl get pods -n inference -w
$ kubectl describe pod model-serve-abc -n inference | grep -A 5 "Last State"

# Check for cold starts — was the container recently created?
$ kubectl get pods -n inference -o custom-columns=\
NAME:.metadata.name,START:.status.startTime,READY:.status.conditions[0].lastTransitionTime
```

Check if model loading is the bottleneck:

```bash
# Check container startup logs for model load time
$ kubectl logs model-serve-abc -n inference | grep -i "model loaded\|loading model\|startup"
[2024-07-15 08:12:03] Loading model from /models/llama-7b...
[2024-07-15 08:14:47] Model loaded in 164.2 seconds
```

A 164-second model load time means every container restart creates a nearly 3-minute latency hole.

### Root Cause

Three common causes, often overlapping:

1. **Container cold start**: The inference pod was evicted (OOM, node drain, spot node reclaim) and restarted. Model weights are loaded from Azure Blob Storage on startup — downloading 14+ GB over the network takes minutes.
2. **GPU thermal throttling**: Sustained 100% GPU utilization pushed the GPU temperature above the throttle threshold (typically 83°C), causing automatic clock reduction.
3. **Noisy neighbor**: Another pod on the same node is consuming CPU, memory, or network bandwidth needed for preprocessing or postprocessing.

### Resolution

**For cold starts — pre-load models and cache locally:**

```yaml
# Use an init container to download model weights to local NVMe
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

**For cold starts — configure readiness probes correctly:**

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 180  # Give the model time to load
  periodSeconds: 10
  failureThreshold: 3
```

This prevents Kubernetes from routing traffic to a pod that's still loading the model.

**For thermal throttling:**

```bash
# Check GPU temperature
$ nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader
82

# If consistently above 80°C, reduce concurrent requests or add cooling
```

**For noisy neighbors — isolate GPU inference pods:**

```yaml
resources:
  requests:
    cpu: "8"
    memory: "32Gi"
    nvidia.com/gpu: 1
  limits:
    cpu: "8"
    memory: "32Gi"
    nvidia.com/gpu: 1  # GPUs are always exclusive per container
```

Set `requests = limits` for both CPU and memory to get a Guaranteed QoS class, which prevents eviction and noisy-neighbor CPU contention.

### Prevention

- **Set `minReplicas` > 0** in your Horizontal Pod Autoscaler to avoid scaling to zero.
- **Use local NVMe cache** on ND/NC-series VMs for model weights. Loading from local SSD takes seconds; loading from Blob Storage takes minutes.
- **Configure liveness and readiness probes** with adequate `initialDelaySeconds` for model loading.
- **Monitor GPU temperature** and set alerts at 80°C.

**Production Gotcha**: Readiness probes with default `initialDelaySeconds` (0) will mark a model-serving pod as "ready" before the model is actually loaded. Kubernetes routes traffic to it, requests hit an uninitialized model, and users see errors. Always set `initialDelaySeconds` to at least your model load time.

---

## Scenario 6: Distributed Training Hangs at Gradient Sync

### Symptoms

A multi-node training job stops making progress. The terminal shows no new log output. GPU utilization drops to 0% across all nodes. No error messages appear. The job just... hangs.

```bash
$ nvidia-smi  # On any node
+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                GPU Memory  |
|  0     N/A  N/A     12345    C   python                          78000MiB  |
+-----------------------------------------------------------------------------+
# GPU memory allocated but utilization at 0%
```

### Diagnosis

Enable NCCL debug logging and restart:

```bash
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL
export NCCL_SOCKET_IFNAME=eth0
torchrun --nproc_per_node=8 --nnodes=4 --node_rank=0 train.py
```

Check InfiniBand status on each node:

```bash
$ ibstat
CA 'mlx5_0'
    CA type: MT4123
    Number of ports: 1
    Port 1:
        State: Down          # <-- Problem! Should be "Active"
        Physical state: Disabled
        Rate: 0
```

Compare with a healthy node:

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

### Root Cause

One node in the 4-node training cluster lost InfiniBand connectivity. NCCL's `all-reduce` operation requires every participant to complete before any node can proceed. A single failed node blocks the entire job indefinitely — NCCL waits forever by default.

This is particularly insidious because:
- The job doesn't crash — it silently hangs
- The other 3 nodes (24 GPUs) sit idle, burning money
- No error appears in standard training logs

### Resolution

**Identify and replace the failed node:**

```bash
# Run on all nodes to find which has InfiniBand down
for node in node-0 node-1 node-2 node-3; do
    echo "=== $node ==="
    ssh $node "ibstat | grep -A 2 'Port 1'"
done
```

**Set NCCL timeout so jobs fail fast instead of hanging:**

```python
import datetime
import torch.distributed as dist

dist.init_process_group(
    backend="nccl",
    timeout=datetime.timedelta(minutes=10)  # Fail after 10 min, not forever
)
```

**Remove the failed node and restart from checkpoint:**

```bash
# Restart with 3 nodes, loading from latest checkpoint
torchrun --nproc_per_node=8 --nnodes=3 --node_rank=0 \
  train.py --resume_from_checkpoint ./checkpoints/step-15000/
```

### Prevention

- **Run pre-job InfiniBand health checks** before starting multi-node training:

```bash
#!/bin/bash
# ib-health-check.sh — Run on every node before training
IB_STATE=$(ibstat | grep "State:" | head -1 | awk '{print $2}')
if [ "$IB_STATE" != "Active" ]; then
    echo "FAIL: InfiniBand not active on $(hostname)"
    exit 1
fi
echo "PASS: InfiniBand active on $(hostname)"
```

- **Set `NCCL_TIMEOUT`** to a reasonable value (5–10 minutes) so hung jobs fail with actionable errors instead of blocking silently.
- **Checkpoint frequently** — every 15–30 minutes for large jobs. The cost of writing a checkpoint is negligible compared to losing hours of training.
- **Use Azure CycleCloud or AKS job schedulers** that can detect unresponsive nodes and restart jobs automatically.

**Pro Tip**: If `ibstat` shows `Active` but training still hangs, run `ib_write_bw` between node pairs to test actual InfiniBand bandwidth. A link can be "Active" but degraded.

---

## Scenario 7: Model Serving Container Crash Loop

### Symptoms

Your inference pod restarts every 2–3 minutes:

```bash
$ kubectl get pods -n inference
NAME                        READY   STATUS             RESTARTS   AGE
model-serve-abc-12345       0/1     CrashLoopBackOff   7          14m
```

### Diagnosis

Check the reason for the last termination:

```bash
$ kubectl describe pod model-serve-abc-12345 -n inference | grep -A 10 "Last State"
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Mon, 15 Jul 2024 08:10:03 +0000
      Finished:     Mon, 15 Jul 2024 08:12:47 +0000
```

`OOMKilled` with exit code 137 means the Linux kernel's OOM killer terminated the process because it exceeded the container's memory limit.

Check the container's memory limit vs. actual needs:

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

A 7B parameter model in FP16 is ~14 GB on disk. But loading it requires CPU RAM first — the model weights are read into CPU memory before being transferred to GPU memory. With a 16 GB limit, there's no headroom.

### Root Cause

Three common causes for model serving crash loops:

1. **Memory limit too low**: Model loading uses CPU RAM as a staging area. A 14 GB model needs ~28 GB of CPU RAM during loading (file read + tensor deserialization). The 16 GB limit triggers OOMKilled.
2. **Corrupted model file**: An incomplete download from Blob Storage produces a truncated model file. The loading code crashes with a deserialization error.
3. **Missing Python dependencies**: The container image is missing a library the model requires (common with custom model architectures).

Check logs before the OOMKilled:

```bash
$ kubectl logs model-serve-abc-12345 -n inference --previous
Loading model weights...
Loaded 48/64 shards [==========>          ] 75%
Killed
```

Loading at 75% confirms the OOMKilled — CPU RAM ran out before all shards were loaded.

### Resolution

**Increase memory limits** — set to at least 2× the model weight file size:

```yaml
resources:
  requests:
    memory: "32Gi"        # Model size × 2 for loading overhead
    nvidia.com/gpu: 1
  limits:
    memory: "32Gi"        # Set equal to requests for Guaranteed QoS
    nvidia.com/gpu: 1
```

**For corrupted model files:**

```bash
# Verify model file integrity
$ md5sum /models/model-7b.safetensors
$ az storage blob show --container-name models --name model-7b.safetensors \
  --account-name mystorageaccount --query "properties.contentMd5"
```

**For missing dependencies:**

```bash
$ kubectl logs model-serve-abc-12345 -n inference --previous | tail -20
# Look for ImportError, ModuleNotFoundError
```

### Prevention

- **Set `requests = limits`** for memory on all GPU inference pods. This guarantees a Guaranteed QoS class and prevents the kubelet from setting a low cgroup memory limit.
- **Rule of thumb**: CPU memory limit = model weight file size × 2. This accounts for the loading overhead where weights exist in both file buffer and tensor form simultaneously.
- **Test containers locally** with `docker run --memory=32g` before deploying to Kubernetes.
- **Use `safetensors` format** instead of pickle-based formats. Safetensors supports memory-mapped loading, which drastically reduces peak CPU RAM usage.

---

## Scenario 8: GPU Quota Exhaustion

### Symptoms

Your Terraform deployment fails:

```
Error: creating Virtual Machine: compute.VirtualMachinesClient#CreateOrUpdate:
StatusCode=409 -- Original Error: Code="OperationNotAllowed"
Message="Operation could not be completed as it results in exceeding
approved Standard NDSv2 Family vCPUs Quota. Current usage: 96,
Additional Required: 40, (Effective) Limit: 96."
```

Or via Azure CLI:

```bash
$ az vm create --resource-group myRG --name gpu-vm --image UbuntuLTS \
  --size Standard_ND40rs_v2
(OperationNotAllowed) Operation could not be completed as it results in
exceeding approved quota.
```

### Diagnosis

Check current GPU quota usage:

```bash
$ az vm list-usage --location eastus -o table | grep -i "standard ND"
Name                          CurrentValue    Limit
----------------------------  --------------  ------
Standard NDSv2 Family vCPUs   96              96
Standard NDAMSv5 Family vCPUs 0               0

# See what's consuming the quota
$ az vm list -g myRG -o table --query "[?contains(hardwareProfile.vmSize,'ND')]"
Name          ResourceGroup    Location    VmSize
-----------   ---------------  ----------  ----------------------
train-node-0  myRG             eastus      Standard_ND40rs_v2
train-node-1  myRG             eastus      Standard_ND40rs_v2
dev-gpu-01    myRG             eastus      Standard_ND40rs_v2
```

Three ND40rs_v2 VMs × 40 vCPUs = 120 requested, but quota is 96 — so two are running (80 vCPUs) and one partially allocated. The third VM and any new ones will fail.

### Root Cause

GPU quotas in Azure are per-subscription, per-region, per-VM-family. Default quotas for GPU families are typically **0** — you must request increases explicitly. Common reasons for exhaustion:

- Running VMs that should have been deallocated (forgotten dev/test VMs)
- Multiple teams deploying in the same subscription without coordination
- Requesting a VM family you've never used before (quota = 0)

### Resolution

**Immediate — deallocate unused GPU VMs:**

```bash
# Find stopped-but-still-allocated VMs (these consume quota!)
$ az vm list -g myRG --show-details -o table \
  --query "[?powerState!='VM deallocated' && contains(hardwareProfile.vmSize,'ND')]"

# Deallocate (not just stop)
$ az vm deallocate --resource-group myRG --name dev-gpu-01
```

**Production Gotcha**: `az vm stop` keeps the VM allocated — it still consumes quota and you still pay for the compute. Only `az vm deallocate` releases the resources.

**Request a quota increase:**

```bash
az quota create \
  --resource-name "StandardNDSv2Family" \
  --scope "/subscriptions/{sub-id}/providers/Microsoft.Compute/locations/eastus" \
  --limit-object value=192 limit-object-type=LimitValue \
  --resource-type "dedicated"
```

Quota increases for GPU VMs can take 1–5 business days. Plan ahead.

**Try a different region** if you need capacity immediately:

```bash
$ az vm list-skus --location westus2 --size Standard_ND40rs_v2 \
  --query "[].{Name:name, Restrictions:restrictions}" -o table
```

### Prevention

- **Build a GPU quota monitoring dashboard** in Azure Monitor. Track `CurrentValue / Limit` ratio per VM family per region.
- **Set alerts at 80% quota usage** so you have time to request increases before hitting the wall.
- **Add pre-flight quota checks to IaC pipelines**:

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

- **Tag GPU VMs with expiry dates** and automate deallocation of expired resources.

---

## Scenario 9: BlobFuse2 Mount Failures

### Symptoms

A training job starts but can't find its dataset:

```
FileNotFoundError: [Errno 2] No such file or directory: '/mnt/data/training/dataset.parquet'
```

The mount point exists but is empty:

```bash
$ ls /mnt/data/
# (empty)

$ mount | grep blobfuse
# (no output — mount failed silently)
```

### Diagnosis

Check BlobFuse2 logs:

```bash
$ journalctl -u blobfuse2-mount.service --since "1 hour ago"
blobfuse2[1234]: Error: Failed to authenticate. StatusCode=403
AuthorizationFailure. This request is not authorized to perform
this operation using this permission.

# Or check directly if run manually
$ blobfuse2 mount /mnt/data --config-file=/etc/blobfuse2/config.yaml 2>&1
Error: authorization failure: identity not authorized
```

Check managed identity assignment:

```bash
$ az vm identity show --resource-group myRG --name gpu-vm-01
{
  "type": "UserAssigned",
  "userAssignedIdentities": {
    "/subscriptions/.../my-ml-identity": { ... }
  }
}

# Check RBAC on the storage account
$ az role assignment list --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/mldatastorage" \
  --query "[?principalName=='my-ml-identity'].{Role:roleDefinitionName}" -o table
# (empty — no role assignment!)
```

### Root Cause

Two primary causes:

1. **Missing RBAC**: The VM's managed identity was not assigned the `Storage Blob Data Reader` role on the storage account. The identity exists, but has no permissions to read blobs.
2. **Storage firewall blocking**: The storage account's network rules are set to "Selected networks" and the VM's VNet/subnet is not in the allowed list.

Check the firewall:

```bash
$ az storage account show --name mldatastorage --resource-group myRG \
  --query "networkRuleSet.defaultAction"
"Deny"

$ az storage account network-rule list --account-name mldatastorage \
  --query "virtualNetworkRules[].virtualNetworkResourceId" -o table
# VM's subnet not listed
```

### Resolution

**Fix RBAC:**

```bash
# Get the managed identity principal ID
PRINCIPAL_ID=$(az identity show --name my-ml-identity --resource-group myRG \
  --query principalId -o tsv)

# Assign Storage Blob Data Reader
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/mldatastorage"
```

**Fix storage firewall:**

```bash
az storage account network-rule add \
  --account-name mldatastorage \
  --resource-group myRG \
  --vnet-name ml-vnet \
  --subnet gpu-subnet
```

Then remount:

```bash
$ blobfuse2 mount /mnt/data --config-file=/etc/blobfuse2/config.yaml
$ ls /mnt/data/training/
dataset.parquet  validation.parquet
```

### Prevention

- **Provision storage + RBAC together in IaC.** Never create a storage account without also creating the role assignment in the same template:

```hcl
# Terraform example — storage + RBAC in one module
resource "azurerm_role_assignment" "ml_storage_reader" {
  scope                = azurerm_storage_account.ml_data.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.ml_identity.principal_id
}
```

- **Include VNet rules in Terraform** so storage firewall rules are always in sync with network topology.
- **Test mounts in CI** — add a pipeline step that mounts the storage and verifies file access before deploying training jobs.

**Pro Tip**: RBAC role assignments can take up to 10 minutes to propagate. If you just created the assignment and the mount still fails, wait and retry. Don't start adding storage keys as a workaround.

---

## Scenario 10: Model Quality Degradation in Production

### Symptoms

No infrastructure alarms fired. No deployments happened. But the product team reports that AI output quality has visibly degraded:

- Customer satisfaction scores dropped 15% over two weeks
- Internal quality reviews show the model producing less relevant responses
- Error rates haven't changed — the model responds, it just responds poorly

### Diagnosis

This is the hardest scenario because infrastructure metrics look perfectly normal. You need to work with the ML team to trace the issue:

**Step 1 — Verify the model version:**

```bash
# Check which model version is actually serving
$ kubectl get deployment model-serve -n inference \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
myregistry.azurecr.io/llm-serve:v2.3.1

# Compare against the expected version
$ az acr repository show-tags --name myregistry --repository llm-serve --top 5 -o table
```

**Step 2 — Check the data pipeline:**

```bash
# When was the training dataset last updated?
$ az storage blob show --container-name datasets --name training-data.parquet \
  --account-name mldatastorage \
  --query "properties.lastModified"
"2024-05-15T08:00:00+00:00"   # 2 months stale
```

**Step 3 — Compare current vs. baseline outputs:**

Run the same evaluation prompts through the production model and compare against known-good baseline responses. Use automated evaluation metrics (BLEU, ROUGE, or LLM-as-judge) to quantify the difference.

### Root Cause

Three common causes:

1. **Data drift**: Production queries have shifted in topic, style, or complexity since the model was trained. The model's training data no longer represents what users actually ask.
2. **Wrong model version**: A rollback or misconfigured CI/CD pipeline deployed an older, less capable model version.
3. **Upstream API change**: For RAG (retrieval-augmented generation) architectures, the search API or embedding model changed its response format, breaking the retrieval pipeline silently.

### Resolution

- **Data drift**: Retrain or fine-tune on a fresh dataset that includes recent production queries (with appropriate privacy controls).
- **Wrong model version**: Correct the deployment manifest and redeploy the intended version.
- **Upstream API change**: Audit the entire inference pipeline — embedding model, search index, prompt template, and serving model — for version mismatches.

### Prevention

- **Automated model quality monitoring**: Run a suite of evaluation prompts on a schedule (daily or weekly) and alert when scores drop below a threshold.
- **A/B testing for model updates**: Never replace a production model wholesale. Route 5–10% of traffic to the new version and compare metrics before full rollover.
- **Data drift detection**: Monitor the statistical distribution of incoming queries vs. training data. Tools like Azure Machine Learning's data drift monitor can automate this.
- **Version pinning in deployment manifests**: Use immutable image tags (never `latest`) and track model versions in your deployment pipeline.

**Production Gotcha**: Quality degradation is the only production issue on this list where all infrastructure metrics look green. GPU utilization is normal. Latency is normal. Error rates are normal. The model is just confidently producing bad outputs. This is why model quality monitoring is separate from infrastructure monitoring — and equally important.

---

## Quick Reference: Diagnostic Command Cheatsheet

### GPU Diagnostics

| Command | What It Shows |
|---|---|
| `nvidia-smi` | GPU utilization, memory, temperature, running processes |
| `nvidia-smi -l 2` | Continuous GPU monitoring (every 2 seconds) |
| `nvidia-smi topo -m` | GPU-to-GPU interconnect topology (NVLink vs. PCIe) |
| `nvidia-smi --query-gpu=timestamp,memory.used,memory.free,utilization.gpu,temperature.gpu --format=csv -l 5` | Structured metrics output for logging |
| `dmesg \| grep -i nvidia` | Kernel messages about NVIDIA driver loading |
| `ibstat` | InfiniBand port state, link speed, physical status |
| `ib_write_bw` | InfiniBand bandwidth test between node pairs |
| `dcgmi diag -r 3` | NVIDIA DCGM full diagnostic (stress test + health check) |

### Kubernetes GPU Diagnostics

| Command | What It Shows |
|---|---|
| `kubectl get pods -o wide` | Pod status, node placement, restarts |
| `kubectl describe pod <name>` | Events, scheduling failures, OOMKilled reasons |
| `kubectl logs <pod> --previous` | Logs from the last crashed container |
| `kubectl get nodes -l accelerator=nvidia` | GPU-capable nodes |
| `kubectl top nodes` | Node CPU/memory utilization |
| `kubectl get events --sort-by=.lastTimestamp` | Recent cluster events |
| `kubectl describe node <name> \| grep nvidia.com/gpu` | GPU capacity and allocatable on a node |

### Azure Resource Diagnostics

| Command | What It Shows |
|---|---|
| `az vm list-usage --location <region> -o table` | vCPU quota usage per VM family |
| `az vm get-instance-view --name <vm> -g <rg>` | VM power state, extension statuses |
| `az aks nodepool show --cluster-name <aks> -g <rg> -n <pool>` | Node pool size, autoscaler config |
| `az monitor metrics list --resource <id> --metric <name>` | Azure Monitor metrics for any resource |
| `az storage account show --name <acct> --query networkRuleSet` | Storage firewall configuration |
| `az cognitiveservices account deployment show --name <acct> -g <rg> --deployment-name <dep>` | OpenAI deployment config and rate limits |

### Storage and Connectivity

| Command | What It Shows |
|---|---|
| `blobfuse2 mount <path> --config-file=<cfg>` | Mount Azure Blob Storage |
| `journalctl -u blobfuse2-mount.service` | BlobFuse2 mount service logs |
| `az role assignment list --scope <resource-id>` | RBAC roles on a resource |
| `az storage account network-rule list --account-name <acct>` | Storage firewall VNet rules |

---

## Chapter Checklist

Before you close this chapter, make sure you have:

- **GPU driver monitoring** in place — alerts on `nvidia-smi` failures, not just GPU utilization
- **Kernel pinning** configured on GPU VMs to prevent unattended upgrade breakage
- **Memory calculations** done before training jobs start — use the formula from Chapter 4
- **GPU pod templates** with correct `sku=gpu:NoSchedule` tolerations as defaults
- **Exponential backoff with jitter** implemented in all Azure OpenAI client code
- **Readiness probes** with adequate `initialDelaySeconds` on model-serving containers
- **NCCL timeout** configured for distributed training jobs (don't let hangs run forever)
- **Container memory limits** set to 2× model weight size for inference pods
- **GPU quota monitoring** with alerts at 80% usage per VM family per region
- **Storage RBAC and firewall rules** provisioned alongside storage accounts in IaC
- **Model quality monitoring** separate from infrastructure monitoring
- **Checkpoint frequency** set for distributed training (every 15–30 minutes minimum)

---

## What's Next

These scenarios cover the most common production failures in AI infrastructure. But troubleshooting is reactive — you're fixing things after they break. What about proactive AI?

Chapter 13 shows how you can apply AI to your own infrastructure work: predictive failure detection, log anomaly analysis, and ops copilots that help you diagnose issues before users notice them. The same AI capabilities you've been building infrastructure for? They can work *for* you too.
