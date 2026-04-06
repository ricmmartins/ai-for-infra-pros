# Chapter 4 — The GPU Deep Dive

*"The GPU has 40 gigs of memory — why can't it fit a 14 GB model?"*

---

## The Ticket That Changes Everything

It's 2 AM and a Slack message lights up your phone. The ML team's training job just crashed — again. The error is one line long and supremely unhelpful: `CUDA out of memory. Tried to allocate 2.00 GiB`. The team lead is frustrated. "We're running a 7-billion parameter model in FP16. That's only 14 GB. The A100 has 40 GB of memory. There should be 26 GB of headroom. What's going on?"

You SSH into the VM, run `nvidia-smi`, and see memory usage pegged at 100%. But the math doesn't add up — 14 GB of model weights can't fill 40 GB of GPU memory. Unless something else is consuming the rest. You dig deeper and discover the truth: model parameters are only one piece of the memory puzzle. Gradients, optimizer states, and activations each claim their own slice. A "14 GB model" actually needs 90+ GB to train with full-precision Adam.

This chapter gives you the knowledge to answer that question — and dozens more like it. Not so you can write CUDA kernels, but so you can troubleshoot GPU failures, right-size allocations, and have informed conversations with your ML teams. This is the chapter that separates "I provision GPU VMs" from "I understand GPU infrastructure."

---

## Inside the GPU: Architecture for Infra Engineers

You don't need to design GPU circuits. But you do need a mental model of what's inside the box, because that mental model will tell you why workloads behave the way they do, why certain errors appear, and why some VM SKUs perform dramatically better than others for a given job.

### Streaming Multiprocessors: The Building Blocks

A GPU is built from repeated units called **Streaming Multiprocessors (SMs)**. Each SM is an independent processor containing its own cores, cache, and scheduling hardware. An NVIDIA A100 GPU has 108 SMs. An H100 has 132.

Think of each SM as a small, self-contained factory floor. It has its own workers (cores), its own local storage (shared memory and registers), and its own task scheduler. The GPU's job is to keep all 100+ factory floors busy at the same time.

### CUDA Cores and Tensor Cores

Inside each SM, you'll find two types of processing units:

**CUDA Cores** are general-purpose parallel processors. They handle standard floating-point and integer math — the kind of operations that make up traditional GPU computing. An A100 has 6,912 CUDA cores. An H100 has 16,896. These cores deliver raw throughput through parallelism: thousands of simple operations executed simultaneously.

**Tensor Cores** are the reason modern GPUs dominate AI workloads. These specialized units perform matrix-multiply-and-accumulate operations in a single clock cycle — the exact operation at the heart of neural network training and inference. An A100 has 432 Tensor Cores (3rd generation). An H100 has 528 (4th generation). When someone says "the H100 is 3× faster than the A100 for training," Tensor Cores are the primary reason.

🔄 **Infra ↔ AI Translation**: A GPU is like a 100-lane highway where every lane carries math operations simultaneously. A CPU is a 4-lane highway where each lane can handle complex turns, exits, and decision-making. For matrix math — the backbone of AI — you want the highway. For complex branching logic, you still want the CPU.

### NVLink: The GPU-to-GPU Superhighway

When you have multiple GPUs in a single VM, they need to communicate. PCIe provides a baseline connection, but for serious multi-GPU training, you need **NVLink** — NVIDIA's high-speed GPU-to-GPU interconnect.

- **A100 NVLink**: 600 GB/s bidirectional bandwidth
- **H100 NVLink**: 900 GB/s bidirectional bandwidth
- **B200 NVLink 5.0**: 1.8 TB/s bidirectional bandwidth

NVLink matters because multi-GPU training strategies (covered later in this chapter) exchange massive amounts of data between GPUs every few milliseconds. If that exchange bottlenecks on PCIe (64 GB/s), your expensive GPUs sit idle waiting for data. On Azure, NVLink is available on ND-series VMs — and you can verify its presence with `nvidia-smi topo -m`.

💡 **Pro Tip**: If `nvidia-smi topo -m` shows `PIX` or `PHB` between GPUs instead of `NV#`, you're running on PCIe, not NVLink. For multi-GPU training, this makes a dramatic difference in throughput. Verify you're on the right VM SKU before debugging performance problems.

---

## GPU Memory: The Resource You'll Manage Most

If you remember one section from this chapter, make it this one. GPU memory — specifically, running out of it — is the single most common issue you'll troubleshoot in AI infrastructure. Understanding what fills GPU memory and why is essential knowledge.

