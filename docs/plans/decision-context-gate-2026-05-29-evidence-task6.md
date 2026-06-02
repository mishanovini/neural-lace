# Task 6 Evidence — decision-context-reply-emit.sh

Task: Author the UserPromptSubmit hook that detects Misha's replies to open
decision-context nodes + its self-test + mirror to live ~/.claude/hooks/.

## Task 6 — Comprehension Articulation (builder-authored)

### Spec meaning

The hook is a UserPromptSubmit-class **writer** (NOT a gate) that closes the
round-trip in the decision-context substrate: when Misha replies to a prompt
soliciting a decision/question/action that has already landed in his
conversation tree as an open item, this hook detects the reply, projects it
onto ADR-032 §2 events (`answered` for decision/question, `action-done` for
action), and lands the resolution in the tree state via the frozen state.js
facade. A follow-up response text after the trigger gets captured on the
item via `item-details-set` with `details.response_text`. Three detection
modes layer in specificity order: (a) item_id literal token match, (b)
node_id literal token match, (c) case-insensitive `details.reply_with`
substring match. Only OPEN items on OPEN nodes count — checked/deferred/
backlogged items and archived/concluded nodes are silently skipped so a
stale mention of an already-resolved item is a no-op. Idempotency is the
load-bearing property because UserPromptSubmit fires on every prompt: the
event_id is deterministic per (item_id, sha1(prompt)) so re-firing on the
same prompt produces the same event_id and the facade dedupes. Failure
isolation is absolute — every code path exits 0, facade-unreachable events
land in fallback.jsonl for Task 8's drainer; the user's prompt must NEVER
be blocked by a writer-class hook (gate-respect.md).

### Edge cases covered

- **Archived/concluded nodes silently skipped (ST10).** The node-state
  filter is the first check inside the per-node loop in `_scan_and_emit`;
  archived/concluded never reaches item iteration.
- **Already-checked/deferred/backlogged items skipped (ST10b).** Filtered
  per-item inside the loop before any detection runs, so a stale mention
  of a resolved item is a no-op even on an open node.
- **Action items emit `action-done`, not `answered` (ST4).** The reducer
  rejects `answered` on an action kind (`expectAction && !kind==='action'`)
  — the hook chooses event type by `it.kind` exactly so a reducer-reject
  never happens for a legitimate match.
- **Multiple open items, prompt mentions a subset (ST9).** Each open item
  is independently scanned; non-matched items produce no event.
- **Idempotency on 3 re-fires same prompt (ST6).** The deterministic
  event_id `dcre-<tag>-<sha1(item_id|sha1(prompt))[0:24]>` is the same on
  re-fire, and `appendEvent` dedupes per ADR-032 §2 idempotency.
- **Facade-down / state-lib unreachable (ST7).** The node subprocess
  returns a `LIBERR:` or `READERR:` sentinel; `_scan_and_emit` returns
  non-zero; the dispatcher writes a `_facade_down_sentinel` line to
  `~/.claude/state/decision-context/fallback.jsonl` and exits 0. The
  user's prompt is never blocked.
- **Case-insensitive reply_with phrase (ST3).** `phraseMatch()`
  lowercases both haystack and needle before substring search.
- **Follow-up response text capture (ST5).** `followUp()` slices the
  prompt after the matched span, trims leading punctuation/whitespace,
  caps at 2000 chars, and returns null if empty. An `item-details-set`
  event with `details.response_text` is emitted only when non-null.
- **No-match silent (ST8).** Empty prompts and prompts with no token/
  phrase hits exit 0 with zero events emitted.
- **Multi-sink dedupe.** GUI STATE_FILE + §5 gate path receive the same
  deterministic event_ids; coincidentally-equal sinks are a per-file
  no-op via facade idempotency (same pattern conversation-tree-emit.sh
  uses, attributed in comment).

### Edge cases NOT covered

