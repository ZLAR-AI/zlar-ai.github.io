# zlar.ai

Static public website for ZLAR Inc.

The current information architecture is a plain public path:

- "ZLAR is the doorway AI must pass through before it does something real."
- "ZLAR lets AI act, but makes it pass through rules, real people, and proof."
- "AI can move. People stay present. Actions leave proof."
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
| Founder Note | `founder-note.html` | First-person statement of the doorway thesis |
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

ZLAR governs routed/intercepted action surfaces only. Safe Codex wording:

> ZLAR can govern Codex CLI-invoked MCP tool calls when those MCP servers are routed through ZLAR.

Unrouted shell/filesystem/browser/app/network/model-reasoning/final-text surfaces are not claimed as governed by the current proof path. `/contest` is not implemented. External non-Vincent verifier attestation remains prepared/pending unless state changes.

## Hosting

Hosted on GitHub Pages. Static HTML and CSS. No build step.
