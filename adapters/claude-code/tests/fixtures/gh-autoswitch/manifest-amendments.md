# GH-AUTH-AUTOSWITCH-WORKORG-01 manifest amendment (for the orchestrator integration pass)

Per the dispatch note, `manifest.json` is ORCHESTRATOR-ONLY. This fragment
names the single new entry this task's work makes true, schema-valid
against `adapters/claude-code/schemas/manifest.schema.json` (v1).

Insertion point verified via `jq -r '.entries[].id' manifest.json | LC_ALL=C
sort` against this worktree's tree: sorted neighbors are
`...gate-respect, gen-architecture-doc, gh-account-hint, git-freshness...`.
`gh-account-autoswitch` sorts strictly between `gen-architecture-doc` and
`gh-account-hint` (compare char-by-char: `g`,`h`,`-` common with
`gh-account-hint`, then `a` (autoswitch) vs `h` (hint) — `a` < `h`, so
`gh-account-autoswitch` sorts BEFORE `gh-account-hint`).

## NEW entry — `gh-account-autoswitch` (insert between `gen-architecture-doc`
## and `gh-account-hint`)

```json
{
  "id": "gh-account-autoswitch",
  "kind": "surfacer",
  "doctrine_file": "doctrine/git.md",
  "hooks": [
    "gh-account-autoswitch.sh"
  ],
  "events": [
    "PreToolUse"
  ],
  "wired_template": true,
  "selftest": true,
  "jit_triggers": {
    "paths": [],
    "keywords": []
  },
  "blocking": false,
  "budget_class": "pretool",
  "honesty_rationale": "Never blocks (every path exits 0) — it prepares the gh CLI environment (a pre-emptive `gh auth switch`) before the tool call proceeds, it never denies the tool call. Purely a side-effecting preparatory action, not a world-state assertion gate, so no waiver_path is offered (nothing to waive — there is no refusal to bypass).",
  "added_after": "2026-07",
  "golden_scenario": "A `gh pr merge`/`gh pr create`/`gh pr view`/`git push <remote>` command targets a repo owned by the OTHER gh account than the one currently active (e.g. active=alice-at-acme, target repo owned by alice-example, or vice versa). Without this hook the command 403s (\"Repository not found\") and the agent historically stopped and waited on the operator for a one-line `gh auth switch` fix. This hook resolves the target owner (via --repo flag, the git remote's URL, or the cwd repo's origin) and pre-emptively runs `gh auth switch -u <owner>` before the command executes, so the 403 never happens.",
  "fp_expectation": "Near-zero false-positive risk since the hook never blocks or denies anything — the only 'cost' of a false-positive-shaped trigger is an unnecessary (but harmless, idempotent) `gh auth switch` call on a command that would have succeeded anyway (e.g. the owner heuristic misfires on a command that doesn't actually need a different account). A legitimate same-account session touching only one account's repos in a row triggers zero switches after the first (idempotent no-op path verified by self-test scenario S10). Read-only gh/git commands (gh pr list/gh repo list/gh api GET-shaped calls not in the write-subcommand list, plain `git fetch`/`git pull`) are explicitly excluded from the write-scope regex and never trigger a switch.",
  "retirement_condition": "Retire or demote if: (a) gh CLI ships native multi-account auto-resolution making the manual switch step obsolete, (b) the operator consolidates to a single GitHub account (eliminating the dual-account problem this hook exists to solve), or (c) signal-ledger data over a full quarter shows zero 'warn' events with gate=gh-account-autoswitch (meaning the SessionStart directory-default switcher alone is sufficient and this PreToolUse layer is never actually needed)."
}
```

Field-by-field rationale:

- `id: "gh-account-autoswitch"` — kebab-case; distinct from the pre-existing
  `gh-account-hint` entry (that entry names `gh-account-blindness-hint.sh`,
  the REACTIVE PostToolUse+SessionStart mechanism; this is the PROACTIVE
  PreToolUse mechanism).
