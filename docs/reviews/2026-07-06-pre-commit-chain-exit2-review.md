# 2026-07-06 — harness-reviewer: pre-commit-chain exit-2 flip + hygiene remediation

**Change reviewed:** settings.json.template line 301 — PreToolUse git-commit wrapper
`bash ~/.claude/hooks/pre-commit-gate.sh || exit 1` → `|| exit 2` (Claude Code PreToolUse
blocks only on exit 2; exit 1 is non-blocking, stderr to the user pane only) — plus the
same-commit hygiene content fixes (manifest golden_scenario reword, doctor fixture,
evidence-file path redaction, plan/review prose).

**Verdict: CONDITIONAL-PASS** (3 Major / 2 Minor, no Critical). Core premise verified
independently: scope-enforcement-gate.sh exits 2 at three sites and demonstrably blocks;
the pre-commit chain's exit-1 wrapper cannot block. Live probes: this commit's staged set
scans clean (RC=0); a probe file carrying the denylisted codename token fires the scan
(RC=1); the reworded phrasing does not (RC=0). Doctor self-test fixture reword provably
cannot break the new-gate-evidence-bar check (RC/presence assertions only).

**Findings (condensed):**
1. Major (PROVEN) — hygiene-scan's block message prescribed `git commit --no-verify` as
   the bypass: a stale remedy that cannot bypass PreToolUse wiring and is §7-prohibited.
   → FIXED in the same commit (message now prescribes fix-content or is_exempt() +
   restage). Generalization: sweep all FRESHNESS_GATES block messages for remedies that
   work under PreToolUse semantics.
2. Major (PROVEN) — highest-FP sub-gate post-flip is hygiene-scan itself: whole-file
   scanning × ~70 residual full-tree matches × no session-time waiver ⇒ blocks sessions
   for debt they didn't create. → mitigation required with/immediately after any flip
   (GAP-55 sweep or structured waiver).
3. Major (PROVEN) — GAP-54's residual list was too narrow: three additional wired
   blocking PreToolUse hooks exit 1 on their block paths (no-test-skip-gate,
   plan-deletion-protection, wire-check-gate) plus four suspects. → GAP-54 amended.
4. Minor (PROVEN) — no regression guard on the fixed line; doctor check must be
   wrapper-aware (assert template wiring maps failure to exit 2). → folded into GAP-54.
5. Minor (HYPOTHESIZED) — git-commit matcher regex misses `git -C <path> commit` and
   fires on `cd X && git commit` against the wrong index; normalize in the GAP-54 sweep.

**Post-review discovery (this session, after the reviewer ran) + disposition:** direct
runs of plan-reviewer.sh against the real staged workflow show the chain is ALSO
latent-RED on the ACTIVE program plan (Check 1 undecomposed-sweep, mostly on completed
`- [x]` lines) and was RED on every spec appendix until this commit's header fixes
(Check 10). A live flip would therefore hard-block every program checkbox-flip commit.
**Decision (decide-and-go): flip DEFERRED to GAP-54 with binding activation
preconditions** (plan-reviewer REFERENCE skip; Check 1 unchecked-only; block-message
sweep; hygiene-residual mitigation). The hygiene content fixes, spec-appendix headers,
and block-message remedy fix shipped now; the one-character flip ships when the chain is
genuinely green on the real workflow. Until then the manifest's `pre-commit-chain.
blocking: true` claim is documented-false in GAP-54 (constitution §10 marking).
