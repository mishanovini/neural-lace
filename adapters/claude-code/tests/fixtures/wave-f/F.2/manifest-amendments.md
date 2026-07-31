# F.2 manifest amendments (for the F.1 orchestrator integration pass)

Per §F.0.1, `manifest.json` is ORCHESTRATOR-ONLY (F.1 is this wave's designated
integrator). This fragment lists the entries F.2's work makes true, for F.1 to
fold in.

## 0. URGENT — pre-existing manifest coverage gap, surfaced by this task's
   `gen-architecture-doc.sh` / `manifest-check.sh --gen-index` regeneration

Six doctrine files exist on disk, are still actively referenced (grepped live
in `agents/*.md`, `templates/plan-template.md`, `CLAUDE.md`, `doctrine/planning.md`
— NOT dead content), but have **zero manifest entries** pointing at them:
`acceptance-scenarios.md`, `claims.md`, `completion-criteria.md`,
`customer-facing-review.md`, `orchestrator-pattern.md`,
`pr-health-snapshot.md`. This predates F.2 — the stale, hand-drifted
`doctrine/INDEX.md` this task regenerated USED to list these six (from some
earlier manifest state), but the CURRENT manifest.json has no entry for any
of them, so `evals/golden/rules-index-coverage.sh` — which checks "every
non-`-full` doctrine/*.md has a row in `doctrine/INDEX.md`" — now correctly
fails post-regeneration (it was passing before only because the stale INDEX.md
happened to still list files the manifest had stopped covering; the
regeneration didn't create the gap, it stopped MASKING it).

**Recommended fix (F.1 fold-in):** add six `kind: pattern` manifest entries
mirroring the existing `diagnosis`/`gate-respect`/`work-shapes`-style pattern
entries (no hooks, no events, `wired_template: false`, `selftest: false`,
`blocking: false`, `budget_class: none`):

```json
{ "id": "acceptance-scenarios", "kind": "pattern", "doctrine_file": "doctrine/acceptance-scenarios.md", "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": {"paths": [], "keywords": []}, "blocking": false, "budget_class": "none" }
{ "id": "claims", "kind": "pattern", "doctrine_file": "doctrine/claims.md", "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": {"paths": [], "keywords": []}, "blocking": false, "budget_class": "none" }
{ "id": "completion-criteria", "kind": "pattern", "doctrine_file": "doctrine/completion-criteria.md", "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": {"paths": [], "keywords": []}, "blocking": false, "budget_class": "none" }
{ "id": "customer-facing-review", "kind": "pattern", "doctrine_file": "doctrine/customer-facing-review.md", "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": {"paths": [], "keywords": []}, "blocking": false, "budget_class": "none" }
{ "id": "orchestrator-pattern", "kind": "pattern", "doctrine_file": "doctrine/orchestrator-pattern.md", "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": {"paths": [], "keywords": []}, "blocking": false, "budget_class": "none" }
{ "id": "pr-health-snapshot", "kind": "pattern", "doctrine_file": "doctrine/pr-health-snapshot.md", "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": {"paths": [], "keywords": []}, "blocking": false, "budget_class": "none" }
```

(`completion-criteria`, `customer-facing-review`, `pr-health-snapshot` were
each ONCE `kind: gate` manifest entries whose enforcing hooks retired to
`attic/` at D.5/D.6 into the `wave-d-retired-shims` aggregate entry — but
their DOCTRINE content, unlike their hooks, was never folded into that
aggregate or given its own surviving entry. `acceptance-scenarios`,
`claims`, `orchestrator-pattern` appear to simply have never had an entry —
possibly an original C.4 doctrine-buildout omission.)

**After F.1 folds these in:** re-run `bash adapters/claude-code/scripts/manifest-check.sh --gen-index`
to regenerate `doctrine/INDEX.md` with the six new rows, then re-run
`bash evals/golden/rules-index-coverage.sh` to confirm it passes again.
This F.2 branch intentionally ships `doctrine/INDEX.md` in its CURRENT
regenerated (accurate-to-the-CURRENT-manifest) state rather than hand-patching
it to paper over the gap — the manifest is the single source of truth this
whole program is built around; patching the generated artifact instead of the
source would reintroduce exactly the kind of drift F.2 exists to kill.

## 1. NEW entry — `harness-changelog`

`scripts/harness-changelog.sh` (§F.2b mechanism 2) is a new standalone script
in the same class as `nl-issue`, `harness-kpis`, `session-resumer`,
`needs-you-ledger` (all currently `kind: writer`, `wired_template: false`,
`hooks: []`, `events: []`, non-event-wired scripts consumed by the digest or
by a scheduled task). Recommended new entry:

```json
{
  "id": "harness-changelog",
  "kind": "writer",
  "doctrine_file": null,
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": true,
  "jit_triggers": { "paths": [], "keywords": [] },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "scripts/harness-changelog.sh (F.2b) -- machine-wide 'what's new' ledger + --digest-line consumed by session-start-digest.sh's feed 14; not event-wired."
}
```

## 2. `session-start-digest` entry — no schema change required

`hooks/session-start-digest.sh` gained a 14th feed (`feed_harness_changelog`)
calling `scripts/harness-changelog.sh --digest-line`. This is a behavior
change inside an EXISTING manifest-registered unit (id `session-start-digest`)
— it adds no new hook file, no new event, no new blocking unit. No manifest
entry change required beyond optionally extending its existing
`honest_status` string to mention the new feed count (cosmetic; not required
for schema validity):

Current:
```json
"honest_status": "ONE SessionStart digest replacing the transitional surfacer-pack (E.1); wired at §E.W."
```

Optional amendment:
```json
"honest_status": "ONE SessionStart digest replacing the transitional surfacer-pack (E.1); wired at §E.W. 14 feeds as of F.2 (added harness-changelog 'what's new' feed)."
```

## 3. `plan-edit-validator` entry — no schema change required

`hooks/plan-edit-validator.sh` gained a new WARN-only check
(`check_docs_impact_warn`, §F.2b mechanism 1) inside the SAME existing hook
file already registered under the `plan-edit-validator` manifest entry. No
new hook file, no new event, no blocking-count change (the new check never
blocks — WARN only). No manifest entry change required.

## 4. `gen-architecture-doc` — NEW entry recommended

```json
{
  "id": "gen-architecture-doc",
  "kind": "writer",
  "doctrine_file": null,
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": true,
  "jit_triggers": { "paths": [], "keywords": [] },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "scripts/gen-architecture-doc.sh (F.2) -- regenerates docs/harness-architecture.md from manifest.json; --check is the doctor drift predicate (tests/fixtures/wave-f/F.2/doctor-predicate.md); not event-wired (manual + doctor-invoked)."
}
```

## 5. No change to blocking-gate count (still expected 12/12 post-F.1)

Nothing in this task adds or removes a `blocking: true` unit. The two new
scripts (`harness-changelog.sh`, `gen-architecture-doc.sh`) are both
`blocking: false`, `kind: writer`. The `plan-edit-validator` and
`session-start-digest` behavior changes are inside existing non-blocking-count-
affecting units (plan-edit-validator's OWN blocking behavior — the checkbox-
flip authorization — is unchanged; only a new WARN was added alongside it).
