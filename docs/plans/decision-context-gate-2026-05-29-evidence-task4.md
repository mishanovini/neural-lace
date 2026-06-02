# Task 4 — Comprehension Articulation (builder-authored)

### Spec meaning

Task 4 asks for the Stop-hook script that operationalizes ADR 047's
"Stop-hook reactive enforcement" model for the Decision-Context substrate:
read `$TRANSCRIPT_PATH` (agent-uneditable, Gen-6 narrative-integrity
property), classify the last assistant message via a three-tier scanner
(Tier 1 hard block on enumerated options / terminal-?-plus-list /
explicit "pick one" phrases; Tier 2 soft warn on "should I" / "would you
like" / terminal `?` alone; Tier 3 rhetorical whitelist for
"make sense?" / "right?" / "sound good?"), and BLOCK Stop when Tier 1
fires without a properly-fenced Decision-Context block per the grammar
in `~/.claude/rules/decision-context.md`. When a fence IS present in any
tier, call into the SOLE-NORMATIVE Zod-backed validator at
`neural-lace/conversation-tree-ui/state/decision-context-schema.js` (Task
2 module) via `node -e require(...)` — never re-implement the validator
in shell. Project each validated block onto an ADR-032 §2 event
(`decision-raised` / `question-raised` / `action-added` /
`autonomous-action-logged`) plus a sibling `item-details-set` carrying
the rich payload, and emit via the frozen `state.js` `appendEvent`
facade — never direct JSON write, never direct HTTP POST. The hook
honors the per-session waiver pattern (`.claude/state/decision-context-waiver-*.txt`,
≥1 substantive line, mtime <1h) borrowed verbatim from
`bug-persistence-gate.sh`, sources the shared retry-guard library so a
3-strike identical-failure loop downgrades to warn, and provides
`--self-test` covering eleven scenarios. Failure-isolation per
`gate-respect.md`: writer-hook failure (broken `CONV_TREE_STATE_LIB`,
node unavailable, all sinks reject) NEVER blocks Stop on its own — it
appends to `~/.claude/state/decision-context/fallback.jsonl` (Task 8
drains) and logs to `~/.claude/logs/decision-context-gate.log`. Mirror
to `~/.claude/hooks/` per the two-layer-config rule.

### Edge cases covered

- **Cheap pre-filter short-circuit** (R7 performance risk): when the
  trailing 1200 chars of the last assistant message contain ZERO of
  any signal token (no `?`, no enumerated marker, no explicit phrase,
  no fence opener, no rhetorical), the hook exits 0 BEFORE invoking
  the `node` subprocess. ST8's `DC_PERF_TRACE_FILE` mechanism asserts
  no node was invoked.
- **Multiline-content jq extraction**: a transcript line whose
  `.content` is a multi-line string is extracted in FULL via
  `jq -rs '... | last'` — using `jq -r ... | tail -n 1` would only
  return the trailing line of the content (e.g., the `:::` fence
  closer), causing every fenced message to be silently dropped. The
  fix uses `-s` slurp + `last` to get the entire last assistant
  message as one string.
- **item_id required on three-of-four primary events**: per
  `state/schema.js` `EVENT_REQUIRED_FIELDS`, `decision-raised` /
  `question-raised` / `action-added` require `node_id + item_id + text`
  while `autonomous-action-logged` requires `node_id + text + details`
  (no item_id — fait-accompli). The emitter sets `item_id` on the first
  three categories only; ST11 asserts a count of 1 for each of the four
  event types after emitting one fence per category.
- **Cross-field validation rejection**: Tier-1 + fence whose Zod
  validation produces a ZodIssue (e.g., `expires_at` set with
  `default_if_no_response` referencing an "expensive" option) is
  treated as malformed-fence and BLOCKs with the Zod issue path:message
  string in stderr (ST5).
- **Voluntary fence on Tier-3 rhetorical**: when a fence is present
  alongside a rhetorical "make sense?", the hook still emits the fence
  (no block, no waiver needed) — the rule is "fence is always honored,
  block fires only on Tier-1 + missing fence".
- **No transcript path**: missing `$TRANSCRIPT_PATH` (also missing
  file, missing jq) → exit 0 silent no-op, mirroring sibling Stop
  hooks (ST10).
