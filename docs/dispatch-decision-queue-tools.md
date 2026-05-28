# Dispatch — Decision Queue calling convention

This doc tells Dispatch (and any other agent) how to use the Decision Queue substrate. The substrate is documented in [ADR-043](decisions/043-decision-queue-substrate.md); the schema is at `adapters/claude-code/schemas/decision-queue.schema.json`; the storage layer is `adapters/claude-code/scripts/decision-queue.sh`.

The harness does not expose custom MCP tools — Dispatch interacts with the queue by shelling out to the storage script via `Bash`. This is intentional: shell wrappers are easier to compose, easier to debug, and identical across all execution modes (interactive local, parallel local, cloud-remote, scheduled, agent-team).

## When to add a decision to the queue

**Add when:** the human owes a real choice (not a clarifying question, not a status update). The classic shape: "I'm about to do X but there are 2-3 ways to do it and the human should pick."

**Don't add when:**

- The decision is trivially reversible AND you can pick a default per `discovery-protocol.md`'s auto-apply rule. Just do it and document.
- The work doesn't actually depend on the decision yet. Add later when it becomes blocking.
- You're surfacing an *observation*, not an ask. Observations go to `docs/findings.md`.
- You're surfacing *open work*, not a decision. Open work goes to `docs/backlog.md`.

## When to highlight

**Highlight when:** the item has elevated salience beyond the default priority score. Use the human-readable `--reason` to explain WHY this item matters NOW.

- `--level subtle` — gentle nudge ("this has been open 7 days"). Don't add to top of list.
- `--level strong` — pulsing border in UI ("this blocks 3 in-flight PRs"). Top-of-list adjacent.
- `--level urgent` — bell badge, top-of-list anchor ("the cascade from your reply on DQ-bcd...8 is waiting"). Use sparingly.

**Auto-clear:** the UI will clear highlight automatically when the user engages (clicks, replies, dismisses). Dispatch can also `unhighlight` explicitly when the trigger condition resolves.

## The five subcommands

### `add` — create a new item

```bash
~/.claude/scripts/decision-queue.sh add \
  --question "Should we use Lambda or Fly for the new endpoint?" \
  --project "<project-a>" \
  --mode PICK \
  --recommendation "Fly — fewer cold-start surprises and we already pay for a Fly app for monitoring." \
  --counter "Lambda is free for our traffic level and ops cost is real for Fly." \
  --defer-cost "Blocks the alert-routing PR (#187); aging tax begins after 14d." \
  --option "fly:default:Use Fly with existing Fly app; ops setup ~1h" \
  --option "lambda:Cheaper but new cold-init class" \
  --option "vercel-edge:Free; runtime feature gaps we'd need to verify" \
  --source-link "docs/plans/alert-routing-2026-05-24.md" \
  --source-link "https://github.com/<your-org>/<repo>/pull/187" \
  --source-session "$CLAUDE_SESSION_ID" \
  --downstream "alert-routing-PR:1" \
  --downstream "ops-runbook-update:1"
# → prints DQ-uuid to stdout, exit 0
```

**Mode rules:**
- `QUICK` — no `--option` flags needed. UI shows a single text input.
- `PICK` — at least 2 `--option label[:default][:consequences]` flags. UI shows radio buttons.
- `DEEP` — the answer requires a real conversation; UI offers "start deep-dive thread."

**Empty / minimal call:**

```bash
~/.claude/scripts/decision-queue.sh add --question "Should I default to opt-in or opt-out for the new email digest?"
# → adds with mode=QUICK, project=cross-cutting, no recommendation, no counter
```

### `list` — query the queue

```bash
# All open items in the default project bucket, sorted by priority desc.
~/.claude/scripts/decision-queue.sh list --format json

# Filter by project and mode.
~/.claude/scripts/decision-queue.sh list --project <project-b> --mode PICK --format json

# Highlighted items only.
~/.claude/scripts/decision-queue.sh list --highlighted true --format json

# Quick human-skim view.
~/.claude/scripts/decision-queue.sh list --format table
# Output: priority \t id... \t project \t mode \t star \t question
```

### `get` — fetch one item by id

```bash
~/.claude/scripts/decision-queue.sh get DQ-bcd900b8-1234-4abc-9def-1234567890ab
# → full item JSON to stdout
```

### `close` — mark answered

