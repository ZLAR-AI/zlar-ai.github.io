#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const SAFE_CLAIM =
  'ZLAR can govern Codex CLI-invoked MCP tool calls when those MCP servers are routed through ZLAR.';

const REQUIRED_NON_CLAIMS = [
  'This report covers routed or intercepted action surfaces only.',
  'This report does not assert coverage for Codex shell, filesystem, browser, app-control, direct network, model reasoning, or final text surfaces.',
  'MCP servers registered directly with a client instead of through the ZLAR MCP gate are outside this report.',
  '/contest is not implemented.',
  'External non-operator verifier attestation is not present in v0.',
];

const UNSAFE_PATTERNS = [
  [/\/Users\/[^\s"'`]+/, 'private operator path'],
  [/\/home\/[^\s"'`]+/, 'home path'],
  [new RegExp(`\\b${['chat', 'id'].join('_')}\\b`, 'i'), 'chat id field'],
  [/\bhuman:[0-9]/, 'numeric human identifier'],
  [/\b(?:raw_args|tool_args|mcp_args|args_preview)\b/i, 'raw argument key'],
  [/\b(?:token|secret|password|api[_-]?key)\s*[:=]\s*[^&\s"'`,;})\]]+/i, 'credential-shaped value'],
  [/\b(?:govern|governs|governed)\s+Codex\b/, 'broad Codex governance claim'],
  [/\bexternally attested\b/i, 'external attestation completion claim'],
];

function readText(path) {
  return readFileSync(path, 'utf8');
}

function readJson(path) {
  return JSON.parse(readText(path));
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function pass(message) {
  console.log(`PASS ${message}`);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
  pass(message);
}

function scanSafe(label, text) {
  const scanText = text.replaceAll(SAFE_CLAIM, '[SAFE_CLAIM]');
  for (const [pattern, name] of UNSAFE_PATTERNS) {
    if (pattern.test(scanText)) {
      throw new Error(`${label} contains ${name}`);
    }
  }
}

const root = process.cwd();
const manifestPath = join(root, 'proof-pack-manifest.json');
const coverageJsonPath = join(root, 'evidence', 'governed-profile-coverage-report.json');
const coverageTextPath = join(root, 'evidence', 'governed-profile-coverage-report.txt');
const readmePath = join(root, 'README.md');

const manifest = readJson(manifestPath);
const coverage = readJson(coverageJsonPath);
const coverageText = readText(coverageTextPath);
const readme = readText(readmePath);

assert(manifest.pack_type === 'zlar-proof-pack-v0', 'proof-pack manifest type');
assert(manifest.claim_ceiling === SAFE_CLAIM, 'manifest claim ceiling');
assert(coverage.report_type === 'governed-profile-coverage-v0', 'coverage report type');
assert(coverage.safe_claim_ceiling === SAFE_CLAIM, 'coverage claim ceiling');
assert(manifest.evidence.governed_profile_coverage_report.json_sha256 === sha256(coverageJsonPath), 'coverage JSON hash matches manifest');
assert(manifest.evidence.governed_profile_coverage_report.text_sha256 === sha256(coverageTextPath), 'coverage text hash matches manifest');

for (const claim of REQUIRED_NON_CLAIMS) {
  assert(manifest.non_claims.includes(claim), `non-claim present: ${claim}`);
  assert(coverage.non_claims.includes(claim), `coverage non-claim present: ${claim}`);
}

for (const [key, value] of Object.entries(coverage.privacy)) {
  assert(value === false, `coverage privacy flag false: ${key}`);
}

assert(manifest.privacy_validation.passed === true, 'manifest privacy validation passed');
for (const [key, value] of Object.entries(manifest.privacy_validation.checks)) {
  assert(value === true, `manifest privacy check true: ${key}`);
}

scanSafe('manifest', JSON.stringify(manifest));
scanSafe('coverage JSON', JSON.stringify(coverage));
scanSafe('coverage text', coverageText);
scanSafe('README', readme);
pass('privacy and claim text scan');
pass('scratch proof pack verified');
