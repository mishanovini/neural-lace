# Checkpoint — Model-Assignment Enforcement + Evidence-Before-Fix Gate (2026-07-14)

**Written pre-compaction (context 239%+).** Self-contained resume state. Session: main 0dea9856.

## ⚡⚡ STATUS (latest — supersedes the block below)
**Model-enforcement mechanism BUILT + on ORIGIN @ `f97bfb8` (NOT yet live — by design):**
- Task 1 policy `config/model-policy.json` ✅ (fb762b9). Task 2 all 24 agents pinned + build-agent
  check tightened ✅ (c5041eb). Task 3+doctrine: `hooks/model-pin-gate.sh` (PreToolUse Task|Agent,
  blocks silent-inherit, self-test **9/9**), wired in settings.json.template, manifest entry,
  `doctrine/model-selection.md` (honest residual), harness-architecture row ✅ (1d80926). Merged to
  master + pushed origin (f97bfb8). Verified on master: gate 9/9, `grep -L '^model:' agents/*.md`=0.
- The builder (afdcb7239ab5755d9) was STOPPED after it committed Task 2 (c5041eb); I built Task 3/5
  myself in its worktree (branch `worktree-agent-afdcb7239ab5755d9`) and merged. **LESSON: TaskStop
  discards a builder's UNCOMMITTED work — commit-early or salvage before stopping.**

**REMAINING (do next, fresh context):**
1. **Task 4 — harness-doctor check** that every `agents/*.md` has `^model:` and the value ∈
   model-policy.json model_ids (keeps agents pinned over time). Not built yet.
