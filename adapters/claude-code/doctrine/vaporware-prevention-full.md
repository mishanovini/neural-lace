# Anti-Vaporware — full detail

> Companion to the compact: `doctrine/vaporware-prevention.md`. Carries the registry-vs-callsite invariant pattern behind the "decorative config control" class; the compact is the operative summary (capped at 3000 bytes).

## The registry-vs-callsite invariant

**Definition.** Any code that maintains a registry of capabilities — permission IDs, feature flags, event types — plus a separate UI to configure those entries MUST have a mechanical check that every registry entry is wired to enforcement. The registry declares "this is configurable"; only an enforce-mode call site makes the declaration true. A registry entry with no enforcement consumer is a **decorative config control**: it renders, it persists, and it lies.

The invariant is structural, not stylistic: the registry and the call sites drift independently (a new permission ID added to the registry, a role check hardcoded at the action instead of routed through the registry), and nothing in a per-PR review sees both sides at once. Only a standing check that walks the registry and demands an enforce-mode consumer per entry closes the seam.

## The originating case (a downstream product)

A downstream product's per-org permissions matrix rendered 16 permission toggles; **6 were decorative**. Each rendered as configurable, persisted its value on save, and changed nothing — hardcoded caller-role guards governed the behavior. The actions themselves worked and were access-controlled, so no error ever surfaced; the RBAC admin surface simply lied. An org admin could "revoke" a permission the system kept honoring, or "grant" one to no effect. Every component-level signal was green — the matrix rendered, the API persisted, unit tests passed — while the functionality (toggle → behavior change) did not exist for 6 of 16 entries.

## Instantiating a project-level drift check

A check-permission-drift-style script, run in CI or as a standing invariant:

1. **Enumerate the registry IDs.** Parse the canonical registry source (the permission-definitions file, the flag manifest, the event-type enum) into the full ID list — not the UI's copy of it.
2. **For each ID, find an enforce-mode call site.** Grep/trace for the enforcement helper invoked with that ID (`checkPermission('<id>')`, `requireFlag('<id>')`, string-keyed dispatch included — trace the helper's callers, not just the literal ID).
3. **Fail on any ID with no enforce-mode call site.** Log-only / shadow-mode consumers do not count as enforcement (see below). The failure message names the decorative IDs so the fix is per-entry.

Keep the check registry-driven so a newly added entry is covered the moment it lands; a hand-maintained allowlist of "known-wired" IDs recreates the drift the check exists to catch.

## Shadow-mode: the legitimate carve-out

Log-only (shadow-mode) wiring is a legitimate rollout state ONLY while it is **declared and time-bounded**: the shadow phase is named in a plan or ADR, carries an expiry or flip obligation, and someone owns flipping it to enforce. A shadow-mode entry with no flip obligation is vaporware — "we'll enforce it later" with no mechanism is the canonical vaporware deferral. A drift check may whitelist declared shadow-mode entries, but each whitelist row must cite its declaration and expiry.

## The two verification-time paths this enables

- **`agents/functionality-verifier.md` — the config-control protocol (per-task, forward).** On `Verification: full` tasks that claim a control governs behavior, the verifier exercises the control at ≥2 values the spec claims produce DIFFERENT behavior and observes the GOVERNED surface, not the settings page. Dispatched by task-verifier (the sole checkbox-flipper) before any flip; the flip is mechanically backstopped by `plan-edit-validator.sh` (blocking PreToolUse — evidence block with a `Runtime verification:` line required) and work-integrity-gate via `stop-verdict-dispatcher.sh` (blocking Stop).
- **`agents/functionality-auditor.md` — the registry-vs-callsite sweep (standing surfaces).** The auditor enumerates every registry entry on an audited surface as an auditable element and def-use traces each to an enforce-mode call site, routing every decorative verdict through the Chesterton's-fence / indirect-consumption checklist first.

## The inverse shape: a consumed lever with no producer (HARNESS-GAP-57)

The registry-vs-callsite invariant above checks ONE direction: does a registry
entry have a consumer. It structurally assumes the other half — the
producer — is guaranteed, because a UI toggle's producer is the user
clicking it. That assumption fails for config levers with no UI: env vars,
CLI overrides, caller-set fields read deep in library code. Those can be
faithfully CONSUMED (the read site is real, the branch is real) while having
ZERO producers anywhere — so the branch never fires in production. Same
vaporware effect (a documented lever that does nothing), opposite missing
half: instead of "registry entry with no consumer," it's "consumer with no
producer."

**The originating case.** `NL_PROTECTED_ORCHESTRATOR`, documented in
`hooks/lib/admission-lib.sh` as the tag a "protected downstream orchestrator"
must set so its traffic isn't learned from during a chronic-storm period,
was discovered (accountable-estate T7, task-verifier pass 4, D-4,
2026-07-29) to have ZERO producers anywhere in the repo: all 888 live ledger
rows carry `protected:0`. Nothing in the registry-vs-callsite check would
have caught this — it isn't a registry+UI surface (functionality-auditor's
remit) and no `Verification: full` task ever claimed "this flag governs
behavior" (functionality-verifier's config-control-protocol trigger). A
task-verifier pass happened to read the comment narratively and catch it;
nothing made that catch repeatable.

