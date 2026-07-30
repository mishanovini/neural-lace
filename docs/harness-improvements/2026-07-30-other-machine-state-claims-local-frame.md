# Enforcement Gap Proposal: Other-machine state claims asserted from the local frame

**Date:** 2026-07-30
**Triggered by:** needs-you ask `NY-1785394095-d8ec` (retracted defective, `NEEDS-YOU.md:39`) + wrong-root-cause retraction (landed `77abbcf`, refuted+corrected `b848a0b`)
**Proposal type:** AMENDMENT (needs-you.sh lint) + one-sentence Pattern residual (doctrine/claims.md)
**Control rung (proposed):** Mechanism (path-existence core) + Pattern (residual)
**Class severity:** HIGH
**Confidence in diagnosis:** PROVEN (all artifacts verified in-repo this session)
**FM catalog:** extends FM-029 (diagnosis arm; new context: cross-machine harness ops, decisive check = git-vs-origin/master, not platform logs); composition arm new — add as FM-039 on acceptance

## Class of failure
**Other-machine state claims asserted from local frame** (8 words). The session mechanically re-verified every LOCALLY-observable claim (re-ran all builder suites) yet asserted/accepted claims about state observable only via the shared frame (origin/master, another machine's checkout) with zero verification. Siblings (hypothetical, distinct): (1) an ask instructs the laptop to run `scripts/foo.sh` renamed on master last week — dead path shipped as instruction; (2) the incident's inverse: an ask instructs the desktop to run a genuinely branch-local script without saying so — the operator cannot succeed until an unmentioned merge; (3) a session accepts "the LaunchAgent never ran on the laptop" and asserts a cause without pulling the shared coord ledger.

## 5-Whys to the latent cause
1. Why did the operator's command fail? PowerShell CWD `C:\Users\misha`; relative `-File` path unresolvable (PROVEN: `b848a0b` body; corrected ask `NEEDS-YOU.md:13-15` adds the cd step).
2. Why did the ask ship without the CWD precondition or any check the desktop could have the file? Nothing at composition checks an instruction's TRUTH — needs-you.sh lints FORM only (PROVEN: `needs-you.sh:525-673` — context-length, anchor-presence, outcome-connective heuristics).
3. Why was "exists only on this Mac's unmerged branch" then written into four durable artifacts without the one-line decisive check? §1/claims.md tagging is Pattern-class, self-applied; vigilance failed under multi-lane load exactly where the claim was non-local (PROVEN: `git cat-file -e origin/master:adapters/claude-code/scripts/install-coord-sync-task.ps1` exits 0; on master since `14568b2`, 2026-07-17; wrong claim landed `77abbcf`, refuted `b848a0b`).
4. Why did no mechanical layer catch it? Every mechanical control checks claim FORM (sections, anchors, tags), never TRUTH; none distinguishes local-frame claims (habitually verified) from shared-frame claims (vigilance-only). ← latent condition: **no control demands verification when a claim's subject is not locally observable — even for the subset one-line-checkable against origin/master.**

## Defensive-layer walk (Swiss-Cheese)
- **Composition-time (`needs-you.sh add`):** lint ran; hole: form-only (triggered-but-shallow). EARLIEST VIABLE LAYER — both firings pass through `add`.
- **Commit-time (`evidence-before-fix-gate.sh`):** trigger is `fix(` subjects, WARN-mode, checks evidence-section STRUCTURE (PROVEN: its header). Wrong claim landed in `docs(...)` commit `77abbcf` → not-triggered; even on a `fix(` commit it cannot test decisiveness → shallow.
- **Always-on:** constitution §1 + `doctrine/claims.md`; §3 amendment 2026-07-28 ("name the check you ran") — both pattern-only-unenforced.
- **Common-mode hole across ALL layers:** each inspects artifact shape; none executes the claim's own one-line verifier. The amendment fixes that assumption rather than stacking another shape-checker.

## Existing controls that should have caught this
- `needs-you.sh` `_ny_lint_ask_text`/`_ny_lint_decision_text` — **triggered-but-shallow** (PROVEN: lines 525-673; a wrong path satisfies the anchor check perfectly). AMENDMENT TARGET.
- `evidence-before-fix-gate.sh` — **not-triggered** for `77abbcf` (docs commit) and **triggered-but-shallow** by design (structure-only, WARN-mode; PROVEN: header).
- constitution §1 + `doctrine/claims.md` — **pattern-only-unenforced** (PROVEN: "Enforcement: Pattern — self-applied" header).
- constitution §3 check-you-ran clause (2026-07-28) — **pattern-only-unenforced**; no hook backing.
- `harness-claim-lint.sh` — **trigger-too-narrow** (PROVEN: header — Class 2 fires on absolute/perf keywords, not existence claims about remote state).
- `transcript-lie-detector.sh` — retired exit-0 shim (PROVEN: file body).
- Sweep (`rg "origin/master|other machine|cross-machine|remote state|non-local"` over rules/ hooks/ agents/ doctrine/ + `docs/failure-modes.md`): FM-029 names diagnosis-from-inference but scopes to production-log pulls and is Pattern-only ("detection is reflexive" — its own text). Nothing covers the composition arm.

## Why current mechanisms missed this (root-cause statement)
The mechanizable layers verify claim FORM; the truth-verifying discipline lives only at the Pattern rung (PROVEN: lint source; claims.md header). Claims about origin/master are the one non-local class with a deterministic one-line verifier, and no control invokes it — so the claims most likely to be wrong (composed from a frame the composer isn't in) received the least verification (PROVEN: the session re-ran every builder suite locally yet wrote the refutable claim into four artifacts unchecked).

## Proposed change (concrete diff or file creation)
**(a) AMENDMENT — `adapters/claude-code/scripts/needs-you.sh` (Mechanism):** new helper `_ny_check_remote_paths <text>`, called from `add` for both `--section question` and `--section decision`, compound trigger:
- **Part 1 (other-machine signal):** text matches `on (the |your )?(windows|desktop|laptop|other machine|that machine)` (case-insensitive) — the instruction executes where the only shared state is origin/master.
- **Part 2 (instruction-context path):** a line containing a command verb (`run|powershell|bash |sh |cd |git |-File`) also contains a repo-relative path token (`[A-Za-z0-9_.-]+([/\\][A-Za-z0-9_.-]+)+\.[A-Za-z0-9]+`, not `http*`, not absolute). Reference-only mentions on non-command lines never trigger.
- **Check per path:** normalize `\`→`/`; skip if annotated `branch-local: <branch>`; else best-effort `git fetch -q origin master` (10s timeout; on failure proceed against the stale ref and say so), then `git cat-file -e origin/master:<path>`.
- **On failure:** interactive → `die` naming the exact failing path + command + three remediations (merge first / fix the path / annotate `branch-local: <branch>`, which tells the operator their machine lacks it). Mechanical → store + quarantine, `lint_warnings+=("unverified-remote-path:<path>")` (existing LINT PROMOTION semantics).
- **Companion code `no-cwd-precondition` (WARN-only, per §10 — heuristic arm ships unblocking until measured):** when the trigger fires, text must contain a working-directory signal (`cd |From:|repo root|in your .* (checkout|repo)`); else warn.

**(b) Pattern residual — one sentence in `doctrine/claims.md`:** "A claim about another machine's repo state is a claim about origin/master by proxy: cite the `git cat-file -e origin/master:<path>` / `git merge-base --is-ancestor` check you ran, or tag it HYPOTHESIZED." Mechanism is infeasible for the general class (recognizing arbitrary non-local claims needs LLM-grade judgment); the path subset is the mechanizable core — the rung split is justified, not convenient.

**§10 gate credentials:** Golden scenario = this incident, both arms (arm A: original ask lacked CWD precondition → `no-cwd-precondition` fires; arm B: composed through the check, `cat-file` exits 0 and mechanically refutes "unmerged branch" before it is written — and the inverse, instructing a truly branch-local path, BLOCKS). FP expectation: measured this session against the full historical ledger — trigger fires 2/5 items, both genuine cross-machine asks (0 FP; n=5, small-sample caveat); the `cat-file` check is deterministic, so residual FP surface is trigger classification only; estimate <1/month. Retirement: when coord-sync cockpit actions replace manual cross-machine asks AND the trigger fires 0 times in 60 days, demote to WARN then retire.

## Evasion & over-block analysis
- **Cheap-evasion:** (i) reflexive `branch-local:` annotation — self-defeating: operator-visible text stating the file is NOT on their machine (the exact information whose absence caused firing 1); a false one is a §1 violation in the ledger. (ii) chat-only asks bypassing needs-you.sh — residual, but §2 mandates the same-turn ledger write, so bypass is itself a visible violation. (iii) prose-only references ("the coord sync installer") — dodges the regex; covered by the Pattern residual, named honestly as residual. Not teach-to-the-test: fires on ANY cross-machine-instructed repo path, both directions (absent-from-master AND falsely-claimed-absent).
- **Over-block (must pass):** asks mentioning another machine but citing paths only as references on non-command lines ("context: see docs/reviews/brief.md") — excluded by Part 2; sanctioned empty asks (`Blocking: nothing`) — existing whitelist untouched; genuinely branch-local instructions that SAY so — annotation is the sanctioned pass-through.

## Testing strategy
Extend `needs-you.sh --self-test` (existing `HARNESS_SELFTEST=1` sandbox), against a FIXTURE repo whose synthetic `origin/master` ref the test creates (before/after-delta form — avoids harness-claim-lint CLASS 1's assert-on-production-state trap):
1. **Golden A (firing 1):** "on the Windows desktop … run powershell -File adapters/claude-code/scripts/present.ps1", path in fixture master, no cd line → `no-cwd-precondition` warns; no block.
2. **Golden B (firing 2 world + sibling 2):** same text, path absent from fixture master → interactive add BLOCKS naming that path; `--mechanical` stores + quarantines.
3. **Sibling 1 (renamed script):** path present only on a feature branch → BLOCKS.
4. **Escape hatch:** absent path + `branch-local: wip/x` annotation → passes clean.
5. **Negative (over-block guard):** desktop mentioned + `docs/reviews/brief.md` on a non-command line → no fire.
6. **Negative (regression):** `Blocking: nothing` and all existing lint scenarios unchanged.
