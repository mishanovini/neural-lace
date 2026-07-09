# backlog-escalation — one state machine, two deliverables

Fragment record for the change landed on `build/backlog-build-escalation-v2`
(continuing the crashed partial salvaged at `a49cdfc` on
`build/backlog-build-escalation`). Mirrors the splice-fragment convention
used by `tests/fixtures/wave-o/O.9/od-backlog-health-functions.md` — this is
a design + code + self-test record for future review/reference, not a
build artifact the code sources.

## The state machine

A backlog row (`docs/backlog.md`) moves through exactly one of three states,
enforced across two files that must agree with each other:

```
        undisposed, aging
   ┌─────────────────────────┐
   │  OPEN (fresh)            │  is_overdue:false, dispositioned_in_flight:false, terminal:false
   └───────────┬──────────────┘
               │ age > BACKLOG_TIER_{HIGH,MEDIUM,LOW}_DAYS (7/30/90)
               ▼
   ┌─────────────────────────┐
   │  OVERDUE (neutral nag)   │  is_overdue:true  -> feed_backlog_accountability's
   └───────────┬──────────────┘     4-way "SCHEDULE/FOLD/DEMOTE/WONTFIX" proposal
               │ fester_count >= BACKLOG_ESCALATION_DIGESTS (3)
               │   OR age > BACKLOG_ESCALATION_AGE_{HIGH,MEDIUM}_DAYS (14/60)
               ▼
   ┌─────────────────────────┐
   │  ESCALATED (build-now)   │  -> "backlog ESCALATED: <id> ... propose BUILD NOW"
   └───────────┬──────────────┘     dedup-exempt; recurs every digest until answered
               │ operator replies SCHEDULE/DEFERRED/DEMOTED/FOLDED
               ▼
   ┌─────────────────────────┐
   │  DISPOSITIONED-IN-FLIGHT │  dispositioned_in_flight:true, is_overdue:false,
   │  (answered, not done)    │  terminal:false -- suppressed from overdue_ids AND
   └───────────┬──────────────┘  from escalation; never re-nags
               │ the scheduled build actually MERGES and the row gets a
               │ real terminal marker (WONTFIX is answered-and-done in one step)
               ▼
   ┌─────────────────────────┐
   │  TERMINAL (done)         │  terminal:true -- DISPOSITIONED/IMPLEMENTED/ABSORBED/
   └─────────────────────────┘     CLOSED/SUPERSEDED/WONTFIX
```

**The invariant this encodes:** the disposition words
`feed_backlog_accountability` PROPOSES (`SCHEDULE` / `FOLD` / `DEMOTE` /
`WONTFIX`) must be a subset of the states `od_backlog_health` recognizes as
no-longer-awaiting-a-proposal (`TERM` ∪ `INFLIGHT`), or a row the operator
already answered re-nags forever. `WONTFIX` already lived in `TERM` before
this change; this change adds the `SCHEDULE`→`SCHEDULED` /
`FOLD`→`FOLDED`/`FOLD-INTO-*` / `DEMOTE`→`DEMOTED` mappings so the other
three proposal words also have a recognized in-flight landing state. A
`DEFERRED` marker (operator-authored, not a digest-proposed word) is
additionally recognized for the same reason — an operator can defer a row
without the digest ever having proposed exactly that word.

## Golden regression this closes

`GH-AUTH-AUTOSWITCH-WORKORG-01` (`docs/backlog.md`) festered 36 days
undisposed before the operator answered **SCHEDULED 2026-07-07**. Before
this fix, `od_backlog_health` had no `INFLIGHT` state — a SCHEDULED row kept
reading `terminal:false` / `is_overdue:true`, so `session-start-digest.sh`
re-proposed it every week despite the operator having already answered.
Live-asserted fixed (`BACKLOG_MD_PATH=docs/backlog.md`, real repo file, real
row, verification run only — no writes): `overdue_ids` no longer contains
it; `dispositioned_in_flight_total` includes it alongside two other real
rows (`RESUMER-SCHEDULED-EXIT1-01`, `HARNESS-GAP-48`) that were silently
suffering the same bug.

## Deliverable A — BUILD-ESCALATION tier (`session-start-digest.sh`)

