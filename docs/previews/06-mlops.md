# Chapter 6 — Model Lifecycle and MLOps from an Infra Lens <span class="badge-premium">Full Book</span>

> *"Here's the model. It's a 15 GB PyTorch checkpoint. We need it in production by Friday."*

---

<div class="teaser-banner" markdown>

### 📖 This chapter is available in the full book

A data scientist drops a message in your team's channel with a link to a shared drive. "Here's the model. It's a 15 GB PyTorch checkpoint. We need it in production by Friday." You open the folder and find a single file: `model_final_v2_FIXED.pt`.

You start asking questions. Which version is this? What data was it trained on? What's the rollback plan? The answers are vague. "It's the latest one. It works on my machine. Just put it behind an API."

You've seen this movie before — just with different actors. Developers used to hand you a compiled binary and say "deploy this." That chaos led your industry to build container registries, CI/CD pipelines, semantic versioning, and automated rollback. Models are no different.

</div>

## What You'll Learn in This Chapter

<div class="teaser-toc" markdown>

- The Model That Arrived Without a Birth Certificate
- Models Are Artifacts — Treat Them Like It
- Model Registries
- CI/CD for Models
- A/B Testing and Canary Deployments for Models
- Model Supply Chain Security
- Reproducible Training Environments
- Feature Stores — The Infra View

</div>

---

<div class="cta-group" markdown>

[Get the Full Book :fontawesome-solid-book:](https://leanpub.com/ai-for-infra-pros){ .cta-primary }
[Read Free Chapters :fontawesome-solid-glasses:](../index.md#free-chapters){ .cta-secondary }

</div>
