# Chapter 3 — Compute: Where Intelligence Comes to Life <span class="badge-premium">Full Book</span>

> *"Compute for AI isn't about raw horsepower. It's about the right kind of horsepower, connected in the right way."*

---

<div class="teaser-banner" markdown>

### 📖 This chapter is available in the full book

Picture this: your ML team asks you to provision "a GPU cluster for training." You do what any seasoned infrastructure engineer would do — spin up eight `Standard_D16s_v5` virtual machines. Sixty-four vCPUs each, 128 GiB of RAM, premium SSD storage. On paper, serious horsepower.

The team launches their training script. Progress bar: estimated completion in **47 hours**. Then a colleague suggests two `Standard_ND96asr_v4` nodes — each packing eight A100 GPUs connected by 200 Gb/s InfiniBand. Same training job, same dataset, same code. The job finishes in **90 minutes**.

The difference isn't just the GPUs. It's how those GPUs talk to each other across nodes, how data flows through NVLink inside the node, and how InfiniBand keeps gradient synchronization from becoming the bottleneck.

</div>

## What You'll Learn in This Chapter

<div class="teaser-toc" markdown>

- The story you don't want to live
- Training vs. Inference: Two Different Worlds
- The Compute Spectrum: CPU, GPU, and Beyond
- Azure GPU VM Families — The Decision Matrix
- Clustering: When One VM Isn't Enough
- Networking: The Hidden Multiplier
- Example Architecture: LLM Inference on AKS
- Hands-On: Create Your First GPU VM
- Monitoring GPU Workloads
- Security Considerations

</div>

---

<div class="cta-group" markdown>

[Get the Full Book :fontawesome-solid-book:](https://leanpub.com/ai-for-infra-pros){ .cta-primary }
[Read Free Chapters :fontawesome-solid-glasses:](../index.md#free-chapters){ .cta-secondary }

</div>
