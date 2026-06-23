#!/bin/bash
# Public-copy guard for website receipt authority boundaries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

PASS=0
FAIL=0
TOTAL=0

PUBLIC_PATHS=(
    '*.html'
    '*.txt'
    '*.md'
    'release.json'
    'docs'
    'specs'
    'demo'
)

pass() {
    PASS=$((PASS + 1))
}

fail() {
    local label="$1"
    local detail="${2:-}"
    FAIL=$((FAIL + 1))
    printf '  FAIL: %s\n' "${label}"
    if [ -n "${detail}" ]; then
        printf '%s\n' "${detail}" | sed 's/^/    /'
    fi
}

assert_contains_fixed() {
    local label="$1"
    local path="$2"
    local needle="$3"
    TOTAL=$((TOTAL + 1))

    if grep -Fq "${needle}" "${path}"; then
        pass
    else
        fail "${label}" "missing in ${path}: ${needle}"
    fi
}

assert_json_value() {
    local label="$1"
    local path="$2"
    local pointer="$3"
    local expected="$4"
    TOTAL=$((TOTAL + 1))

    local output rc
    set +e
    output=$(JSON_PATH="${path}" JSON_POINTER="${pointer}" JSON_EXPECTED="${expected}" node <<'NODE'
const fs = require('node:fs');

const jsonPath = process.env.JSON_PATH;
const pointer = process.env.JSON_POINTER;
const expected = process.env.JSON_EXPECTED;
const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

let value = data;
for (const part of pointer.split('.').filter(Boolean)) {
  if (!value || !Object.prototype.hasOwnProperty.call(value, part)) {
    throw new Error(`missing ${pointer}`);
  }
  value = value[part];
}

if (String(value) !== expected) {
  throw new Error(`${pointer} expected ${expected} but got ${String(value)}`);
}
NODE
)
    rc=$?
    set -e

    if [ "${rc}" -eq 0 ]; then
        pass
    else
        fail "${label}" "${output}"
    fi
}

read_json_value() {
    local path="$1"
    local pointer="$2"

    JSON_PATH="${path}" JSON_POINTER="${pointer}" node <<'NODE'
const fs = require('node:fs');

const jsonPath = process.env.JSON_PATH;
const pointer = process.env.JSON_POINTER;
const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

let value = data;
for (const part of pointer.split('.').filter(Boolean)) {
  if (!value || !Object.prototype.hasOwnProperty.call(value, part)) {
    throw new Error(`missing ${pointer}`);
  }
  value = value[part];
}

if (value === null || typeof value === 'undefined') {
  throw new Error(`${pointer} is null or undefined`);
}

process.stdout.write(String(value));
NODE
}

assert_no_public_regex() {
    local label="$1"
    local pattern="$2"
    TOTAL=$((TOTAL + 1))

    local matches rc
    set +e
    matches=$(git grep -n -i -E "${pattern}" -- "${PUBLIC_PATHS[@]}" 2>&1)
    rc=$?
    set -e

    if [ "${rc}" -eq 0 ]; then
        fail "${label}" "${matches}"
    elif [ "${rc}" -eq 1 ]; then
        pass
    else
        fail "${label}" "${matches}"
    fi
}

assert_no_public_regex_collapsed() {
    local label="$1"
    local pattern="$2"
    TOTAL=$((TOTAL + 1))

    local matches rc
    set +e
    matches=$(PUBLIC_COPY_PATTERN="${pattern}" node <<'NODE'
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');

const publicPaths = ['*.html', '*.txt', '*.md', 'docs', 'specs', 'demo'];
const pattern = new RegExp(process.env.PUBLIC_COPY_PATTERN, 'i');
const files = execFileSync('git', ['ls-files', '-z', '--', ...publicPaths])
  .toString('utf8')
  .split('\0')
  .filter(Boolean);

const hits = [];
for (const file of files) {
  const body = fs.readFileSync(file, 'utf8').replace(/\s+/g, ' ');
  if (pattern.test(body)) {
    hits.push(file);
  }
}

if (hits.length > 0) {
  console.log(hits.join('\n'));
  process.exit(1);
}
NODE
)
    rc=$?
    set -e

    if [ "${rc}" -eq 0 ]; then
        pass
    else
        fail "${label}" "${matches}"
    fi
}

assert_latest_release_metadata_fresh() {
    local label="$1"
    TOTAL=$((TOTAL + 1))

    local output rc
    set +e
    output=$(node <<'NODE'
const fs = require('node:fs');
const https = require('node:https');

const strict = process.env.ZLAR_REQUIRE_LATEST_RELEASE_FRESHNESS === 'true';
const release = JSON.parse(fs.readFileSync('release.json', 'utf8')).current_public_release;

function fetchJson(url) {
  const headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'zlar-public-copy-guard',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  return fetchJsonWithRetry(url, headers);
}

function fetchJsonOnce(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          reject(new Error(`${url} returned HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
          return;
        }

        try {
          resolve(JSON.parse(body));
        } catch (err) {
          reject(new Error(`${url} returned invalid JSON: ${err.message}`));
        }
      });
    }).on('error', reject).setTimeout(10000, function onTimeout() {
      this.destroy(new Error(`${url} timed out after 10000ms`));
    });
  });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTransient(err) {
  return /getaddrinfo|ENOTFOUND|ECONNRESET|ETIMEDOUT|EAI_AGAIN|timed out|HTTP 403|HTTP 429/.test(err.message);
}

async function fetchJsonWithRetry(url, headers) {
  let lastErr;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await fetchJsonOnce(url, headers);
    } catch (err) {
      lastErr = err;
      if (!isTransient(err) || attempt === 3) {
        break;
      }
      await delay(attempt * 1000);
    }
  }

  throw lastErr;
}

function requireEqual(name, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${name} expected ${expected} but got ${actual}`);
  }
}

(async () => {
  const latest = await fetchJson('https://api.github.com/repos/ZLAR-AI/ZLAR/releases/latest');
  requireEqual('latest release tag', latest.tag_name, release.version);
  requireEqual('latest release URL', latest.html_url, release.url);
  requireEqual('latest release published_at', latest.published_at, release.published_at);
  const expectedNames = [
    `${release.version} - ${release.title}`,
    `${release.version} \u2014 ${release.title}`,
  ];
  if (!expectedNames.includes(String(latest.name || ''))) {
    throw new Error(`latest release name expected one of ${expectedNames.join(' / ')} but got ${latest.name}`);
  }

  const ref = await fetchJson(`https://api.github.com/repos/ZLAR-AI/ZLAR/git/ref/tags/${release.tag}`);
  requireEqual('latest tag object', ref.object.sha, release.tag_object);

  if (ref.object.type === 'tag') {
    const tag = await fetchJson(ref.object.url);
    requireEqual('latest tag target commit', tag.object.sha, release.commit);
  } else {
    requireEqual('latest lightweight tag commit', ref.object.sha, release.commit);
  }
})().catch((err) => {
  if (!strict && /getaddrinfo|ENOTFOUND|ECONNRESET|ETIMEDOUT|EAI_AGAIN|timed out|HTTP 403|HTTP 429/.test(err.message)) {
    console.log(`freshness check skipped outside strict mode: ${err.message}`);
    process.exit(2);
  }

  console.error(err.message);
  process.exit(1);
});
NODE
)
    rc=$?
    set -e

    if [ "${rc}" -eq 0 ]; then
        pass
    elif [ "${rc}" -eq 2 ] && [ "${ZLAR_REQUIRE_LATEST_RELEASE_FRESHNESS:-false}" != "true" ]; then
        pass
        printf '  WARN: %s\n' "${output}"
    else
        fail "${label}" "${output}"
    fi
}

