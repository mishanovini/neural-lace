# Plan: Problems-persist mechanism (inline ledger IDs + Stop-time WARN + operator auto-file)
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal mechanism with no product user — the maintainer is the user, and --self-test passing is the demonstration (constitution §4).
tier: 2
rung: 2
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
ask-id: none — no linked ask

<!--
Retroactive plan (written after the build, in the same session): the
operator's dispatch (verbatim, 2026-07-29) already specified the full
three-part design in detail — see docs/reviews/2026-07-29-operator-five-
questions.md Q2 and docs/decisions/065-problems-persist-warn-consolidation.md
for the WARN-vs-block reasoning. This plan file exists to satisfy
scope-enforcement-gate.sh (a commit governed by an ACTIVE plan's declared
`## Files to Modify/Create` scope) and to give the work a durable,
closeable record — not as a planning exercise that preceded the build.
lifecycle-schema: v2 intentionally omitted (grandfathered v1 shape): this
plan is opened and closed in the same session with no multi-day ownership
window, so owner/target-completion-date/Closure Contract do not apply.
-->

## Goal

Operator directive (2026-07-29, verbatim): "Can we enforce a system where
anytime you tell me about a problem that should probably be fixed, you
never just allow it to not be addressed? ... I need these concerns to
persist until we actually address them." Constitution §5 already says
bugs/gaps/findings get written to their durable home in the same response
that surfaces them — but filing was entirely discretionary, so the ledger
reflected what a session remembered to file, not what it found. This plan
builds the three-part mechanism that makes an unfiled problem statement
mechanically visible and, where the operator is the one naming it,
mechanically captured.

## User-facing Outcome

The operator can no longer have a raised concern silently vanish because
they didn't have time to read the whole response: (1) every problem
statement in chat now carries its ledger ID inline, so a missing ID is
visible at read time without an audit; (2) if a session ends a turn with
problem-shaped prose and no inline ID, a teaching WARN fires (visible in
the signal ledger + stderr) naming the exact `nl-issue.sh` command to file
it; (3) if the OPERATOR is the one who names a problem in their own prompt
("why is X broken", "critical problem"), it is filed into the nl-issue.sh
ledger automatically, tagged `source: operator-verbatim`, with no session
action required at all.

## Scope

In scope: doctrine amendment (inline ledger IDs), a WARN-only Stop-time
check consolidated into `stop-verdict-dispatcher.sh`, a UserPromptSubmit
splice in `workstreams-read.sh`, the `nl-issue.sh` schema/dedup changes
part 3 depends on, and the portability fix to `_nli_json_field` found
while testing part 3 on this machine's BSD sed (in-scope because it
directly affects the correctness of this build's own new dedup-exemption
logic — see docs/backlog.md `NL-ISSUE-JSON-FIELD-BSD-SED-ALTERNATION-BUG-01`
for the full write-up).

Out of scope: the pre-existing `workstreams-read.sh` Scenario R20 mtime
flake and the `INDEX.md`/manifest.json drift noticed in passing (both
logged to `docs/backlog.md` / `nl-issue.sh`, confirmed pre-existing via
git-stash A/B, not touched here); the broader verification-dispatch
enforcement gap (Q1 of the five-questions review, tracked by its own plan
`docs/plans/verification-dispatch-directive.md`); the 110-file review
backlog (Q5).

## Tasks

