#!/bin/bash
# Public-copy guard for website receipt authority and private-core boundaries.
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
    '*.json'
    '*.xml'
    '*.css'
    'CNAME'
    'LICENSE'
    'docs'
    'specs'
    'demo'
    'install.sh'
    'uninstall.sh'
)

pass() { PASS=$((PASS + 1)); }

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

assert_not_contains_fixed() {
    local label="$1"
    local path="$2"
    local needle="$3"
    TOTAL=$((TOTAL + 1))

    if grep -Fq "${needle}" "${path}"; then
        fail "${label}" "unexpected in ${path}: ${needle}"
    else
        pass
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
const data = JSON.parse(fs.readFileSync(process.env.JSON_PATH, 'utf8'));

let value = data;
for (const part of process.env.JSON_POINTER.split('.').filter(Boolean)) {
  if (!value || !Object.prototype.hasOwnProperty.call(value, part)) {
    throw new Error(`missing ${process.env.JSON_POINTER}`);
  }
  value = value[part];
}

if (String(value) !== process.env.JSON_EXPECTED) {
  throw new Error(`${process.env.JSON_POINTER} expected ${process.env.JSON_EXPECTED} but got ${String(value)}`);
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
const data = JSON.parse(fs.readFileSync(process.env.JSON_PATH, 'utf8'));

let value = data;
for (const part of process.env.JSON_POINTER.split('.').filter(Boolean)) {
  if (!value || !Object.prototype.hasOwnProperty.call(value, part)) {
    throw new Error(`missing ${process.env.JSON_POINTER}`);
  }
  value = value[part];
}
if (value === null || typeof value === 'undefined') throw new Error(`${process.env.JSON_POINTER} is null or undefined`);
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

assert_regex_matches_text() {
    local label="$1"
    local pattern="$2"
    local text="$3"
    TOTAL=$((TOTAL + 1))

    if printf '%s\n' "${text}" | grep -Eiq "${pattern}"; then
        pass
    else
        fail "${label}" "pattern did not match representative bad example: ${text}"
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
  if (actual !== expected) throw new Error(`${name} expected ${expected} but got ${actual}`);
}
function requireIncludes(name, body, needle) {
  if (!String(body).includes(needle)) throw new Error(`${name} missing ${needle}`);
}

requireEqual('proof-pack current release', manifest.current_public_release, current.version);
requireEqual('proof-pack current release URL', manifest.current_public_release_url, current.url);
requireEqual('proof-pack release metadata timestamp', manifest.release_metadata_updated_at, release.generated_at);
requireEqual('proof-pack claim ceiling', manifest.claim_ceiling, safeClaim);
requireEqual('coverage safe claim ceiling', coverage.safe_claim_ceiling, safeClaim);
requireIncludes('proof-pack README release pointer', readme, `ZLAR ${current.version} - ${current.title}.`);
requireIncludes('proof-pack boundary title', manifest.current_public_release_boundary, current.version);
requireIncludes('release evidence threshold', release.claim_boundary?.evidence_threshold || '', 'static zlar.ai receipt-scanner path');
requireIncludes('release source boundary', release.source_boundary || '', 'Current core source access is private');
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
CURRENT_RELEASE_COMMIT="$(read_json_value "release.json" "current_public_release.commit")"
CURRENT_RELEASE_TAG_OBJECT="$(read_json_value "release.json" "current_public_release.tag_object")"
CURRENT_RELEASE_POINTER="ZLAR ${CURRENT_RELEASE_VERSION} - ${CURRENT_RELEASE_TITLE}"
CURRENT_RELEASE_LLM_POINTER="Current public release: ${CURRENT_RELEASE_POINTER}."

private_absolute_path_pattern='/Users/[A-Za-z0-9._-]+(/[^[:space:]"'"'"'<>]*)?|/home/[A-Za-z0-9._-]+(/[^[:space:]"'"'"'<>]*)?|C:\\Users\\[A-Za-z0-9._-]+'
fixture_operator_name_pattern='"(user|operator|authorizer|approver|reviewer|maintainer)"[[:space:]]*:[[:space:]]*"(vincent|vincentnijjar|Vincent|Vincent Nijjar)"'
hardware_serial_pattern='(YubiKey|hardware|device|security key|key)[[:print:]]{0,100}(serial|s/n|serial number)[[:print:]]{0,60}[0-9]{6,}|(serial|s/n|serial number)[[:print:]]{0,60}[0-9]{6,}[[:print:]]{0,100}(YubiKey|hardware|device|security key|key)'
machine_model_pattern='(^|[^[:alnum:]])(Mac mini|MacBook|Mac Studio|Mac Pro|iMac)([^[:alnum:]]|$)'
numeric_human_id_pattern='(human|authorizer|approver|telegram|chat_id|telegram[_ -]?(chat|human)?[_ -]?id)[^[:space:]]{0,30}(:|=| )[[:space:]]*[0-9]{7,}|human:[0-9]{7,}'
token_secret_pattern="(Bearer[[:space:]]+[A-Za-z0-9._-]{20,}|(token|api[_-]?key|secret)[[:space:]]*[:=][[:space:]]*['\"]?([A-Za-z0-9._-]{20,}|sk-[A-Za-z0-9_-]{8,}|pk-[A-Za-z0-9_-]{8,}))"
unsupported_public_claim_pattern='(ZLAR (is )?(production[- ]ready|externally attested|independently attested)|production[- ]ready ZLAR|external attestation (is )?(complete|completed|done|achieved|received)|public external attestation (is )?(complete|completed|done|achieved|received)|non[- ]Vincent verifier (has )?(verified|attested)|production (adapter|adaptor) proof)'
authority_overclaim_pattern='authority (is|becomes|must become) code[- ]based|code[- ]based authority|code creates legitimacy|legal standing|statutory (right|rights|remedy|remedies)'
private_core_github_pattern='github[.]com/ZLAR-AI/ZLAR([/.?#"'"'"'[:space:]<>]|$)'
private_core_clone_pattern='git[[:space:]]+clone[[:space:]]+https://github[.]com/ZLAR-AI/ZLAR[.]git'
public_machine_room_pattern='GitHub[[:space:]]*/[[:space:]]*Machine Room|View on GitHub|Inspect GitHub|Machine Room'
current_open_source_source_pattern='ZLAR[[:space:]]+(is|products[[:space:]]+are|products[[:space:]]+are[[:space:]]+distributed[[:space:]]+as)[^.?!]{0,80}open[- ]source|open[- ]source[[:space:]]+at'
public_install_promise_pattern='curl[[:space:]]+-fsSL[[:space:]]+https://zlar[.]ai/install[.]sh[[:space:]]*[|][[:space:]]*bash|Install with curl|one command[^.?!]{0,80}governance'
public_ci_evidence_pattern='Remote CI|CodeQL|OpenSSF|Scorecard'
bad_serial_digits="37175116"
bad_numeric_human_id="123456789"
bad_token_suffix="live-secret-1234567890"

echo "=== Website Public-Copy Guard ==="

assert_no_public_regex "public surfaces must not link the private core GitHub repo" "${private_core_github_pattern}"
assert_no_public_regex "public surfaces must not publish private core clone instructions" "${private_core_clone_pattern}"
assert_no_public_regex "public surfaces must not promise GitHub Machine Room inspection" "${public_machine_room_pattern}"
assert_no_public_regex "public surfaces must not claim current ZLAR core source is open source" "${current_open_source_source_pattern}"
assert_no_public_regex "public surfaces must not promise a public installer" "${public_install_promise_pattern}"
assert_no_public_regex "public surfaces must not promise public CI visibility" "${public_ci_evidence_pattern}"
assert_no_public_regex "public surfaces must not expose private absolute local paths" "${private_absolute_path_pattern}"
assert_no_public_regex "public surfaces must not name the operator in fixture role fields" "${fixture_operator_name_pattern}"
assert_no_public_regex "public surfaces must not expose hardware serial numbers" "${hardware_serial_pattern}"
assert_no_public_regex "public surfaces must not expose machine model names" "${machine_model_pattern}"
assert_no_public_regex "public surfaces must not expose numeric Telegram or human ids" "${numeric_human_id_pattern}"
assert_no_public_regex "public surfaces must not expose token or API-key shaped strings" "${token_secret_pattern}"
assert_no_public_regex "public surfaces must not imply unsupported production or attestation claims" "${unsupported_public_claim_pattern}"
assert_no_public_regex "public surfaces must not imply code-created or legal authority" "${authority_overclaim_pattern}"
assert_no_public_regex "public surfaces must not publish v3.4.55" 'v3[.]4[.]55'
assert_no_public_regex "public surfaces must not publish v3.4.57" 'v3[.]4[.]57'

assert_regex_matches_text "private-core guard catches repo URLs" "${private_core_github_pattern}" "example.html:1:https://github.com/ZLAR-AI/ZLAR"
assert_regex_matches_text "clone guard catches private clone commands" "${private_core_clone_pattern}" "example.html:1:git clone https://github.com/ZLAR-AI/ZLAR.git"
assert_regex_matches_text "installer guard catches curl installer command" "${public_install_promise_pattern}" "example.html:1:curl -fsSL https://zlar.ai/install.sh | bash"
assert_regex_matches_text "current-source guard catches open-source-at wording" "${current_open_source_source_pattern}" "example.html:1:ZLAR is open source at github.com/ZLAR-AI/ZLAR"
assert_regex_matches_text "privacy guard catches private path examples" "${private_absolute_path_pattern}" "example.html:1:/Users/alice/.ssh/id_ed25519"
assert_regex_matches_text "privacy guard catches operator fixture names" "${fixture_operator_name_pattern}" 'demo/example.json:1:{"operator":"Vincent"}'
assert_regex_matches_text "privacy guard catches hardware serial examples" "${hardware_serial_pattern}" "example.html:1:YubiKey spare device serial ${bad_serial_digits}"
assert_regex_matches_text "privacy guard catches machine model examples" "${machine_model_pattern}" "example.html:1:Mac mini filesystem checked"
assert_regex_matches_text "privacy guard catches numeric human id examples" "${numeric_human_id_pattern}" "demo/example.json:1:{\"authorizer\":\"human:${bad_numeric_human_id}\"}"
assert_regex_matches_text "privacy guard catches token examples" "${token_secret_pattern}" "example.html:1:api_key=sk-${bad_token_suffix}"
assert_regex_matches_text "authority guard catches legal standing wording" "${authority_overclaim_pattern}" "example.html:1:ZLAR gives legal standing to affected people"

assert_contains_fixed "homepage keeps airport hero" "index.html" "Intelligence may change. Consequence still needs authority."
assert_contains_fixed "homepage uses authority-gate headline" "index.html" "Consequential machine action needs a boarding gate."
assert_contains_fixed "homepage keeps human institution authority source" "index.html" "Human institutions define authority."
assert_contains_fixed "homepage keeps machine-checkable action gate" "index.html" "machine-checkable at the point of action."
assert_contains_fixed "homepage keeps core claim" "index.html" "For defined routed action surfaces, ZLAR makes consequential AI action pass"
assert_contains_fixed "homepage states private current core" "index.html" "Current core source access is private."
assert_contains_fixed "homepage keeps Bring One Action concrete" "index.html" "One action. One route. One policy. One receipt. One refusal rule. One honest"
assert_contains_fixed "proof-pack page keeps receipt scanner summary" "proof-pack.html" "Receipt scanner summary: the public sample is fake/scratch evidence"
assert_contains_fixed "proof-pack page uses public proof desk boundary" "proof-pack.html" "Public release metadata and proof-pack detail live in"
assert_contains_fixed "boundaries page keeps side-door map" "boundaries.html" "The airport map is honest because it names the side doors."
assert_contains_fixed "boundaries page keeps exact routed-surface boundary" "boundaries.html" "ZLAR governs routed/intercepted action surfaces only."
assert_contains_fixed "proof-pack page downloads release metadata" "proof-pack.html" "curl -fsSLO https://zlar.ai/release.json"
assert_contains_fixed "proof-pack sidecar hashes release metadata" "demo/proof-pack/SHA256SUMS" "release.json"
assert_contains_fixed "website README keeps evergreen boundary" "README.md" "The website should remain evergreen"
assert_contains_fixed "LLM index keeps current release pointer" "llms.txt" "${CURRENT_RELEASE_LLM_POINTER}"
assert_contains_fixed "LLM index states private current core" "llms.txt" "Current core source access is private"
assert_contains_fixed "public installer fails closed" "install.sh" "This stub does not install, activate, configure hooks"
assert_not_contains_fixed "receipt verify page has no fake private clone replacement" "receipt-verify.html" "public proof artifacts on zlar.ai.git"

assert_json_value "release metadata keeps schema" "release.json" "schema" "zlar-public-release-metadata-v1"
assert_json_value "release metadata keeps current release" "release.json" "current_public_release.version" "${CURRENT_RELEASE_VERSION}"
assert_json_value "release metadata keeps release title" "release.json" "current_public_release.title" "${CURRENT_RELEASE_TITLE}"
assert_json_value "release metadata uses static public release URL" "release.json" "current_public_release.url" "https://zlar.ai/release.json"
assert_json_value "release metadata uses private source descriptor" "release.json" "current_public_release.repository" "private-core-source"
assert_json_value "release metadata states private current core" "release.json" "current_public_release.source_visibility" "private_current_core"
assert_json_value "release metadata points public verification to proof-pack manifest" "release.json" "current_public_release.public_verification_url" "https://zlar.ai/demo/proof-pack/proof-pack-manifest.json"
assert_json_value "release metadata keeps release commit as historical reference" "release.json" "current_public_release.commit" "${CURRENT_RELEASE_COMMIT}"
assert_json_value "release metadata keeps tag object as historical reference" "release.json" "current_public_release.tag_object" "${CURRENT_RELEASE_TAG_OBJECT}"
assert_json_value "release metadata keeps live URL" "release.json" "website.live_url" "https://zlar.ai/release.json"
assert_json_value "proof-pack manifest uses static public release URL" "demo/proof-pack/proof-pack-manifest.json" "current_public_release_url" "https://zlar.ai/release.json"
assert_json_value "proof-pack manifest keeps release metadata timestamp" "demo/proof-pack/proof-pack-manifest.json" "release_metadata_updated_at" "${RELEASE_METADATA_GENERATED_AT}"

assert_contains_fixed "release metadata keeps receipt invariant" "release.json" "A log records what happened. A ZLAR receipt records what counted as authorized effect"
assert_contains_fixed "release metadata preserves license boundary" "release.json" "Prior Apache-2.0 public distribution remains licensed"
assert_contains_fixed "proof-pack manifest preserves source boundary" "demo/proof-pack/proof-pack-manifest.json" "Current core source access is private"

assert_release_boundary_manifest "release boundary manifest agrees with proof-pack mirror"
assert_proof_pack_bundle_verifies "downloadable proof-pack bundle verifies against release metadata"

echo
printf "Results: %d/%d passed" "${PASS}" "${TOTAL}"
if [ "${FAIL}" -gt 0 ]; then
    printf " (%d FAILED)" "${FAIL}"
    echo
    exit 1
fi
echo " OK"
