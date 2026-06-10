#!/usr/bin/env bash
# One-shot generator for MANIFEST.md (kept in-tree for regeneration if fixtures change).
set -euo pipefail
cd "$(dirname "$0")"
OUT=MANIFEST.md

meta() { # $1=agent -> echo "TIER|STAGING|RISK"
case "$1" in
claim-reviewer) echo "APPLY-WITH-WATCH|clean apply (byte-exact from proposal section C; zero drift since 2026-06-05)|Stricter aggregation (any NEI on a functionality claim -> FAIL) means more rewrite cycles before user-facing answers; self-invoked so it cannot hard-block sessions. Watch for over-FAILing honest summaries." ;;
comprehension-reviewer) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift)|Blocks checkbox flips at rung 2+; the two NEW fail classes (unconsidered-edge-class, unsurfaced-assumption) will measurably raise R2+ FAIL rates and lengthen build loops. Class vocabulary is additive and parser-safe. Watch R2+ flip-block frequency on the first few plans." ;;
plan-evidence-reviewer) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift). REVIEW COMPLETE / VERDICT: sentinels verified present in staged file|Fires at the tool-call-budget ack and session end - stricter verdicts mean more CONCERNS/BLOCKED at the 30-call threshold (mid-build friction). Sentinels preserved so the ack mechanism is safe. Watch budget-ack block frequency." ;;
end-user-advocate) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift). Artifact JSON fields verified additive (plan_commit_sha/verdict intact; oracles_checked/tours_run added)|PASS is harder to earn (named oracle + toured factors per scenario) -> more session-end FAILs/waivers via product-acceptance-gate. Watch waiver frequency. The GWT scenario-format change also touches plans authored under the old format - fixture rubric carries a hard parser-contract check." ;;
functionality-verifier) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift)|Fires before checkbox flips on Verification: full tasks - oracle discipline + mandatory metamorphic relations will produce more FAIL/INCOMPLETE, especially on AI-feature tasks (real-model calls now mandatory-er). Watch flip-block rate and AI-task verification cost." ;;
domain-expert-tester) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift). Title-case frontmatter name preserved (customer-facing-review-gate greps the exact family name)|Tool grant changes it from static reader to live-app driver (browser MCP) - meaningful capability expansion; findings stay advisory. Watch its first few live runs for browser-session interference." ;;
ux-end-user-tester) echo "APPLY-WITH-WATCH|RECONCILED apply: digest-flagged tools-vs-prose mismatch resolved by adding 7 browser-MCP tools to frontmatter (prose said prefer-browser; proposal frontmatter had omitted them). Title-case name preserved|Low risk (advisory reporter) once the tools mismatch is reconciled - which the staged file does. Watch narration-vs-substance balance." ;;
ux-designer) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift)|ux-designer review is mandatory pre-build for UI surfaces - the explicit FAIL verdict formalizes plan-blocking that was previously prose. Severity-inflation guards exist; watch Critical rates on the next few UI plans." ;;
prd-validity-reviewer) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift)|Both tightens (could-be-any-product fast-fail) and loosens (low-confidence FAILs become advisory). NL mostly uses the harness-dev carve-out so exposure is limited to product plans. Verdict vocabulary preserved. Watch the first product-plan review for calibration." ;;
harness-evaluator) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift). NOTE: proposal pins model: opus - per-run cost decision the digest says to sanity-check before adoption|Read-only (never mutates), but the opus pin raises per-run cost; the proposal itself flags that its model/tools frontmatter lines need checking against conventions. Decide the model pin at apply time." ;;
enforcement-gap-analyzer) echo "APPLY-WITH-WATCH|clean apply (byte-exact; zero drift). PAIR-COUPLED: must land in the SAME commit as harness-reviewer (verified: staged analyzer emits the renamed sections the staged reviewer greps)|COUPLING is the risk: it renames a mechanically-checked output section. Applied alone, every proposal would REFORMULATE on format under the current reviewer. Apply only as a pair." ;;
harness-reviewer) echo "APPLY-WITH-WATCH|RECONCILED apply: Step 5.1/5.3 extended to accept BOTH the new analyzer section name (Existing controls...) AND the legacy name, with prefix-match on suffix-qualified headings - implements the digest's pair-coupling requirement|Check 2.8 will REJECT more new gates (block-mode without escape hatches / negative self-tests) - intended, but raises the bar for all future mechanisms. Apply paired with enforcement-gap-analyzer; watch REJECT rate on the next few harness PRs." ;;
task-verifier) echo "NEEDS-MISHA (results-only; NO apply)|staged for A/B only (byte-exact; zero drift). Hook-grepped strings verified present (EVIDENCE BLOCK / Task ID: / Runtime verification: formats / Verdict:)|Highest-blast-radius reviewer in the harness - the single checkbox-flip authority. Oracle rule + confidence floor will raise FAIL/INCOMPLETE rates harness-wide; any evidence-block drift hits plan-edit-validator.sh / pre-stop-verifier.sh parsing. Misha decides strictness; run a hook-parse smoke test on the emitted evidence block before any apply." ;;
plan-phase-builder) echo "NEEDS-MISHA (results-only; NO apply)|staged for A/B only (byte-exact; zero drift)|The agent that does ALL dispatched build work - mandatory red-first TDD + skeleton-first sequencing changes the shape, pace, and cost of every build. Mis-calibration slows the whole factory. Misha decides whether to mandate red-first everywhere or stage it (e.g., product repos first)." ;;
systems-designer) echo "NEEDS-MISHA (results-only; NO apply)|staged for A/B only (byte-exact; zero drift)|Scope-of-authority change, not just quality: the agent would start reviewing (and FAILing) product plans it never touched before, and the binary PASS/FAIL contract documented in design-mode-planning.md gains a third value (PASS-WITH-CONCERNS) downstream readers do not expect. Misha owns the remit decision." ;;
documentation-auditor) echo "NEEDS-MISHA (results-only; NO apply)|staged for A/B only (byte-exact; zero drift). NET-NEW agent - no current counterpart exists; the A/B baseline is the nearest per-doc review capability|Inventory decision: a new roster agent means docs/harness-architecture coupling, a broad tool grant (Write + browser MCP + WebFetch), and overlap-management with existing per-doc skills. The design is strong; adding it to the roster is the call." ;;
esac
}