assert_release_boundary_manifest() {
    local label="$1"
    TOTAL=$((TOTAL + 1))

    local output rc
    set +e
    output=$(node <<'NODE'
const fs = require('node:fs');

const release = JSON.parse(fs.readFileSync('release.json', 'utf8'));
const manifest = JSON.parse(fs.readFileSync('demo/proof-pack/proof-pack-manifest.json', 'utf8'));
const coverage = JSON.parse(fs.readFileSync('demo/proof-pack/evidence/governed-profile-coverage-report.json', 'utf8'));
const readme = fs.readFileSync('demo/proof-pack/README.md', 'utf8');

const current = release.current_public_release || {};
const safeClaim = release.claim_boundary?.safe_codex_wording;

function requireEqual(name, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${name} expected ${expected} but got ${actual}`);
  }
}

function requireIncludes(name, body, needle) {
  if (!String(body).includes(needle)) {
    throw new Error(`${name} missing ${needle}`);
  }
}

requireEqual('proof-pack current release', manifest.current_public_release, current.version);
requireEqual('proof-pack current release URL', manifest.current_public_release_url, current.url);
requireEqual('proof-pack release metadata timestamp', manifest.release_metadata_updated_at, release.generated_at);
requireEqual('proof-pack claim ceiling', manifest.claim_ceiling, safeClaim);
requireEqual('coverage safe claim ceiling', coverage.safe_claim_ceiling, safeClaim);
requireIncludes('proof-pack README release pointer', readme, `ZLAR ${current.version} - ${current.title}.`);
requireIncludes('proof-pack boundary title', manifest.current_public_release_boundary, current.title);
requireIncludes('release evidence threshold', release.claim_boundary?.evidence_threshold || '', `${current.version} release checks pass`);
NODE
)
    rc=$?
    set -e

    if [ "${rc}" -eq 0 ]; then
        pass
    else
        fail "${label}" "${output}"
    fi
}

assert_proof_pack_bundle_verifies() {
    local label="$1"
    TOTAL=$((TOTAL + 1))

    local tmpdir output rc
    tmpdir="$(mktemp -d)"
    set +e
    output=$(
        cp release.json "${tmpdir}/release.json" &&
        cp demo/proof-pack/README.md "${tmpdir}/README.md" &&
        cp demo/proof-pack/proof-pack-manifest.json "${tmpdir}/proof-pack-manifest.json" &&
        cp demo/proof-pack/SHA256SUMS "${tmpdir}/SHA256SUMS" &&
        cp demo/proof-pack/verify-proof-pack.mjs "${tmpdir}/verify-proof-pack.mjs" &&
        mkdir -p "${tmpdir}/evidence" &&
        cp demo/proof-pack/evidence/governed-profile-coverage-report.json "${tmpdir}/evidence/governed-profile-coverage-report.json" &&
        cp demo/proof-pack/evidence/governed-profile-coverage-report.txt "${tmpdir}/evidence/governed-profile-coverage-report.txt" &&
        (
            cd "${tmpdir}" &&
            shasum -a 256 -c SHA256SUMS &&
            node verify-proof-pack.mjs
        ) 2>&1
    )
    rc=$?
    rm -rf "${tmpdir}"
    set -e

    if [ "${rc}" -eq 0 ]; then
        pass
    else
        fail "${label}" "${output}"
    fi
}

RELEASE_METADATA_GENERATED_AT="$(read_json_value "release.json" "generated_at")"
CURRENT_RELEASE_VERSION="$(read_json_value "release.json" "current_public_release.version")"
CURRENT_RELEASE_TITLE="$(read_json_value "release.json" "current_public_release.title")"
CURRENT_RELEASE_TITLE_LOWER="$(printf '%s' "${CURRENT_RELEASE_TITLE}" | tr '[:upper:]' '[:lower:]')"
CURRENT_RELEASE_URL="$(read_json_value "release.json" "current_public_release.url")"
CURRENT_RELEASE_COMMIT="$(read_json_value "release.json" "current_public_release.commit")"
CURRENT_RELEASE_TAG_OBJECT="$(read_json_value "release.json" "current_public_release.tag_object")"
CURRENT_RELEASE_POINTER="ZLAR ${CURRENT_RELEASE_VERSION} - ${CURRENT_RELEASE_TITLE}"
CURRENT_RELEASE_GITHUB_POINTER="ZLAR ${CURRENT_RELEASE_VERSION} on GitHub"
CURRENT_RELEASE_LLM_POINTER="Current public release: ${CURRENT_RELEASE_POINTER}."
CURRENT_RELEASE_CLAIM_BOUNDARY="Current ZLAR public claims are bounded by ${CURRENT_RELEASE_VERSION}"
CURRENT_RELEASE_CHECK_THRESHOLD="${CURRENT_RELEASE_VERSION} release checks pass with ${CURRENT_RELEASE_TITLE_LOWER}"

echo "=== Website Public-Copy Guard ==="

assert_contains_fixed \
    "homepage keeps log/receipt invariant" \
    "index.html" \
    "A log records what happened. A ZLAR receipt records what counted as authorized effect"

assert_contains_fixed \
    "receipt verify page keeps quickstart demo boundary" \
    "receipt-verify.html" \
    "The gate decisions are real; the receipt is bounded demo evidence, not live production governance."

assert_contains_fixed \
    "boundaries page keeps release boundary" \
    "boundaries.html" \
    "that guard is CI evidence only and adds no runtime authority"

assert_contains_fixed \
    "boundaries page keeps current release pointer" \
    "boundaries.html" \
    "${CURRENT_RELEASE_GITHUB_POINTER}"

assert_contains_fixed \
    "proof-pack page keeps current release pointer" \
    "proof-pack.html" \
    "${CURRENT_RELEASE_GITHUB_POINTER}"

assert_contains_fixed \
    "proof-pack page downloads release metadata" \
    "proof-pack.html" \
    "curl -fsSLO https://zlar.ai/release.json"

assert_contains_fixed \
    "proof-pack sidecar hashes release metadata" \
    "demo/proof-pack/SHA256SUMS" \
    "release.json"

assert_contains_fixed \
    "proof-pack page links release metadata" \
    "proof-pack.html" \
    "Release Metadata"

assert_contains_fixed \
    "proof-pack page shows release metadata agreement checks" \
    "proof-pack.html" \
    "manifest release version matches release metadata"

assert_contains_fixed \
    "proof-pack page keeps current release boundary" \
    "proof-pack.html" \
    "The current release makes trusted-issuer registry recognition evidence first-class"

assert_contains_fixed \
    "proof-pack page keeps private result verification section" \
    "proof-pack.html" \
    "Private Result Verification Evidence"

assert_contains_fixed \
    "proof-pack page keeps registry recognition evidence section" \
    "proof-pack.html" \
    "Trusted Issuer Registry Recognition Evidence"

assert_contains_fixed \
    "proof-pack page keeps registry recognition manifest field" \
    "proof-pack.html" \
    "trusted_issuer_registry_recognition_evidence"

assert_contains_fixed \
    "proof-pack page keeps bundled local registry boundary" \
    "proof-pack.html" \
    "registry_evidence_model=bundled-local-fixture"

assert_contains_fixed \
    "proof-pack page keeps malformed registry fail-closed boundary" \
    "proof-pack.html" \
    "malformed_registry_fail_closed_before_verdict=true"

assert_contains_fixed \
    "proof-pack page keeps private non-operator sample boundary" \
    "proof-pack.html" \
    "private_non_operator_pass_validated=false"

assert_contains_fixed \
    "proof-pack page keeps forged inner preflight and service hash refusal" \
    "proof-pack.html" \
    "release-forward dry-run exports terminal_chain_refusal_evidence.nested_artifact_tamper_refusals with forged_inner_preflight_hash_refused=true and forged_inner_service_hash_refused=true after refusing forged inner preflight and service-proof hashes while recomputing outer terminal-chain artifact integrity"

assert_contains_fixed \
    "proof-pack page keeps readiness case-ID report contract" \
    "proof-pack.html" \
    "v3.4.25+ proof-smoke and North Star readiness preserve \`group_count=3\`, \`case_count=18\`, and exact grouped case IDs"

assert_contains_fixed \
    "proof-pack page keeps terminal-chain refusal evidence field" \
    "proof-pack.html" \
    "terminal_chain_refusal_evidence"

assert_contains_fixed \
    "proof-pack page keeps recognition group case IDs" \
    "proof-pack.html" \
    "recognition_refusal_group_case_ids"

assert_contains_fixed \
    "proof-pack page keeps recognition group case-ID requirement" \
    "proof-pack.html" \
    "recognition_refusal_group_case_ids_required=true"

assert_contains_fixed \
    "proof-pack page keeps all case IDs preserved flag" \
    "proof-pack.html" \
    "all_recognition_refusal_group_case_ids_preserved=true"

assert_contains_fixed \
    "proof-pack page keeps named refusal hash" \
    "proof-pack.html" \
    "named_receipt_refusals_sha256"

assert_contains_fixed \
    "proof-pack page keeps recognition-contract digest field" \
    "proof-pack.html" \
    "installed_runtime_profile_recognition_contract_sha256"

assert_contains_fixed \
    "proof-pack page keeps named refusal cases" \
    "proof-pack.html" \
    "wrong-tool receipt cases"

assert_contains_fixed \
    "proof-pack page keeps recognition-group evidence boundary" \
    "proof-pack.html" \
    "local disposable verifier-owned terminal-chain nested binding summary and tamper-refusal evidence, installed-runtime-profile recognition-refusal group case-id, recognition-refusal group, named-refusal, and recognition-contract evidence only"

assert_contains_fixed \
    "proof-pack page keeps product proof path command" \
    "proof-pack.html" \
    "zlar product-proof-path --json-out zlar-product-proof-path-v1.json"

assert_contains_fixed \
    "proof-pack page keeps product proof path artifact" \
    "proof-pack.html" \
    "zlar-product-proof-path-v1.json"

assert_contains_fixed \
    "website README keeps current release pointer" \
    "README.md" \
    "${CURRENT_RELEASE_POINTER}"

assert_contains_fixed \
    "LLM index keeps current release pointer" \
    "llms.txt" \
    "${CURRENT_RELEASE_LLM_POINTER}"

assert_contains_fixed \
    "LLM index keeps release metadata pointer" \
    "llms.txt" \
    "https://zlar.ai/release.json"

assert_contains_fixed \
    "website README keeps release metadata pointer" \
    "README.md" \
    "machine-readable current-release pointer"

assert_json_value \
    "release metadata keeps schema" \
    "release.json" \
    "schema" \
    "zlar-public-release-metadata-v1"

assert_json_value \
    "release metadata keeps current release" \
    "release.json" \
    "current_public_release.version" \
    "${CURRENT_RELEASE_VERSION}"

assert_json_value \
    "release metadata keeps release title" \
    "release.json" \
    "current_public_release.title" \
    "${CURRENT_RELEASE_TITLE}"

assert_json_value \
    "release metadata keeps release commit" \
    "release.json" \
    "current_public_release.commit" \
    "${CURRENT_RELEASE_COMMIT}"

assert_json_value \
    "release metadata keeps tag object" \
    "release.json" \
    "current_public_release.tag_object" \
    "${CURRENT_RELEASE_TAG_OBJECT}"

assert_latest_release_metadata_fresh \
    "release metadata matches GitHub latest release and tag"

assert_json_value \
    "release metadata keeps live URL" \
    "release.json" \
    "website.live_url" \
    "https://zlar.ai/release.json"

assert_contains_fixed \
    "release metadata keeps receipt invariant" \
    "release.json" \
    "A log records what happened. A ZLAR receipt records what counted as authorized effect"

assert_contains_fixed \
    "release metadata keeps service-proof command" \
    "release.json" \
    "zlar protected-records-installed-runtime-profile-service-proof --sample"

assert_contains_fixed \
    "release metadata keeps service-proof artifact verification command" \
    "release.json" \
    "zlar protected-records-installed-runtime-profile-service-proof verify --sample --json"

assert_contains_fixed \
    "release metadata keeps terminal-chain command as prior boundary" \
    "release.json" \
    "zlar protected-records-installed-runtime-profile-terminal-chain --sample"

assert_contains_fixed \
    "release metadata keeps recognition group threshold" \
    "release.json" \
    "${CURRENT_RELEASE_CHECK_THRESHOLD}"

assert_contains_fixed \
    "release metadata keeps forged inner preflight and service hash refusal" \
    "release.json" \
    "release-forward dry-run exports terminal_chain_refusal_evidence.nested_artifact_tamper_refusals with forged_inner_preflight_hash_refused=true and forged_inner_service_hash_refused=true after refusing forged inner preflight and service-proof hashes while recomputing outer terminal-chain artifact integrity"

assert_contains_fixed \
    "release metadata keeps observed summary threshold" \
    "release.json" \
    "For v3.4.26+ the Enterprise Deployment Profile and Downstream Recognition Rule observed summaries mirror that same case-ID contract"

assert_contains_fixed \
    "release metadata keeps readiness case-ID report contract" \
    "release.json" \
    "v3.4.25+ proof-smoke and North Star readiness preserve group_count=3, case_count=18, and exact grouped case IDs"

assert_contains_fixed \
    "release metadata keeps recognition group case-ID field" \
    "release.json" \
    "recognition_refusal_group_case_ids"

assert_contains_fixed \
    "release metadata keeps recognition group case-ID requirement" \
    "release.json" \
    "recognition_refusal_group_case_ids_required=true"

assert_contains_fixed \
    "release metadata keeps all case IDs preserved flag" \
    "release.json" \
    "all_recognition_refusal_group_case_ids_preserved=true"

assert_contains_fixed \
    "release metadata keeps prior recognition group hash threshold" \
    "release.json" \
    "recognition_refusal_groups_sha256"

assert_contains_fixed \
    "release metadata keeps named refusal hash threshold" \
    "release.json" \
    "named_receipt_refusals_sha256"

assert_contains_fixed \
    "release metadata keeps current-machine non-claim" \
    "release.json" \
    "No current-machine governance claim."

assert_release_boundary_manifest \
    "release boundary manifest agrees with proof-pack mirror"

assert_proof_pack_bundle_verifies \
    "downloadable proof-pack bundle verifies against release metadata"

assert_contains_fixed \
    "proof-pack README keeps current release pointer" \
    "demo/proof-pack/README.md" \
    "${CURRENT_RELEASE_POINTER}."

assert_json_value \
    "proof-pack manifest keeps current release pointer" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "current_public_release" \
    "${CURRENT_RELEASE_VERSION}"

assert_json_value \
    "proof-pack manifest keeps current release URL" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "current_public_release_url" \
    "${CURRENT_RELEASE_URL}"

assert_json_value \
    "proof-pack manifest keeps release metadata timestamp" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "release_metadata_updated_at" \
    "${RELEASE_METADATA_GENERATED_AT}"

assert_contains_fixed \
    "proof-pack manifest keeps readiness case-ID report contract" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "v3.4.25+ proof-smoke and North Star readiness preserve group_count=3, case_count=18, and exact grouped case IDs"

assert_contains_fixed \
    "proof-pack manifest keeps verifier target boundary" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "${CURRENT_RELEASE_TITLE}"

assert_contains_fixed \
    "proof-pack manifest keeps registry recognition evidence section" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "Trusted Issuer Registry Recognition Evidence"

assert_contains_fixed \
    "proof-pack manifest keeps registry recognition manifest field" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "trusted_issuer_registry_recognition_evidence"

assert_contains_fixed \
    "proof-pack manifest keeps exact malformed registry artifact name" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "zlar-trusted-receipt-issuer-recognition-malformed-registry.json"

assert_contains_fixed \
    "proof-pack manifest keeps exact malformed registry error artifact name" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "zlar-trusted-receipt-issuer-recognition-malformed-registry-error.txt"

assert_contains_fixed \
    "proof-pack manifest keeps no live registry claim" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "proves_live_registry=false"

assert_contains_fixed \
    "proof-pack manifest keeps malformed registry fail-closed boundary" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "malformed_registry_fail_closed_before_verdict=true"

assert_contains_fixed \
    "proof-pack manifest keeps nested artifact binding" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "nested_artifacts"

assert_contains_fixed \
    "proof-pack manifest keeps forged inner preflight and service hash refusal" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "terminal_chain_refusal_evidence.nested_artifact_tamper_refusals.forged_inner_preflight_hash_refused"

assert_contains_fixed \
    "proof-pack manifest keeps forged inner service hash refusal" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "terminal_chain_refusal_evidence.nested_artifact_tamper_refusals.forged_inner_service_hash_refused"

assert_contains_fixed \
    "proof-pack manifest keeps observed summary boundary" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "v3.4.26+ North Star readiness observed summaries mirror the terminal-chain case-ID contract"

assert_contains_fixed \
    "proof-pack manifest keeps terminal-chain refusal evidence field" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "terminal_chain_refusal_evidence"

assert_contains_fixed \
    "proof-pack manifest keeps recognition group case IDs" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "recognition_refusal_group_case_ids"

assert_contains_fixed \
    "proof-pack manifest keeps recognition group case-ID requirement" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "recognition_refusal_group_case_ids_required=true"

assert_contains_fixed \
    "proof-pack manifest keeps all case IDs preserved flag" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "all_recognition_refusal_group_case_ids_preserved=true"

assert_contains_fixed \
    "proof-pack manifest keeps named refusal hash field" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "named_receipt_refusals_sha256"

assert_contains_fixed \
    "proof-pack manifest keeps recognition-contract digest field" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "installed_runtime_profile_recognition_contract_sha256"

assert_contains_fixed \
    "proof-pack manifest keeps recognition-group evidence boundary" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "local disposable installed-runtime-profile recognition-refusal group case-id, recognition-refusal group, and named-refusal evidence only"

assert_contains_fixed \
    "proof-pack manifest keeps no production downstream non-claim" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "no production downstream recognition"

assert_contains_fixed \
    "proof-pack manifest keeps external-attestation non-claim" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "no public external attestation"

assert_contains_fixed \
    "architecture archive keeps current release pointer" \
    "architecture.html" \
    "${CURRENT_RELEASE_LLM_POINTER}"

assert_contains_fixed \
    "CAISI archive keeps current release boundary" \
    "caisi-submission.html" \
    "The current release makes trusted-issuer registry recognition evidence first-class"

assert_contains_fixed \
    "CAISI metadata keeps current claim boundary" \
    "caisi-submission.html" \
    "${CURRENT_RELEASE_CLAIM_BOUNDARY}"

assert_contains_fixed \
    "fail-open archive keeps current release boundary" \
    "fail-open.html" \
    "The current release makes trusted-issuer registry recognition evidence first-class"

assert_contains_fixed \
    "boundaries page keeps records.write terminal proof boundary" \
    "boundaries.html" \
    "records-write-terminal-proof"

assert_contains_fixed \
    "boundaries page keeps verifier packet split status" \
    "boundaries.html" \
    "The historical private verifier request remains sent and private-by-default"

assert_contains_fixed \
    "boundaries page keeps current release boundary" \
    "boundaries.html" \
    "The current release makes trusted-issuer registry recognition evidence first-class"

assert_contains_fixed \
    "boundaries page keeps private result verification section" \
    "boundaries.html" \
    "Private Result Verification Evidence"

assert_contains_fixed \
    "boundaries page keeps registry recognition evidence section" \
    "boundaries.html" \
    "Trusted Issuer Registry Recognition Evidence"

assert_contains_fixed \
    "boundaries page keeps registry recognition manifest field" \
    "boundaries.html" \
    "trusted_issuer_registry_recognition_evidence"

assert_contains_fixed \
    "boundaries page keeps no live registry claim" \
    "boundaries.html" \
    "proves_live_registry=false"

assert_contains_fixed \
    "boundaries page keeps recognition-contract digest field" \
    "boundaries.html" \
    "installed_runtime_profile_recognition_contract_sha256"

assert_contains_fixed \
    "boundaries page keeps named refusal hash" \
    "boundaries.html" \
    "named_receipt_refusals_sha256"

assert_contains_fixed \
    "boundaries page keeps recognition-group evidence boundary" \
    "boundaries.html" \
    "local disposable verifier-owned terminal-chain nested binding summary and tamper-refusal evidence, installed-runtime-profile recognition-refusal group case-id, recognition-refusal group, named-refusal, and recognition-contract evidence only"

assert_contains_fixed \
    "boundaries page keeps readiness verified field" \
    "boundaries.html" \
    "product_proof_path_verified=true"

assert_contains_fixed \
    "boundaries page keeps product proof path command" \
    "boundaries.html" \
    "zlar product-proof-path --json-out zlar-product-proof-path-v1.json"

assert_contains_fixed \
    "boundaries page keeps product proof path artifact" \
    "boundaries.html" \
    "zlar-product-proof-path-v1.json"

assert_contains_fixed \
    "boundaries page keeps byte-binding audit result" \
    "boundaries.html" \
    "ready_for_public_distribution_claim=true"

assert_contains_fixed \
    "boundaries page keeps current release asset-publication boundary" \
    "boundaries.html" \
    "The v3.4.10 release also published all required verifier-kit assets"

assert_contains_fixed \
    "boundaries page keeps public-distribution audit command" \
    "boundaries.html" \
    "zlar verifier-kit-public-distribution"

assert_contains_fixed \
    "boundaries page keeps public-distribution report artifact" \
    "boundaries.html" \
    "zlar-verifier-kit-public-distribution-v1.json"

assert_contains_fixed \
    "boundaries page keeps production-authority non-claim" \
    "boundaries.html" \
    "not public external attestation"

assert_contains_fixed \
    "boundaries page keeps v3.3.108 pointer summary as historical" \
    "boundaries.html" \
    "The v3.3.108 release added release-forward result pointer summary"

assert_contains_fixed \
    "boundaries page keeps historical readiness pointer field" \
    "boundaries.html" \
    "private_intake_sample_manifest_pointer"

assert_contains_fixed \
    "boundaries page keeps historical pointer contract section" \
    "boundaries.html" \
    "Private Intake Pointer Contract"

assert_contains_fixed \
    "boundaries page keeps v3.3.107 pointer reporting as historical" \
    "boundaries.html" \
    "The v3.3.107 release added North Star private intake pointer reporting"

assert_contains_fixed \
    "boundaries page keeps v3.3.105 private sample as historical" \
    "boundaries.html" \
    "The v3.3.105 release added release-forward private intake sample evidence"

assert_contains_fixed \
    "boundaries page keeps v3.3.104 hash verification as historical" \
    "boundaries.html" \
    "The v3.3.104 release added private evidence hash verification"

assert_contains_fixed \
    "boundaries page keeps v3.3.103 verifier intake as historical" \
    "boundaries.html" \
    "The v3.3.103 release added private verifier result intake"

assert_contains_fixed \
    "boundaries page keeps private verifier result command" \
    "boundaries.html" \
    "bin/zlar private-verifier-result verify"

assert_contains_fixed \
    "boundaries page keeps private verifier result schema" \
    "boundaries.html" \
    "zlar-private-verifier-result-v1"

assert_contains_fixed \
    "boundaries page keeps v3.3.102 receipt boundary as historical" \
    "boundaries.html" \
    "The v3.3.102 release clarified receipt-emission boundaries"

assert_contains_fixed \
    "boundaries page keeps configured action receipt boundary" \
    "boundaries.html" \
    "ZLAR_EMIT_RECEIPTS=true"

assert_contains_fixed \
    "boundaries page keeps constructed quickstart event boundary" \
    "boundaries.html" \
    "constructed quickstart audit event"

assert_contains_fixed \
    "boundaries page keeps reproducibility claim-boundary flags" \
    "boundaries.html" \
    "false reproducibility claim-boundary flags"

assert_contains_fixed \
    "boundaries page keeps v3.3.101 readiness bridge as historical" \
    "boundaries.html" \
    "The v3.3.101 release added the readiness report reproducibility bridge"

assert_contains_fixed \
    "boundaries page keeps verifier kit reproducibility artifact" \
    "boundaries.html" \
    "zlar-verifier-kit-reproducibility-v1.json"

assert_contains_fixed \
    "boundaries page keeps source-build determinism boundary" \
    "boundaries.html" \
    "source-build archive determinism for identical inputs and the same publisher key only"

assert_contains_fixed \
    "boundaries page keeps v3.3.100 reproducibility as historical" \
    "boundaries.html" \
    "The v3.3.100 release added verifier-kit reproducibility evidence"

assert_contains_fixed \
    "boundaries page keeps v3.3.99 markdown polish as historical" \
    "boundaries.html" \
    "The v3.3.99 release added release-forward result Markdown polish"

assert_contains_fixed \
    "boundaries page keeps dry-run result markdown artifact" \
    "boundaries.html" \
    "DRY-RUN-RESULT.md"

assert_contains_fixed \
    "boundaries page keeps markdown polish regression boundary" \
    "boundaries.html" \
    "rejects escaped Markdown backticks"

assert_contains_fixed \
    "boundaries page keeps North Star readiness artifact" \
    "boundaries.html" \
    "zlar-north-star-readiness-v1.json"

assert_contains_fixed \
    "boundaries page keeps not-ready-for-v3.4 result" \
    "boundaries.html" \
    "NOT_READY_FOR_V3_4_0"

assert_contains_fixed \
    "boundaries page keeps no v3.4 readiness claim" \
    "boundaries.html" \
    "not v3.4.0 readiness"

assert_contains_fixed \
    "boundaries page keeps malformed-registry no-verdict boundary" \
    "boundaries.html" \
    "no \`RECOGNIZED\` or \`RECOGNITION-REFUSED\` verdict is emitted before the schema-contract error"

assert_contains_fixed \
    "boundaries page keeps schema-contract mismatch boundary" \
    "boundaries.html" \
    "unsupported top-level fields, unsupported issuer fields, missing \`evidence_model\`, missing issuer \`public_key_pem\`, or bad \`required_detail_hash\`"

assert_contains_fixed \
    "boundaries page keeps refusal matrix boundary" \
    "boundaries.html" \
    "unknown issuer, retired issuer, compromised issuer, wrong policy, wrong scope, and malformed registry input are refused"

assert_contains_fixed \
    "boundaries page keeps service-profile coverage lane" \
    "boundaries.html" \
    "protected-records.service-profile.records.write"

assert_contains_fixed \
    "boundaries page keeps current 5/5 coverage boundary" \
    "boundaries.html" \
    "current \`v3.3.91+\` service-profile coverage lane at \`5/5\` and the \`v3.3.93+\` service-profile wrong-policy preflight at \`11/11\`"

assert_contains_fixed \
    "boundaries page keeps verifier recognition boundary" \
    "boundaries.html" \
    "the release-forward verifier packet can preserve \`zlar-trusted-receipt-issuer-recognition.json\` for \`v3.3.94+\` targets"

assert_contains_fixed \
    "boundaries page keeps dry-run manifest file" \
    "boundaries.html" \
    "DRY-RUN-MANIFEST.json"

assert_contains_fixed \
    "boundaries page keeps dry-run manifest fields" \
    "boundaries.html" \
    "explicit target, observed commit, assertion counts, artifact hashes, run-file hashes, privacy flags, and non-claim flags"

assert_contains_fixed \
    "boundaries page keeps helper moving-target refusal" \
    "boundaries.html" \
    "refuses moving targets such as \`main\`, \`HEAD\`, \`latest\`, and \`--latest\`"

assert_contains_fixed \
    "boundaries page keeps pinned v3.3.90 verifier target" \
    "boundaries.html" \
    "The prepared pinned \`v3.3.90\` release-forward verifier target"

assert_contains_fixed \
    "boundaries page keeps pinned verifier target sha" \
    "boundaries.html" \
    "9a8147163384f776777bf283217a5cd55cbbdfe7"

assert_contains_fixed \
    "boundaries page keeps verifier preservation boundary" \
    "boundaries.html" \
    "The verifier/evaluator boundary still preserves the \`v3.3.81+\` runtime-profile installation counts"

assert_contains_fixed \
    "boundaries page keeps 4/4 coverage boundary" \
    "boundaries.html" \
    "older pinned \`v3.3.90\` coverage sample at \`4/4\`"

assert_contains_fixed \
    "boundaries page keeps configured-channel fail-closed boundary" \
    "boundaries.html" \
    "configured approval channel when enabled and fail closed when absent"

assert_contains_fixed \
    "boundaries page keeps earlier v3.3.76 target boundary" \
    "boundaries.html" \
    "the earlier prepared \`v3.3.81\` runtime-profile-installation target and \`v3.3.76\` active-profile target remain intact"

assert_contains_fixed \
    "boundaries page keeps no non-operator review claim" \
    "boundaries.html" \
    "does not prove non-operator review"

assert_contains_fixed \
    "boundaries page keeps no new verifier contact" \
    "boundaries.html" \
    "It sends no verifier request, contacts no verifier, creates no public external attestation"

assert_contains_fixed \
    "boundaries page keeps previous runtime-profile installation proof boundary" \
    "boundaries.html" \
    "The previous \`v3.3.81\` release added local disposable runtime-profile installation proof"

assert_contains_fixed \
    "boundaries page keeps public claim guard hardening boundary" \
    "boundaries.html" \
    "Approval-channel boundary copy remains configured-channel behavior"

assert_contains_fixed \
    "boundaries page keeps private verifier request boundary" \
    "boundaries.html" \
    "private-by-default non-Vincent verifier request"

assert_contains_fixed \
    "boundaries page keeps public attestation non-claim" \
    "boundaries.html" \
    "no public external attestation is claimed in this repo"

assert_contains_fixed \
    "boundaries page keeps verifier-env JSON report boundary" \
    "boundaries.html" \
    "zlar-verifier-env-report-v0.json"

assert_contains_fixed \
    "boundaries page keeps verifier-env public attestation non-claim" \
    "boundaries.html" \
    "creates no public external attestation"

assert_contains_fixed \
    "boundaries page keeps Codex adapter Telegram-silent boundary" \
    "boundaries.html" \
    "ZLAR_TELEGRAM_DISABLED=1"

assert_contains_fixed \
    "boundaries page keeps Telegram health non-claim" \
    "boundaries.html" \
    "does not prove Telegram health"

assert_no_public_regex \
    "public copy must not mark v3.3.99 Markdown polish as current" \
    'The[[:space:]]+current[[:space:]]+release[[:space:]]+adds[[:space:]]+release-forward[[:space:]]+result[[:space:]]+Markdown[[:space:]]+polish'

assert_no_public_regex \
    "public proof-pack manifest must not keep stale v3.3.99 boundary" \
    'Verifier[[:space:]]+kit[[:space:]]+reproducibility[[:space:]]+evidence;[[:space:]]+release-forward[[:space:]]+packet[[:space:]]+readability'

assert_no_public_regex \
    "public copy must not say receipts prove/record what happened" \
    '(^|[^[:alnum:]_])receipts?[^.?!]{0,80}(records?|shows?|captures?|explains?|proves?)[^.?!]{0,80}what happened'

assert_no_public_regex \
    "public copy must not say a receipt is proof of what happened" \
    '(^|[^[:alnum:]_])receipts?[^.?!]{0,80}proof of[^.?!]{0,80}what happened'

assert_no_public_regex \
    "public copy must not describe receipts as receipts of what happened" \
    '(^|[^[:alnum:]_])receipts?[^.?!]{0,80}of what happened'

assert_no_public_regex \
    "public copy must not claim ZLAR reconstructs agent history" \
    '(^|[^[:alnum:]_])ZLAR[[:space:]]+reconstructs?[[:space:]]+what[[:space:]]+the[[:space:]]+agent[[:space:]]+did'

assert_no_public_regex \
    "public copy must not say receipts record the agent full history" \
    '(^|[^[:alnum:]_])the[[:space:]]+receipt[[:space:]]+records?[[:space:]]+the[[:space:]]+agent.?s[[:space:]]+full[[:space:]]+history'

assert_no_public_regex \
    "public copy must not say receipts prove agent intent" \
    '(^|[^[:alnum:]_])the[[:space:]]+receipt[[:space:]]+proves?[[:space:]]+what[[:space:]]+the[[:space:]]+agent[[:space:]]+intended'

assert_no_public_regex \
    "public copy must not say receipts prove correctness" \
    '(^|[^[:alnum:]_])the[[:space:]]+receipt[[:space:]]+proves?[[:space:]]+the[[:space:]]+decision[[:space:]]+was[[:space:]]+correct'

assert_no_public_regex \
    "public copy must not claim quickstart has no simulation boundary" \
    'Nothing[[:space:]]+is[[:space:]]+simulated'

assert_no_public_regex \
    "public copy must not claim gate unconditionally writes action receipts" \
    'audit[[:space:]]+entry[[:space:]]+[+][[:space:]]+receipt[[:space:]]+written|writes[[:space:]]+audit[[:space:]]+trail[[:space:]]+and[[:space:]]+receipts'

assert_no_public_regex \
    "public copy must not claim all actions cross the gate" \
    '(^|>)[[:space:]]*(it|the[[:space:]]+agent|an[[:space:]]+agent)[[:space:]]+cannot[[:space:]]+act[[:space:]]+without[[:space:]]+crossing[[:space:]]+the[[:space:]]+gate'

assert_no_public_regex \
    "public copy must not say before AI acts without a routed qualifier" \
    'Before[[:space:]]+AI[[:space:]]+acts'

assert_no_public_regex \
    "public copy must not say ZLAR is the doorway all AI must pass through" \
    'ZLAR[[:space:]]+is[[:space:]]+the[[:space:]]+doorway[[:space:]]+AI[[:space:]]+must[[:space:]]+pass[[:space:]]+through'

assert_no_public_regex \
    "public copy must not claim every outcome traces to a human decision" \
    'Every[[:space:]]+outcome[[:space:]]+traces[[:space:]]+back[[:space:]]+to[[:space:]]+a[[:space:]]+human[[:space:]]+decision'

assert_no_public_regex \
    "public copy must not claim the agent has no choice but to meet the gate" \
    'agent[[:space:]]+has[[:space:]]+no[[:space:]]+choice[[:space:]]+but[[:space:]]+to[[:space:]]+meet[[:space:]]+the[[:space:]]+gate'

assert_no_public_regex \
    "public copy must not claim categorical touch prevention outside a governed path" \
    'AI[[:space:]]+cannot[[:space:]]+touch[[:space:]]+the[[:space:]]+rules|can.?t[[:space:]]+touch[[:space:]]+what.?s[[:space:]]+on[[:space:]]+the[[:space:]]+other[[:space:]]+side'

assert_no_public_regex \
    "public copy must not claim every important attempt is recorded" \
    'every[[:space:]]+important[[:space:]]+attempt'

assert_no_public_regex \
    "public copy must not claim current independent/external key custody" \
    '(authority[[:space:]]+comes[[:space:]]+from[^.?!]{0,120}(independent|external)[[:space:]]+key[[:space:]]+custody|sealed[[:space:]]+mode[^.?!]{0,160}(independent|external)[[:space:]]+key[[:space:]]+custody)'

assert_no_public_regex \
    "public copy must not claim unconditional working-today approval channel" \
    'human[[:space:]]+approval[[:space:]]+over[[:space:]]+a[[:space:]]+channel[[:space:]]+outside[[:space:]]+the[[:space:]]+AI.?s[[:space:]]+runtime\.'

assert_no_public_regex \
    "public copy must not equate logs and receipts" \
    '(^|[^[:alnum:]_])a[[:space:]]+log[[:space:]]+is[[:space:]]+the[[:space:]]+same[[:space:]]+as[[:space:]]+a[[:space:]]+receipt'

assert_no_public_regex \
    "public copy must not claim unconditional phone approval routing" \
    'message[[:space:]]+appears[[:space:]]+on[[:space:]]+the[[:space:]]+operator.?s[[:space:]]+phone'

assert_no_public_regex \
    "public copy must not claim unconditional Telegram approval routing" \
    'human[-[:space:]]+in[-[:space:]]+the[-[:space:]]+loop[[:space:]]+approval[[:space:]]+via[[:space:]]+Telegram|approval[[:space:]]+via[[:space:]]+Telegram'

assert_no_public_regex \
    "public copy must not claim absolute agent inability to modify governance" \
    'you[[:space:]]+cannot[[:space:]]+modify[[:space:]]+the[[:space:]]+gate,[[:space:]]+the[[:space:]]+policy,[[:space:]]+or[[:space:]]+the[[:space:]]+signing[[:space:]]+key'

assert_no_public_regex \
    "public copy must not claim the gate is unconditionally outside agent writable space" \
    'the[[:space:]]+gate[[:space:]]+sits[[:space:]]+outside[[:space:]]+your[[:space:]]+writable[[:space:]]+space'

assert_no_public_regex \
    "public copy must not claim structurally impossible outcomes without a bounded deployment qualifier" \
    'structurally[[:space:]]+impossible'

assert_no_public_regex \
    "public copy must not claim completed external attestation" \
    'externally[-[:space:]]+attested|external[-[:space:]]+attestation[-[:space:]]+(complete|completed|done)|independently[-[:space:]]+attested|non[-[:space:]]+Vincent[-[:space:]]+verifier[-[:space:]]+has[-[:space:]]+verified'

assert_no_public_regex \
    "public copy must not preserve stale previous-release pointer" \
    'v3[.]3[.]80'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.83 current-release pointer" \
    'ZLAR v3[.]3[.]83 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]83|releases/tag/v3[.]3[.]83|ZLAR v3[.]3[.]83[[:space:]]+—[[:space:]]+Release-forward verifier dry-run helper|ZLAR v3[.]3[.]83[[:space:]]+—[[:space:]]+Release-forward dry-run manifest'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.97 current-release pointer" \
    'ZLAR v3[.]3[.]97 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]97|releases/tag/v3[.]3[.]97|The current release adds release-forward malformed-registry evidence'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.98 current-release pointer" \
    'ZLAR v3[.]3[.]98 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]98|releases/tag/v3[.]3[.]98|The current release adds North Star readiness report evidence'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.100 current-release boundary" \
    'ZLAR v3[.]3[.]100 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]100|releases/tag/v3[.]3[.]100|The current release adds verifier-kit reproducibility evidence|Receipt emission boundary clarity; source-build archive determinism'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.101 current-release boundary" \
    'ZLAR v3[.]3[.]101 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]101|releases/tag/v3[.]3[.]101|The current release adds the readiness report reproducibility bridge|Receipt emission boundary clarity; readiness-report accuracy'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.102 current-release boundary" \
    'ZLAR v3[.]3[.]102 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]102|releases/tag/v3[.]3[.]102|ZLAR v3[.]3[.]102</h3>|The current release clarifies receipt-emission boundaries|Receipt emission boundary clarity; claim-boundary and copy-guard hardening only'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.107 current-release boundary" \
    'ZLAR v3[.]3[.]107 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]107|Current ZLAR public claims are bounded by v3[.]3[.]107|releases/tag/v3[.]3[.]107|ZLAR v3[.]3[.]107</h3>|The current release adds North Star private intake pointer reporting'

assert_no_public_regex \
    "public copy must not preserve stale v3.3.109 current-release boundary" \
    'ZLAR v3[.]3[.]109 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]109|releases/tag/v3[.]3[.]109|The current release adds verifier-kit public distribution posture audit|Verifier-kit public distribution posture audit'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.0 current-release pointer" \
    'ZLAR v3[.]4[.]0 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]0|releases/tag/v3[.]4[.]0|"current_public_release": "v3[.]4[.]0"'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.1 current-release pointer" \
    'ZLAR v3[.]4[.]1 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]1([^0-9]|$)|Current ZLAR public claims are bounded by v3[.]4[.]1([^0-9]|$)|releases/tag/v3[.]4[.]1([^0-9]|$)|"current_public_release": "v3[.]4[.]1"|The current release prepares a pinned v3[.]4[.]0 external-verifier target'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.8 current-release boundary" \
    'ZLAR v3[.]4[.]8 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]8|Current ZLAR public claims are bounded by v3[.]4[.]8|releases/tag/v3[.]4[.]8|"current_public_release": "v3[.]4[.]8"|The current release adds recognition-proof artifact verification|Recognition proof artifact verification'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.10 current-release boundary" \
    'ZLAR v3[.]4[.]10 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]10|Current ZLAR public claims are bounded by v3[.]4[.]10|releases/tag/v3[.]4[.]10|"current_public_release": "v3[.]4[.]10"|The current release adds Product Proof Path readiness intake|The current v3[.]4[.]10 release publishes'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.17 current-release boundary" \
    'ZLAR v3[.]4[.]17 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]17|Current ZLAR public claims are bounded by v3[.]4[.]17|releases/tag/v3[.]4[.]17|"current_public_release": "v3[.]4[.]17"|The current release binds terminal-chain refusal taxonomy'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.18 current-release boundary" \
    'ZLAR v3[.]4[.]18 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]18|Current ZLAR public claims are bounded by v3[.]4[.]18|releases/tag/v3[.]4[.]18|"current_public_release": "v3[.]4[.]18"|The current release binds service-proof artifact verification'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.19 current-release boundary" \
    'ZLAR v3[.]4[.]19 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]19|Current ZLAR public claims are bounded by v3[.]4[.]19|releases/tag/v3[.]4[.]19|"current_public_release": "v3[.]4[.]19"|The current release binds the installed-runtime-profile recognition contract'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.23 current-release boundary" \
    'ZLAR v3[.]4[.]23 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]23|Current ZLAR public claims are bounded by v3[.]4[.]23|releases/tag/v3[.]4[.]23|"current_public_release": "v3[.]4[.]23"|ZLAR v3[.]4[.]23</h3>|Terminal-chain recognition refusal groups'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.24 current-release boundary" \
    'ZLAR v3[.]4[.]24 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]24|Current ZLAR public claims are bounded by v3[.]4[.]24|releases/tag/v3[.]4[.]24|"current_public_release": "v3[.]4[.]24"|ZLAR v3[.]4[.]24</h3>|Release-forward recognition case IDs'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.25 current-release pointer" \
    'ZLAR v3[.]4[.]25 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]25([^0-9+]|$)|Current ZLAR public claims are bounded by v3[.]4[.]25([^0-9+]|$)|releases/tag/v3[.]4[.]25|"current_public_release": "v3[.]4[.]25"|ZLAR v3[.]4[.]25</h3>|v3[.]4[.]25 release</a>'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.28 current-release pointer" \
    'ZLAR v3[.]4[.]28 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]28([^0-9+]|$)|Current ZLAR public claims are bounded by v3[.]4[.]28([^0-9+]|$)|releases/tag/v3[.]4[.]28|"current_public_release": "v3[.]4[.]28"|ZLAR v3[.]4[.]28</h3>|v3[.]4[.]28 release</a>|The current release preserves terminal-chain nested artifact binding'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.31 current-release pointer" \
    'ZLAR v3[.]4[.]31 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]4[.]31([^0-9+]|$)|Current ZLAR public claims are bounded by v3[.]4[.]31([^0-9+]|$)|releases/tag/v3[.]4[.]31|"current_public_release": "v3[.]4[.]31"|ZLAR v3[.]4[.]31</h3>|v3[.]4[.]31 release</a>|Verifier-kit release asset live read'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.33 current-release pointer" \
    'ZLAR v3[.]4[.]33 on GitHub|Current public release:.*ZLAR v3[.]4[.]33([^0-9+]|$)|Current ZLAR public claims are bounded by v3[.]4[.]33([^0-9+]|$)|releases/tag/v3[.]4[.]33|"current_public_release": "v3[.]4[.]33"|ZLAR v3[.]4[.]33</h3>|v3[.]4[.]33 release</a>|The current release makes issuer-status fixture evidence first-class'

assert_no_public_regex \
    "public copy must not preserve stale v3.4.34 current-release pointer" \
    'ZLAR v3[.]4[.]34 on GitHub|Current public release:.*ZLAR v3[.]4[.]34([^0-9+]|$)|Current ZLAR public claims are bounded by v3[.]4[.]34([^0-9+]|$)|releases/tag/v3[.]4[.]34|"current_public_release": "v3[.]4[.]34"|ZLAR v3[.]4[.]34</h3>|v3[.]4[.]34 release</a>|The current release makes private result verification evidence first-class'

assert_no_public_regex \
    "public copy must not shorten trusted issuer malformed-registry artifact names" \
    'zlar-trusted-receipt-issuer-malformed-registry'

assert_no_public_regex \
    "public copy must not claim unconditional Telegram or phone approval routing" \
    'human[[:space:]]+notified[[:space:]]+via[[:space:]]+Telegram|routes?[[:space:]]+to[[:space:]]+a[[:space:]]+human[[:space:]]+via[[:space:]]+Telegram|single[[:space:]]+bot[[:space:]]+that[[:space:]]+routes[[:space:]]+all[[:space:]]+governed[[:space:]]+asks|Telegram[[:space:]]+unreachable:[[:space:]]+deny|human.?s[[:space:]]+only[[:space:]]+interface[[:space:]]+is[^.?!]{0,80}phone|person[[:space:]]+behind[[:space:]]+the[[:space:]]+phone'

assert_no_public_regex \
    "public copy must not claim categorical agent self-modification prevention" \
    'agents[[:space:]]+cannot[[:space:]]+modify[[:space:]]+their[[:space:]]+own[[:space:]]+rules'

assert_no_public_regex \
    "public copy must not use current-release retarget wording" \
    'current[[:space:]]+release[[:space:]]+line[[:space:]]+also[[:space:]]+(adds[[:space:]]+release-forward[[:space:]]+verifier[[:space:]]+packet[[:space:]]+alignment|retargets|hardens[[:space:]]+verifier[[:space:]]+active-profile)'

assert_no_public_regex \
    "public copy must not use muddy prepared-not-sent verifier phrasing" \
    'prepared,[[:space:]]+not-sent[[:space:]]+release-forward[[:space:]]+external[[:space:]]+verifier[[:space:]]+packet|not-yet-sent[[:space:]]+pinned[[:space:]]+target'

assert_no_public_regex \
    "public downloadable assets must not preserve stale verifier status" \
    'prepared_pending|prepared/pending|no-contact external verifier packet|no verifier has been contacted|contacted or appointed'

assert_no_public_regex \
    "public downloadable assets must not preserve stale attestation-pending verifier status" \
    'private_request_sent_attestation_pending|attestation pending|no completed attestation has been received'

assert_no_public_regex_collapsed \
    "public copy must not hide stale attestation-pending wording across line breaks" \
    'private_request_sent_attestation_pending|attestation pending|no completed attestation has been received'

assert_no_public_regex \
    "public downloadable assets must not anchor current safe wording to stale release" \
    'v3\.3\.15 safe Codex wording'

echo
printf "Results: %d/%d passed" "${PASS}" "${TOTAL}"
if [ "${FAIL}" -gt 0 ]; then
    printf " (%d FAILED)" "${FAIL}"
    echo
    exit 1
fi
echo " ✓"
