# Plan: Principles Doctrine Authoring — A Canonical, Scope-Hierarchical Principles Index
Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; the "user" is the maintainer and each shipped component's reviewer-check / `--self-test` PASS is its acceptance artifact. No product UI surface exists. The `## Acceptance Scenarios` below are populated as reviewer-check scenarios (dogfooding the plan-lifecycle-redesign Closure Contract), not browser scenarios.
tier: 3
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-08-15

<!-- `owner:` / `target-completion-date:` model the ADR-036 schema (Pattern 1),
     dogfooded here; today's plan-reviewer.sh does not yet check them.
     `## Closure Contract` dogfoods the plan-lifecycle-redesign (Pattern 1) Closure
     Contract section — this plan is one of the first deliberate dogfoods of it. -->

## Goal

Design the harness's **canonical principles doctrine**: a single document
(canonical at `adapters/claude-code/rules/principles.md`, live mirror
`~/.claude/rules/principles.md` — exact filename a §Decision-for-Misha) that
NAMES the load-bearing principles the harness encodes, organized
**hierarchically BY SCOPE** — universal / mode-specific / tactical — and
explicitly NOT severity-tiered. Build Doctrine already carries five orthogonal
work-classification axes (`build-doctrine/doctrine/`); this doctrine adds a
sixth-axis NOTHING — scope is the ONE organizing dimension, and severity-tiering
is rejected by name (converged with Misha before this session).

Each principle carries SIX fields: (1) name, (2) full-sentence definition, (3)
observable "honored" test (how a reviewer can tell, from artifacts, whether the
principle was honored), (4) a do/don't example pair, (5) a scope tag (universal /
mode-specific / tactical), (6) neighbor relationships (which sibling principles it
composes-with, tensions-with, or is-a-special-case-of). The incentive-design
family of principles is CROSS-REFERENCED to `docs/agent-incentive-map.md` (88 KB,
v1, Munger-framed, owned by Misha) — NOT re-derived here.

**This plan is design-only.** Its deliverable is THIS design + the seed-set
methodology + the reviewer-check acceptance + the roadmap (R-tasks). The
principles doc itself is authored by the R-tasks in subsequent sessions, each
small enough to ship without prompt-too-long risk (FM-030 discipline — see
Pattern 4, `docs/plans/session-resilience-redesign.md`).

## Scope

- IN: Design of `principles.md` — its three-scope hierarchy, the six-field
  per-principle schema, the seed-extraction methodology (which existing rules +
  CLAUDE.md sections + `agent-incentive-map.md` entries each principle is
  distilled from), the reviewer-agent acceptance check (a `principles-reviewer`
  pass OR an extension to an existing reviewer that confirms each principle has
  all six fields + a resolvable scope tag + at least one neighbor link), the
  index/registry entry, the bootstrap-test gate that closes the plan, and the
  cross-reference wiring back-pointer convention (existing rules cite the
  principle they operationalize).
- IN: The seed SET sizing decision (how many principles in v1 — recommended
  10–20, not 100; the doc is an INDEX of load-bearing principles, not an
  exhaustive enumeration of every sentence in every rule).
- IN: The 10-section Systems Engineering Analysis, the self-test/reviewer-check
  design, and the ordered implementation roadmap (R-tasks).
- IN: ADR 043 (RESERVED this session; authored at R1) recording the
  scope-hierarchy-not-severity-tier decision + the six-field schema lock.
- OUT: Any implementation — writing the actual `principles.md` content, editing
  existing rules to add back-pointers, building a `principles-reviewer` agent.
  The only files THIS session writes are this plan (and, per the roadmap, the
  integrated `harness-hygiene-roadmap.md` that references it).
- OUT: Severity-tiering of principles (rejected by name — converged with Misha).
- OUT: A sixth work-classification axis (Build Doctrine's five are sufficient;
  scope is the sole organizing dimension here).