**Mechanical check: `scripts/config-control-producer-scan.sh`.** Scans
`hooks/` + `scripts/` for consumed `NL_*`-prefixed levers and classifies each:
- **PRODUCED** — a real, standalone assignment exists somewhere in scope.
- **MARKED** — no producer, but a file that mentions the var also carries an
  honest-status marker (`HONEST STATUS`, `no producer sets`, `not-yet-wired`)
  within a small line-proximity window of a mention of the var — proximity
  anchors on ANY mention, not the syntactic read site, because real
  annotations often sit in a header/contract comment far from the call site
  (the real admission-lib.sh case: 566 lines from the functional read, 1
  line from the var's own name).
- **ALLOWLISTED** — no producer, no marker, but a justified entry in
  `config/config-control-allowlist.txt` documents a deliberate
  operator-shell / self-test-only override with no in-repo producer expected
  by design (7 such levers existed pre-change: `NL_CHECKOUT_OVERRIDE`,
  `NL_CROSS_REPO_TOUCH_OK`, `NL_EXCLUSIONS_VERIFY_TIMEOUT`,
  `NL_ISSUES_BACKLOG_PATH`, `NL_ISSUE_CLI_OVERRIDE`,
  `NL_SELFTEST_EXCLUSIONS_FILE`, `NL_SPAWN_PROCESS_COUNT_OVERRIDE`).
- **FLAGGED** — none of the above. The vaporware shape.

**Why this ships as a standing sweep, not a new blocking PreToolUse hook.**
D-2 in `docs/plans/archive/vaporware-config-controls.md` declined a new gate
for the registry-vs-callsite class (constitution Sec 10: a new gate needs a
golden scenario + FP rate + retirement condition; the existing blocking
chain — functionality-verifier inside runtime-verification, Stop, blocking —
was judged sufficient, with recurrence past that chain as the escalation
trigger). `NL_PROTECTED_ORCHESTRATOR` IS that recurrence, but in the
non-UI-lever shape D-2 didn't anticipate (no registry+UI surface exists to
audit). This ships the mechanical, self-testing, deterministic scan first —
runnable standalone or wired into CI/pre-commit later once its false-positive
rate is proven in practice (today: 0% against the live repo; `--self-test`
Scenario 7 asserts this directly and fails the suite if a future PR
introduces an unaccounted-for lever).

**Constitution Sec 10 fields.**
- *Golden scenario:* `NL_PROTECTED_ORCHESTRATOR` pre-annotation state
  (consumed, zero producer, zero marker, zero allowlist entry) →
  FLAGGED; post-annotation state (today's real file) → MARKED. Both
  directions are `--self-test` scenarios (`golden-pre-fix-shape` /
  `golden-post-fix-shape`).
- *Expected false-positive rate:* 0% against the current repo (`--self-test`
  Scenario 7 runs the real scan over the real trees and asserts zero
  FLAGGED). The 7 pre-existing operator-shell/self-test-only vars found
  during construction are allowlisted with per-entry justification, not
  blanket-suppressed. A future FP is a var that's legitimately
  externally-produced but lacks an allowlist entry — the fix is a one-line
  allowlist addition, not a code change.
- *Retirement condition:* if a FLAGGED verdict is proven wrong because a
  producer exists in a form this scan's regex can't see (indirect `${!name}`
  dereference, a non-`.sh` producer, a producer outside `hooks/`+`scripts/`),
  that recurrence is the evidence to either extend the producer regex
  (amendment) or retire the static scan in favor of the runtime audit-log
  approach HARNESS-GAP-39 proposes for the same "wired but never exercised"
  class (production-log evidence over static grep).

## Cross-references

- `docs/failure-modes.md` FM-038 — Vaporware: decorative config control (renders but does not change behavior).
- `doctrine/vaporware-prevention.md` — the compact this file backs.
- `agents/functionality-verifier.md` — Config-control protocol (the per-task checked path).
- `agents/functionality-auditor.md` — registry-vs-callsite sweep (the standing-surface audit path).
- `scripts/config-control-producer-scan.sh` — the inverse-shape mechanical scan (HARNESS-GAP-57).
- `config/config-control-allowlist.txt` — the documented external-producer carve-out.
- `docs/backlog.md` HARNESS-GAP-57 — the generalization this section records.