- **3-strike retry-guard downgrade**: identical failure signature
  across N retries with no new commits → block downgrades to warn,
  unresolved-stop-hooks.log entry, exit 0. ST9 exercises this with 5
  consecutive identical-block calls.
- **Multi-fence-per-message**: the parser loop iterates ALL fence
  opener/closer pairs in the message and processes each independently;
  ST11 ships four fences in one message and verifies all four event
  types land.
- **Voluntary harness-dev escape**: `DECISION_CONTEXT_GATE_DISABLE=1`
  short-circuits the gate so sessions editing this hook or its
  self-test don't self-trigger.

### Edge cases NOT covered

- **Fence syntax drift beyond the parser's current grammar**: the
  parser at `decision-context-schema.js:_parseRecommendationBlock`
  expects recommendation sub-fields (`Option key`, `Reasoning`) to be
  **indented** (the parser's `\s*\*\*...\*\*` regex captures them only
  when they're under the `**Recommendation:**` sub-block, which
  requires NOT matching the top-level bold-field regex `^\*\*...\*\*`).
  This is a parser idiosyncrasy the agent must work around in its
  authored fences. The self-test fences indent recommendation
  sub-fields by two spaces; if a future agent writes a recommendation
  block with non-indented bold fields, the Zod validation will fail
  with "recommendation.option_key:Required" and the gate will BLOCK
  with that exact message in stderr. The fix is to indent
  in the agent's emitted fence — the parser is sole-normative and the
  gate honors its grammar verbatim.
- **Late-arriving system reminders inside the assistant message**:
  the classifier scans the LAST assistant message. If a system
  reminder is injected DURING the assistant's reply that contains
  trigger tokens like `?` or "should I", the trigger may falsely fire.
  The waiver escape valve covers this; no inline filter is applied.
- **Fence with valid syntax but unrecognized category**: handled by
  the parser throwing inside the `try`/`catch` in the node script;
  the error is captured into `errors[]` and the verdict becomes
  `ZERR`/`PERR` which BLOCKs in Tier-1. No silent skip.
- **Multi-language assistant messages**: the trigger regexes are
  English-only. Non-English decision-soliciting prose would not fire
  the gate, by design — the harness is English-only canon.
- **Cross-process race on fallback.jsonl**: append-only writes from
  multiple concurrent hook invocations are append-safe on POSIX but
  not strictly atomic for multi-line records. Task 8's replay script
  must read line-by-line and tolerate partial writes; out of scope
  for Task 4.

### Assumptions

- The Task 2 schema module (`decision-context-schema.js`) and the
  Task 1 ADR are NOT yet on the feature branch HEAD at dispatch time
  (they ride on a parallel branch tip the orchestrator will
  cherry-pick before merging Task 4). The hook's resolver
  (`_resolve_schema_module`) honors `DECISION_CONTEXT_SCHEMA` env
  override so a sibling worktree's copy can be pointed to for the
  self-test in isolation; in production after cherry-pick, the
  default git-rev-parse resolution finds the module at
  `neural-lace/conversation-tree-ui/state/decision-context-schema.js`
  alongside `state.js`.
- The Task 3 rule file `~/.claude/rules/decision-context.md` is
  referenced in the block-message but does not need to exist at
  hook-dispatch time — the stderr is documentation pointing the
  agent at the rule when it lands. If the rule file is missing when
  an operator reads the block message, the path is still
  self-documenting (the categories + grammar are also named inline).
- The retry-guard library at `lib/stop-hook-retry-guard.sh` is
  present alongside this hook (sibling-pattern assumption — all six
  sibling Stop hooks already source it; the install convention puts
  the lib next to the hook scripts in `~/.claude/hooks/lib/`).
- Multi-checkout layouts: the resolvers mirror
  `conversation-tree-emit.sh`'s `_resolve_state_lib` /
  `_resolve_gui_state_path` / `_resolve_gate_state_path` exactly, so
  a worktree-rooted hook write reaches the operator's
  single-GUI-server file the same way the writer hook does.
- `jq` is available on the operator's machine — the hook degrades to
  silent no-op when it is not (consistent with sibling Stop hooks).
- `node` + `zod` are available wherever the schema module is
  resolved — the module's package.json declares zod as a runtime
  dependency, and `node_modules/zod` ships with the
  `conversation-tree-ui` module. When `node` is unavailable, the
  hook degrades to writing a stub `branch-note-add` event to
  fallback.jsonl rather than blocking.
