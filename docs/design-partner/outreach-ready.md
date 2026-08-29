# Ready-to-send outreach (copy/paste)

**Landing page:** https://narendranadh6.github.io/asta-cloud/  
**GitHub:** https://github.com/narendranadh6/asta-cloud  
**Install:** `pip install asta-cloud==0.10.0`

Replace `{{first_name}}` before sending. Sign as Narendra.

---

## Email 1 — cold (platform lead)

**To:** _pick from target list below_  
**Subject:** PR security checks for your agent code?

Hi {{first_name}},

I built **ASTA Cloud** — a CI scanner for LangChain / OpenAI Agents / MCP / RAG Python code. It catches issues generic SAST misses: missing tool allowlists, unscoped memory, unsafe handoffs, MCP exposure.

It runs in GitHub Actions on every PR (policy gate + comment). We validated it on LangChain and OpenAI Agents SDK production trees with zero noise after tuning.

We're onboarding **5 design partners** for a 30-day pilot ($500–2k/mo) with hands-on setup.

- Landing: https://narendranadh6.github.io/asta-cloud/
- 60-second setup: https://github.com/narendranadh6/asta-cloud/blob/main/docs/github-integration.md

Worth a 15-minute look this week?

— Narendra

---

## Email 2 — warm (LinkedIn / intro)

**Subject:** Following up — agent security in CI

Hi {{first_name}},

Good connecting. You mentioned shipping agents faster than security review can keep up — that's what we're solving with ASTA Cloud.

Static scans on every PR: tools, memory scoping, handoffs, MCP/RAG patterns. No code execution, no LLM calls.

Looking for 5 teams to pilot the GitHub Action + policy workflow. Happy to run a scan on a public repo you point us at (read-only, local).

Open to a quick demo?

— Narendra

---

## Email 3 — security champion

**Subject:** SARIF + policy gate for AI agent repos?

Hi {{first_name}},

Quick one: are you running anything in CI today for **agent-specific** risks (tool sprawl, memory isolation, MCP resources)?

ASTA Cloud outputs SARIF, supports baselines for legacy debt, and fails PRs on `fail_on: high`. Tuned against LangChain and OpenAI Agents production code.

Piloting with 5 companies — 30 days, includes baseline migration and rule tuning.

Interested in seeing it on your stack?

— Narendra

---

## Email 4 — follow-up (no reply, send day 5–7)

**Subject:** Re: agent CI security

Hi {{first_name}},

Bumping this in case it got buried. Happy to:

1. Send a 2-minute screen recording of the PR check, or
2. Run ASTA on a public repo you name (no access needed)

If timing's wrong, who owns agent platform security on your side?

— Narendra

---

## Email 5 — post-demo close

**Subject:** ASTA pilot next steps

Hi {{first_name}},

Great speaking today. Recap:

- **Pilot:** 30 days, Team tier ($1,200/mo)
- **Scope:** up to 3 repos, GitHub Action + `asta.yaml` policy + baseline
- **Start:** _agree date_

**Workflow to add** (`.github/workflows/asta.yml`):

```yaml
name: ASTA Security
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
  pull-requests: write
jobs:
  asta:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: narendranadh6/asta-cloud/action@v0.10.0
        with:
          path: .
          config: asta.yaml
          post-comment: true
```

**Install locally:** `pip install asta-cloud==0.10.0`

Next steps:

1. Grant GitHub Action access to the pilot repo(s)
2. Baseline snapshot call (30 min)
3. Enable PR gate at `fail_on: high`

Confirm and we'll kick off.

— Narendra

---

## Suggested first 5 targets

| # | Company | Contact idea | Role | Channel | Email to use |
| --- | --- | --- | --- | --- | --- |
| 1 | LangChain | Platform / DX lead | Platform | LinkedIn warm intro | Email 2 |
| 2 | CrewAI | Founder or eng lead | AI eng | Cold email | Email 1 |
| 3 | LlamaIndex | Security or platform | Security | LinkedIn | Email 3 |
| 4 | Series A agent startup (your network) | CTO you know | CTO | Warm intro | Email 2 |
| 5 | AI security consultancy (e.g. NCC, Trail of Bits alum shop) | Partner | Consultancy | Cold | Email 1 |

**Send order:** 3 cold/warm on Monday → follow up Friday with Email 4 → Email 5 after any demo.

---

## Share snippet (Twitter / LinkedIn / Slack)

```
Shipped ASTA Cloud v0.10 — SAST for AI agent code in CI.

✅ LangChain / OpenAI Agents patterns
✅ PR policy gate + comments
✅ Baseline for legacy repos

pip install asta-cloud==0.10.0
https://narendranadh6.github.io/asta-cloud/
```
