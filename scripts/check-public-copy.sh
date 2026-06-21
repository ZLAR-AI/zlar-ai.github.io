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
    "ZLAR v3.4.0 on GitHub"

assert_contains_fixed \
    "website README keeps current release pointer" \
    "README.md" \
    "ZLAR v3.4.0 - Public verifier-kit distribution boundary release"

assert_contains_fixed \
    "LLM index keeps current release pointer" \
    "llms.txt" \
    "Current public release: ZLAR v3.4.0 - Public verifier-kit distribution boundary release."

assert_contains_fixed \
    "proof-pack README keeps current release pointer" \
    "demo/proof-pack/README.md" \
    "ZLAR v3.4.0 - Public verifier-kit distribution boundary release."

assert_contains_fixed \
    "proof-pack manifest keeps current release pointer" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "\"current_public_release\": \"v3.4.0\""

assert_contains_fixed \
    "proof-pack manifest keeps verifier target boundary" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "Public verifier-kit distribution boundary release"

assert_contains_fixed \
    "proof-pack manifest keeps external-attestation non-claim" \
    "demo/proof-pack/proof-pack-manifest.json" \
    "no public external attestation"

assert_contains_fixed \
    "architecture archive keeps current release pointer" \
    "architecture.html" \
    "Current public release: ZLAR v3.4.0 - Public verifier-kit distribution boundary release."

assert_contains_fixed \
    "CAISI archive keeps current release boundary" \
    "caisi-submission.html" \
    "The current release is the public verifier-kit distribution boundary release"

assert_contains_fixed \
    "fail-open archive keeps current release boundary" \
    "fail-open.html" \
    "The current release is the public verifier-kit distribution boundary release"

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
    "The current release is the public verifier-kit distribution boundary release"

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
    'ZLAR v3[.]3[.]107 on GitHub|Current public release:[[:space:]]*ZLAR v3[.]3[.]107|releases/tag/v3[.]3[.]107|ZLAR v3[.]3[.]107</h3>|The current release adds North Star private intake pointer reporting'

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