### The Memory Hierarchy

GPU memory is organized in layers, just like CPU memory. Each layer trades capacity for speed:

| Layer | A100 Spec | H100 Spec | Analogy |
|---|---|---|---|
| **HBM (High Bandwidth Memory)** | 40 or 80 GB, 2 TB/s | 80 GB, 3.35 TB/s | System RAM |
| **L2 Cache** | 40 MB | 50 MB | CPU L3 cache |
| **Shared Memory / L1 Cache** | Up to 164 KB per SM | Up to 256 KB per SM | CPU L1/L2 cache |
| **Registers** | 256 KB per SM | 256 KB per SM | CPU registers |

**HBM** is what `nvidia-smi` reports and what you'll monitor daily. It's the "main memory" of the GPU — where model weights, training data, and intermediate results live. When someone says "the A100 has 80 GB," they're talking about HBM.

**L2 Cache** is shared across all SMs and automatically manages data reuse. You can't directly control it, but it explains why some access patterns are faster than others.

**Shared Memory** is per-SM and configurable by the application. CUDA kernels use it for fast data sharing within a compute block. Framework developers (PyTorch, TensorFlow) optimize for it — you generally don't need to worry about it.

**Registers** are the fastest storage, but limited. When a kernel needs more registers than available, it "spills" to slower memory, reducing performance.

🔄 **Infra ↔ AI Translation**: If you've ever diagnosed CPU performance by looking at L1/L2/L3 cache hit rates, the same mental model applies to GPUs. HBM is your RAM — it determines whether a model fits. The cache layers determine how fast it runs.

### What Fills GPU Memory During Training

Here's where the 2 AM ticket starts making sense. When you train a model, GPU memory holds four major consumers:

**1. Model Parameters (the weights)**
These are the learned values that make the model work. Size is straightforward: parameter count × bytes per parameter. A 7B parameter model in FP16 (2 bytes each) requires ~14 GB.

**2. Gradients**
During backpropagation, the training process computes a gradient for every parameter — a value indicating how much that parameter should change. Gradient storage equals parameter storage: 7B parameters × 2 bytes = another ~14 GB.

**3. Optimizer States**
This is the hidden memory killer. The Adam optimizer — used by nearly every modern training job — maintains two additional values per parameter: momentum (the running average of gradients) and variance (the running average of squared gradients). These are typically stored in FP32 regardless of model precision. For a 7B parameter model: 7B × 4 bytes × 2 states = **~56 GB** just for the optimizer.

**4. Activations**
Every layer in the neural network produces intermediate results (activations) that are saved during the forward pass and consumed during backpropagation. Activation memory depends on model architecture and **batch size** — which is why "reduce the batch size" is often the first fix for OOM errors.

### The Memory Math

Here's the formula that will save you countless debugging sessions:

```
Total GPU Memory ≈ Parameters + Gradients + Optimizer States + Activations
```

Let's do the math for that 7B parameter model from the opening ticket:

| Component | Calculation | Memory |
|---|---|---|
| Parameters (FP16) | 7B × 2 bytes | ~14 GB |
| Gradients (FP16) | 7B × 2 bytes | ~14 GB |
| Optimizer States (FP32, Adam) | 7B × 4 bytes × 2 | ~56 GB |
| Activations (varies) | Depends on batch size | ~8-20 GB |
| **Total** | | **~92-104 GB** |

Now the 2 AM ticket makes perfect sense. A "14 GB model" needs 90+ GB to train. A single A100-40GB never had a chance. Even an A100-80GB is cutting it close. This is exactly why techniques like ZeRO, LoRA, and gradient checkpointing exist — they attack different parts of this equation.

⚠️ **Production Gotcha**: When an ML engineer says "the model is X gigabytes," they almost always mean parameter size — the size of the saved checkpoint file. Training memory is 4-8× larger. Always multiply by at least 4× for a rough training estimate with Adam, and 6-8× for a comfortable margin.

💡 **Pro Tip**: **Gradient checkpointing** (also called activation recomputation) trades compute for memory. Instead of saving all activations during the forward pass, it saves only some and recomputes the rest during backpropagation. It slows training by ~20-30% but can cut activation memory by 60-80%. If you see `gradient_checkpointing=True` in a training config, that's what it's doing.

---

## Precision: Trading Accuracy for Speed and Memory