- **Two different items with overlapping `reply_with` phrases.** If
  item A has `reply_with: "yes"` and item B has `reply_with: "yes
  please"`, a prompt containing "yes please" matches BOTH (item A via
  the "yes" substring; item B via the full phrase). Both events emit,
  potentially closing item A when only B was intended. The schema's
  guidance to make `reply_with` phrases distinctive mitigates but does
  not eliminate this — accepting as a soft failure mode the operator
  resolves by phrasing distinct reply_withs.
- **A prompt that references an item via paraphrase only.** "the
  database question we discussed" does not match either id or
  reply_with — no event emitted. Pending-surfacer (Task 5) re-injects
  on next SessionStart so the item doesn't disappear from view (per
  plan's Edge Cases section "Misha replies in plain prose...").
- **Schema-version skew.** This hook does NOT call into the Zod
  validator — it only reads the snapshot's item shape (which is in
  schema major 1 territory). A future schema major bump would require
  re-validating the assumption that `it.checked`/`it.deferred`/
  `it.kind`/`it.details.reply_with` retain their meaning.
- **Cross-session ambiguity.** If two parallel Dispatch sessions
  receive replies to the SAME item_id concurrently, the facade's
  append-and-rename atomicity handles the race but the event_id is
  keyed on (item_id, sha1(prompt)) so two DIFFERENT prompt texts
  produce two events. The reducer's `answered`-on-already-checked is a
  rejection (item already checked), so the second event is dropped
  silently — acceptable.
- **`item-details-set` overwrite on subsequent reply.** A user
  replying twice to the same item with different follow-up text
  produces two `item-details-set` events with DIFFERENT event_ids
  (the second `|details` hash differs because the prompt differs), so
  both land. The reducer's last-writer-wins on `it.details` means the
  most recent response_text persists. Out of scope to dedupe at the
  hook layer — the reducer's semantics are the source of truth.

### Assumptions

- **Schema major 1 stable.** The hook reads `it.checked`, `it.deferred`,
  `it.backlogged`, `it.kind`, `it.details.reply_with`, `node.state`,
  `node.items[]` — all per ADR-032 §2/§4 within schema major 1. A future
  major bump invalidates this assumption (mitigated by the existing
  conv-tree gate's `SchemaTooNewError` behavior, which the facade
  surfaces; this hook would catch the throw and fall back to silent
  no-op via the `READERR:` sentinel path).
- **State-lib at the conventional path.** Resolver follows
  conversation-tree-emit.sh's exact pattern (git-toplevel +
  fallback-conv-tree-path) so writer and gate see the same library and
  state file.
- **The Task 4 Stop hook stores `reply_with` as `details.reply_with` on
  the item via `item-details-set`.** This is the contract Task 4 must
  honor for path (c) to work. If Task 4 stores it differently (e.g.,
  on a sibling event), paths (a) and (b) still work but (c) silently
  no-ops — degraded behavior but not broken.
- **`UserPromptSubmit` input JSON has `prompt` field.** Per
  goal-extraction-on-prompt.sh precedent, this hook reads
  `.prompt // .user_prompt // .message` as a fallback chain.
- **`node` is available in PATH.** All facade calls go through `node
  -e` (per ADR-031 r7: facade is the SOLE NORMATIVE write path). If
  node is unavailable the hook logs and exits 0 (writer discipline).
- **`zod` is installed** in the conv-tree-ui module (via Task 2). The
  reply-emit hook does not directly require `zod` (it only reads the
  snapshot), but the `state.js` facade chain ultimately requires the
  module to load. Task 2 absorbed the `package.json` + `zod` install
  in the plan's in-flight scope updates.
- **Settings.json wiring lands in Task 9.** This hook ships with NO
  wiring; the bootstrap wave (Task 9) registers it under
  UserPromptSubmit. Until Task 9 lands, the hook does not fire on real
  user prompts and the self-test is the only exercise path.
