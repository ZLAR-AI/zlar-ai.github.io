# ZLAR Scratch Proof Pack v0

This public bundle is a fake/scratch proof-pack example for zlar.ai. It is designed to show the shape of verification without exposing operator data, raw MCP arguments, private paths, approval-channel identifiers, credentials, prompt text, or final client text.

Current public release:

ZLAR v3.4.54 - Scoped Claude Code pre-authority install readiness. Public verification uses static zlar.ai artifacts, not private GitHub URLs.

Claim ceiling:

ZLAR can govern Codex CLI-invoked MCP tool calls when those MCP servers are routed through ZLAR.

Included evidence:

- `proof-pack-manifest.json`
- `evidence/governed-profile-coverage-report.json`
- `evidence/governed-profile-coverage-report.txt`
- `verify-proof-pack.mjs`
- `SHA256SUMS`

What the scratch verifier checks:

- The bundle is a `zlar-proof-pack-v0` manifest.
- The claim ceiling matches the current safe Codex wording.
- Coverage report type is `governed-profile-coverage-v0`.
- Required non-claims are present.
- Privacy flags remain false.
- Manifest hashes match the included coverage report files.
- The text contains no private paths, credentials, raw argument keys, or broad Codex governance claim.

Source boundary:

Prior Apache-2.0 public distribution remains licensed. Current core source access is private. This bundle does not provide a public clone, installer, public CI view, or current-source inspection path.

What this does not prove:

- It does not prove production deployment coverage.
- It does not verify a live private receipt.
- It does not prove external attestation.
- It records that a private-by-default non-Vincent verifier request has been
  sent and that no public external attestation is claimed in this repo.
- It does not implement `/contest`.
- It does not claim governance for unrouted shell/filesystem/browser/app/network/model-reasoning/final-text surfaces.