- OUT: Re-deriving the incentive map — `docs/agent-incentive-map.md` is the
  canonical incentive-design artifact; principles.md CROSS-REFERENCES it.
- OUT: Doctrine LOCATION policy (where doctrine lives by type, the memory-load
  rule) — that is the SIBLING plan `docs/plans/doctrine-scoping-rules-authoring.md`.
  These two plans are deliberately split: this one is WHAT the principles are +
  how they're structured; the sibling is WHERE doctrine of each type lives.

## Tasks

The tasks below ARE the implementation roadmap. Each is a self-contained future
session. THIS design session checks off NONE of them. Ordered by dependency;
each ships its slice with a reviewer-check / `--self-test`
(harness-internal → `Verification: mechanical`).

- [ ] R1. Author ADR 043 + the `principles.md` skeleton (structure-only, zero principle bodies). Lock the three-scope hierarchy headings (`## Universal principles` / `## Mode-specific principles` / `## Tactical patterns`), the six-field per-principle template, and the index/registry row. Resolve the §D1 filename + §D2 seed-set-size decisions at authoring time. ADR 043 records scope-hierarchy-not-severity + the six-field schema lock. Verification: mechanical
- [ ] R2. Build the seed-extraction methodology + extract the UNIVERSAL-scope principles (the smallest, highest-leverage set — e.g. functionality-over-components, no-false-promises, diagnose-before-fixing, gate-respect, evidence-over-narration). Each carries the six-field schema; the incentive-family entries cross-reference `agent-incentive-map.md` by section. Verification: mechanical
- [ ] R3. Extract the MODE-SPECIFIC principles (keyed to the five session modes in `automation-modes.md` — interactive / parallel-local / cloud-remote / scheduled / agent-team — and to Mode:code vs Mode:design). Each names which mode(s) it binds. Verification: mechanical
- [ ] R4. Extract the TACTICAL patterns (narrow, situational — e.g. sweep-task decomposition, reusable-component-coverage, class-sweep-on-feedback). Each links to the universal principle it specializes. Verification: mechanical
- [ ] R5. Build the acceptance reviewer-check: a `principles-reviewer` agent (or an extension to an existing reviewer) that, given `principles.md`, confirms each principle carries the six fields populated (≥ 30 non-ws chars where prose), a scope tag in the legal set, and ≥ 1 resolvable neighbor link; and confirms the index/registry row exists. This is the acceptance artifact generator. Verification: mechanical
- [ ] R6. Cross-reference sweep: wire back-pointers from existing rules to the principle each operationalizes (the rule cites `principles.md#<principle-slug>`), and forward-pointers from `principles.md` neighbor fields. Decompose per-rule at authoring time (sweep-task discipline — enumerate the rule-file list before starting). Verification: mechanical
- [ ] R7. Bootstrap test + finalization. A test that, on a fresh harness install, asserts `principles.md` exists, the reviewer-check (R5) passes, and a sample of existing-rule back-pointers (R6) resolve to live principle slugs. Register `principles.md` in `docs/harness-architecture.md`. Sync live mirror. Verification: mechanical

## Files to Modify/Create

(Future-session targets — each roadmap session has a frozen file set. THIS
session writes only the documentation files marked ✎.)

- `docs/plans/principles-doctrine-authoring.md` — ✎ this design plan (this session)
- `docs/decisions/043-principles-doctrine-scope-hierarchy.md` — R1: ADR (number RESERVED this session; authored at R1)
- `docs/DECISIONS.md` — R1: index row for ADR 043
- `adapters/claude-code/rules/principles.md` — R1–R4: NEW canonical principles doctrine
- `adapters/claude-code/agents/principles-reviewer.md` — R5: NEW reviewer-check agent (or, if R5 chooses extension, the extended existing agent file)
- `adapters/claude-code/rules/*.md` — R6: back-pointer citations added to existing rules (sweep — exact file list enumerated at R6 start)
- `adapters/claude-code/rules/principles-bootstrap-test.sh` OR an addition to an existing self-test harness — R7: bootstrap test
- `docs/harness-architecture.md` — R1/R7: inventory entry for `principles.md` per `harness-maintenance.md`
- `~/.claude/rules/principles.md` (+ mirrored agent/test) — R1–R7: live-mirror sync per two-layer-config discipline

