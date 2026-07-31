# O.5 manifest amendments (for the orchestrator integration pass)

Per §O.0.1, `manifest.json` is ORCHESTRATOR-ONLY. This fragment is the complete,
schema-valid entry for the new ntfy-push surfacer, for the orchestrator to fold in
(`adapters/claude-code/schemas/manifest.schema.json` validated).

## New entry — `ntfy-push`

`kind: surfacer` (read-only informational output — a push notification — at a
lifecycle boundary; it never blocks or gates anything, matching `writer`/`surfacer`
semantics rather than `gate`). `doctrine_file: null` — no dedicated doctrine compact
for this task; the design sketch (`docs/reviews/2026-07-04-observability-design-
sketch.md`) and this task's own header comment in `scripts/ntfy-push.sh` are the
authoritative source; if the orchestrator prefers a doctrine surface, folding a
"push rules" section into the O.3-authored `doctrine/observability.md` (§O.3
deliverable 1) is the natural home — left to orchestrator judgment, not asserted
here.

```json
{
  "id": "ntfy-push",
  "kind": "surfacer",
  "doctrine_file": null,
  "hooks": [],
  "events": [
    "manual"
  ],
  "wired_template": false,
  "selftest": true,
  "jit_triggers": {
    "paths": [
      "adapters/claude-code/scripts/ntfy-push.sh"
    ],
    "keywords": []
  },
  "blocking": false,
  "budget_class": "none",
  "added_after": "2026-07",
  "golden_scenario": "Operator misses a new NEEDS-YOU entry, a session stalling out unattended for hours, or a doctor RED regression because nothing interrupts them outside the terminal — the 2026-07-04 design sketch's push surface exists to close exactly this gap for the three classes the operator actually wants an interrupt for.",
  "fp_expectation": "Near-zero: push only fires for a genuinely NEW item-id per class (deduped forever via sent.jsonl) and only once a real ntfy topic is configured; an unknown --class is rejected before any network attempt (self-tested negative) so no other event type can ever reach this channel. Legitimate no-push cases (topic not yet configured, no new items, doctor staying green) are silent — never a false push.",
  "retirement_condition": "Retire or fold into a broader alerting mechanism if the operator reports push volume becoming noise (more than a few pushes/week outside genuine incidents), or if the O.4 cockpit's own visibility make phone push redundant for all three classes per the O.7 retro's operator-trust check.",
  "honesty_rationale": "Not a gate — a best-effort external notification writer. `send`/`scan` never block or fail any caller (needs-you.sh's call site is fire-and-forget; the scheduled scan tick's own exit code is not consumed by anything blocking)."
}
```

Note on `hooks: []` / `wired_template: false` / `budget_class: none`: this is a
standalone script (`scripts/ntfy-push.sh`), not a `hooks/*.sh` hook — it is invoked
(a) directly by `needs-you.sh add`'s guarded call, and (b) on a schedule via the
per-machine tick wrapper `.cmd` (see `scan-tick-wiring.md` in this same fixture
directory), never through `settings.json.template`. `events: ["manual"]` reflects
that both call sites are script-to-script invocations, not a Claude Code hook event.

## Existing entry to note (no change needed, cross-reference only)

`needs-you.sh` is covered by the pre-existing `needs-you-ledger` (or equivalently-
named) manifest entry from Wave E task E.6 — this task only adds a call site inside
`cmd_add`, it does not change that entry's `hooks`/`events`/`selftest` shape (the
guarded push call is fully internal to `needs-you.sh add`'s existing self-test
coverage; no new entry needed for it).
