# Chapter 15 — Visual Glossary: Infra ↔ AI Translation Guide

> "You already speak infrastructure fluently. AI isn't a foreign language — it's a dialect."

## Introduction

This chapter is your quick-reference card. Every AI term you'll encounter in production is mapped to an infrastructure concept you already know — complete with a one-line definition, a practical analogy, and context for when that term will actually matter in your day-to-day work. Whether you're reviewing an architecture diagram, sitting in a planning meeting with data scientists, or troubleshooting a GPU cluster at 2 AM, this is the chapter you'll keep pinned.

The glossary is organized into six categories — Core AI Concepts, Data and Storage, Compute and Hardware, Model Operations, Deployment and Serving, and Advanced Concepts — with terms listed alphabetically within each section for fast lookup. Every entry uses the same format: the AI term, an infra analogy in parentheses, a concise definition, and a "when you'll encounter this" note. At the end, you'll find a condensed quick-reference card with the 20 most essential terms on a single page. Tear it out, bookmark it, pin it to your monitor — this is your Rosetta Stone.

---

## 🔄 Category 1: Core AI Concepts

| AI Term | Infra Analogy | Definition | When You'll See It |
|---------|---------------|------------|--------------------|
| **Artificial Intelligence** | Umbrella automation discipline | The broad field encompassing any system that performs tasks typically requiring human intelligence — from rule-based automation to generative models. | When scoping AI projects and understanding where ML, deep learning, and LLMs fit within the larger discipline. |
| **Batch Size** | Chunk size | The number of training samples processed before the model updates its weights. Larger batches use more GPU memory but train more efficiently. | When tuning training jobs and troubleshooting GPU out-of-memory (OOM) errors — reducing batch size is often the first fix. |
| **Deep Learning** | Multi-layered ML (like nested load balancers) | A subset of machine learning using neural networks with many layers to learn complex patterns from raw data (images, text, audio). | When workloads require GPUs rather than CPUs — deep learning is almost always the reason for GPU infrastructure requests. |
| **Epoch** | Full backup cycle | One complete pass through the entire training dataset. Models typically train for tens to hundreds of epochs. | When estimating training job duration and cost — more epochs mean longer jobs and higher compute bills. |
| **Fine-tuning** | Configuration customization | Adapting a pre-trained model to your specific domain by training it further on your own data, adjusting its weights for specialized tasks. | When teams need a model that understands company-specific terminology, internal processes, or domain knowledge. |
| **Foundation Model** | Base image | A large, pre-trained model (like GPT-4, LLaMA, or Mistral) designed to be adapted for many downstream tasks, much like a golden VM image used as a starting point. | When selecting which base model to deploy or fine-tune — this is the starting artifact in most AI projects. |
| **Inference** | API endpoint | Running a trained model with new data to generate predictions or responses. Real-time, latency-sensitive, and the operational phase of AI. | Every time a user or system calls an AI service — inference is the production workload you'll monitor and scale. |
| **Large Language Model (LLM)** | Specialized API service (text-in, text-out) | A foundation model specifically trained on massive text corpora to understand and generate human language. GPT-4, Claude, and LLaMA are examples. | When deploying Azure OpenAI endpoints, sizing token quotas, and planning capacity for chat or text generation workloads. |
| **Machine Learning** | Statistical pattern recognition | A subset of AI where systems learn patterns from data rather than following explicit rules — like auto-scaling rules that learn optimal thresholds from historical metrics. | When evaluating whether a workload needs GPU compute, specialized storage, or ML pipeline infrastructure. |
| **Model** | Compiled binary | The trained artifact — the output of a training job, packaged and deployed to serve predictions. Contains the learned parameters that define its behavior. | When managing deployments, versioning artifacts, or sizing storage — models range from megabytes to hundreds of gigabytes. |
| **Neural Network** | Multi-stage CI/CD pipeline | A processing architecture where data flows through interconnected layers of nodes, each transforming the input progressively — like a pipeline with build, test, and deploy stages. | When understanding why AI workloads need parallel compute — each layer performs matrix operations that GPUs accelerate. |
| **Parameters** | Configuration values | The internal values learned during training that define how a model processes input and generates output. GPT-4 has over a trillion parameters. | When sizing infrastructure — more parameters mean more memory, more compute, and more storage for the model. |
| **Training** | Batch job | The process of teaching a model by feeding it data and adjusting its parameters. Long-running, GPU-intensive, reads the entire dataset repeatedly. | When provisioning GPU clusters, estimating job duration, and planning for large-scale compute bursts. |
| **Transfer Learning** | Template reuse | Using a model pre-trained on one task as the starting point for a different task, preserving learned knowledge and reducing training time and data requirements. | When teams want to get results faster and cheaper by starting from a foundation model instead of training from scratch. |
| **Weights** | Same as parameters | The actual numerical values stored inside a model. "Weights" and "parameters" are often used interchangeably — these are the numbers that make the model work. | When managing model files on disk, transferring checkpoints, or calculating storage and memory requirements. |

