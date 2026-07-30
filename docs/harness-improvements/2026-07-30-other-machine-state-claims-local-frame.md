# Enforcement Gap Proposal: Other-machine state claims asserted from the local frame

**Date:** 2026-07-30 (revised same day per harness-reviewer REFORMULATE — 2 CRITICAL, 4 MAJOR, 2 MINOR; class, layer choice, controls audit, cat-file core upheld)
**Triggered by:** needs-you ask `NY-1785394095-d8ec` (retracted defective, `NEEDS-YOU.md:39`) + wrong-root-cause retraction (landed `77abbcf`, refuted+corrected `b848a0b`)
**Proposal type:** AMENDMENT (needs-you.sh lint + manifest.json mirror) + one-sentence Pattern residual (doctrine/claims.md)
**Control rung (proposed):** Mechanism (path-existence core) + Pattern (residual)
**Class severity:** HIGH
**Confidence in diagnosis:** PROVEN (all artifacts verified in-repo)
**FM catalog:** extends FM-029 (diagnosis arm; new context: cross-machine harness ops, decisive check = git-vs-origin/master, not platform logs); composition arm new — add as FM-039 on acceptance

## Class of failure
**Other-machine state claims asserted from local frame** (8 words). The session re-verified every LOCALLY-observable claim (re-ran all builder suites) yet asserted/accepted claims about state observable only via the shared frame (origin/master, another machine's checkout) unverified. Siblings (hypothetical, distinct): (1) an ask instructs the laptop to run `scripts/foo.sh` renamed on master last week — dead path shipped as instruction; (2) the incident's inverse: an ask instructs the desktop to run a genuinely branch-local script without saying so; (3) a session accepts "the LaunchAgent never ran on the laptop" and asserts a cause without pulling the shared coord ledger.

## 5-Whys to the latent cause
1. Why did the operator's command fail? PowerShell CWD `C:\Users\misha`; relative `-File` path unresolvable (PROVEN: `b848a0b` body; corrected ask `NEEDS-YOU.md:13-15` adds the cd step).
2. Why did the ask ship without the CWD precondition or any check of what the desktop shares? Nothing at composition checks an instruction's TRUTH — needs-you.sh lints FORM only (PROVEN: `needs-you.sh:525-673`).
3. Why was "exists only on this Mac's unmerged branch" then written into four durable artifacts without the decisive check? §1/claims.md tagging is Pattern-class, self-applied; vigilance failed under multi-lane load exactly where the claim was non-local (PROVEN: `git cat-file -e origin/master:adapters/claude-code/scripts/install-coord-sync-task.ps1` exits 0, on master since `14568b2`; wrong claim landed `77abbcf`, refuted `b848a0b`).
4. Why did no mechanical layer catch it? Every mechanical control checks claim FORM (sections, anchors, tags), never TRUTH; none distinguishes local-frame claims (habitually verified) from shared-frame claims (vigilance-only). ← latent condition: **no control demands verification when a claim's subject is not locally observable — even for the subset one-line-checkable against origin/master.**

## Defensive-layer walk (Swiss-Cheese)
- **Composition-time (`needs-you.sh add`):** lint ran; hole: form-only. EARLIEST VIABLE LAYER — firing 1 and the corrected-ask cycle pass through `add`.
- **Commit-time (`evidence-before-fix-gate.sh`):** trigger is `fix(` subjects, WARN-mode, structure-only (PROVEN: header). Wrong claim landed in `docs(...)` commit `77abbcf` → not-triggered; even on a `fix(` commit it cannot test decisiveness.
- **Always-on:** constitution §1 + `doctrine/claims.md`; §3 check-you-ran amendment (2026-07-28) — both pattern-only-unenforced.
- **Common-mode hole across ALL layers:** each inspects artifact shape; none executes the claim's own one-line verifier. The amendment fixes that assumption rather than stacking another shape-checker.

## Existing controls that should have caught this
- `needs-you.sh` `_ny_lint_ask_text`/`_ny_lint_decision_text` — **triggered-but-shallow** (PROVEN: lines 525-673; a wrong path satisfies the anchor check perfectly). AMENDMENT TARGET.
- `evidence-before-fix-gate.sh` — **not-triggered** for `77abbcf` (docs commit) and **triggered-but-shallow** by design (structure-only, WARN-mode; PROVEN: header).
- constitution §1 + `doctrine/claims.md` — **pattern-only-unenforced** (PROVEN: "Enforcement: Pattern — self-applied" header).
- constitution §3 check-you-ran clause (2026-07-28) — **pattern-only-unenforced**; no hook backing.
- `harness-claim-lint.sh` — **trigger-too-narrow** (PROVEN: header — Class 2 fires on absolute/perf keywords, not existence claims about remote state).
- `transcript-lie-detector.sh` — retired exit-0 shim (PROVEN: file body).
- Sweep (`rg "origin/master|other machine|cross-machine|remote state|non-local"` over rules/ hooks/ agents/ doctrine/ + `docs/failure-modes.md`): FM-029 names diagnosis-from-inference but scopes to production-log pulls and is Pattern-only. Nothing covers the composition arm.

## Why current mechanisms missed this (root-cause statement)
The mechanizable layers verify claim FORM; the truth-verifying discipline lives only at the Pattern rung (PROVEN: lint source; claims.md header). Claims about origin/master are the one non-local class with a deterministic one-line verifier, and no control invokes it — the claims most likely to be wrong got the least verification.

## Proposed change (concrete diff or file creation)
**(a) AMENDMENT — `adapters/claude-code/scripts/needs-you.sh` (Mechanism):** new helper `_ny_check_remote_paths <text>`, spliced at the existing lint call site inside `add` (both `--section question` and `--section decision`), BEFORE `_ny_write_ledger` (`needs-you.sh:503`) — an interactive block is "exit 1, nothing written", matching the manifest's existing two-path contract verbatim; `--mechanical` stores + quarantines, never rejects. Compound trigger:
- **Part 1 (other-machine signal):** text matches `(on|at|from) (the |your )?(windows|desktop|laptop|other machine|that machine)` (case-insensitive).
- **Part 2 (instruction-context path):** an instruction-shaped line — `STEP`-prefixed, inside a fenced block, or line-initial command verb — whose verbs are word-boundaried (`\b(run|powershell|bash|sh|cd|git)\b|-File`) and which contains a repo-relative path token (`[A-Za-z0-9_.-]+([/\\][A-Za-z0-9_.-]+)+\.[A-Za-z0-9]+`). Excluded: `http*`, drive-prefixed (`C:\...`), and absolute paths. `~/.claude/<p>` tokens are MAPPED to their repo source `adapters/claude-code/<p>` (the install mirror) before checking; other `~/` paths are excluded. Reference-only mentions on non-instruction lines never trigger.
- **Check per path:** normalize `\`→`/`; `git -C "$(nl_main_checkout_root)" fetch -q origin master` (10s bounded). **Fresh-ref discipline — never hard-block on stale evidence:** on fetch success, `git -C "$(nl_main_checkout_root)" cat-file -e origin/master:<path>`; absent+unannotated → interactive BLOCK naming the exact path, command, and three remediations (merge first / fix the path / annotate `branch-local: <branch>`). On fetch failure BOTH directions demote to recorded WARN `stale-ref-unverified:<path>`.
- **Audited escape hatch (mechanizes the firing-2 direction):** `branch-local:` annotations are VERIFIED, not trusted — cat-file runs anyway; exit 0 → BLOCK: "path IS on origin/master since `<sha>`; remove the false annotation" (exactly the firing-2 claim, refuted at write time). A surviving (true) annotation is stored as lint code `branch-local-annotated:<path>` so weekly triage audits hatch usage.
- **Visible durable pass line:** every verified path prints AND stores on the ledger item `verified on origin/master @<short-sha>` (`rev-parse --short origin/master` at check time) — a later contrary diagnosis now contradicts a recorded verification instead of unrecorded vigilance.
- **Cross-repo asks** (path belongs to another repo): recorded warn-only skip `cross-repo-unverified:<path>`, never a block.
- **Companion code `no-cwd-precondition` (WARN-only, per §10):** when the trigger fires, text must contain a working-directory signal (`cd |From:|repo root|in your .* (checkout|repo)`); else warn.
- **Fire ledger (makes retirement measurable):** every fire — block, warn, annotated-pass, stale-skip, cross-repo-skip — appends one JSONL line to `~/.claude/state/needs-you/remote-path-check.jsonl` (the existing would-block-ledger pattern, cf. `agent-commit-gate.sh`).

**(b) Manifest mirror (same change):** update manifest.json `needs-you-ledger` `honest_status` (id at manifest.json:1373) with the new codes, golden scenario, FP expectation, and retirement condition.

**(c) Pattern residual — one sentence in `doctrine/claims.md`:** "A claim about another machine's repo state is a claim about origin/master by proxy: cite the `git cat-file -e origin/master:<path>` / `git merge-base --is-ancestor` check you ran, or tag it HYPOTHESIZED." Mechanism is infeasible for the general class (arbitrary non-local claims need LLM-grade judgment); the path subset is the mechanizable core.

**§10 gate credentials (honest scope):** Golden scenario = arm A (the original ask: `no-cwd-precondition` fires, pass line recorded) + the inverse-direction BLOCK (instructing a truly branch-local path). Stated plainly: the mechanism could NOT fire on the literal firing-2 retraction text (`NEEDS-YOU.md:39` — bare filename, no separator; "the desktop checkout" evades the preposition trigger; landed via a docs commit + resolve path, not `add`). The firing-2 DIRECTION is covered where mechanizable: the audited annotation refutes a false branch-locality claim at composition time, and the durable pass line makes prior verification citable against later wrong diagnoses; the remainder is the named Pattern residual. FP expectation: trigger measured against the full historical ledger — 2/5 items fire, both genuine cross-machine asks (0 FP; n=5, small-sample caveat); the cat-file check is deterministic; blocks issue only on a fresh ref. Retirement: the fire ledger is the counter — 0 lines in 60 days once coord-sync cockpit actions replace manual cross-machine asks → demote to WARN, then retire.

## Evasion & over-block analysis
- **Cheap-evasion:** (i) reflexive `branch-local:` annotation — audited: a false one is BLOCKED (cat-file exit 0), a true one recorded for triage; (ii) chat-only asks bypassing needs-you.sh — residual; §2 mandates the same-turn ledger write, so bypass is itself a visible violation; (iii) prose-only references ("the coord sync installer") dodge the regex — the named Pattern residual. Not teach-to-the-test: fires on ANY cross-machine-instructed repo path, both directions.
- **Over-block (must pass):** reference-only mentions on non-instruction lines; words merely containing verb substrings; absolute/drive-prefixed paths; cross-repo asks (recorded skip); sanctioned empty asks (`Blocking: nothing`); truthfully-annotated branch-local instructions; anything on a stale ref (WARN, never block).

## Testing strategy
Extend `needs-you.sh --self-test` (existing `HARNESS_SELFTEST=1` sandbox) against a fixture repo whose synthetic `origin/master` ref each test creates (avoids harness-claim-lint CLASS 1):
1. **Golden A (firing 1):** desktop ask, path present, no cd line → `no-cwd-precondition` warns; pass line `verified on origin/master @<sha>` printed AND stored.
2. **Inverse BLOCK (sibling 2):** path absent, unannotated → interactive add exits 1, nothing written, path named; `--mechanical` quarantines with `unverified-remote-path:<path>`.
3. **Renamed script (sibling 1):** path on a feature branch only → BLOCKS (fresh ref).
4. **False annotation (firing-2 direction):** path present + `branch-local: wip/x` → BLOCKS naming the refutation sha.
5. **True annotation:** path absent + annotation → passes; `branch-local-annotated` code stored; fire-ledger line appended.
6. **Stale ref:** fixture remote unreachable → no block either direction; `stale-ref-unverified:<path>` recorded.
7. **Negative, one per M3 surface:** (a) reference-only path, non-instruction line → no fire; (b) embedded verb substring ("brushing docs/reviews/brief.md") → no fire; (c) `C:\Users\x\a.ps1` → excluded; (d) `~/.claude/hooks/foo.sh` → mapped to `adapters/claude-code/hooks/foo.sh`, verified; plain `~/other/x.sh` → excluded; (e) cross-repo path → recorded skip.
8. **Regression:** `Blocking: nothing` + all existing lint scenarios unchanged.
