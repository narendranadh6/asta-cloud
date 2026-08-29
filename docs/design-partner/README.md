# ASTA Cloud — design partner kit

Use this kit to run **5 design-partner conversations** before building a full dashboard.

## Goal

Validate willingness to pay for:

- PR policy gates on AI agent code
- Baseline/suppression for legacy repos
- Future org-wide GitHub App + dashboard

**Target offer:** 30-day pilot at **$500–2,000/month** with white-glove onboarding.

---

## One-pager (talk track)

### Problem

Teams shipping LangChain / OpenAI Agents / MCP / RAG apps lack **CI checks for agent-specific risks**: unscoped memory, missing tool allowlists, unsafe handoffs, broad filesystem tools, MCP exposure.

Generic SAST misses these patterns. Manual review does not scale.

### Solution

**ASTA Cloud** — static SAST for AI agents. Runs in GitHub Actions on every PR.

- 17 deterministic rules (tools, memory, handoffs, MCP, RAG, secrets)
- SARIF + PR comments + policy gate (`fail_on: high`)
- Baseline file for adopting without blocking on legacy debt
- Validated on LangChain and OpenAI Agents SDK production code (0 false positives after tuning)

### What you get in the pilot

1. GitHub Action installed on 1–3 repos
2. Policy + baseline setup workshop (1 hour)
3. Weekly tuning for your stack
4. Direct line for false-positive fixes
5. Early access to GitHub App (org install)

### What we need from you

- 1 platform or security champion
- 1–3 Python agent repos
- 30 minutes/week feedback for 4 weeks
- Permission to publish anonymized metrics (optional)

### Pricing (pilot)

| Tier | Price | Includes |
| --- | --- | --- |
| Starter pilot | $500/mo | 1 repo, Action setup, email support |
| Team pilot | $1,200/mo | 3 repos, baseline migration, Slack channel |
| Enterprise pilot | $2,000/mo | Monorepo, custom rules, weekly review |

---

## Demo script (15 minutes)

1. **Hook (2 min)** — "We scan agent code like Snyk scans dependencies, but for tools/memory/handoffs."
2. **Live scan (5 min)**
   ```bash
   pip install asta-cloud
   asta scan ./examples/vulnerable_agent --format text
   asta scan ./examples/safe_agent --format text  # clean
   ```
3. **CI story (5 min)** — Show PR comment mock / workflow file. Explain `fail_on` + baseline.
4. **Proof (2 min)** — LangChain + OpenAI Agents SDK: production scans clean.
5. **Ask (1 min)** — "If this blocked unsafe PRs last month, would that have been worth $1k/mo?"

---

## Outreach emails

### Email 1 — cold (platform lead)

**Subject:** PR security checks for your agent code?

Hi {{first_name}},

I built **ASTA Cloud** — a CI scanner for LangChain / OpenAI Agents / MCP / RAG Python code. It catches issues generic SAST misses: missing tool allowlists, unscoped memory, unsafe handoffs, MCP exposure.

It runs in GitHub Actions on PRs (policy gate + comment), validated on LangChain and OpenAI Agents SDK with zero production noise.

We're onboarding **5 design partners** for a 30-day pilot ($500–2k/mo) with hands-on setup.

Worth a 15-minute look this week?

— {{your_name}}

---

### Email 2 — warm (met at event / LinkedIn)

**Subject:** Following up — agent security in CI

Hi {{first_name}},

Good connecting {{context}}. You mentioned shipping agents faster than security review can keep up — that's exactly what we're solving with ASTA Cloud.

Static scans on every PR: tools, memory scoping, handoffs, MCP/RAG patterns. No code execution, no LLM calls.

Looking for 5 teams to pilot the GitHub Action + policy workflow. Happy to run a scan on one of your repos (read-only, local).

Open to a quick demo?

— {{your_name}}

---

### Email 3 — security champion

**Subject:** SARIF + policy gate for AI agent repos?

Hi {{first_name}},

Quick one: are you running anything in CI today for **agent-specific** risks (tool sprawl, memory isolation, MCP resources)?

ASTA Cloud outputs SARIF, supports baselines for legacy debt, and fails PRs on `fail_on: high`. We tuned it against LangChain and OpenAI Agents production trees.

Piloting with 5 companies — 30 days, includes baseline migration and rule tuning.

Interested in seeing it on {{company}}'s stack?

— {{your_name}}

---

### Email 4 — follow-up (no reply)

**Subject:** Re: agent CI security

Hi {{first_name}},

Bumping this in case it got buried. Happy to:

1. Send a 2-minute screen recording of the PR check, or
2. Run ASTA on a public repo you point us at (no access needed)

If timing's wrong, who owns agent platform security on your side?

— {{your_name}}

---

### Email 5 — post-demo close

**Subject:** ASTA pilot next steps

Hi {{first_name}},

Great speaking today. Recap:

- **Pilot:** 30 days, {{tier}} (${{price}}/mo)
- **Scope:** {{repos}} repos, GitHub Action + `asta.yaml` policy + baseline
- **Start:** {{date}}

Next steps:

1. You grant GitHub Action access to {{repo}}
2. We run baseline snapshot call (30 min)
3. Enable PR gate at `fail_on: high`

I'll send the workflow file and a sample `asta.yaml`. Confirm and we'll kick off.

— {{your_name}}

---

## Target list (fill in)

| # | Company | Contact | Role | Channel | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | | | Platform | | |
| 2 | | | Security | | |
| 3 | | | AI eng lead | | |
| 4 | | | Startup CTO | | |
| 5 | | | Consultancy | | |

---

## Objection handling

| Objection | Response |
| --- | --- |
| "We have Snyk/Semgrep" | "Great for general code. ASTA targets agent patterns they don't model." |
| "Too many false positives" | "We validated on LangChain + OpenAI Agents prod. Baselines handle legacy." |
| "Not ready to pay" | "Start free on the Action. Pilot is for tuning + priority support." |
| "Need on-prem" | "CLI/Docker already local. Enterprise pilot includes air-gapped support." |