---

## 🔄 Category 2: Data and Storage

| AI Term | Infra Analogy | Definition | When You'll See It |
|---------|---------------|------------|--------------------|
| **Data Augmentation** | Synthetic data generation | Creating modified copies of existing training data (rotations, noise, paraphrasing) to increase dataset size and improve model robustness. | When data scientists request additional storage for expanded datasets or when training pipelines include preprocessing stages. |
| **Data Drift** | Schema change / input distribution shift | When the statistical properties of production input data diverge from the data the model was trained on, causing accuracy degradation over time. | When model performance degrades in production without code changes — data drift is the silent killer of ML accuracy. |
| **Dataset** | Data source / storage volume | The structured or unstructured data used to train, validate, or test a model. Can range from gigabytes to petabytes. | When provisioning storage, planning data pipelines, and managing access controls for training data. |
| **Embedding** | Hash / index key | A numerical vector representation of text, images, or other data that captures semantic meaning, enabling similarity search and comparison. | When deploying RAG architectures, building search systems, or sizing vector databases for semantic retrieval. |
| **Feature** | Column in a database / input variable | A single measurable property of the data used as input to a model — like CPU utilization, request count, or user age. | When data engineers build data pipelines and you provision the compute and storage for feature extraction jobs. |
| **Feature Store** | Caching layer for ML inputs | A centralized repository that stores, manages, and serves pre-computed features for both training and inference, ensuring consistency. | When architecting ML platforms that need low-latency access to processed features at inference time. |
| **Tokenization** | Serialization | The process of breaking text into smaller units (tokens) that a model can process — similar to how serialization converts objects into transmittable formats. | When calculating costs (you pay per token), estimating context window usage, and optimizing prompt length. |
| **Vector Database** | Search index | A specialized database that stores embeddings and retrieves them using similarity search (nearest-neighbor) rather than exact-match queries. | When deploying RAG solutions, building semantic search, or provisioning Azure AI Search with vector capabilities. |

---

## 🔄 Category 3: Compute and Hardware

| AI Term | Infra Analogy | Definition | When You'll See It |
|---------|---------------|------------|--------------------|
| **CUDA** | GPU instruction set / SDK | NVIDIA's parallel computing platform and API that lets developers write code executed on GPUs. The foundation of most AI compute. | When installing GPU drivers, configuring containers for GPU workloads, or troubleshooting "CUDA out of memory" errors. |
| **GPU** | Coprocessor | A processor designed for massive parallel computation, offloading matrix math from the CPU the way a NIC offloads network processing. Essential for training and inference. | Everywhere in AI infrastructure — from provisioning VM SKUs (NC, ND series) to monitoring utilization and managing costs. |
| **HBM (High Bandwidth Memory)** | GPU RAM | Specialized high-speed memory stacked directly on the GPU die, providing the bandwidth needed for large model operations. A100 has 80 GB HBM2e. | When selecting GPU SKUs — HBM capacity determines the maximum model size a single GPU can hold in memory. |
| **InfiniBand** | High-speed node-to-node networking | Ultra-low-latency, high-bandwidth interconnect used for distributed training across multiple nodes, far faster than standard Ethernet. | When provisioning multi-node GPU clusters (ND-series VMs) for large-scale training jobs that span multiple machines. |
| **NCCL** | Multi-GPU communication library | NVIDIA's Collective Communications Library — handles data exchange between GPUs during distributed training (all-reduce, broadcast, etc.). | When troubleshooting distributed training failures, network timeouts between GPUs, or multi-node scaling issues. |
| **NVLink** | GPU-to-GPU interconnect | A high-speed link connecting GPUs within a single node, providing ~10× the bandwidth of PCIe for GPU-to-GPU data transfer. | When sizing multi-GPU VMs — NVLink-connected GPUs can share data fast enough to act as a unified memory pool. |
| **Tensor Core** | Specialized matrix math unit | Dedicated hardware units within NVIDIA GPUs optimized for the matrix multiply-and-accumulate operations that dominate AI workloads. | When evaluating GPU generations — Tensor Cores are why an A100 is dramatically faster for AI than a gaming GPU with similar specs. |
| **TPU (Tensor Processing Unit)** | Google's custom AI chip | Google's purpose-built ASIC for accelerating machine learning workloads, available through Google Cloud. | When evaluating multi-cloud AI strategies or comparing Google Cloud's AI infrastructure to Azure's GPU offerings. |