The choice of numerical precision — how many bits represent each number — has a direct, measurable impact on GPU memory consumption, training speed, and model quality. As an infra engineer, you need to understand these tradeoffs because precision determines whether a model fits on your hardware.

### The Precision Spectrum

| Format | Bits | Bytes per Parameter | Range | Use Case |
|---|---|---|---|---|
| **FP32** | 32 | 4 | ±3.4 × 10³⁸ | Full-precision training, master weights |
| **TF32** | 19* | 4 (stored) | Same as FP32 | A100+ default for matmul, transparent |
| **BF16** | 16 | 2 | ±3.4 × 10³⁸ | Preferred for training (same range as FP32) |
| **FP16** | 16 | 2 | ±65,504 | Training with loss scaling, inference |
| **INT8** | 8 | 1 | -128 to 127 | Quantized inference |
| **INT4** | 4 | 0.5 | -8 to 7 | Aggressively quantized inference |

*TF32 uses 19 bits internally but is stored as 32-bit. It's a hardware format on A100+ that provides FP32 range with reduced precision — and it's enabled by default.*

**FP32** is the safe default. Every number gets full precision, but it uses 4 bytes per parameter — the most memory-hungry option.

**BF16 (bfloat16)** is the current sweet spot for training. It maintains the same exponent range as FP32 (so it handles very large and very small numbers equally well) while using only 2 bytes. Most modern training pipelines default to BF16.

**FP16** was the previous standard for mixed-precision training. It has a narrower range than BF16, which means some values can overflow or underflow. This requires "loss scaling" — multiplying the loss by a large number to keep gradients in representable range. It works, but BF16 is simpler and more stable.

**INT8 and INT4** are quantization formats used primarily for inference. A model trained in BF16 can be quantized to INT8 or INT4 after training, dramatically reducing memory requirements and increasing throughput — at the cost of slight quality degradation.

📊 **Decision Matrix: Choosing Precision**

| Scenario | Recommended Precision | Why |
|---|---|---|
| Training from scratch | BF16 mixed precision | Best balance of speed, memory, and stability |
| Fine-tuning a pretrained model | BF16 mixed precision | Consistent with most pretrained models |
| Inference (latency-sensitive) | INT8 or FP16 | 2-4× throughput vs FP32 |
| Inference (cost-sensitive) | INT4 (GPTQ/AWQ) | 4-8× memory reduction, slight quality loss |
| Legacy workload compatibility | FP32 | When precision matters more than performance |

🔄 **Infra ↔ AI Translation**: Think of precision like JPEG quality settings. FP32 is the uncompressed RAW image — highest quality, largest file. BF16 is like a high-quality JPEG — imperceptibly different for most purposes, half the file size. INT4 is like a thumbnail — visibly lossy, but it loads instantly and fits anywhere.

---

## Multi-GPU Strategies Deep Dive

When a model won't fit on a single GPU — or when training on one GPU takes days instead of hours — you need to spread the work across multiple GPUs. How you spread that work has profound implications for memory consumption, network utilization, and overall training efficiency.

### Data Parallelism (DP)

The simplest approach. You place a complete copy of the model on every GPU, and each GPU processes a different batch of data. After each step, the GPUs synchronize their gradients via an **all-reduce** operation, so all copies of the model stay identical.

Data Parallelism scales training speed nearly linearly with GPU count: 8 GPUs ≈ 8× the throughput. The catch? Every GPU must hold the entire model, all its gradients, and all its optimizer states. If one GPU can't hold the model, DP alone won't help.

**Infra impact**: DP is network-intensive. Every training step requires an all-reduce across all GPUs. Within a node, NVLink handles this beautifully. Across nodes, you need high-bandwidth, low-latency networking — which is where InfiniBand (covered in Chapter 3) earns its keep.

### DeepSpeed ZeRO: The Memory Breaker

Microsoft's **ZeRO (Zero Redundancy Optimizer)** is the single most impactful technique for fitting large models on GPU clusters. It comes in three stages, each partitioning more state across GPUs:

| Stage | What's Partitioned | Per-GPU Memory Savings | Communication Overhead |
|---|---|---|---|
| **ZeRO-1** | Optimizer states | ~4× reduction in optimizer memory | Minimal |
| **ZeRO-2** | Optimizer states + Gradients | Additional gradient savings | Moderate |
| **ZeRO-3** | Optimizer + Gradients + Parameters | Everything sharded, maximum savings | Highest |