```bash
~/.claude/scripts/decision-queue.sh close DQ-bcd900b8-... \
  --answer "Go with Fly. I'll handle the Fly app provisioning myself." \
  --by user
```

**`--by` values:**
- `user` (default) — Misha typed it
- `dispatch` — Dispatch auto-resolved per a recovered constraint (rare; document why in `--answer`)
- `auto-default` — closed by the system after a default option fired

### `update` — mutate arbitrary fields

```bash
# Mark superseded by another decision.
~/.claude/scripts/decision-queue.sh update DQ-bcd900b8-... \
  --field state=superseded \
  --field answer="Superseded by DQ-newer-id; the platform decision absorbed this."

# Mark moot.
~/.claude/scripts/decision-queue.sh update DQ-bcd900b8-... \
  --field state=moot \
  --field answer="Feature shipped without the deployment-target choice mattering."

# Edit the recommendation in-place (e.g., new info arrived).
~/.claude/scripts/decision-queue.sh update DQ-bcd900b8-... \
  --field recommendation="Reversed recommendation after the cold-init data came in: go with Lambda."
```

### `highlight` / `unhighlight` — visual emphasis

```bash
~/.claude/scripts/decision-queue.sh highlight DQ-bcd900b8-... \
  --reason "Blocks 8 other items in the alert-routing sequence" \
  --level strong

~/.claude/scripts/decision-queue.sh unhighlight DQ-bcd900b8-... \
  --reason "Misha unblocked the dependency this AM"
```

The actor (`by` field in `highlight_history`) is read from `$DQ_ACTOR` env var (default: `dispatch`). Set this when invoking from a specific identity:

```bash
DQ_ACTOR=harness-evaluator ~/.claude/scripts/decision-queue.sh highlight DQ-... \
  --reason "Aging past 14 days — drift risk" --level subtle
```

## Recommended `--reason` phrasings

Highlight reasons render verbatim in the Conv Tree panel. Write them as the human would read them, not as codes.

Good:
- `"Blocks 8 other items in the alert-routing sequence"`
- `"Aging past 14 days — drift risk"`
- `"Cascade from your reply on DQ-7c2a... — that answer made this one actionable"`
- `"Surfaced by daily harness evaluator — recommendation has 3 cross-references"`
- `"Customer launch Friday depends on this"`

Bad:
- `"DEP_COUNT=8"`
- `"AGED"`
- `"see logs"`
- `"important"` (empty signal)

## Exit codes

| Exit | Meaning |
|---|---|
| `0` | Success. For `add`, the new item's ID is on stdout. For `list`/`get`, the JSON is on stdout. For mutations, no stdout. |
| `1` | Failure. Error message on stderr. Common: not found, validation failed, unknown flag. |
| `2`+ | Reserved for future scripted failures. |

## Composition with other harness substrates

- **Backlog (`docs/backlog.md`)**: open work; decisions queue is asks-the-human-owes. Don't mirror items between them.
- **Findings ledger (`docs/findings.md`)**: class-aware observations with severity/scope/source/location/status. Observations may *trigger* a decision item, but the finding stays in the ledger.
- **Discoveries (`docs/discoveries/`)**: mid-process realizations needing a yes/no. Often the "irreversible-pause" branch of the discovery protocol = a decision queue item with mode=PICK or DEEP.
- **Session-end markers (`DONE:` / `PAUSING:` / `BLOCKED:`)**: per-session terminal-state markers. If the PAUSING reason is "user must decide X," the right move is to ALSO add a decision queue item so the ask survives session boundaries.

## Auto-emit to Conv Tree (deferred)

Today, `decision-queue.sh` operations do NOT auto-emit to the Conv Tree's event stream — `conversation-tree-emit.sh`'s tool-surface matrix is currently scoped to Dispatch spawn tools only (per ADR-031 r7 / ADR-034). Extending the matrix to include decision-queue operations is a follow-up; for now, Dispatch can manually note in chat ("added DQ-bcd... — see queue") if the operator wants tree-visible awareness before the Conv Tree Decisions panel ships.

## See also

- `docs/decisions/043-decision-queue-substrate.md` — substrate ADR (why this exists, alternatives rejected)
- `docs/conv-tree-decisions-panel-spec.md` — Conv Tree Decisions panel spec (the UI surface)
- `adapters/claude-code/schemas/decision-queue.schema.json` — item shape (single source of truth)
- `adapters/claude-code/scripts/decision-queue.sh` — the script (`--self-test` to verify)