---

## 🔄 Category 4: Model Operations

| AI Term | Infra Analogy | Definition | When You'll See It |
|---------|---------------|------------|--------------------|
| **Backpropagation** | Feedback loop | The algorithm that calculates how each weight contributed to the model's error, flowing error signals backward through the network to update weights. | When understanding why training is compute-intensive — backpropagation requires a full reverse pass through every layer. |
| **Checkpoint** | Snapshot / backup | A saved copy of model state during training — weights, optimizer state, and training progress — enabling resumption after failures. | When managing storage for training jobs (checkpoints can be tens of GB each) and designing fault-tolerant training pipelines. |
| **Gradient** | Error signal | A mathematical value indicating the direction and magnitude of weight adjustments needed to reduce the model's error. | When troubleshooting training instability — "exploding gradients" and "vanishing gradients" are common failure modes. |
| **Hyperparameter** | Tunable config value | A value set before training begins that controls the training process itself — learning rate, batch size, number of layers — like thread count or connection pool size. | When data scientists request multiple training runs with different configurations — each combination is a separate compute job. |
| **Loss Function** | Error metric | A mathematical function that measures how far the model's predictions are from the correct answers. Training aims to minimize this value. | When monitoring training progress — the loss curve should trend downward. A flat or rising loss indicates problems. |
| **MLOps** | DevOps for models | The discipline of applying DevOps practices — CI/CD, versioning, monitoring, automation — to the machine learning lifecycle. | When building ML platforms, designing model deployment pipelines, and implementing model monitoring and governance. |
| **Model Registry** | Container registry for models | A versioned repository for storing, cataloging, and managing trained model artifacts — like Azure Container Registry but for models. | When implementing MLOps pipelines that need to version, promote, and roll back model deployments across environments. |
| **Optimizer** | Learning rate controller | The algorithm that determines how model weights are updated during training (Adam, SGD, AdamW). Controls the speed and stability of learning. | When tuning training performance — optimizer choice and learning rate are the most impactful hyperparameters. |

---

## 🔄 Category 5: Deployment and Serving

| AI Term | Infra Analogy | Definition | When You'll See It |
|---------|---------------|------------|--------------------|
| **Completion** | API response body | The model's generated output in response to a prompt. In chat APIs, this is the assistant's reply returned to the caller. | When parsing API responses, calculating output token costs, and monitoring response quality and latency. |
| **Context Window** | Maximum request payload size | The maximum number of tokens a model can process in a single request (prompt + completion combined). GPT-4o supports 128K tokens. | When designing prompts and RAG systems — exceeding the context window truncates input or causes errors. |
| **Inference Endpoint** | API endpoint serving predictions | A deployed model exposed as an HTTP API that accepts input and returns predictions or generated text in real-time. | When provisioning, scaling, and monitoring the production-facing AI service — this is your primary operational surface. |
| **Prompt** | API request body | The text input sent to a model to guide its output — instructions, context, examples, and the actual question or task. | Every interaction with an LLM — prompt design directly impacts output quality, token consumption, and cost. |
| **Provisioned Throughput (PTU)** | Reserved capacity (like reserved VM instances) | Pre-allocated, guaranteed compute capacity for Azure OpenAI models, providing consistent latency and throughput regardless of platform load. | When workloads need predictable performance — PTU eliminates throttling at a fixed cost, like reserved instances for AI. |
| **RAG (Retrieval-Augmented Generation)** | Dynamic prompt enrichment from external data | A pattern that retrieves relevant documents from a knowledge base and injects them into the prompt before the model generates a response. | When building enterprise AI solutions that need to answer questions using company-specific, up-to-date data. |
| **Requests Per Minute (RPM)** | Request rate limit | The maximum number of API calls allowed per minute for a model deployment, enforced at the endpoint level. | When capacity planning and troubleshooting HTTP 429 errors — RPM limits are independent of token quotas. |
| **Tokens Per Minute (TPM)** | Bandwidth / throughput quota | The maximum number of tokens (input + output) processed per minute for a model deployment. The primary throughput metric for LLM endpoints. | When sizing deployments, estimating costs, and diagnosing throttling — TPM is the most common capacity constraint. |

---

## 🔄 Category 6: Advanced Concepts