`feed_backlog_accountability` (operator directive 2026-07-07: "more
proactive about resurfacing backlog items to actually be built"). Full
design rationale lives inline as a comment block immediately above the
function in `adapters/claude-code/hooks/session-start-digest.sh`.

Per-row fester count (reuses `_seen_lookup`/`_seen_bump`, key
`backlog-fester`, deliberately NOT isoweek-suffixed unlike the neutral
`backlog` key) increments every digest run a row is a live overdue
candidate. A row escalates the moment EITHER:
- `fester_count >= BACKLOG_ESCALATION_DIGESTS` (default 3), OR
- age crosses `BACKLOG_ESCALATION_AGE_HIGH_DAYS` (default 14, high
  priority) / `BACKLOG_ESCALATION_AGE_MEDIUM_DAYS` (default 60, medium
  priority). Low priority has no age hard-bound — fester count only.

**Config invariant (the actual bug this build fixed in the salvaged
partial):** each `BACKLOG_ESCALATION_AGE_*_DAYS` default MUST stay strictly
greater than its matching `BACKLOG_TIER_*_DAYS` (`observability-derive.sh`).
The salvaged commit had `BACKLOG_ESCALATION_AGE_MEDIUM_DAYS` default (30)
equal to `BACKLOG_TIER_MEDIUM_DAYS` (30) — a medium row hard-escalated the
INSTANT it became overdue, collapsing the neutral tier to nothing and
breaking pre-existing `S13a`/`S16b`/`S13c`/`S13c2`. Fixed to 60 (2x its
tier, mirroring the high tier's 7→14 ratio).

Escalated rows: lead with `backlog ESCALATED: <id> undisposed across N
digests, <age>d -> propose BUILD NOW: reply SCHEDULE (spawn builder) / or
DEMOTE / WONTFIX <reason>`; sort above neutral rows; are EXEMPT from the
weekly `seen.jsonl` dedup collapse (recur every digest — the whole point);
collapse to one summary line once escalated-row count exceeds
`BACKLOG_ESCALATION_SUMMARY_THRESHOLD` (default 2), naming only the oldest.

## Deliverable B — DISPOSITIONED-IN-FLIGHT (`observability-derive.sh`)

`od_backlog_health`'s row classifier gains a third branch (`INFLIGHT`
regex family — R1-R4, position-anchored exactly like the pre-existing
`TERM` regex family it sits beside) checked only when `!terminal`:

```js
var INFLIGHT = "(SCHEDULED|DEFERRED|DEMOTED|FOLDED|FOLD-INTO-[^*]+)";
var reInflightR1 = new RegExp("^- \\*\\*[^*]*\\b" + INFLIGHT + "\\b", "i");
var reInflightR2 = new RegExp("\\*\\*" + SP + "+(—|--?)" + SP + "+" + INFLIGHT + "\\b", "i");
var reInflightR3 = new RegExp("\\*\\*\\((scheduled|deferred|demoted|folded|fold-into[^)]*)\\b", "i");
var reInflightR4 = new RegExp("\\*\\*((PARTIALLY|LARGELY)" + SP + "+)?" + INFLIGHT + "\\b", "i");
```

Row facts gain `dispositioned_in_flight` (bool), `inflight_date`,
`inflight_epoch`. Summary gains `dispositioned_in_flight_total` and
`dispositioned_in_flight_ids`. A dispositioned-in-flight row: `is_overdue =
false` (forced), excluded from `open_total`/`priority_counts`/`age_tiers`,
excluded from `terminal_total` (it is NOT done), never enters `overdue_ids`.

See `adapters/claude-code/hooks/lib/observability-derive.sh` lines ~1547
onward (search `DISPOSITIONED-IN-FLIGHT`) for the full implementation and
inline design comment.

## Self-test coverage map

| Scenario | File | Asserts |
|---|---|---|
| S16a | session-start-digest.sh | high row, age hard-bound, escalates on 1st digest |
| S16b | session-start-digest.sh | medium row just over its overdue tier (31d) stays neutral (does NOT also cross the escalation hard bound) |
| S16c/S16d | session-start-digest.sh | fester-count trigger (3 digests) escalates; escalated rows recur same ISO week (dedup-exempt) |
| S16e | session-start-digest.sh | SCHEDULED-marked row is silent end-to-end (digest-level) |
| S16f | session-start-digest.sh | >threshold escalated rows collapse to one summary line |
| S16g | session-start-digest.sh | real flagless invocation (`bash session-start-digest.sh`, no flags) surfaces escalation |
| S13a/S13c/S13c2 | session-start-digest.sh | pre-existing neutral-proposal + cap/overflow/drain mechanics stay green (unaffected by escalation for low-priority / non-hard-bound rows) |
| Scenario 4b | observability-derive.sh | direct oracle-level: SCHEDULED row -> `dispositioned_in_flight:true`, `terminal:false`, absent from `overdue_ids` |

Live-asserted against the real `docs/backlog.md` (read-only) and the real
flagless digest entry point (`bash session-start-digest.sh`, isolated
`DIGEST_SEEN_PATH` so the verification run doesn't mutate production
fester-count/seen state) — see the build commit messages on
`build/backlog-build-escalation-v2` for the captured output.