- [ ] **T1 — Doctrine: inline ledger IDs.** Amend
  `adapters/claude-code/doctrine/findings-ledger.md` establishing that
  every problem statement in operator-facing chat carries its ledger ID
  inline (`NL-FINDING-###`, `NL-ISSUE-###`, or the row's own slug).
  Verification: mechanical (doctrine-text amendment, no runtime behavior
  of its own).

- [ ] **T2 — Stop-time WARN check.** Add `_svd_problems_persist_check` to
  `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` (consolidated
  into the existing dispatcher per `docs/decisions/065-problems-persist-
  warn-consolidation.md`, not a new hook file) — scans the final assistant
  message paragraph-by-paragraph for problem vocabulary
  (defect/bug/broken/silently/data loss/root cause) with no inline ledger
  ID, warns (never blocks) with a pre-filled `nl-issue.sh` command.
  Verification: mechanical (harness-internal Stop hook; `--self-test` is
  the demonstration per constitution §4).
  **Prove it works:** `bash adapters/claude-code/hooks/stop-verdict-
  dispatcher.sh --self-test` — scenarios 27-30 exercise unfiled/filed/
  ordinary-prose/multi-paragraph cases; RED-GREEN proven by disabling the
  call site (80/3 fail) then restoring it (83/0 pass).
  **Wire checks:** `adapters/claude-code/hooks/stop-verdict-dispatcher.sh`
  `_svd_main` → `_svd_problems_persist_check` → `_svd_paragraph_is_problem_shaped`
  / `_svd_paragraph_has_ledger_id` → `_svd_ledger "warn"`.
  **Integration points:** signal ledger (`lib/signal-ledger.sh`'s
  `ledger_emit`) — verified via `grep '"gate":"stop-verdict-dispatcher".*problems-persist' <ledger>` in self-test scenarios 27/30.

- [ ] **T3 — Operator-named auto-file.** Add `_problem_capture_on_prompt`
  splice to `adapters/claude-code/hooks/workstreams-read.sh` (following its
  existing ASK-CAPTURE splice precedent, zero new settings.json entries),
  plus the `source` field / dedup-exemption / BSD-sed portability fix in
  `adapters/claude-code/scripts/nl-issue.sh` it depends on.
  Verification: mechanical (harness-internal UserPromptSubmit splice;
  `--self-test` is the demonstration).
  **Prove it works:** `bash adapters/claude-code/hooks/workstreams-read.sh
  --self-test` (scenarios PC1-PC4) and `bash adapters/claude-code/scripts/
  nl-issue.sh --self-test` (scenarios 11-15) — RED-GREEN proven by
  disabling the splice call site (58/5 fail) then restoring it (62/1 pass,
  the 1 being the pre-existing unrelated R20 flake).
  **Wire checks:** `adapters/claude-code/hooks/workstreams-read.sh`
  `_run_read` → `_problem_capture_on_prompt` → `_nli_capture_cli_path` →
  `adapters/claude-code/scripts/nl-issue.sh` `nli_append` (NLI_SOURCE=operator-verbatim).
  **Integration points:** `nl-issue.sh`'s ledger at `$NL_ISSUES_PATH` —
  verified via `grep '"source":"operator-verbatim"'` in nl-issue.sh
  self-test scenarios 12-15.

## Files to Modify/Create

- `adapters/claude-code/doctrine/findings-ledger.md` — inline-ledger-ID doctrine amendment (T1).
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` — PROBLEMS-PERSIST WARN check + self-test scenarios 27-30 (T2).
- `adapters/claude-code/hooks/workstreams-read.sh` — PROBLEM-CAPTURE splice + self-test scenarios PC1-PC4 (T3).
- `adapters/claude-code/scripts/nl-issue.sh` — `source` field, dedup exemption, BSD-sed portability fix, self-test scenarios 11-15 (T3).
- `adapters/claude-code/manifest.json` — `honest_status` updates on `stop-verdict-dispatcher`, `workstreams-emitters`, `nl-issue-capture-loop` entries (no new entries, no budget-class changes).
- `docs/backlog.md` — two pre-existing, unrelated findings noticed in passing (nl-issue.sh BSD-sed bug — since fixed — and workstreams-read.sh R20 flake).
- `docs/decisions/065-problems-persist-warn-consolidation.md` — Decisions-Log entry for the WARN-vs-block / file-placement choice (created alongside this plan).

## Assumptions

- The operator's five-questions review (`docs/reviews/2026-07-29-operator-
  five-questions.md`, reachable via `git show 1a2ba8a:...` from this
  worktree's lineage) is the authoritative design source; this plan does
  not re-litigate its content.
- `stop-verdict-dispatcher.sh` is confirmed the live Stop-chain entry point
  (verified: `adapters/claude-code/settings.json.template`'s `Stop` array
  wires it directly; the three member gates are invoked internally via
  `--report` mode, not as separate settings.json entries) — this is the
  premise the WARN-consolidation decision rests on.
- `blocking session-event units` measured 14/14 in this worktree's own
  `manifest.json` (not 16/14 as the original dispatch prompt cited) —
  likely a different measurement surface (live `~/.claude/manifest.json`
  vs this worktree's repo copy; harness-doctor.sh confirmed 16/14 against
  the LIVE manifest during this same session). Either number supports the
  same conclusion: zero headroom for a new blocking unit.

## Edge Cases

- A problem-shaped paragraph split across the Stop-time check's paragraph
  boundary from its citing ID (ID in an adjacent paragraph, not the same
  one) still warns — a known, accepted false-positive documented in the
  check's own header (start narrow, precision over recall).
- An operator prompt containing the named vocabulary as an aside, not a
  real problem report (e.g., "why is the sky blue" mid-conversation),
  still files a row — accepted; `nl-issue.sh --triage <n> wontfix <reason>`
  is the correct disposition, not a smarter heuristic that risks missing
  real reports.
- Pre-existing `nl-issues.jsonl` lines with no `source` field read as
  `"session"` by every consumer (nli_list, nli_triage) — additive schema
  change, verified backward compatible.
- An operator-verbatim row is exempted from dedup in BOTH directions
  (never a merge target, never merged from) — verified by nl-issue.sh
  self-test scenarios 13-14.

## Testing Strategy

Every part is harness-internal (Verification: mechanical) — the test IS
the artifact's own `--self-test`, run under BOTH `/opt/homebrew/bin/bash`
(5.3) and `/bin/bash` (3.2.57, the portability floor), per file:

- `stop-verdict-dispatcher.sh --self-test`: 83/0 both interpreters.
- `nl-issue.sh --self-test`: 32/0 both interpreters (was 13/11 pre-fix;
  the BSD-sed regex bug explains all 11 pre-existing failures).
- `workstreams-read.sh --self-test`: 62/1 both interpreters (the 1 is
  the pre-existing, unrelated R20 mtime flake — confirmed via git-stash
  A/B on the unmodified file, filed in docs/backlog.md).

RED-GREEN mutation proof for every new check (not just "tests pass"):
disabling each new call site (via a temporary comment-out, restored
immediately after) reproduces the exact pre-fix failure count, proving
the self-test scenarios exercise the real behavior, not a vacuous pass.

## Closure

All three tasks are built, self-tested (including RED-GREEN mutation
proof) under both bash interpreters, and committed. Closeable via the
`close-plan` skill (harness-internal → Verification: mechanical routing;
no runtime instance beyond `--self-test` to exercise).
