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

echo "=== Website Public-Copy Guard ==="

assert_contains_fixed \
    "homepage keeps log/receipt invariant" \
    "index.html" \
    "A log records what happened. A ZLAR receipt records what counted as authorized effect"

assert_contains_fixed \
    "boundaries page keeps release boundary" \
    "boundaries.html" \
    "that guard is CI evidence only and adds no runtime authority"

assert_contains_fixed \
    "boundaries page keeps current release pointer" \
    "boundaries.html" \
    "ZLAR v3.3.79 on GitHub"

assert_contains_fixed \
    "website README keeps current release pointer" \
    "README.md" \
    "ZLAR v3.3.79 — Verifier handoff wording normalization"

assert_contains_fixed \
    "LLM index keeps current release pointer" \
    "llms.txt" \
    "Current public release: ZLAR v3.3.79 — Verifier handoff wording normalization."

assert_contains_fixed \
    "proof-pack README keeps current release pointer" \
    "demo/proof-pack/README.md" \
    "ZLAR v3.3.79 — Verifier handoff wording normalization."

assert_contains_fixed \
    "proof-pack manifest keeps current release pointer" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "\"current_public_release\": \"v3.3.79\""

assert_contains_fixed \
    "architecture archive keeps current release pointer" \
    "architecture.html" \
    "Current public release: ZLAR v3.3.79 — Verifier handoff wording normalization."

assert_contains_fixed \
    "boundaries page keeps records.write terminal proof boundary" \
    "boundaries.html" \
    "records-write-terminal-proof"

assert_contains_fixed \
    "boundaries page keeps verifier packet split status" \
    "boundaries.html" \
    "The historical private verifier request remains sent and private-by-default. Separately, the prepared pinned release-forward verifier target remains"

assert_contains_fixed \
    "boundaries page keeps verifier packet target" \
    "boundaries.html" \
    "the \`v3.3.76\` proof-pack/proof-smoke release"

assert_contains_fixed \
    "boundaries page keeps active profile selection preservation" \
    "boundaries.html" \
    "\`active_profile_selection\` summary"

assert_contains_fixed \
    "boundaries page keeps verifier handoff normalization" \
    "boundaries.html" \
    "current release normalizes verifier handoff wording"

assert_contains_fixed \
    "boundaries page keeps verifier-kit runner non-claim" \
    "boundaries.html" \
    "no external attestation is claimed unless a real non-operator runner fills, signs, or publishes the result"

assert_contains_fixed \
    "boundaries page keeps no new verifier contact" \
    "boundaries.html" \
    "The verifier handoff status sends no new verifier request, contacts no verifier, creates no public external attestation"

assert_contains_fixed \
    "boundaries page keeps active profile selection non-claims" \
    "boundaries.html" \
    "no persistent runtime-profile install, no hook activation, no live profile check, and no \`--latest\` selection"

assert_contains_fixed \
    "boundaries page keeps public claim guard hardening boundary" \
    "boundaries.html" \
    "approval routing is described as configured-channel behavior, not unconditional phone or Telegram availability"

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
    "public copy must not claim all actions cross the gate" \
    '(^|>)[[:space:]]*(it|the[[:space:]]+agent|an[[:space:]]+agent)[[:space:]]+cannot[[:space:]]+act[[:space:]]+without[[:space:]]+crossing[[:space:]]+the[[:space:]]+gate'

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
    'v3[.]3[.]78'

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