Let's revisit our 7B parameter example. Training with Adam on a single GPU needs ~92 GB. With 8 GPUs and ZeRO-3, each GPU holds only 1/8th of the parameters, gradients, and optimizer states — roughly 11-13 GB per GPU, plus activations. A 7B model that couldn't train on one A100-80GB now comfortably trains across eight A100-40GB GPUs.

**ZeRO-3** is what makes training 70B+ parameter models on Azure ND-series VMs practical. It shards everything — parameters, gradients, and optimizer states — across all GPUs, gathering them only when needed for computation.

### Fully Sharded Data Parallel (FSDP)

**FSDP** is PyTorch's native answer to ZeRO-3. It provides the same core capability — full sharding of parameters, gradients, and optimizer states — but integrated directly into PyTorch's distributed training API. If the ML team uses PyTorch (most do), they'll likely choose between DeepSpeed ZeRO and FSDP.

From an infra perspective, FSDP and ZeRO-3 have similar resource requirements: high GPU memory bandwidth, fast inter-GPU communication, and good storage throughput for data loading.

### Pipeline Parallelism (PP)

Pipeline Parallelism splits the model's layers across GPUs sequentially. GPU 0 holds layers 1-10, GPU 1 holds layers 11-20, and so on. Data flows through the pipeline like an assembly line.

The advantage: each GPU holds only a fraction of the model's parameters, dramatically reducing per-GPU memory. The disadvantage: **pipeline bubbles**. While GPU 0 processes the next micro-batch's forward pass, GPU 3 might be idle waiting for data. Sophisticated scheduling (like interleaved 1F1B) minimizes but can't eliminate these bubbles.

**Infra impact**: PP is less network-intensive than DP because communication only happens between adjacent pipeline stages. But it's latency-sensitive — high-latency interconnect will amplify pipeline bubbles.

### Tensor Parallelism (TP)

Tensor Parallelism is the most fine-grained approach. It splits individual layers across GPUs, so a single matrix multiplication is distributed across multiple devices. This requires extremely high bandwidth between GPUs because partial results must be exchanged mid-computation.

**Infra impact**: TP absolutely requires NVLink. Running TP over PCIe or Ethernet is technically possible but practically useless — the communication overhead would negate the parallelism benefits. TP is used within a node (over NVLink), while DP or PP is used across nodes (over InfiniBand).

### 3D Parallelism: Combining Everything

For the largest models (100B+ parameters), production training pipelines combine all three strategies:

- **Tensor Parallelism** within a node (over NVLink) — splits layers across GPUs
- **Pipeline Parallelism** across a few nodes — distributes layer groups
- **Data Parallelism** (with ZeRO) across many nodes — replicates the pipeline for throughput

This is called **3D parallelism**, and it's how models like GPT-4 and LLaMA 3 are trained. As an infra engineer, you need to understand that this level of training hammers every resource simultaneously: GPU memory, NVLink bandwidth, InfiniBand throughput, and storage I/O.

📊 **Decision Matrix: Choosing a Parallelism Strategy**

| Model Size | Strategy | GPU Requirement | Network Requirement |
|---|---|---|---|
| < 1B parameters | Single GPU or DP | 1-8 GPUs | PCIe is fine |
| 1-10B parameters | DP + ZeRO-2 | 4-16 GPUs | NVLink preferred |
| 10-70B parameters | ZeRO-3 / FSDP | 8-64 GPUs | NVLink + InfiniBand |
| 70-200B+ parameters | 3D Parallelism | 64-512+ GPUs | NVLink + InfiniBand required |

---

## The NVIDIA Software Stack

Every GPU debugging session eventually comes down to software compatibility. The NVIDIA stack is a layered system where each layer depends on the one below it, and a mismatch at any level can cause failures that range from cryptic error messages to silent incorrect results.

### The Compatibility Chain

```
┌─────────────────────────────────────────────────────┐
│  Model Code (your ML team's training script)        │
├─────────────────────────────────────────────────────┤
│  Framework (PyTorch 2.x, TensorFlow, JAX)           │
├─────────────────────────────────────────────────────┤
│  cuDNN (optimized DL primitives) + NCCL (multi-GPU) │
├─────────────────────────────────────────────────────┤
│  CUDA Toolkit (libraries, runtime, compiler)        │
├─────────────────────────────────────────────────────┤
│  NVIDIA Driver (kernel module → GPU hardware)       │
├─────────────────────────────────────────────────────┤
│  GPU Hardware (A100, H100, etc.)                    │
└─────────────────────────────────────────────────────┘
```

