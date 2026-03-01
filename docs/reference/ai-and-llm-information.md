---
title: AI and LLM Information
description: AI/LLM references plus MCP planning links for homelab operations
published: true
date: 2026-02-19
tags:
  - ai
  - llm
  - machine-learning
  - resources
  - mcp
---

## MCP Operations

- [MCP Kubernetes Deployment Strategy](./mcp-kubernetes-deployment-strategy.md)
- [PostgreSQL HA (MCP sections)](./postgresql-ha.md#mcp-server-access)
- [Overnight Audit (MCP utilization)](../analysis/overnight-audit-2026-02-18.md#4-mcp-server-utilization)

## Active MCP Servers

The current `.mcp.json` configuration (as of 2026-02-26) includes:

| Server | Package/binary | Purpose |
|---|---|---|
| `context7` | `@upstash/context7-mcp` | Library documentation lookup |
| `github` | HTTP proxy via `api.githubcopilot.com` | GitHub API (issues, PRs, code search) |
| `kubernetes` | `kubernetes-mcp-server` | kubectl operations |
| `prometheus` | `prometheus-mcp` | Metric queries against Prometheus |
| `postgres` | `@modelcontextprotocol/server-postgres` | Read-only DB queries via mcp_readonly user |
| `terraform` | `/home/homelab-admin/go/bin/terraform-mcp-server` | Terraform registry lookups |
| `flux` | `/home/homelab-admin/.local/bin/flux-operator-mcp` | Flux CD status (read-only) |
| `gitlab` | `@modelcontextprotocol/server-gitlab` | GitLab API |
| `drawio` | `npx @drawio/mcp` | Create/open/export `.drawio` diagram files |

Note: After adding a new MCP server to `.mcp.json`, a Claude Code session restart is required to activate it.

## AI Coding Framework Reference

Nate Jones' five-levels framework for AI-assisted development provides a useful model for describing the intensity of AI involvement in a software project:

| Level | Name | Description |
|---|---|---|
| 0 | Spicy Autocomplete | AI suggests completions; human drives all decisions |
| 1 | Co-pilot | AI generates code blocks; human reviews and assembles |
| 2 | Pair programmer | AI and human collaborate on design and implementation |
| 3 | Developer as Manager | Human writes specs and reviews; AI executes full implementations |
| 4 | Developer as PM | Human writes product specs; AI handles full technical execution |
| 5 | Dark Factory | AI runs end-to-end with minimal human checkpoints |

Reference: [Simon Willison's summary](https://simonwillison.net/2026/Jan/28/the-five-levels/)

This homelab project operates at **Level 3** during active sessions: the human acts as a full-time code reviewer, approving or rejecting AI-generated PRs, writing specs for new features, and maintaining the GitOps configuration.

## Related Projects

### homelab-as-production

A Substack blog series documenting this homelab project as a production-grade infrastructure reference.

- Repository: `https://github.com/homelab-admin/homelab-as-production`
- ~17 posts, ~50k words (first draft complete 2026-02-26)
- Covers: infrastructure philosophy, K3s, GitOps, observability, security, SBOM, SSO, and developer tooling
- The blog series was developed using the same GitOps workflow documented in this repo

### agent-control-plane

A multi-agent orchestration hub at `~/git/valhalla/agent-control-plane` for coordinating Claude Code, Codex, Gemini, and GitHub Copilot on the same codebase.

- Phases 1-5 complete (agent adapters, task routing, shared context, result aggregation)
- Planned for future deployment as a K8s workload in the homelab cluster
- Would consume the in-cluster MCP servers described in [MCP Kubernetes Deployment Strategy](./mcp-kubernetes-deployment-strategy.md)

## Links

- Open-source AI Models
  - [Fireworks.ai](https://fireworks.ai/)
  - [Hugging Face](https://huggingface.co/)
  - [Meta AI](https://github.com/meta-llama/llama3)
  - [Google Gemma 2](https://huggingface.co/google/gemma-2b)
  - [Command R+](https://huggingface.co/CohereForAI/c4ai-command-r-plus)
  - [Misral-8x22b](https://huggingface.co/mistralai/Mixtral-8x22B-Instruct-v0.1)
  - [Falcon 2](https://github.com/falconpl/Falcon2)
  - [Qwen1.5](https://github.com/QwenLM/Qwen2)
  - [Bloom](https://github.com/huggingface/transformers/blob/main/src/transformers/models/bloom)
  - [GPT-NeoX](https://github.com/EleutherAI/gpt-neox)
  - [Vicuna-13B](https://github.com/lm-sys/FastChat)