{
echo "# Agent-Upgrade A/B Test Manifest — batch 2 (16 agents)"
echo
echo "Generated: 2026-06-10 on branch feat/agent-upgrades-batch2-2026-06-10."
echo "Upgraded (staged) agent files: \`adapters/claude-code/agents-staged/<name>.md\`"
echo "Current agent files: \`adapters/claude-code/agents/<name>.md\` (zero drift since the"
echo "2026-06-05 proposals on all 15 existing agents; documentation-auditor is net-new)."
echo "Proposals: \`docs/reviews/agent-upgrades/2026-06-05-<name>.md\` (gitignored — live in"
echo "the MAIN checkout working tree, not in this branch)."
echo
echo "## How the orchestrator runs one A/B"
echo
echo "1. Run A (current): dispatch the fixture's dispatch-prompt with the CURRENT agent"
echo "   file as the agent definition. Run B (upgraded): same prompt, agent definition"
echo "   from \`agents-staged/\`. Same model, same cwd (repo root of this branch checkout)."
echo "2. Fixtures are read-only unless the prompt says otherwise; builder/verifier"
echo "   fixtures explicitly instruct output-in-response instead of file edits."
echo "3. Score both transcripts against the fixture's expected-delta rubric: upgrade"
echo "   wins if it shows the listed deltas WITHOUT any regression signal; any"
echo "   'Contract checks (both runs)' violation in Run B is an auto-reject."
echo "4. The 12 WATCH agents: apply per-agent on PASS (gap-analyzer + harness-reviewer"
echo "   ONLY as a pair, same commit). The 4 NEEDS-MISHA agents: present results only."
echo
echo "---"
} > "$OUT"

for a in claim-reviewer comprehension-reviewer plan-evidence-reviewer end-user-advocate functionality-verifier domain-expert-tester ux-end-user-tester ux-designer prd-validity-reviewer harness-evaluator enforcement-gap-analyzer harness-reviewer task-verifier plan-phase-builder systems-designer documentation-auditor; do
  IFS='|' read -r TIER STAGING RISK <<<"$(meta "$a")"
  {
    echo
    echo "## $a"
    echo
    echo "- **Tier:** $TIER"
    echo "- **Staging status:** $STAGING"
    echo "- **Staged file:** \`adapters/claude-code/agents-staged/$a.md\`"
    echo "- **Fixture path:** \`.claude/state/agent-ab-fixtures/$a/\`"
    echo "- **Apply-risk notes (from digest):** $RISK"
    echo
    echo "### Dispatch prompt (verbatim — same prompt for both runs)"
    echo
    echo '```'
    cat "$a/dispatch-prompt.md"
    echo '```'
    echo
    echo "### Expected-delta rubric"
    echo
    sed 's/^# Expected-delta rubric.*$//' "$a/expected-delta.md" | sed 's/^## /#### /' | sed '/./,$!d'
    echo
    echo "---"
  } >> "$OUT"
done
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