- `kind: "surfacer"` — matches the existing `gh-account-hint` entry's kind
  classification: read-only-in-effect on the tool call itself (it never
  blocks/refuses), even though it does have one side effect (the `gh auth
  switch` call). `writer` was considered but `surfacer` better matches the
  "advisory/preparatory, never blocks" semantics already established by its
  sibling entry.
- `doctrine_file: "doctrine/git.md"` — same doctrine file as `gh-account-hint`
  (both are the dual-account convention's enforcement side; `doctrine/git.md`
  already carries the Pattern-layer note per the original hook's L3 reference).
- `hooks: ["gh-account-autoswitch.sh"]` — the one new top-level hook file.
  Note `hooks/lib/gh-account-lib.sh` (the new shared library both this hook
  and `gh-account-blindness-hint.sh` source) is NOT listed here — per the
  established convention (verified against `nl-cli`'s O.3 fragment reasoning
  and the live manifest's treatment of other `hooks/lib/*.sh` files), library
  files under `hooks/lib/` are excluded from the coverage sweep and from any
  entry's `hooks[]` array.
- `events: ["PreToolUse"]` — fires only on PreToolUse, matcher "Bash" (see
  template-wiring.md fragment).
- `wired_template: true` — the orchestrator's settings.json.template
  amendment (template-wiring.md fragment) adds the "Bash" PreToolUse
  matcher block referencing this hook's basename.
- `selftest: true` — `gh-account-autoswitch.sh --self-test` exists and
  passes 10/10 (see report-back for the exact scenario list and counts).
- `blocking: false`, `budget_class: "pretool"` — never blocks; this is a
  new PreToolUse "Bash" matcher entry, so it counts +1 against whatever
  PreToolUse-Bash budget the harness tracks (flagged for the orchestrator's
  awareness, not something this builder can verify against a numeric cap
  without reading the current live budget counters).
- `honesty_rationale` (not `waiver_path`) — required because `blocking` is
  NOT true here, so strictly neither field is schema-required by the
  general blocking-gate rule; however `added_after` >= "2026-07" triggers
  the SEPARATE new-gate-evidence-bar clause, which requires `anyOf
  waiver_path OR honesty_rationale` regardless of `blocking`'s value. This
  entry supplies `honesty_rationale` (no waiver makes sense for a
  never-blocking preparatory action — there is nothing to waive).
- `added_after: "2026-07"` — this is a new gate/mechanism landing this
  month, so the new-gate-evidence-bar (ADR 059 D4) applies. The three
  companion fields (`golden_scenario`, `fp_expectation`,
  `retirement_condition`) are populated above per the schema's conditional
  requirement.

## Existing entry `gh-account-hint`: UNCHANGED

No edits to the existing `gh-account-hint` entry's fields. Its `hooks[]`
still lists only `gh-account-blindness-hint.sh` — that file's refactor (now
sourcing the new shared `hooks/lib/gh-account-lib.sh`) does not change its
own self-test coverage (still passes 9/9, confirmed unchanged) or its
event wiring (still PostToolUse + SessionStart).

## No doctor-predicate.md, no install-sync.md

No new doctor predicate: this task does not add a doctor-enforced invariant
(the manifest coverage sweep + wired_template/selftest derivation already
mechanically verify hook-file existence and --self-test presence — no
NEW doctor check needed). No install-sync fragment: `hooks/*.sh` and
`hooks/lib/*.sh` are already glob-synced by `install.sh`'s existing passes,
same precedent as O.3's fragment.

## ORCHESTRATOR TODO — observability-consumer-map.json

NOT required as a new entry: this hook emits `event=warn`, gate
`gh-account-autoswitch`, via the EXISTING `warn` event type in
`observability-consumer-map.json`, which already names real consumers
(`digest:feed_ledger_summary`, `kpi:harness-kpis.sh`). No new event type
was introduced, so no consumer-map edit is needed. Verified live in this
worktree: `jq '.event_types.warn.consumers' adapters/claude-code/observability-consumer-map.json`
returns both consumers already. Flagging this explicitly so the
orchestrator does not go looking for a missing consumer-map fragment that
was never needed.
