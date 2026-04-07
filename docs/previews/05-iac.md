# Chapter 5 — Infrastructure as Code for AI <span class="badge-premium">Full Book</span>

> *"Instead of Standard_NC6s_v3, the node pool is running Standard_D16s_v5 — a general-purpose CPU VM with no GPU at all."*

---

<div class="teaser-banner" markdown>

### 📖 This chapter is available in the full book

It started as a win. You manually provisioned a GPU cluster in East US 2 for an ML experiment — an AKS cluster with a Standard_NC6s_v3 node pool, accelerated networking, the right NVIDIA drivers, proper taints. It took most of a day, but it worked.

Three weeks later, the same team needs the identical setup in West US 3. Two days later, it's "done." Except it isn't. Someone fat-fingered the VM SKU. The training job launches, finds no CUDA device, falls back to CPU, and grinds along at a fraction of the expected speed. Nobody notices for three days. By the time someone checks, the cluster has burned through $4,000 in compute on a VM that can't do the one thing it was provisioned for.

</div>

## What You'll Learn in This Chapter

<div class="teaser-toc" markdown>

- The $4,000 Typo
- Why IaC Is Non-Negotiable for AI
- The IaC Landscape for AI
- Terraform for AI Infrastructure
- Bicep for AI Infrastructure
- CI/CD Pipelines for AI Infrastructure
- Governance and Guardrails
- Hands-On: Deploy an AKS GPU Cluster with Terraform

</div>

---

<div class="cta-group" markdown>

[Get the Full Book :fontawesome-solid-book:](https://leanpub.com/ai-for-infra-pros){ .cta-primary }
[Read Free Chapters :fontawesome-solid-glasses:](../index.md#free-chapters){ .cta-secondary }

</div>