**Driver**: The kernel-level module that communicates directly with GPU hardware. It must support your GPU architecture (an old driver won't recognize an H100). Each driver version has a maximum CUDA version it supports.

**CUDA Toolkit**: A collection of libraries, a runtime API, and a compiler (`nvcc`). The CUDA version in `nvidia-smi` shows the maximum CUDA version supported by the installed driver — not necessarily the version being used by your application.

**cuDNN**: NVIDIA's library of optimized deep learning primitives — convolutions, normalizations, recurrent operations. PyTorch and TensorFlow call cuDNN under the hood. cuDNN versions must match the CUDA Toolkit version.

**NCCL (NVIDIA Collective Communications Library)**: Handles multi-GPU communication — all-reduce, broadcast, all-gather. NCCL automatically detects the best available transport (NVLink, InfiniBand, PCIe) and optimizes accordingly. It's the engine behind PyTorch's `DistributedDataParallel` and DeepSpeed's communication layer.

**TensorRT**: NVIDIA's inference optimization engine. It analyzes a trained model and applies optimizations: layer fusion (combining multiple operations into one kernel), precision calibration (automatic FP32→INT8 conversion), and memory planning. TensorRT can deliver 2-5× inference speedup compared to running a model directly in PyTorch.

⚠️ **Production Gotcha: The Container Escape Hatch**

The most common GPU software issue is version mismatch: PyTorch was compiled against CUDA 12.1, but your VM has CUDA 11.8 drivers. Or cuDNN 8.6 is installed, but the framework expects 8.9. These mismatches produce errors like `CUDA error: no kernel image is available for execution on the device` or, worse, silent crashes.

The solution? **Use NVIDIA's prebuilt container images from NGC (NVIDIA GPU Cloud)**. Available at `nvcr.io/nvidia/pytorch` and `nvcr.io/nvidia/tensorflow`, these images bundle a specific, tested combination of Driver API compatibility, CUDA Toolkit, cuDNN, NCCL, and framework. Every layer is verified to work together.

```bash
# Pull the official NVIDIA PyTorch container (monthly releases)
docker pull nvcr.io/nvidia/pytorch:24.05-py3

# Run with GPU access
docker run --gpus all -it nvcr.io/nvidia/pytorch:24.05-py3
```

On Azure, the **NVIDIA GPU Driver Extension** handles driver installation on GPU VMs. For containerized workloads on AKS, the **NVIDIA Device Plugin** (deployed as a DaemonSet) exposes GPUs to Kubernetes pods. The combination of NVIDIA containers + Azure GPU extensions eliminates most software stack headaches.

💡 **Pro Tip**: When troubleshooting GPU software issues, always collect three version numbers first: `nvidia-smi` (driver + max CUDA version), `nvcc --version` (installed CUDA Toolkit), and `python -c "import torch; print(torch.version.cuda)"` (CUDA version PyTorch was compiled against). Mismatches between any of these are your most likely root cause.

---

## Reading nvidia-smi Like a Pro

`nvidia-smi` is the first tool you run when troubleshooting any GPU issue. It's the `top` command of the GPU world — a quick snapshot of what's happening on every GPU in the system. Learning to read it fluently will save you hours of debugging.

### Anatomy of nvidia-smi Output

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.161.08    Driver Version: 535.161.08    CUDA Version: 12.2               |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |          Memory-Usage  | GPU-Util  Compute M. |
|=========================================+========================+======================|
|   0  NVIDIA A100-SXM4-80GB         On   | 00000001:00:00.0  Off  |                    0 |
| N/A   42C    P0              72W / 400W |  71458MiB / 81920MiB   |     94%      Default |
|-----------------------------------------+------------------------+----------------------|
|   1  NVIDIA A100-SXM4-80GB         On   | 00000002:00:00.0  Off  |                    0 |
| N/A   39C    P0              68W / 400W |  71210MiB / 81920MiB   |     91%      Default |
|-----------------------------------------+------------------------+----------------------|
```

### Field-by-Field Breakdown

**Driver Version / CUDA Version** (top line): `535.161.08` is the installed driver. `CUDA Version: 12.2` is the *maximum* CUDA version this driver supports — not necessarily what your application is using.

**Persistence-M** (Persistence Mode): Should be `On` for servers. When `Off`, the driver unloads between jobs, adding seconds of latency to each GPU operation. Azure GPU VMs typically have this enabled by default.

**Temp**: GPU temperature in Celsius. Healthy training temps range from 35-75°C. Above **83°C**: thermal throttling begins — the GPU reduces clock speeds to cool down. Above **90°C**: danger zone — risk of crashes or hardware damage.

**Perf**: Performance state. **P0** = maximum performance. **P8** = idle. If you see P2 or lower during a training job, the GPU is being throttled (thermal or power). This should stay at P0 during active training.

**Pwr:Usage/Cap**: Power draw vs. limit. `72W / 400W` = 18% power draw — this GPU is not working hard. During training, you should see 250-350W on an A100. Near the cap means the GPU is fully loaded.

**Memory-Usage**: `71458MiB / 81920MiB` = 87% memory utilization. This is the number that tells you how close you are to an OOM error. Above 95% is risky. At 100%, the next allocation triggers `CUDA out of memory`.

**GPU-Util**: Compute utilization percentage. **94%** = excellent — the GPU is busy processing. **Below 50%** during training signals a problem: your GPUs are starving for data, waiting on CPU preprocessing, or waiting on network communication.

**Volatile Uncorr. ECC**: Uncorrectable ECC (Error-Correcting Code) errors since last reboot. **0** is expected. **Any non-zero value** means GPU memory cells are failing. This is a hardware problem — request VM replacement from Azure.

### Essential nvidia-smi Commands

```bash
# Basic snapshot (what you'll use 90% of the time)
nvidia-smi

# Continuous monitoring — refreshes every 5 seconds
nvidia-smi -l 5

# CSV output for scripting and dashboards
nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.used --format=csv

# GPU utilization monitoring (compact, real-time)
nvidia-smi dmon -s u

# GPU topology — verify NVLink connectivity
nvidia-smi topo -m

# Check for ECC errors (hardware health)
nvidia-smi --query-gpu=ecc.errors.uncorrected.volatile.total --format=csv

# List all running GPU processes
nvidia-smi pmon -s u -c 1
```

### What Healthy vs. Unhealthy Looks Like

| Metric | Healthy (Training) | Unhealthy / Investigate |
|---|---|---|
| GPU-Util | 85-100% | Below 50% |
| Memory-Usage | 70-95% of total | 100% (OOM imminent) or < 30% (underutilized) |
| Temperature | 35-75°C | Above 83°C (throttling) |
| Power | 60-90% of cap | Below 30% (idle GPU) or 100% sustained (throttling) |
| Perf State | P0 | P2 or higher during active job |
| ECC Errors | 0 | Any non-zero uncorrectable |

💡 **Pro Tip**: For continuous GPU monitoring in production, `nvidia-smi dmon` is more useful than repeated `nvidia-smi` calls. It outputs a compact, timestamped stream of GPU metrics that's easy to pipe into log aggregation systems. Combine it with Azure Monitor's GPU metrics for historical dashboards.

---

## GPU Debugging: The Troubleshooting Guide

These are the seven GPU issues you'll encounter most often in production AI infrastructure. For each one: what you see, why it happens, and what to do about it.

### 1. CUDA Out of Memory (OOM)

**What you see:**
```
RuntimeError: CUDA out of memory. Tried to allocate 2.00 GiB
(GPU 0; 79.35 GiB total capacity; 77.42 GiB already allocated)
```

**Why it happens:** The training job's combined memory needs (parameters + gradients + optimizer states + activations) exceed available GPU memory. The most common trigger is batch size — too many samples processed simultaneously inflate activation memory.

**What to do:**
1. **Reduce batch size** — the quickest fix. Cut it in half and retry.
2. **Enable gradient checkpointing** — trades ~20-30% compute for 60-80% activation memory savings.
3. **Enable ZeRO-2 or ZeRO-3** — shard optimizer states and gradients across GPUs.
4. **Use mixed precision** (BF16) — halves parameter and gradient memory.
5. **Move to a larger GPU** — A100-80GB instead of A100-40GB, or move to H100.

### 2. CUDA Version Mismatch

**What you see:**
```
RuntimeError: The current PyTorch install supports CUDA capabilities sm_80 sm_86 sm_90.
If you want to use the NVIDIA H100 GPU with PyTorch, please check the instructions at
https://pytorch.org/get-started/locally/
```

Or more cryptically:
```
CUDA error: no kernel image is available for execution on the device
```

**Why it happens:** PyTorch (or TensorFlow) was compiled against a specific CUDA version, and the installed driver doesn't support it — or the GPU architecture wasn't included in the build.

**What to do:**
1. Check the three version numbers: `nvidia-smi` (driver), `nvcc --version` (toolkit), `python -c "import torch; print(torch.version.cuda)"` (PyTorch CUDA).
2. Upgrade the NVIDIA driver to support the required CUDA version.
3. Or — the easier path — use an NVIDIA NGC container that bundles tested, compatible versions.

### 3. GPU Not Found / Driver Failures

**What you see:**
```
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver.
```
Or: `nvidia-smi` returns "No devices were found."

**Why it happens:** The NVIDIA driver isn't installed, failed to load, or the VM SKU doesn't actually include a GPU. On Azure, this can also happen when the GPU Driver VM Extension fails silently.

**What to do:**
1. Verify the VM SKU includes GPUs (NC, ND, NV series).
2. Check the Azure GPU Driver Extension status: `az vm extension list --resource-group <rg> --vm-name <vm> -o table`.
3. Reboot the VM — driver installation sometimes requires a restart.
4. Reinstall the extension or manually install the driver from NVIDIA's repository.

### 4. ECC Errors (Hardware Failure)

**What you see:**
```bash
$ nvidia-smi --query-gpu=ecc.errors.uncorrected.volatile.total --format=csv
ecc.errors.uncorrected.volatile.total
3
```

Or GPU processes crash intermittently with `CUDA error: uncorrectable ECC error encountered`.

**Why it happens:** Physical GPU memory cells have failed. Correctable ECC errors are automatically fixed by hardware (and are normal in small numbers). Uncorrectable errors mean data corruption — and there's no software fix.

**What to do:**
1. Confirm with `nvidia-smi -q -d ECC` for detailed ECC status.
2. Stop all workloads on the affected GPU.
3. On Azure, open a support request for hardware replacement. Azure will redeploy your VM to healthy hardware (note: GPU VMs do not support live migration — expect downtime during the move).
4. If using AKS, cordon the node to prevent new GPU workloads from scheduling.

### 5. Thermal Throttling

**What you see:** GPU temperature above 83°C in `nvidia-smi`. Performance state drops from P0 to P2 or P3. Training throughput drops by 20-40% compared to baseline.

**Why it happens:** Insufficient cooling, workload density too high (too many VMs on the same physical host generating heat), or ambient datacenter temperature issues.

**What to do:**
1. Monitor with `nvidia-smi dmon -s p` (power and thermal metrics).
2. In cloud environments, thermal throttling is Azure's problem — but document the issue and open a support ticket with GPU serial numbers and timestamps.
3. Reduce concurrent workloads if running multiple jobs per GPU (via MIG or time-slicing).
4. Consider VMs with better thermal profiles (SXM form factor GPUs have better cooling than PCIe).

### 6. Low GPU Utilization During Training

**What you see:** `GPU-Util` consistently below 50% during active training. Training is running, but GPUs spend most of their time idle.

**Why it happens:** The GPU is faster than the data pipeline can feed it. This is **data starvation** — the CPU can't preprocess and deliver training data fast enough. Common when reading from remote storage without caching, or when `num_workers` in the data loader is too low.

**What to do:**
1. Increase DataLoader `num_workers` (typically 4-8 per GPU).
2. Enable `pin_memory=True` in the DataLoader for faster CPU→GPU transfers.
3. Cache data on local NVMe (use BlobFuse2 with NVMe caching — see Chapter 2).
4. Pre-process data into optimized formats (WebDataset, TFRecord, Mosaic StreamingDataset).
5. Profile with `torch.profiler` to confirm the bottleneck is data loading, not communication.

⚠️ **Production Gotcha**: Low GPU utilization doesn't always mean data starvation. It can also indicate excessive gradient synchronization overhead (too many GPUs for a small model), pipeline bubbles (poorly configured pipeline parallelism), or a checkpoint-save operation blocking training. Check what the GPUs are waiting on before prescribing data pipeline fixes.

### 7. NVLink Not Detected

**What you see:**
```bash
$ nvidia-smi topo -m
        GPU0    GPU1    GPU2    GPU3
GPU0     X      PHB     PHB     PHB
GPU1    PHB      X      PHB     PHB
GPU2    PHB     PHB      X      PHB
GPU3    PHB     PHB     PHB      X
```

All connections show `PHB` (PCIe Host Bridge) or `PIX` (PCIe switch) instead of `NV#` (NVLink).

**Why it happens:** The VM SKU doesn't support NVLink (only ND-series VMs have NVLink on Azure), the driver version doesn't support the NVLink topology, or the NVLink hardware has a fault.

**What to do:**
1. Verify the VM SKU: NVLink is available on ND-series (ND96asr_v4, ND96amsr_A100_v4, ND_H100_v5, etc.). NC-series and NV-series use PCIe.
2. Update the NVIDIA driver to the latest version supported by your GPU.
3. If on the correct SKU with correct drivers and NVLink still doesn't appear, open an Azure support ticket — this indicates a hardware issue.

---

## GPU Generations at a Glance

As an infra engineer, you need to know what each GPU generation brings to the table — not for trivia, but because the generation determines what precision formats are supported, what bandwidth is available, and what software features are unlocked.

| Generation | Architecture | Key GPU | HBM Capacity | HBM Bandwidth | Tensor Core Gen | Key Innovation |
|---|---|---|---|---|---|---|
| **Volta** (2017) | GV100 | V100 | 16 / 32 GB (HBM2) | 900 GB/s | 1st gen | First Tensor Cores |
| **Ampere** (2020) | GA100 | A100 | 40 / 80 GB (HBM2e) | 2 TB/s | 3rd gen | TF32, Sparsity, MIG |
| **Hopper** (2022) | GH100 | H100 | 80 GB (HBM3) | 3.35 TB/s | 4th gen | FP8, Transformer Engine |
| **Blackwell** (2024) | GB200/GB300 | B200 | 192 GB (HBM3e) | 8 TB/s | 5th gen | FP4, NVLink 5.0 |

### Azure VM Mapping

| GPU | Azure VM Series | GPUs per VM | NVLink | InfiniBand |
|---|---|---|---|---|
| V100 | NC v3 | 1-4 | No | No |
| A100 40GB | ND A100 v4 | 8 | Yes (600 GB/s) | Yes (200 Gb/s) |
| A100 80GB | ND A100 v4 (80GB) | 8 | Yes (600 GB/s) | Yes (200 Gb/s) |
| H100 | ND H100 v5 | 8 | Yes (900 GB/s) | Yes (400 Gb/s) |
| B200 | ND GB200 v6 / ND GB300 v6 | 4 | Yes (1.8 TB/s) | Yes (400 Gb/s) |

💡 **Pro Tip**: Each generation roughly doubles the HBM bandwidth and introduces a new reduced-precision format. Ampere brought TF32 and structured sparsity. Hopper brought FP8 and the Transformer Engine (which automatically manages precision during training). Blackwell brings FP4, 192 GB of HBM per GPU, and NVLink 5.0 with 1.8 TB/s per VM. When the ML team says "we need H100s, not A100s," they're usually chasing the higher memory bandwidth and Transformer Engine — not just more FLOPS.

---

## Chapter Checklist

Before moving to the next chapter, make sure you can confidently answer these questions and perform these tasks:

- ✅ **Explain GPU architecture** — You can describe SMs, CUDA Cores, and Tensor Cores and explain why GPUs dominate matrix math workloads.
- ✅ **Diagnose memory issues** — You can calculate the memory footprint of a training job (parameters + gradients + optimizer states + activations) and explain why a "7B model" needs 90+ GB to train.
- ✅ **Understand precision tradeoffs** — You know the difference between FP32, BF16, FP16, and INT8/INT4, and when each is appropriate.
- ✅ **Choose a parallelism strategy** — Given a model size and GPU count, you can recommend DP, ZeRO-2, ZeRO-3/FSDP, or 3D parallelism.
- ✅ **Navigate the NVIDIA software stack** — You can explain the Driver → CUDA → cuDNN → NCCL → Framework chain and diagnose version mismatches.
- ✅ **Read nvidia-smi fluently** — You can interpret every field, identify healthy vs. unhealthy states, and use advanced monitoring commands.
- ✅ **Troubleshoot GPU issues** — You can diagnose and resolve OOM errors, version mismatches, driver failures, ECC errors, thermal throttling, low utilization, and NVLink problems.
- ✅ **Compare GPU generations** — You know the capabilities of V100, A100, H100, and B200, and which Azure VM SKUs map to each.

---

## What's Next

Now that you understand what's happening inside the GPU — the architecture, the memory hierarchy, the software stack, and the debugging playbook — it's time to automate everything around it. Chapter 5 covers **Infrastructure as Code for AI**: how to template GPU clusters, inference endpoints, and training pipelines so they're reproducible, version-controlled, and audit-ready. Because understanding GPUs is only half the battle — provisioning them consistently at scale is where infrastructure engineering truly meets AI.
