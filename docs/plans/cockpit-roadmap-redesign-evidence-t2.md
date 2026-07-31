# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 2

Task: 2. Work-item layer (Verification: full, rung 3)
Builder: plan-phase-builder (Fable), commits 541a8df/f950f1c/45fa815 (build/roadmap-t2)
→ master a567d59/a948676/6769bbb; derive-lib fragment applied by orchestrator (commit
"splice(...t2)"), proven composed: derive-lib 56/0, server.selftest 168/0, cockpit 139/0
(pre-T6; 146/0 post-T6). ask-registry union with T7 marker scenarios: 45/0.
Gates: pending.

## Builder-reported evidence (gates re-derive)
- ask-registry.sh --self-test 43/0 (union-composed 45/0; baseline 24; RED first: 12
  expected FAILs incl. Q4 distiller-clobbers-operator-edit race with control leg).
- workstreams-read.sh --self-test 56/0 (baseline 45; RED 8).
- Scenario V = real flagless production shape (subprocess verbs, no seams).
- Livesmoke: production-shape register + 2× capture-candidate with ASK_SUMMARIZER=haiku
  → created(title_source:auto) + both candidates pending with correct refs/ids.
- LIVE DEFECT found+fixed (6769bbb): LLM lane dead from EVERY hook context (CLI nested
  guard rc=1 stderr-only) — env -u CLAUDECODE on both spawns. HYPOTHESIZED working from
  operator logged-in env; refuter: one register with ASK_SUMMARIZER=haiku from operator
  shell not producing summary_updated.
- Fragment: derive-lib title fold precedence (operator-beats-auto regardless of ts),
  git apply --check clean, red-green proven (166/2→168/0 in-worktree).

## Rung-3 articulation (builder-authored, condensed)
**Spec meaning:** title = the folded summary field, not a new field — one name, two writer
classes, precedence by SOURCE CLASS not timestamp (title_source stamped on every
summary-writing record; fold exception binding on readers, writer-side skip as defense).
Amendment capture = three honest layers: mechanical ref-only candidates (never text),
gated async classification (pending = named state), operator correction
(detach/classify/amend). One-writer discipline: UI edits via set-title/detach-candidate;
fold/schema lives in exactly one file's header.
**Edge cases covered:** operator edit vs newer distiller re-run (Q4 + T2-A3a); empty
title/amend no-ops; invalid classification vocabulary rejected; classifier failure →
pending, no record; label-less "amendment" verdict; spawned/no-text sessions never produce
candidates; transcript-less ref fallback session:<sid>#<n>; ordinal advance; raw-text
non-persistence; legacy records fold as auto; flagless-merge emitter unchanged.
**NOT covered:** capture continues after ask close/merge — the marker is never invalidated; candidates/classifications land on closed asks by append-only design; task-5 timeline rendering must decide how post-'became →' rows display. A prompt that the model also amends explicitly yields TWO timeline rows (candidate + amended); no dedupe/linkage — correction is manual detach; task-5 render decision pending. Also: concurrent same-second appends (O_APPEND-safe, ts-tie fold order
unpinned); real-model output quality; detach feeding future classification (records
durable, no live loop); mirror divergence under partial write.
**Assumptions:** registry consumers tolerate 3 additive JSON fields (verified for
derive-lib/auditor/export-state readers); .count sidecar single-writer per session;
per-prompt synchronous bash spawn on UserPromptSubmit acceptable (precedent: first-prompt
register; watch under AV pressure).

## Orchestrator seams (from builder)
roadmap_rank verb NOT built (t3 bullet, t2 owns ask-registry — t3 overlay is the interim;
set-rank verb = queued follow-up); auditor.js duplicate-fold parity t4-owned; server.js
title endpoint landed via t3-int; ASK_SUMMARIZER not set in production template
(opt-in-dormant).

## Gate results
### task-verifier (Fable): FAIL conf 9 — all 4 suites re-derived green (45/0, 56/0, 56/0, 168/0) + 6 probes; falsification succeeded ONCE: D1 amendment labels masquerade as titles (derive-lib.js:122 folds ANY non-empty summary as title-class; candidate_classified/amended stamp labels into summary) — latent (0 such records in production) but reachable on first amend. D2 (routed to task 3): roadmap-routes foldRegistryForRoadmap expects title_set shape NO writer produces; ignores title_source → operator title misreported auto + clobberable on /api/roadmap. Fix builder dispatched (sonnet build/roadmap-title-fold-fix): D1 = title fold restricted to created/summary_updated + pin + FOLD CONTRACT header; D2 = align roadmap-routes fold to summary_updated+title_source. Checkbox held for re-verify.
### comprehension-reviewer (Fable): FAIL conf 7 — 2 unconsidered-edge-class gaps (post-close capture continuation; splice/amend double-representation), both articulation-only; bullets added above per reviewer spec; 3a/3b/3d/3e all PASS. Delta re-gate: dispatched (opus).