## In-flight scope updates

- 2026-05-26: `docs/harness-hygiene-roadmap.md` — the integrated Hygiene-track roadmap (this plan + its sibling doctrine-scoping plan + the nine implementation-piece shells) was authored in the SAME scoping session as this plan and is its co-deliverable; claimed here so the scoping session's three docs commit together.

## Assumptions

- The harness's load-bearing principles are ALREADY encoded implicitly across
  ~30 rule files + CLAUDE.md + `agent-incentive-map.md`; this plan distills and
  indexes them, it does not invent new principles (confirmed by the rules corpus
  visible in this session's context).
- `docs/agent-incentive-map.md` exists (87,957 bytes, verified this session) and
  is the canonical incentive-design artifact to cross-reference, not duplicate.
- The five session modes are the stable set in `automation-modes.md` (confirmed:
  interactive / parallel-local / cloud-remote / scheduled / agent-team).
- A reviewer agent can mechanically check field-presence + scope-tag-legality +
  neighbor-link-resolution against a Markdown doc (confirmed — the seven existing
  adversarial-review agents already parse structured Markdown sections).
- "Hierarchical by scope, not severity-tiered" is a settled decision (converged
  with Misha before this session) and needs only RECORDING in ADR 043, not
  re-litigating.
- The exact canonical filename (`principles.md` vs an alternative) and the v1
  seed-set size are NOT settled — §D1/§D2 resolve them at R1 with Misha input.

## Edge Cases

- **A principle that genuinely spans two scopes** (universal in spirit but with a
  mode-specific tightening) → list under its BROADEST scope with a neighbor link
  to the mode-specific specialization; do not duplicate the body.
- **An existing rule encodes two principles** → R6 cites both; the rule→principle
  mapping is many-to-many, not one-to-one.
- **A principle has no clean do/don't example** → the reviewer-check (R5) FAILs
  the principle; the fix is to find a real example from the originating incident,
  not to ship an empty field (no-placeholder discipline).
- **The incentive-family overlaps `agent-incentive-map.md` heavily** → principles.md
  carries only the NAME + one-line definition + a pointer to the map section;
  the full treatment stays in the map (single-source-of-truth).
- **Seed set grows toward exhaustive enumeration** → cap at the load-bearing set
  (v1 rec 10–20); a principle that only ever applies in one narrow rule is a
  TACTICAL pattern at most, or stays in its rule and is NOT promoted.
- **A back-pointer (R6) points at a renamed/removed principle slug** → the
  bootstrap test (R7) catches the dangling pointer; this is the same dangling-
  citation class the hygiene cleanup pass (roadmap piece #8) detects generally.
- **Scope tag set needs a fourth value later** → the schema reserves scope as a
  closed enum in v1 (universal/mode-specific/tactical); widening it is an ADR-043
  amendment, not an ad-hoc edit.

## Acceptance Scenarios

(This plan is `acceptance-exempt: true` — harness-development. Closure target is
the reviewer-check / bootstrap-test PASS recorded in `## Closure Contract`. The
scenarios below are the maintainer-facing reviewer-checks, populated to dogfood
the Pattern-1 Closure Contract discipline — NOT browser scenarios.)

### all-principles-six-field-complete — every principle row is fully populated

**Slug:** `all-principles-six-field-complete`

**User flow:**
1. Maintainer runs the R5 `principles-reviewer` check against `principles.md`.
2. The reviewer iterates every principle under the three scope headings.
3. For each, it asserts all six fields present + substantive + scope-tag legal + ≥1 neighbor link.

**Success criteria (prose):** the reviewer reports PASS with zero principles
flagged for a missing/empty/placeholder field, an illegal scope tag, or a
dangling neighbor link. A maintainer reading the report can trust every principle
in the doc is complete.

**Artifacts to capture:** reviewer-check stdout (PASS + per-scope principle
counts); no console errors; the PASS recorded as the closure artifact.

### index-and-backpointers-resolve — the doc is discoverable and wired in

**Slug:** `index-and-backpointers-resolve`

**User flow:**
1. Maintainer runs the R7 bootstrap test on a fresh-mirror state.
2. The test asserts `principles.md` exists + is registered in `docs/harness-architecture.md`.
3. The test samples N existing-rule back-pointers and resolves each to a live principle slug.

**Success criteria (prose):** the bootstrap test exits 0; `principles.md` is
present and indexed; every sampled back-pointer resolves; no dangling citation.

**Artifacts to capture:** bootstrap-test stdout (exit 0, "N passed, 0 failed");
the resolved-pointer list.

## Closure Contract

- **Commands that run (per component, at R-session close):** the R5
  `principles-reviewer` check against `principles.md`; the R7 bootstrap test
  (`bash adapters/claude-code/rules/principles-bootstrap-test.sh --self-test` or
  the chosen harness).
- **Expected outputs:** reviewer-check reports PASS (zero flagged principles);
  bootstrap test exits 0 with "N passed, 0 failed".
- **On-disk artifact location:** structured evidence at
  `docs/plans/principles-doctrine-authoring-evidence/<R-task-id>.evidence.json`
  (verdict PASS) per the Tranche B mechanical-evidence substrate.
- **Done when:** all of R1–R7 are task-verifier PASS AND the R5 reviewer-check
  reports zero flagged principles AND the R7 bootstrap test exits 0. (THIS plan,
  design-only, is "done for the design phase" when this plan + the roadmap land
  and systems-designer PASSes; it stays ACTIVE through implementation.)

## Testing Strategy

Per-component reviewer-check / `--self-test` is the verification idiom.

**R1 skeleton:** the three scope headings exist; the six-field template renders;
the index row is present; ADR 043 authored + indexed.

**R2–R4 extraction:** each scope section is non-empty; every principle has six
fields; the reviewer-check (once R5 lands) reports zero flagged principles for
that scope; incentive-family entries each carry a resolvable
`agent-incentive-map.md` section pointer.

**R5 reviewer-check:** a principle missing a field → FLAGGED; a principle with an
illegal scope tag → FLAGGED; a dangling neighbor link → FLAGGED; a fully-complete
principle → PASS; the index-row-absent case → FLAGGED.

**R6 cross-reference sweep:** every rule in the enumerated list cites at least the
principle it most-directly operationalizes; no back-pointer is dangling
(cross-checked by R7).

**R7 bootstrap:** fresh-mirror → `principles.md` present + indexed; reviewer-check
PASS; sampled back-pointers resolve; dangling pointer (negative fixture) → test
fails loudly.

## Walking Skeleton

The thinnest end-to-end slice that proves the architecture: author the
`principles.md` skeleton with the three scope headings and ONE fully-populated
universal principle (six fields, one neighbor link, one `agent-incentive-map.md`
cross-reference) + the index row; build the R5 reviewer-check; run it against the
one-principle doc → PASS; add ONE back-pointer from the originating rule; run the
R7 bootstrap test → resolves. This single slice exercises every layer (structure,
the six-field schema, the reviewer-check, the cross-reference wiring, the
bootstrap gate) with minimal content and is the R7 bootstrap test's core path.

## Decisions Log

### Decision: Scope-hierarchy, NOT severity-tiering (recorded, not re-litigated)
- **Tier:** 2
- **Status:** proceeded with recommendation (converged with Misha pre-session)
- **Chosen:** Organize principles by SCOPE (universal / mode-specific / tactical). One organizing dimension.
- **Alternatives:** Severity-tiering (P0/P1/P2-style). Rejected — Build Doctrine already has five orthogonal work-classification axes; severity would be a redundant sixth axis and would imply some principles are "optional," which is wrong for universal principles.
- **Reasoning:** Scope tells the reader WHEN a principle binds, which is the actionable question; severity does not. ADR 043 records this.
- **To reverse:** Re-introduce a severity field; low cost (docs only) but contradicts the converged decision.

### Decision: Split principles-WHAT (this plan) from doctrine-location-WHERE (sibling plan)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** This plan designs the principles doc and its structure; the sibling `doctrine-scoping-rules-authoring.md` designs WHERE doctrine of each type lives + the memory-load rule.
- **Reasoning:** Two distinct concerns; bundling would mega-session. They cross-reference but ship independently.

### Decision: Cross-reference `agent-incentive-map.md`, do not re-derive
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** The incentive-design principle family carries name + one-line def + a pointer to the map section; the full treatment stays in the 88 KB map.
- **Reasoning:** Single-source-of-truth; the map is v1, owned by Misha, Munger-framed. Duplication would drift.

## Definition of Done

- [ ] (design phase) This plan authored + passes plan-reviewer; the three-scope hierarchy + six-field schema are the explicit spine; ADR 043 number reserved.
- [ ] (design phase) systems-designer returns PASS on the 10-section analysis (gate before implementation).
- [ ] (design phase) Misha reviews + authorizes the roadmap + resolves §D1 (filename) / §D2 (seed-set size).
- [ ] (implementation) R1–R7 each task-verifier PASS with reviewer-check / `--self-test` green.
- [ ] (implementation) R5 reviewer-check reports zero flagged principles; R7 bootstrap test exits 0.
- [ ] SCRATCHPAD updated.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

Success, measured post-implementation: (1) a fresh maintainer (or a fresh
session) can open ONE document and see every load-bearing principle the harness
encodes, each with a definition, an observable honored-test, and an example —
without reading 30 rule files; (2) a new rule authored after this lands cites the
principle it operationalizes (R6 back-pointer convention), so principle drift
across rules becomes detectable (a rule that operationalizes no named principle is
a smell); (3) the reviewer-check (R5) can mechanically confirm the doc is
complete, so the doc cannot silently rot into half-populated rows; (4) the
incentive-design work (`agent-incentive-map.md`) is connected to the rules via
the principles index, instead of being an orphaned 88 KB artifact. The honest
non-goal: this is an INDEX of principles, not an enforcement mechanism — it makes
the principle set visible and checkable, it does not by itself gate behavior (the
rules + hooks do that).

### 2. End-to-end trace with a concrete example

Take the principle "functionality-over-components" (the most-important rule per
`planning.md`). R2 extracts it as a UNIVERSAL principle: name =
`functionality-over-components`; definition = the full sentence from planning.md
("a task is done when a user can perform the action … not when the code
compiles"); honored-test = "the task's evidence demonstrates a user-observable
outcome, not only a passing unit test (a reviewer can confirm from the evidence
block which one)"; do/don't = DO "drive the UI flow end-to-end and capture the
rendered outcome" / DON'T "mark done because typecheck passed"; scope = universal;
neighbors = composes-with `evidence-over-narration`, specialized-by the tactical
`sweep-task-decomposition`, motivated-by `agent-incentive-map.md#completion-signal`.
R5's reviewer-check reads this row, confirms six fields + legal scope + three
resolvable neighbor links → PASS. R6 adds a back-pointer in `planning.md`
("operationalizes `principles.md#functionality-over-components`"). R7's bootstrap
test samples that back-pointer and resolves it to the live slug → exit 0. A fresh
session reading `principles.md` sees the principle and its example without opening
`planning.md` at all.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| `principles.md` (the doc) | maintainer / fresh session | Single doc; three scope headings; each principle a `### <slug>` block with the six labeled fields. The slug is the stable cross-reference key. |
| six-field schema | `principles-reviewer` (R5) | Each `### <slug>` block exposes Name, Definition, Honored-test, Do/Don't, Scope, Neighbors — parseable by labeled lines, mirroring the comprehension-gate four-field parse. |
| `agent-incentive-map.md` | incentive-family principles | The principle cites a map section anchor; the map is the full treatment; the principle is the index entry. |
| existing rules | `principles.md` (R6 back-pointer) | A rule cites `principles.md#<slug>` for the principle it operationalizes; the bootstrap test (R7) resolves the citation. |
| `principles-reviewer` (R5) | closure | Emits PASS (zero flagged) or a per-principle flag list (which field/scope/neighbor failed). PASS is the acceptance artifact. |
| bootstrap test (R7) | fresh-install gate | Asserts presence + index + sampled-back-pointer resolution; exit 0/non-0. |

### 4. Environment & execution context

All components are harness documentation + one reviewer agent + one bootstrap
test, living under `adapters/claude-code/` (canonical) mirrored to `~/.claude/`.
The reviewer-check runs as a Task-dispatched agent (like the seven existing
adversarial reviewers) or as a bash self-test (R5 chooses). The bootstrap test is
a bash script with `--self-test`, `jq` available (degraded no-jq fallback per
convention). No external services, no auth boundaries, no network. Two-layer
config discipline: every edit to `adapters/claude-code/` is mirrored to
`~/.claude/` and verified byte-identical.

### 5. Authentication & authorization map

No external auth boundaries. No new BLOCK authority is introduced (the principles
doc is an index, not a gate; the reviewer-check is advisory at the doc level and
gating only at plan-task close via the Closure Contract). No tokens, quotas, or
rate limits. The only authorization-adjacent surface is the R6 sweep editing many
rule files — covered by the standard scope-enforcement-gate against this plan's
frozen file set.

### 6. Observability plan (built before the feature)

- `principles-reviewer` (R5) on each run: `[principles-reviewer] <N> principles
  checked across 3 scopes; <M> flagged (<reasons>)` → PASS line on zero flagged.
- bootstrap test (R7): `[principles-bootstrap] doc present: yes; indexed: yes;
  back-pointers sampled <K>, resolved <K>` → exit line.
- Reconstruct-from-output test: from the reviewer-check + bootstrap output alone,
  a maintainer can determine which principles are incomplete, whether the doc is
  indexed, and whether any back-pointer dangles — without opening the doc.

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / policy | Escalation |
|---|---|---|---|---|
| R1 skeleton | Scope headings ambiguous | extractors disagree where a principle goes | ADR 043 defines the three scopes precisely (the honored-test for scope) | amend ADR 043 |
| R2–R4 extract | A principle ships with an empty field | reviewer-check FLAGS it | fill from the originating incident; no placeholder | block close if flagged |
| R2 incentive family | Duplicates `agent-incentive-map.md` content | drift between doc and map | enforce pointer-only (def + anchor), full treatment in map | reviewer-check could later flag over-long incentive bodies |
| R5 reviewer | False PASS on an empty field | incomplete doc looks complete | reviewer-check self-test includes a missing-field negative fixture | tighten the parse |
| R6 sweep | Misses a rule that encodes a principle | a rule with no back-pointer | sweep enumerates ALL rule files first (sweep-task discipline) | re-run sweep; the "rule with no named principle" smell surfaces it |
| R6 sweep | Back-pointer to a renamed slug | dangling citation | bootstrap test (R7) catches it | same class as hygiene piece #8 |
| R7 bootstrap | Passes despite a dangling pointer | false confidence | bootstrap test includes a dangling-pointer negative fixture | block ship if negative fixture green |

### 8. Idempotency & restart semantics

- `principles.md` authoring is plain doc editing — idempotent, restart-safe;
  re-running an extractor R-task overwrites the same `### <slug>` block.
- `principles-reviewer` (R5): pure read + report, no state mutation, restart-safe.
- R6 back-pointer sweep: re-running re-adds the same citation (idempotent if the
  edit is "ensure the citation line exists" rather than "append").
- bootstrap test (R7): pure read + assert, idempotent.
- The slug is the stable key across restarts; renaming a slug is a deliberate
  schema event that triggers R6 + R7 re-resolution.

### 9. Load / capacity model

No runtime load surface — these are docs + a reviewer agent + a bootstrap test
run on demand. The reviewer-check iterates ≤ ~20 principles (v1 cap), each a
small Markdown block — sub-second. The R6 sweep touches ≤ ~30 rule files once.
No saturation concern. The only capacity question is the seed-set SIZE (§D2): too
large and the doc becomes an exhaustive enumeration nobody reads; capped at the
load-bearing set (10–20) it stays an index. That cap is the deliberate capacity
bound, by design.

### 10. Decision records & runbook

**Open decisions to resolve before / at the relevant R-session (= ADR 043
§D1–§D2):**

- **§D1 (R1): canonical filename.** `principles.md` vs an alternative (e.g.
  `harness-principles.md`). *Recommendation:* `principles.md` under
  `adapters/claude-code/rules/` (short, discoverable, mirrors the rules-dir
  convention). **Needs Misha confirm** (naming — `~/.claude/CLAUDE.md` "never name
  without consulting" applies even to doc filenames at the margin).
- **§D2 (R1): v1 seed-set size.** *Recommendation:* 10–20 load-bearing
  principles, not exhaustive. **Needs Misha preference** (how much of an index vs
  encyclopedia he wants v1 to be).

**Runbook (post-implementation):**
- *Symptom: a new rule operationalizes no named principle.* Either the rule is
  tactical-only (fine, note it) or a principle is missing from `principles.md` —
  extract it and add the back-pointer.
- *Symptom: reviewer-check flags a principle.* Read the flag (which field/scope/
  neighbor); fill the field from the originating incident; re-run.
- *Symptom: bootstrap test reports a dangling back-pointer.* A principle slug was
  renamed/removed; update the citing rule OR restore the slug; this is the same
  class the hygiene obsolescence detector (roadmap piece #4) generalizes.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in §1–§10 is cited in a
`## Tasks` R-entry AND a `## Files to Modify/Create` line (R1↔skeleton+ADR,
R2/R3/R4↔per-scope extraction, R5↔reviewer-check, R6↔back-pointer sweep,
R7↔bootstrap+index); 0 stranded.
S2 (Existing-Code-Claim Verification): swept — claims about
`agent-incentive-map.md` (87,957 bytes, verified this session), the five session
modes in `automation-modes.md`, the seven adversarial-review agents parsing
structured Markdown, and the comprehension-gate four-field parse pattern were each
verified against files/context visible this session; all confirmed accurate.
S3 (Cross-Section Consistency): swept — "index not enforcement mechanism"
consistent across Goal/§1/§5; "scope-hierarchy not severity" consistent across
Scope-OUT/Decisions Log/§10/ADR-043-reservation; "cross-reference incentive map,
don't duplicate" consistent across Scope/Edge Cases/§2/§3/Decisions Log; 0
contradictions.
S4 (Numeric-Parameter Sweep): swept for params [v1 seed-set size (rec 10–20),
six fields per principle, three scope tags, R1–R7 roadmap, ADR 043]; all values
consistent across §2/§9/Testing Strategy/Tasks; the seed-set size is flagged
build-calibrated (§D2) where the exact count is a Misha preference.
S5 (Scope-vs-Analysis Check): swept — every "Author/Extract/Build/Wire" verb in
§1–§10 targets a file in `## Files to Modify/Create`; no prescription targets a
Scope-OUT concern (severity-tiering prescribed NOWHERE; the incentive map is
cross-referenced not edited; doctrine-LOCATION is the sibling plan, prescribed
nowhere here; no code shipped this session per Scope OUT).
