# zlar.ai

Static public website for ZLAR Inc.

The current information architecture is a plain public path:

- "ZLAR is where AI action becomes answerable."
- "ZLAR keeps humans in the loop when AI starts doing real things."
- "AI can move. Humans remain present. Actions become answerable."
- "If AI affected you, ask for the receipt."

## Primary Pages

| Page | Path | Purpose |
| --- | --- | --- |
| Homepage | `index.html` | Plain voice spine, operator routing, sample receipt, scope disclosure, contact |
| Enterprise | `enterprise.html` | Rules before enterprise AI changes files, calls tools, or starts workflows |
| Government | `government.html` | Public records for AI actions: what happened, what rule applied, and what proof remains |
| Financial Services | `financial-services.html` | The gap between login and what AI is allowed to do |
| Healthcare | `healthcare.html` | Bounded healthcare workflow framing without clinical claims |
| Defense / Military | `defense.html` | Command visibility, rules, people, and proof for routed actions |
| Founder Note | `founder-note.html` | First-person statement of the threshold thesis |
| Sample receipt | `proof-pack.html` | Human-first sample receipt with optional bounded terminal verification |
| Open Memo | `open-memo.html` | Policy memo for rules before action and receipts afterward |
| Boundaries | `boundaries.html` | What passes through ZLAR, what does not, and what the sample does not prove |
| Archive | `archive.html` | Affected-person pathway, Sealed Mode, older material, standards submissions, and secondary resources |

## Demo Artifacts

`demo/proof-pack/` contains the public fake/scratch sample verification artifacts:

- `proof-pack-manifest.json`
- `evidence/governed-profile-coverage-report.json`
- `evidence/governed-profile-coverage-report.txt`
- `verify-proof-pack.mjs`
- `SHA256SUMS`

Do not edit these files unless the sample bundle is intentionally regenerated and all checksums/manifests are updated together.

## Claim Boundary

Current public release: [ZLAR v3.3.106 — Private intake manifest pointer](https://github.com/ZLAR-AI/ZLAR/releases/tag/v3.3.106).

ZLAR governs routed/intercepted action surfaces only. Safe Codex wording:

> ZLAR can govern Codex CLI-invoked MCP tool calls when those MCP servers are routed through ZLAR.

Unrouted shell/filesystem/browser/app/network/model-reasoning/final-text surfaces are not claimed as governed by the current proof path. `/contest` is not implemented. A private-by-default non-Vincent verifier request has been sent; no public external attestation is claimed in this repo, and any private reply or later result remains bounded by verifier relationship, disclosure permission, and exact evidence returned.

## Public Copy Guard

Run the website claim-boundary guard before changing public copy:

```bash
bash scripts/check-public-copy.sh
```

The guard fails language that treats receipts as logs, after-the-fact event
history, agent intent, decision correctness, or global authorization.

## Hosting

Hosted on GitHub Pages. Static HTML and CSS. No build step.