2. **harness-review the mechanism** (it's a BLOCKING gate — §10 requires review before it goes live).
   Dispatch harness-reviewer WITH AN EXPLICIT model (its live frontmatter isn't synced yet). Fix findings.
3. **THEN live-sync** (auto-install additively activates the gate in ~/.claude — do NOT do this before
   review; a false-positive blocking gate would break Task|Agent spawns estate-wide).
4. **Reconcile pt** — DIVERGED: origin=f97bfb8 (my 4 commits), pt=7511ce8 (13 OTHER-session commits:
   auditor timeout fix, NEW `architecture-reviewer` agent, artifact-evidence-bar doctrine). Merge
   pt/master in (§9 no force), RESOLVE conflicts, and **PIN the new `architecture-reviewer.md`** (+ any
   other new agent) with a `model:` per policy (design→fable) or the doctor check will red. Push both.
5. Close the plan (evidence log + close-plan). Then Directive 1 (evidence-before-fix gate, separate plan).

## ⚡ STATUS NOW (resume here — EARLIER, mostly superseded above)
- Foundation COMMITTED @ `fb762b9` (pushed to ORIGIN): `config/model-policy.json` (operator-set
  chains) + `docs/plans/model-enforcement-2026-07-14.md`. **pt/master DIVERGED** (another session
  pushed) — pt push rejected non-ff → RECONCILE on resume (fetch pt, merge --no-ff, push both; §9 no force).
- **Builder DISPATCHED (background, Sonnet-pinned, worktree)** agentId in the workflow/tasks — building
  Tasks 2-5: `model:` frontmatter on all 24 agents/*.md per policy chain[0]; tighten build-agent check;
  `hooks/model-pin-gate.sh` (+self-test, settings wiring, manifest); harness-doctor model-pin check;
  `doctrine/model-selection.md`. It commits IN ITS WORKTREE (no push). ON RESUME: read its completion
  report, cherry-pick its commits to master, run the self-tests MYSELF (never trust builder claims),
  harness-review the mechanism, fix findings, close the plan, push both remotes, live-sync.
- **This checkpoint doc is UNCOMMITTED** (docs/handoffs out of every plan's scope) — persists on disk
  across compaction; commit later if desired (system-managed? or add to a plan).
- **SHARED-INDEX HAZARD active:** another live session keeps staging its own lessons into the shared
  index (`credentials-are-available-inject-dont-surrender.md` = 6th lesson). Commit with a PRIOR
  `git restore --staged <foreign>` call, THEN commit mine in the NEXT call (gate checks index before
  the command runs). `-F COMMIT_EDITMSG`/scratch files get cleaned — prefer `git commit -m ... -m ...`.
- **STILL TODO after model-enforcement lands:**
  1. Directive 1 — the evidence-before-fix commit gate (SEPARATE plan `evidence-before-fix-gate-2026-07-14.md`;
     re-gather the failed Task-A evidence: diagnosis.md/claims.md class + commit-msg gate substrate +
     code-reviewer remit + failure-modes shape). Lesson §4 is the design.
  2. The 6th lesson (credentials-are-available-inject-dont-surrender.md) — review + secure (uncommitted, staged by another session).

## The two operator directives (faithful, in my words)

### Directive 1 — Evidence-before-fix, MORE ROBUST (recurring failure)
Operator: "Review [`docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`]. This was
supposed to be fixed in the past but still continues to come up. We need a more robust solution."
- The lesson's own §4 already prescribes the upgrade: the DIAGNOSTIC-FIRST protocol
  (`diagnosis.md`) EXISTS but is a **Pattern** (nothing gates it) → recurs under shipping momentum.
  Make it a **Mechanism**: a gate on `fix(...)`-class commits/PRs requiring a
  `## Root cause (evidenced)` section that cites the OBSERVED artifact (rows/logs/repro of the
  SPECIFIC incident) with each causal claim tagged **PROVEN** (observed) vs **INFERRED** (reasoned);
  FAIL a fix whose cause is entirely INFERRED, OR whose evidence is "unreachable" while the fix's
  grain is not fail-safe. Also: broaden diagnosis.md beyond prod CRASHES to ANY defect
  (data/behavior/state), and add a failure-modes entry "mechanism-sufficient fix."
- ROBUSTNESS ask ⇒ do NOT ship yet another Pattern. The honest constraint (from the lesson itself):
  a hook can require the SECTION EXISTS + tags present; it CANNOT judge PROVEN-vs-INFERRED truth —
  so the mechanism is (gate: section-present on fix-commits) + (reviewer remit: code-reviewer judges
  the tag honesty). Scope to `fix(...)`/incident-linked changes only (not refactors/features/typos).

### Directive 2 — Model assignment enforced at EVERY session/subagent initiation (recurring, costly)
Operator: "Every session (spawned by Claude) and sub-agent needs to ALWAYS be assigned an
appropriate model at initiation, without exception. This was supposed to be designed already but
clearly has failed. Multiple cases of a session spawning sub-agents that inherited **Fable** when
they should not have — wasted a lot of money. (1) Create an EXHAUSTIVE list of every category of
session and what model should be assigned to each. (2) Build ENFORCEMENT into session initiation
that enforces model selection and does NOT just inherit by default."
- Models (from env): Fable 5 `claude-fable-5`, Opus 4.8 `claude-opus-4-8`, Sonnet 5
  `claude-sonnet-5`, Haiku 4.5 `claude-haiku-4-5-20251001`.
- The bug surface = SILENT INHERITANCE/DEFAULT. Agent tool `model` is optional (omit → inherit
  parent); Workflow `agent()` inherits main-loop model by default; `.claude/agents/*.md` may omit
  `model:` frontmatter. Enforcement = force EXPLICIT selection at every spawn; never inherit silently.
- DISCIPLINE (apply the Directive-1 lesson to THIS task): the prior mechanism "failed" — do NOT
  infer why. The evidence workflow (below) is finding the actual failed mechanism + real incidents
  BEFORE I design the replacement.

## Evidence workflow — RUNNING (consume on resume)
`Workflow` run **`wf_5331f63a-8ff`** (background), 4 parallel read-only agents, all cite file:line +
PROVEN/INFERRED:
- `evidence-A:rootcause-gate` — diagnosis.md/claims.md current text + class; existing commit-msg/PR
  gates (pr-template-inline-gate, outcome-evidence-gate, wire-check-gate) as the buildable substrate
  for a fix-commit evidence gate; code-reviewer remit; failure-modes catalog shape.
- `evidence-B:spawn-paths` — EXHAUSTIVE map of how a model is decided on every spawn path; every
  `agents/*.md` with/without `model:` frontmatter; where silent inherit/default happens.
- `evidence-B:failed-mechanism` — the PRIOR model-enforcement design (ADR/decision/hook?) + real
  Fable-inheritance incident evidence + why it failed (evidence-only).
- `evidence-B:taxonomy` — every session/subagent CATEGORY + work-character (cheap-mechanical /
  deep-reasoning / adversarial-review / search) → raw material for the category→model table.
**Resume:** read the workflow result (or `journal.jsonl` in its transcript dir under
`…/subagents/workflows/wf_5331f63a-8ff/`) — do NOT re-run if cached.

## Plan of record (after evidence returns)
1. Synthesize evidence → write the **category→model table** (proposed; see below) + both mechanism
   designs. This is a NEW plan `docs/plans/model-enforcement-2026-07-14.md` (+ likely a second
   `evidence-before-fix-gate-2026-07-14.md`), each ACTIVE, acceptance-exempt, lifecycle-schema v2.
2. **Surface the category→model mapping to the operator** (§3 — the model VALUES are partly their
   call; the ENFORCEMENT mechanism I can build in parallel). Front-load it; decide-and-go on defaults.
3. Build model enforcement: (a) require `model:` frontmatter on EVERY `agents/*.md` (doctor check +
   a gate); (b) a PreToolUse gate on Task/Agent/Workflow spawns that BLOCKS a dispatch with no
   explicit model (or warns if block is too aggressive — verify enforceability); (c) doctrine +
   dispatch convention that every spawn names a model. Self-tests + harness-review.
4. Build the evidence-before-fix gate (Directive 1) per lesson §4. Self-test + harness-review.
5. Merge (both remotes) + live-sync + close plans.

## category→model mapping (OPERATOR-CORRECTED 2026-07-14 — Fable is PREMIUM, not cheap)
CORRECTION (operator, this turn): my earlier cost intuition was INVERTED. **Fable 5 is a
high-capability/preferred tier**; the money waste was CHEAP work (search/explore) inheriting Fable,
not premium work using it. Model policy supports a **PRIMARY + FALLBACK chain** ("fable, fallback
opus if fable unavailable"). Operator-set so far:
- **Adversarial reviewers/verifiers → Fable OR Opus** (premium; both acceptable). [operator-confirmed]
- **Design/planning → Fable primary, Opus fallback** (if Fable unavailable). [operator-confirmed]
- Interactive main/orchestrator → operator's launch choice; explicit, never auto-downgraded.
- Explore/explorer/research + cheap mechanical stages → **Haiku 4.5 → Sonnet 5 fallback**. [operator-confirmed]
- plan-phase-builder (code build) → **Sonnet 5**. [operator-confirmed]
- spawn_task / cron / cloud → explicit per-task, never inherit (no gate can reach these — convention+lint).
The RULE regardless of values: **explicit assignment always; silent inherit = BLOCKED. Fable must
never be reached by DEFAULT/INHERIT — only by explicit pin.** Mechanism must support fallback chains.

### FINAL per-agent assignment (from the operator table)
- **Fable→Opus (reviewers/verifiers):** claim-reviewer, code-reviewer, comprehension-reviewer,
  harness-reviewer, plan-evidence-reviewer, prd-validity-reviewer, security-reviewer, task-verifier,
  end-user-advocate, functionality-verifier, functionality-auditor, harness-evaluator,
  enforcement-gap-analyzer, documentation-auditor, audience-content-reviewer, ux-end-user-tester,
  domain-expert-tester.
- **Fable→Opus (design/planning):** systems-designer, ux-designer, ux-ia-auditor. (Plan built-in agent
  too, but it has no agents/*.md file — covered by the spawn gate / policy default.)
- **Haiku→Sonnet (read-only/cheap):** explorer (currently haiku — upgrade to chain), research.
  (Explore built-in agent → policy default.)
- **Sonnet 5 (build):** plan-phase-builder, test-writer.
- Note: a few classifications are judgment calls (test-writer=build; documentation-auditor=review) —
  reasonable, refine if operator objects. The POLICY FILE is the source of truth; frontmatter mirrors it.

### Mechanism design (HYBRID — from the enforceability evidence)
1. **Source of truth:** `adapters/claude-code/config/model-policy.json` — agent-name/category → ordered
   model chain (e.g. `["fable","opus"]`). One place to edit tiers.
2. **Mandatory `model:` frontmatter on ALL agents/*.md** (mirrors the policy) + tighten
   `work-shapes/build-agent.md` check from `^(model|tools):` to require `^model:`. Fixes every
   agentType spawn immediately.
3. **PreToolUse gate** on Task|Agent (+ workstreams-emit surface): BLOCK a spawn whose resolved model
   is empty/absent AND whose agentType has no policy entry — i.e. force an explicit model or a policy
   default; never let it fall through to inherit. (Can read `tool_input.model` + `subagent_type`.)
4. **harness-doctor check:** FAIL if any agents/*.md lacks `model:` or names a model not in policy.
5. **Honest residual (no gate reaches these):** Workflow-inline `agent()`, spawn_task, cron/remote —
   covered by doctrine convention + a lint, NOT a hard gate. State this plainly (no overclaim).
Plan file: `docs/plans/model-enforcement-2026-07-14.md`.

## Constraints/gotchas learned this session (avoid re-discovery)
- `harness-doctor --quick` and `session-start-auto-install.sh` are SLOW (>2 min, spawn tax) — run in
  background / block-wait; auto-install skips under its own single-flight (use `SSF_DISABLE=1` to force).
- settings.json HAS additive repo→live sync (merge_settings, SessionStart); template canonical;
  non-template `adapters/claude-code/settings.json` is a gitignored DEAD file. Removals/rewires need
  a manual live reconcile (don't rely on additive merge for those).
- `scope-enforcement-gate` blocks any commit whose staged files aren't in an ACTIVE plan's
  Files-to-Modify (2 foreign ACTIVE plans exist: ask-p1, flat-skills). docs/backlog.md is EXEMPT
  (system-managed) — committed fine. So: create the plan FIRST, list files in it, then commit.
- Commit messages: `.git/COMMIT_EDITMSG` gets clobbered — write the message to a scratch file and
  `git commit -F <scratchfile>`, not to COMMIT_EDITMSG.
- The downstream product's codename is denylisted (harness-hygiene-scan) — never let it into a
  committed harness doc; genericize.
- close-plan: mechanical tasks need sibling evidence OR a `## Evidence Log` with `Task N` + `commit: <sha>`;
  Closure Contract "Commands that run:" needs INLINE content (≥5 chars same line) or it FAILs.
- session-wrap "docs/backlog.md stale" Stop signal recurs — cleared it by committing a real backlog
  update (GUARD-REFORMULATE-01 UNBLOCKED note @ 974aa22).

## EVIDENCE GATHERED — workflow `wf_5331f63a-8ff` (3/4 agents; full output in the task .output file + journal.jsonl)

**THE "already-designed but failed" mechanism = `docs/harness-improvements/model-pin-mandatory-gate.md`
— a PROPOSAL doc, Status un-landed. It was designed on paper and NEVER built.** That is the evidence
of the failure (not inference). Build FROM it (it has a golden scenario + a proposed policy map).

Task-B PROVEN facts (all cited in the .output file):
- Agent tool `model` omitted ⇒ INHERITS main-loop model (NOT "let NL choose"). On a Fable session
  every un-pinned Agent/Workflow spawn runs on Fable. 2026-07-11 incident: 6 un-pinned spawns
  (~1.7M tokens; workflows ~588k+381k+120k+310k) all ran Fable → drained monthly budget.
  (`model-pin-mandatory-gate.md:13-25`).
- **22 of 24 `agents/*.md` OMIT `model:` frontmatter** → inherit. Only pinned: `explorer.md`
  (haiku), `audience-content-reviewer.md` (sonnet). Un-pinned includes `plan-phase-builder` + ALL
  adversarial reviewers/verifiers (code-reviewer, harness-reviewer, security-reviewer, task-verifier,
  plan-evidence-reviewer, comprehension-reviewer, prd-validity-reviewer, end-user-advocate, etc.).
- `work-shapes/build-agent.md:11` authoring check greps `^(model|tools): ` — EITHER satisfies, so
  `model:` is NOT forced (an agent with only `tools:` still inherits). This is a gap to tighten.
- `spawn_task` tool schema has NO `model` field (pure inherit; no control point at all).
- cron / `create_scheduled_task` / RemoteTrigger — NO model field (inherit account/routine default).
- Workflow `agent()` inherits main-loop; **a PreToolUse hook CANNOT statically inspect model inside
  the workflow script string** (`model-pin-mandatory-gate.md:44-51`) → the only fix for that path is
  a layer-1 runtime policy default (does not exist) + optional lint.
- `workstreams-ui/state/reconciler.js:134` + `reconciler-config.js:37` — `spawnModel: null` default ⇒
  `--model` omitted ⇒ inherit (dormant; `autoSpawn:false`).
- ENFORCEMENT GAP: `teammate-spawn-validator.sh` checks isolation, NOT `tool_input.model`. The
  proposed `model_pin_mandatory` flag + `default_model:` registry field + gate are ALL un-landed
  (exist ONLY in the proposal doc).

Enforceability read (drives the design): a PreToolUse gate CAN block an Agent-tool spawn whose
`tool_input.model` is empty (with an agent-type→default-model policy map to auto-fill or to name the
required model). It CANNOT reach Workflow `agent()` (in-script) or spawn_task/cron (no field) — those
need (a) `agents/*.md` mandatory `model:` frontmatter (doctor check + tighten build-agent check) so
`agentType`-based spawns carry a model, and (b) a documented policy default per category. So the
mechanism is a HYBRID: gate (Agent tool) + mandatory-frontmatter doctor check + policy-map doctrine +
honest residual on the paths no gate can reach (Workflow-inline / spawn_task / cron → convention + lint).

Task-A: the `evidence-A:rootcause-gate` agent FAILED (schema retry cap) — RE-GATHER directly on resume:
read `diagnosis.md` + `claims.md` (confirm Pattern-class), inventory commit-msg/PR gates
(`pr-template-inline-gate.sh`, `outcome-evidence-gate.sh`, `wire-check-gate.sh`) as the substrate for
a `fix(...)`-commit "## Root cause (evidenced)" gate, and the `code-reviewer.md` remit + failure-modes
catalog shape. (Or re-run the workflow with `resumeFromRunId: wf_5331f63a-8ff` — cached agents replay,
only the failed one re-runs; consider relaxing its schema.)

## Already DONE earlier this thread (do not redo)
- lessons-learned-fixes-2026-07-13 (pre-filters, find-scan-warn, single-flight, doc-accuracy) — CLOSED.
- needs-from-you-two-bucket-signoff-2026-07-13 (constitution §2 Blocking/When-you-can) — CLOSED, live.
- agent-heartbeat-watchdog-2026-07-14 (agent-heartbeat.sh + watchdog) — CLOSED, live @ 1d28e48.
- The agent-efficiency lesson (the anti-malware downstream-product session's deliverable) — already committed
  + all 6 recs shipped/deferred. The operator confirmed seeing it; nothing more owed there.
