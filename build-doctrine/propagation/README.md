# Build Doctrine — Propagation Engine (Tranche 6a — v1)

The propagation engine reads `propagation-rules.json`, evaluates each rule against an input event, dispatches matching rules' actions, and writes an audit-log entry to `build-doctrine/telemetry/propagation.jsonl` for every rule evaluation (matched OR unmatched). The audit log is the measurement substrate — the engine's primary value lives in the structured event stream it produces, not in any single rule.

Authored 2026-05-06 by Tranche 6a of the Build Doctrine integration arc. Per the teaching example at [`docs/teaching-examples/2026-05-06-starter-rules-vs-wait-for-pilot.md`](../../docs/teaching-examples/2026-05-06-starter-rules-vs-wait-for-pilot.md): the audit log IS what converts pilot impressions into structured data. Without the engine, pilot evidence is operator memory.

## Files

```
build-doctrine/propagation/
├── README.md                    # this file
└── propagation-rules.json       # the rule set (8 rules in v1: 4 proven + 3 conjectural + 1 docs-coupling)

adapters/claude-code/
├── hooks/propagation-trigger-router.sh    # the engine (~700 LOC bash)
└── schemas/propagation-rules.schema.json  # rule-format JSON Schema

build-doctrine/telemetry/
├── .gitkeep                     # tracks the directory
└── propagation.jsonl            # gitignored audit log (one JSON per line)
```

## How the engine evaluates an event

1. **Load rules.** `propagation-rules.json` parsed via `jq`; malformed JSON or schema-mismatch fails at load with explicit error to stderr.
2. **Iterate rules in declaration order.** For each rule:
   - **Trigger match.** The rule's `trigger.event_type` must equal the event's `event_type`; if `trigger.path_pattern` is set, the event's `path` must match the glob; if `trigger.metadata_match` is set, every key/value must equal the event's metadata.
   - **Condition evaluation.** If the rule has a `condition` block, the engine runs the condition script/command. Non-zero exit = condition failed, action skipped.
   - **Action dispatch.** If trigger and condition both pass, the action runs (`log-only`, `script`, `command`, or `open-finding`). Action failures are logged but don't crash the engine.
   - **Audit-log entry.** One JSONL entry per rule evaluation, regardless of whether the rule matched.
3. **Negative-space audit.** If NO rule matched the event, a single `no-rules-matched` summary is appended — pilot data shows what events ARE happening that no rule covers, surfacing candidate-rule needs.

## Running the engine

### From the command line

```bash
# Evaluate one event by type + flags:
~/.claude/hooks/propagation-trigger-router.sh evaluate plan-status-flip \
  --path docs/plans/foo.md --meta status_to=COMPLETED

# Evaluate one event by piping JSON on stdin:
echo '{"event_type":"file-modified","path":"docs/prd.md","metadata":{}}' \
  | ~/.claude/hooks/propagation-trigger-router.sh evaluate-stdin

# Run the self-test:
~/.claude/hooks/propagation-trigger-router.sh --self-test
```

### From other harness hooks (post-Tranche-6a wiring)

The engine is currently standalone. Wiring it into the existing hook chain (PostToolUse on Edit/Write, Stop hooks, etc.) is a follow-up commit guarded on operational evidence. The 4 proven rules duplicate behavior already implemented in narrow hooks (`plan-lifecycle.sh`, `plan-edit-validator.sh`, `decisions-index-gate.sh`, `docs-freshness-gate.sh`); consolidation (deleting the narrow hooks) only happens after the engine is proven to handle every case.

## Audit-log format

Every audit entry is a single JSON line at `build-doctrine/telemetry/propagation.jsonl`. Required fields:

| Field | Type | Description |
|---|---|---|
| `schema_version` | `1` | Schema version. |
| `timestamp` | ISO 8601 | When the rule was evaluated. |
| `event_id` | string | Per-event identifier; same across all rule evaluations for one event. |
| `rule_id` | string | The `id` of the rule being evaluated. `null` for negative-space `no-rules-matched` summaries. |
| `severity` | `info \| warning \| critical` | The rule's declared severity. |
| `conjectural` | boolean | Whether the rule is conjectural (its threshold is a hypothesis pending evidence). |
| `verdict` | string | One of: `fired`, `unmatched`, `condition-not-met`, `action-failed`, `event-budget-exceeded`, `no-rules-matched`. |
| `duration_ms` | integer | Wall-clock duration of the rule's evaluation. |
| `event` | object | The full input event (event_type, path, metadata). |

Optional fields:

- `slow_rule: true` — set when `duration_ms` exceeds the per-rule budget threshold (currently 1000ms; v2 target is 100ms).
- `action_exit_code: <int>` — set for `verdict: fired` and `verdict: action-failed`.

## The 8 starter rules in v1

### Proven (generalizes existing narrow hooks; zero conjecture)

1. **`pt-proven-plan-lifecycle-archive`** — fires on `plan-status-flip` events to plans in `docs/plans/*.md`. Generalizes `plan-lifecycle.sh`.
2. **`pt-proven-plan-edit-evidence-first`** — fires on `plan-edit` events to plans. Generalizes `plan-edit-validator.sh`.
3. **`pt-proven-decisions-index-update`** — fires on `decision-record-created` events under `docs/decisions/`. Generalizes `decisions-index-gate.sh`.
4. **`pt-proven-narrative-doc-staleness`** — fires on `narrative-doc-modified` events. Generalizes `docs-freshness-gate.sh`.

