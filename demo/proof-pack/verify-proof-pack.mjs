#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const SAFE_CLAIM =
  'ZLAR can govern Codex CLI-invoked MCP tool calls when those MCP servers are routed through ZLAR.';

const REQUIRED_NON_CLAIMS = [
  'This report covers routed or intercepted action surfaces only.',
  'This report does not assert coverage for Codex shell, filesystem, browser, app-control, direct network, model reasoning, or final text surfaces.',
  'MCP servers registered directly with a client instead of through the ZLAR MCP gate are outside this report.',
  '/contest is not implemented.',
  'Public external verifier attestation is not claimed in v0.',
];

const UNSAFE_PATTERNS = [
  [/\/Users\/[^\s"'`]+/, 'private operator path'],
  [/\/home\/[^\s"'`]+/, 'home path'],
  [new RegExp(`\\b${['chat', 'id'].join('_')}\\b`, 'i'), 'chat id field'],
  [/\bhuman:[0-9]/, 'numeric human identifier'],
  [/\b(?:raw_args|tool_args|mcp_args|args_preview)\b/i, 'raw argument key'],
  [/\b(?:token|secret|password|api[_-]?key)\s*[:=]\s*[^&\s"'`,;})\]]+/i, 'credential-shaped value'],
  [/\b(?:govern|governs|governed)\s+Codex\b/, 'broad Codex governance claim'],
  [new RegExp(`\\b${['externally', 'attested'].join('\\s+')}\\b`, 'i'), 'external attestation completion claim'],
  [new RegExp(`\\b${['prepared', 'pending'].join('_')}\\b|\\bprepared\\/pending\\b`, 'i'), 'stale verifier request status'],
  [
    new RegExp(
      `${['private', 'request', 'sent', 'attestation', 'pending'].join('_')}|` +
        `\\b${['attestation', 'pending'].join('\\s+')}\\b|` +
        `\\b${['no', 'completed', 'attestation', 'has', 'been', 'received'].join('\\s+')}\\b`,
      'i'
    ),
    'stale attestation-pending verifier status',
  ],
  [new RegExp(`\\b${['no-contact', 'external', 'verifier', 'packet'].join('\\s+')}\\b`, 'i'), 'stale no-contact verifier packet status'],
  [
    new RegExp(`\\b${['no', 'verifier', 'has', 'been', 'contacted'].join('\\s+')}\\b|\\b${['contacted', 'or', 'appointed'].join('\\s+')}\\b`, 'i'),
    'stale verifier contact status',
  ],
  [/\bv3\.3\.15 safe Codex wording\b/i, 'stale proof-pack release anchor'],
  [new RegExp(`${'github' + '.com'}/ZLAR-AI/ZLAR(?:[\\/.?#\\s\"'<>]|$)`, 'i'), 'private core GitHub URL'],
  [/git\s+clone\s+https:\/\/github\.com\/ZLAR-AI\/ZLAR\.git/i, 'private core clone instruction'],
  [/ZLAR\s+is\s+open[- ]source\s+at/i, 'current open-source source claim'],
  [new RegExp(`${['Remote', 'CI'].join('\\s+')}|${'Cod' + 'eQL'}|${'Open' + 'SSF'}|${'Score' + 'card'}`, 'i'), 'public CI visibility claim'],
];

function readText(path) {
  return readFileSync(path, 'utf8');
}

function readJson(path) {
  return JSON.parse(readText(path));
}

function readFirstJson(paths, label) {
  for (const path of paths) {
    if (existsSync(path)) {
      return readJson(path);
    }
  }

  throw new Error(`missing ${label}: checked ${paths.join(', ')}`);
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
const release = readFirstJson(
  [
    join(root, 'release.json'),
    join(root, '..', '..', 'release.json'),
  ],
  'release metadata'
);
const currentRelease = release.current_public_release || {};
const releaseSafeClaim = release.claim_boundary?.safe_codex_wording;

assert(manifest.pack_type === 'zlar-proof-pack-v0', 'proof-pack manifest type');
assert(manifest.claim_ceiling === SAFE_CLAIM, 'manifest claim ceiling');
assert(coverage.report_type === 'governed-profile-coverage-v0', 'coverage report type');
assert(coverage.safe_claim_ceiling === SAFE_CLAIM, 'coverage claim ceiling');
assert(releaseSafeClaim === SAFE_CLAIM, 'release metadata safe claim ceiling');
assert(manifest.current_public_release === currentRelease.version, 'manifest release version matches release metadata');
assert(manifest.current_public_release_url === currentRelease.url, 'manifest release URL matches release metadata');
assert(manifest.release_metadata_updated_at === release.generated_at, 'manifest release metadata timestamp matches release metadata');
assert(manifest.claim_ceiling === releaseSafeClaim, 'manifest claim ceiling matches release metadata');
assert(coverage.safe_claim_ceiling === releaseSafeClaim, 'coverage claim ceiling matches release metadata');
assert(
  readme.includes(`ZLAR ${currentRelease.version} - ${currentRelease.title}.`),
  'README release pointer matches release metadata'
);
assert(
  manifest.current_public_release_boundary.includes(currentRelease.title),
  'manifest release boundary title matches release metadata'
);
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
scanSafe('release metadata', JSON.stringify(release));
pass('privacy and claim text scan');
pass('scratch proof pack verified');