| AI Term | Infra Analogy | Definition | When You'll See It |
|---------|---------------|------------|--------------------|
| **Data Parallelism** | Sharding data across GPUs | A distributed training strategy where the dataset is split across GPUs, each processing a different batch with a copy of the full model. | When scaling training to multiple GPUs — data parallelism is the default and simplest distributed training approach. |
| **LoRA (Low-Rank Adaptation)** | Lightweight fine-tuning | A technique that fine-tunes a small adapter layer (~1-2% of parameters) instead of the full model, dramatically reducing compute and memory requirements. | When teams want to customize a foundation model without the cost of full fine-tuning — LoRA makes customization accessible. |
| **Mixed Precision** | Variable data type optimization | Training with a mix of FP32 and BF16/FP16 data types — using lower precision where possible to reduce memory usage and increase throughput without losing accuracy. | When optimizing training jobs for speed and cost — mixed precision can nearly double throughput on modern GPUs. |
| **Model Parallelism** | Sharding model across GPUs | Splitting a single model across multiple GPUs when it's too large to fit in one GPU's memory, with each GPU holding a portion of the layers. | When deploying very large models (70B+ parameters) that exceed a single GPU's HBM capacity. |
| **Pipeline Parallelism** | Assembly line across GPUs | A distributed training approach where model layers are distributed across GPUs in sequence, with micro-batches flowing through like an assembly line. | When training very large models across many GPUs — pipeline parallelism reduces the memory-per-GPU requirement. |
| **Prompt Injection** | SQL injection for AI | An attack where untrusted input is crafted to override or manipulate a model's system instructions, causing unintended behavior or data leakage. | When securing AI endpoints exposed to user input — prompt injection is the #1 security concern for LLM applications. |
| **Quantization** | Compression | Reducing model precision (e.g., FP32 → INT8 or INT4) to shrink model size and accelerate inference, trading a small accuracy loss for major efficiency gains. | When deploying models to production with cost or latency constraints — quantization can cut memory usage by 4× or more. |
| **ZeRO (Zero Redundancy Optimizer)** | Memory optimization for distributed training | A family of techniques that partition optimizer states, gradients, and parameters across GPUs to eliminate redundant memory usage during distributed training. | When training large models that don't fit in GPU memory even with data parallelism — ZeRO is the standard solution in DeepSpeed. |

---

## 🔄 Quick Reference Card — Top 20 Terms

*Pin this page. Screenshot it. Print it out.*

| # | AI Term | 🔄 Infra Translation |
|---|---------|----------------------|
| 1 | **Model** | A compiled binary — the deployable output of training |
| 2 | **Training** | A long-running batch job that produces a model |
| 3 | **Inference** | An API call — real-time request/response against a deployed model |
| 4 | **GPU** | A coprocessor that offloads matrix math, like a NIC offloads networking |
| 5 | **LLM** | A text-in/text-out API service built on a massive trained model |
| 6 | **Prompt** | The API request body — instructions and context sent to the model |
| 7 | **Completion** | The API response body — what the model sends back |
| 8 | **Token** | The smallest processing unit — you pay per token like you pay per byte transferred |
| 9 | **Context Window** | Maximum request payload size — the model's input buffer limit |
| 10 | **Fine-tuning** | Customizing a base image — adapting a pre-trained model with your data |
| 11 | **RAG** | Dynamic prompt enrichment — injecting retrieved data before generation |
| 12 | **Embedding** | A hash/index key — numerical representation for similarity search |
| 13 | **Vector Database** | A search index optimized for nearest-neighbor similarity queries |
| 14 | **TPM** | Bandwidth quota — tokens per minute, the primary throughput limit |
| 15 | **PTU** | Reserved capacity — guaranteed throughput like reserved VM instances |
| 16 | **MLOps** | DevOps for models — CI/CD, versioning, monitoring for ML |
| 17 | **Checkpoint** | A snapshot/backup — saved model state for fault tolerance |
| 18 | **Parameters** | Configuration values — the learned numbers that define model behavior |
| 19 | **Data Drift** | Schema change — when production input diverges from training data |
| 20 | **Prompt Injection** | SQL injection for AI — untrusted input manipulating model behavior |

---

## How to Use This Glossary

This chapter is designed to be a living reference. Here are three ways to get the most from it:

1. **During architecture reviews** — Look up unfamiliar terms before meetings with data science teams. The infra analogies give you instant mental models.
2. **When troubleshooting** — AI failures often map to infrastructure problems you've solved before. "GPU OOM" is just a memory pressure issue. "Token limit exceeded" is a payload size error. The translation helps you triage faster.
3. **For capacity planning** — Terms like TPM, RPM, PTU, context window, and batch size directly impact sizing decisions. Understanding what they mean in infra terms helps you plan accurately.

> "From VMs to inference, from logs to tokens, from pipelines to neural networks — you already had the mental models. Now you have the vocabulary."