### Conjectural (covers existing canon; thresholds pending tuning)

5. **`pt-3-adr-adoption-fanout`** — fires on `decision-record-modified` events; logs that downstream artifacts may need updating. Threshold for "fan-out worth surfacing" is conjectural.
6. **`pt-4-doctrine-change-finding-routing`** — fires on `doctrine-doc-modified` events under `build-doctrine/doctrine/*.md`; logs that downstream projects may need re-validation. Severity threshold (log vs. open-finding) is conjectural.
7. **`pt-6-findings-pattern-detection`** — fires on `finding-added` events; logs the finding metadata for pattern-detection by a follow-up analyzer. Pattern threshold (≥N findings within X days) is conjectural.
8. **`docs-coupling-cross-reference-change`** — fires on `doc-cross-reference-changed` events; logs cross-reference churn. Action ("which cited docs need review?") is conjectural.

## How to add a rule

1. Edit `build-doctrine/propagation/propagation-rules.json`. Add an entry to the `rules` array conforming to `adapters/claude-code/schemas/propagation-rules.schema.json`.
2. **Required fields**: `id` (kebab-case, prefix `pt-N-` for trigger-taxonomy alignment), `description` (≥10 chars; explain when + why), `trigger` (`event_type` minimum), `action` (`type` minimum).
3. **Recommended fields**: `severity` (default `info`), `owner` (logical role), `conjectural` (true if threshold is a hypothesis), `pending_evidence` (when conjectural is true).
4. **Re-run self-test**: `~/.claude/hooks/propagation-trigger-router.sh --self-test` should report PASS (S14 will reflect the new rule count).

## How to read the audit log

The audit log is JSONL — one event per line. Stream operations:

```bash
# Count rule fires by rule_id:
jq -r '.rule_id' build-doctrine/telemetry/propagation.jsonl \
  | sort | uniq -c | sort -rn

# Count verdicts:
jq -r '.verdict' build-doctrine/telemetry/propagation.jsonl \
  | sort | uniq -c | sort -rn

# Find slow rules:
jq 'select(.slow_rule == true) | {rule_id, duration_ms, event_type: .event.event_type}' \
  build-doctrine/telemetry/propagation.jsonl

# Find conjectural rules that have fired (data-collection ready):
jq 'select(.conjectural == true and .verdict == "fired")' \
  build-doctrine/telemetry/propagation.jsonl
```

## Conjectural-rule disposition path

Rules tagged `conjectural: true` ship with thresholds + actions that are hypotheses pending evidence. Disposition happens once the audit log accumulates enough events:

1. **Periodic review** (per `~/.claude/skills/harness-review.md`) reads the audit log and asks: "for each conjectural rule, do the firings match the intended pattern?"
2. **If YES** — promote to proven (flip `conjectural: false`, remove `pending_evidence`). Rule version-bumps; CHANGELOG entry.
3. **If NO** — adjust the threshold or action based on evidence; the rule stays conjectural until the next review confirms the new shape.
4. **If the rule fires NEVER** — either the trigger never happens (de-prioritize the rule, possibly remove) or the trigger detection is broken (check the `event_type` source).

## Performance budget (v1 hypothesis)

- **Per-rule budget**: 1000ms (v1; doctrine target is 100ms).
- **Per-event budget**: 5000ms total (v1; doctrine target is 500ms).
- **Why the gap**: bash + jq on Windows Git Bash measures ~300ms per rule due to subprocess overhead. v2 will optimize jq usage (batch reads, caching) to hit the doctrine target.

Audit-log entries with `slow_rule: true` flag rules exceeding the per-rule budget. Audit-log entries with `verdict: event-budget-exceeded` flag events where the budget was hit before all rules evaluated.

## What is NOT in v1

- **Real-time hook wiring**: the engine is standalone. Integration with the existing PostToolUse/Stop chain happens in a follow-up commit once self-tests are green.
- **Per-canon-category rules** (PT-1 contract, PT-2 design-system, PT-7 cross-repo): Tranche 6b — gated on pilot artifacts existing.
- **PT-5 drift detection**: Tranche 6c — gated on HARNESS-GAP-11 telemetry (2026-08).
- **Refactor of the 4 generalized hooks**: they remain in place; the engine duplicates+supersedes; consolidation is a future cleanup commit.
- **Rule-evaluation parallelism**: rules evaluate sequentially. v1's 8 rules + 5000ms event budget makes this acceptable; v2 may parallelize once rule count grows.

## Cross-references

- `build-doctrine/doctrine/06-propagation.md` — the PT-1..PT-7 trigger taxonomy this engine implements.
- `build-doctrine/doctrine/07-knowledge-integration.md` — the doctrine-evolution ritual; KIT-6 trigger consumes audit-log evidence from this engine.
- `~/.claude/rules/calibration-loop.md` — sibling capture mechanism (per-agent observation log); composes with this engine's audit log to produce harness-wide observability.
- `~/.claude/rules/findings-ledger.md` — `docs/findings.md` is a sibling capture target; `pt-6-findings-pattern-detection` rule reads this engine's audit log to detect patterns in findings.
- [`docs/teaching-examples/2026-05-06-starter-rules-vs-wait-for-pilot.md`](../../docs/teaching-examples/2026-05-06-starter-rules-vs-wait-for-pilot.md) — the conversation that produced this Tranche; reusable lesson on iterative-deployment over waterfall-design.
