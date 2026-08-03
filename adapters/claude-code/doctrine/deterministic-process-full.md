# Deterministic process — full

This is the detail companion to `deterministic-process.md` (the compact, capped at 3000 bytes
by `evals/golden/rules-index-coverage.sh`). It holds the enforcement-status forensics, the
verification commands, and the self-referential history trimmed out of the compact on
2026-08-03 to bring it back under the cap. The compact's three rules and proof-obligation
summary stand alone; this file is the evidence trail behind them.

## Enforcement status — HYBRID, verify do not trust

**The proof obligation is now a Mechanism; the BACKFILL is not.**

WHAT EXISTS (verify, do not trust this line): `manifest.schema.json` defines both
`chokepoint` and `bypass_paths` as optional typed fields; and `harness-doctor.sh`'s
`check_deterministic_process_proof` REDs on any `"blocking": true` entry that is missing
EITHER field, unless it is on a dated, closed grandfather exempt-list or carries
`added_after < "2026-07"`. Re-derive rather than believe:

```
grep -c check_deterministic_process_proof adapters/claude-code/hooks/harness-doctor.sh
jq '.properties.entries.items.properties | has("chokepoint")' adapters/claude-code/schemas/manifest.schema.json
```

WHAT DOES NOT EXIST: the backfill. Of the 40 `blocking: true` units, only 2 are outside
the grandfather list, and the rest still declare neither field — they are exempted by a
DATED list that is meant to shrink to empty, not by having discharged the obligation.
Count it, do not quote this sentence:

```
jq -r '.entries[]|select(.blocking==true)|select((((.chokepoint//"")|length)==0) or (((.bypass_paths//[])|length)==0))|.id' adapters/claude-code/manifest.json | wc -l
```

Nor does a server-side check exist: every gate here is LOCAL, so `--no-verify` and a
web-UI merge remain open on all of them.

## Self-referential history

This file's own header (in the compact) has twice misstated its own enforcement status. The
FIRST version claimed the mechanism existed when it did not. The SECOND (the "NONE YET"
correction) stayed on the page after the mechanism actually landed, so the file spent a day
understating itself while asserting `manifest.schema.json` "would REJECT both keys" — false
the moment the schema was extended in the same commit that added the check. A doc that lies
in EITHER direction about its own enforcement is the defect this file names; the inverse
error is not the safe one, because a stale "not built" is exactly how a real control goes
unused. Tracked as `DETERMINISM-PROOF-OBLIGATION-UNBUILT-01` (docs/backlog.md), which closes
when the grandfather list reaches empty.

Operator directive 2026-07-30: "We should never need to review whether the reviewers fired.
Make them a deterministic part of the process."

## The proof obligation — full detail

**STATUS: SPECIFIED, NOT BUILT** (see enforcement status above — most blocking units carry
neither field yet; the backfill is the open work). This is the obligation the standard
*requires*, written down so the gap is visible and closable, NOT a description of what runs
today.

Every `"blocking": true` manifest unit declares:
- `chokepoint` — the firing event, in verifiable form (`pre-push`, `Stop`, …).
- `bypass_paths` — every known route to the outcome that skips it, each CLOSED
  (with how) or NAMED-AND-ACCEPTED (with why). An empty list claims none exist
  and is a lie unless someone enumerated them.

Prefer MECHANICAL enumeration to careful reading — producer/consumer scanning
(`scripts/config-control-producer-scan.sh`: finds a consumed lever with zero
producers, rule 3's failure mode as a grep) and call-graph reachability. A
reading is done by a mind that may hold the assumption that produced the gap.

A gate at the wrong layer, a waiver anyone can write, and a step nobody invokes
all look like enforcement in the inventory and deliver none at runtime. That is
§10 theatre; this file is its positive statement: **do not ask whether the
process ran — build it so it could not have been skipped.**
