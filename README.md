# zlar.ai

Static public website for ZLAR Inc.

The current information architecture is the public airport map for ZLAR:

- "Intelligence may change. Consequence still needs authority."
- "ZLAR is the boarding system for defined routed AI actions."
- "Terminal activity is not boarding."
- "The receipt is the boarding credential."
- "The scanner verifies the receipt; the manifest names the boundary."
- "Side doors are disclosed, not laundered into the claim."
- "Public Proof Desk is where readers inspect static zlar.ai proof artifacts; current core source review is by request."
- "Bring One Action means one action class, one route, one policy, one receipt, one refusal rule, and one map of side doors."

## Primary Pages

| Page | Path | Purpose |
| --- | --- | --- |
| Homepage / The Map | `index.html` | Airport map for AI action: terminal/reasoning, gate/governed route, checkpoint/policy, ticket/receipt, scanner/verifier, manifest/evidence bundle, aircraft door/refusal, side doors |
| Enterprise | `enterprise.html` | Rules before enterprise AI changes files, calls tools, or starts workflows |
| Government | `government.html` | Public records for routed AI actions: rule, authority, receipt, and boundary |
| Financial Services | `financial-services.html` | The gap between identity and action-level boarding permission |
| Healthcare | `healthcare.html` | Bounded healthcare workflow framing without clinical claims |
| Defense / Military | `defense.html` | Delegation, command visibility, rules, people, and receipts for routed actions |
| Founder Note | `founder-note.html` | First-person statement of the threshold thesis |
| Receipt Scanner | `proof-pack.html` | Human-first receipt/scanner/manifest path with optional bounded terminal verification |
| Open Memo | `open-memo.html` | Policy memo for rules before action and receipts afterward |
| Side Doors / Boundaries | `boundaries.html` | What boards through ZLAR, what does not, and what the sample receipt does not prove |
| Archive | `archive.html` | Affected-person pathway, Sealed Mode, older material, standards submissions, and secondary resources |

## Demo Artifacts

`demo/proof-pack/` contains the public fake/scratch sample verification artifacts:

- `proof-pack-manifest.json`
- `evidence/governed-profile-coverage-report.json`
- `evidence/governed-profile-coverage-report.txt`
- `verify-proof-pack.mjs`
- `SHA256SUMS`

Do not edit these files unless the sample bundle is intentionally regenerated and all checksums/manifests are updated together.

`release.json` is the public machine-readable current-release pointer for `zlar.ai`. It lets an auditor verify the live release claim through static website artifacts instead of scraping HTML copy or relying on private core GitHub access.

## Claim Boundary

Public proof artifacts live in [Public Proof Desk](/proof-pack.html). Current core source access is private. Prior Apache-2.0 public distribution remains licensed. The website should remain evergreen: explain the category, receipt scanner, and side-door boundary without mirroring every repo commit.

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
