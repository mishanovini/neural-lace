# Plan: needs-you.sh ledger-corruption hotfix (validity-guard sweep + 3-state inbox contract)
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: This plan's file set is a harness state-file init class-fix (needs-you.sh, decision-queue.sh, the new shared scripts/lib/state-json-init.sh — self-test IS the demonstration, no live user beyond the maintainer) plus a backend-only JSON contract hardening in inbox-routes.js with no UI change (the rendering consumer of this contract is a sibling builder's separately-tracked work under the same incident response, out of this plan's file scope — see Scope OUT below). inbox-routes.selftest.js's 32/0 pass is the demonstration for the server half.
tier: 2
rung: 2
architecture: hybrid
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-29
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal
Fix the class of bug behind the 2026-07-27 incident: `~/.claude/state/needs-you/ledger.json`
(the canonical "what is waiting on the operator" ledger) sat as a 1-byte file
containing a single newline for roughly two days. `GET /api/inbox` returned
`{"ok":false,"error":"ledger.json is not valid JSON: Unexpected end of JSON
input"}` the entire time, while the cockpit's landing surface rendered it as
a confident "nothing on your list" beside `Inbox (—)`. Root cause #1:
needs-you.sh's own lazy-init guard (`_ny_ensure_state`) tested EXISTENCE only
(`[[ -f "$f" ]] ||`), so once the file existed-but-was-invalid the guard
never fired again and every subsequent `jq` read failed forever. Root cause
#2 (the truncating writer, reproduced byte-for-byte): `cmd_add`'s jq call
used `--args -- "${links[@]}"` with no guard; under `set -u`, bash <4.4 —
including macOS's shipped `/bin/bash` 3.2.57, this repo's portability floor
— treats expanding a zero-element array as an unbound-variable reference and
aborts the command substitution, leaving `$new` empty; the unconditional
`_ny_write_ledger "$new"` then wrote a 1-byte `"\n"` over the real ledger.
`add` is called without `--link` far more often than with, so this fired on
nearly every real invocation run under plain `/bin/bash`. This plan installs
a shared validity-guarded state-file initializer, fixes the truncating
writer, adds a content-validity backstop on every ledger write, applies the
same class-fix to decision-queue.sh's twin `queue.json` init (found by the
harness-wide grep this incident's postmortem asked for), and hardens
inbox-routes.js's read contract so a corrupt/wrong-shape ledger is never
silently reported as a confirmed "zero items."

## User-facing Outcome
For the maintainer (needs-you.sh/decision-queue.sh are harness-internal —
the `--self-test` suites passing on BOTH `/bin/bash` 3.2.57 and Homebrew
bash 5.3.15 IS the demonstration): a corrupt or truncated `ledger.json`/
`queue.json` is now auto-recovered on the next touch (existing bytes
salvaged to a `.corrupt-<date>.bak` file, loud stderr notice, then a fresh
valid skeleton) instead of staying silently broken forever, and the
class-level truncating-writer bug (any `add` invoked under `/bin/bash`
without `--link`) no longer corrupts the ledger at all. For the cockpit's
`/api/inbox` consumer (this plan's server-side half only — see Scope OUT):
the JSON payload now carries an explicit `status` field distinguishing a
CONFIRMED zero (`'ok'`, ledger read + trusted + genuinely empty) from
`'not_yet_derived'` (ledger never created) from `'unavailable'` (ledger
present but untrustworthy) — never again silently coercing a broken ledger
into what looks like a confirmed-empty inbox.

## Scope
- IN: `adapters/claude-code/scripts/needs-you.sh` (validity-guarded
  `_ny_ensure_state`, the bash-3.2 array-expansion fix in `cmd_add`, a
  content-validity backstop on `_ny_write_ledger`, matching self-test
  scenarios T32-T35); `adapters/claude-code/scripts/decision-queue.sh` (the
  same class-fix applied to `ensure_state_dir`/`write_queue`, self-test
  scenarios T19-T21, plus an incidental fix to T17's `set -e` leak that the
  new T21 mutation-testing surfaced); the new shared helper
  `adapters/claude-code/scripts/lib/state-json-init.sh`
  (`nl_state_json_ensure`); `neural-lace/workstreams-ui/server/inbox-routes.js`
  + `inbox-routes.selftest.js` (the three-state read/response contract,
  scenarios S8b/S9b/S11-S14).
- OUT (sibling builders, same incident response, tracked separately — NOT
  this plan's files): `adapters/claude-code/scripts/ensure-cockpit.sh` (a
  second, independently-owned builder's file); everything under
  `neural-lace/workstreams-ui/web/**` and `cockpit.selftest.js` (the
  renderer half that CONSUMES the new `status` field this plan adds —
  explicitly out of scope per this task's own dispatch, reconciled by the
  orchestrator); a pre-existing, unrelated self-test failure in
  needs-you.sh's `cmd_bootstrap_migrate` (T18b/T18c/T19 legacy-content
  migration, confirmed present before AND after this change on both
  interpreters) — flagged as a separate follow-up, not fixed here since it
  is a different bug in a different code path; any OTHER JSON-state-file
  init pattern found during the sweep that turned out to be either a
  self-test fixture (harmless, recreated fresh every run — e.g.
  spec-freeze-gate.sh's `echo "stub" > "$target_full"`) or a fully-rebuilt-
  every-time derived index (e.g. write-review-record.sh's
  `_rrg_rebuild_index`, which recomputes from source files every call and
  is never a "create once, trust forever" pattern) — verified NOT the same
  bug class, deliberately left untouched.

## Tasks

- [ ] 1. Add `adapters/claude-code/scripts/lib/state-json-init.sh` (shared `nl_state_json_ensure` helper: re-init on absent OR invalid content, salvage-before-reset to a `.corrupt-<date>.bak`, atomic tmp+mv write) and wire it into `needs-you.sh`'s `_ny_ensure_state` and `decision-queue.sh`'s `ensure_state_dir`, replacing both existence-only guards — Verification: full — Docs impact: none (self-documenting header comments in the new lib + inline comments at each call site)
  - **Prove it works:** write a ledger/queue file containing exactly `"\n"` (the incident's exact byte sequence) into a sandboxed state dir; call `cmd_render`/`ensure_state_dir`; confirm the file is valid JSON afterward, a `.corrupt-<date>.bak` sibling exists with the ORIGINAL 1-byte content, and a stderr notice was printed.
  - **Wire checks:** `needs-you.sh`'s `_ny_ensure_state` → `nl_state_json_ensure` (`scripts/lib/state-json-init.sh`) → `_nl_sji_write_default`; `decision-queue.sh`'s `ensure_state_dir` → `nl_state_json_ensure` (same shared lib).
  - **Integration points:** none external — pure filesystem/jq; verified via `bash adapters/claude-code/scripts/needs-you.sh --self-test` and `bash adapters/claude-code/scripts/decision-queue.sh --self-test` (scenarios T32-T35 / T19-T21).
- [ ] 2. Fix the truncating-writer root cause in `needs-you.sh`'s `cmd_add` (`--args -- "${links[@]}"` → the bash-3.2-safe `${links[@]+"${links[@]}"}` idiom) and add a content-validity backstop to `_ny_write_ledger`/`decision-queue.sh`'s `write_queue` (refuse to ever commit empty/non-JSON content) — Verification: full — Docs impact: none
  - **Prove it works:** run `/bin/bash adapters/claude-code/scripts/needs-you.sh add --section question --text "..." --session sess-x` (zero `--link` flags, the common case) against a sandboxed `NEEDS_YOU_STATE_DIR`; confirm `ledger.json` is valid JSON containing the new item afterward, on the REAL `/bin/bash` 3.2.57 (not whatever bash happens to be first on PATH).
  - **Wire checks:** `cmd_add` (`needs-you.sh`) → `_ny_write_ledger` (same file, content-validity guard) → atomic tmp+mv.
  - **Integration points:** none external; verified via T34 (bash-3.2 regression, explicit `/bin/bash` invocation) and T35 (write-safety backstop) in `needs-you.sh --self-test`.
- [ ] 3. Harden `neural-lace/workstreams-ui/server/inbox-routes.js`'s ledger read contract to a three-state discriminant (`status: 'ok' | 'not_yet_derived' | 'unavailable'`), including shape validation (a valid-JSON-but-wrong-shape document like top-level `null`/`{}` used to silently coerce to a confirmed-looking `[]`) — Verification: full — Docs impact: inline header comment on `readNeedsYouLedgerItems`/`buildInboxPayload` documenting the contract (no external doc surface for this backend-only route)
  - **Prove it works:** `node server/inbox-routes.selftest.js` — S12 writes the exact incident fixture (`"\n"`) and confirms `status:'unavailable'`; S11 confirms a valid-but-empty ledger reports `status:'ok'` (a CONFIRMED zero, not "unknown"); S13/S13b/S13c confirm wrong-shape-but-valid JSON is also `'unavailable'`, never a silent zero.
  - **Wire checks:** `handle()` (`/api/inbox` GET) → `buildInboxPayload` → `readNeedsYouLedgerItems` (same file) → `LedgerUnavailableError` (same file, thrown on any untrustworthy shape).
  - **Integration points:** `GET /api/inbox` HTTP contract — verified via real HTTP requests against the mounted handler in `inbox-routes.selftest.js` (S1-S14), not just a unit call to `buildInboxPayload`.

## Files to Modify/Create
- `adapters/claude-code/scripts/needs-you.sh` — validity-guarded `_ny_ensure_state`, bash-3.2 array fix in `cmd_add`, `_ny_write_ledger` content-validity backstop, T32-T35 self-test scenarios
- `adapters/claude-code/scripts/decision-queue.sh` — validity-guarded `ensure_state_dir`, `write_queue` content-validity backstop, T17 `set -e` leak fix, T19-T21 self-test scenarios
- `adapters/claude-code/scripts/lib/state-json-init.sh` — NEW shared helper (`nl_state_json_ensure`)
- `neural-lace/workstreams-ui/server/inbox-routes.js` — three-state read/response contract, `LedgerUnavailableError`
- `neural-lace/workstreams-ui/server/inbox-routes.selftest.js` — S8b/S9b/S11-S14 new scenarios

## In-flight scope updates
n/a — plan created frozen at birth (see Decisions Log); the investigation
and fix were complete before this plan file existed, matching the
established hotfix convention (see docs/plans/ps51-emdash-parse-hotfix.md's
own "plan created frozen: true at birth" precedent).

## Assumptions
- macOS's shipped `/bin/bash` (3.2.57) is this repo's binding portability
  floor for every harness script with a `#!/bin/bash` shebang — verified
  (`/bin/bash --version`) and independently reconfirmed by direct
  reproduction of the truncating-writer bug under it.
- jq is a hard dependency of both `needs-you.sh` and `decision-queue.sh`
  already (pre-existing `command -v jq` checks); the shared
  `state-json-init.sh` helper inherits that same hard dependency rather
  than adding a new one.
- The cockpit renderer (`web/**`, a sibling builder's file, out of this
  plan's scope) will consume the new `status` field this plan adds to
  `/api/inbox`'s response; this plan does not and cannot verify that
  consumption since it never touches `web/**`.
- `jq empty`'s vacuous-success-on-whitespace-only-input behavior (verified:
  `printf '\n' | jq empty` exits 0) is jq's documented streaming-parser
  semantics, not a version-specific quirk — the fix uses `jq -e 'type'`
  instead, verified to correctly reject empty/whitespace input (exit 4) and
  malformed input (exit 5) while still accepting every legitimate JSON
  value including top-level `false`/`null`.

## Edge Cases
- Two corruption events on the same calendar day: `nl_state_json_ensure`
  appends a numeric suffix (`.corrupt-<date>-2.bak`, `-3.bak`, ...) rather
  than overwriting a same-day backup — verified by the helper's collision
  loop (not separately self-tested by name, but exercised implicitly by
  running T32 twice in sequence during development).
- A ledger that is valid JSON but has the WRONG top-level shape (`null`,
  `{}`, `{"items":"not-an-array"}`) — previously silently coerced to `[]`
  (a false "confirmed zero"); now explicitly classified `unavailable` (S13/
  S13b/S13c).
- A healthy, valid, pre-existing ledger must NEVER be touched by the
  recovery path (no spurious backup, no unnecessary rewrite) — verified by
  needs-you.sh's T33 and decision-queue.sh's T20.
- `cmd_expire`/`cmd_resolve` (needs-you.sh) and every `write_queue` caller
  (decision-queue.sh) now route through the SAME content-validity backstop
  as `cmd_add`, so a jq failure in any of those paths (not just the
  reproduced `cmd_add` bug) is also caught rather than silently corrupting
  the ledger — each caller's failure-handling contract is preserved
  (`cmd_add`/`cmd_resolve` `die`/return 1 loudly; `cmd_expire` stays
  best-effort per its own "Exit 0 always" documented contract, skipping the
  pass rather than either dying or corrupting).
- A pre-existing, UNRELATED self-test failure in needs-you.sh's
  `cmd_bootstrap_migrate` (T18b/T18c/T19) was discovered while validating
  this fix — confirmed present on both interpreters BEFORE this plan's
  changes too (via `git stash`), so it is not a regression introduced here;
  flagged as a separate follow-up (see Scope OUT) rather than silently
  fixed or silently ignored.

## Testing Strategy
- `needs-you.sh --self-test`, run under BOTH `/bin/bash` (3.2.57) and
  Homebrew bash (5.3.15) explicitly by absolute path (never a bare `bash`,
  which would silently resolve to whichever interpreter is first on PATH
  and could skip the exact interpreter a regression targets): 43/3 → 51/3
  on both (the persisting 3 are the pre-existing, unrelated
  bootstrap-migrate bug above).
- `decision-queue.sh --self-test`, same both-interpreters discipline:
  18/0 → 23/0 on both.
- `node server/inbox-routes.selftest.js`: 23/0 → 32/0.
- Every new scenario mutation-tested: the specific line(s) it covers were
  reverted and the suite re-run to confirm a RED failure attributable to
  the right behavioral reason (not a string match) — done for T32/T33/T34/
  T35 (needs-you.sh), T19/T21 (decision-queue.sh), and a full-file revert
  of inbox-routes.js (confirming exactly S8b/S9b/S11/S12/S12b/S13/S13b/
  S13c/S14 go red, 23/9, with every pre-existing scenario staying green).
  Transcripts captured during the build session.

Walking Skeleton: n/a — this is a bug-fix sweep over existing, already-wired
production code paths (state-file init guards, a jq write function, an HTTP
route handler), not a new integration requiring a first end-to-end slice.

## Acceptance Scenarios
n/a — acceptance-exempt (see header). needs-you.sh/decision-queue.sh are
harness-internal (`--self-test` IS the demonstration per constitution §4's
own harness-work carve-out); inbox-routes.js is a backend-only contract
change with no UI consumer in this plan's file scope (the consumer is a
sibling builder's separately-tracked work) — `inbox-routes.selftest.js`'s
real-HTTP-request-driven 32/0 pass is the demonstration for that half.

## Out-of-scope scenarios
- Verifying the cockpit UI actually renders the three `status` values
  distinctly (three different visual states) — that is the sibling
  `web/**` builder's scope, reconciled by the orchestrator across both
  builders' work, not testable from this plan's files alone.
- Fixing the pre-existing `cmd_bootstrap_migrate` self-test failures
  (T18b/T18c/T19) — a different bug in a different code path, flagged as a
  follow-up rather than silently absorbed into this plan's scope.
- Auditing every OTHER script in the harness for unrelated defects beyond
  the specific "existence-only JSON state-file init guard" pattern this
  incident's postmortem asked for — the sweep was scoped to that one
  pattern class, not a general code-quality audit.

## Closure Contract
- **Commands that run:** `/bin/bash adapters/claude-code/scripts/needs-you.sh --self-test`; `/opt/homebrew/opt/bash/bin/bash adapters/claude-code/scripts/needs-you.sh --self-test`; the same pair for `decision-queue.sh`; `node neural-lace/workstreams-ui/server/inbox-routes.selftest.js`.
- **Expected outputs:** `RESULT: 51 passed, 3 failed` (needs-you.sh, both interpreters, the 3 being the pre-existing unrelated bootstrap-migrate bug); `RESULT: 23 passed, 0 failed` (decision-queue.sh, both interpreters); `inbox-routes self-test: 32 passed, 0 failed`.
- **On-disk artifact location:** this plan file's own completion report (appended below at closure) plus the git commit history on this branch.
- **Done when:** all three tasks' checkboxes are flipped per their `Verification: full` sub-blocks AND the four self-test commands above all match their expected outputs AND the fix commit(s) land on this branch.

## Decisions Log
- 2026-07-29 (decide-and-go, constitution §8 — reversible): plan created
  `frozen: true` at birth — the investigation, fix, and self-tests were
  already complete before this plan file existed (same shape as
  docs/plans/ps51-emdash-parse-hotfix.md's own precedent), because
  `scope-enforcement-gate.sh` requires an ACTIVE plan declaring the staged
  files' scope before any commit can land and none existed for this
  incident-response dispatch. No thaw needed.
- 2026-07-29 (decide-and-go, reversible): extended the sweep to
  `decision-queue.sh`'s `queue.json` init (not originally named in the
  dispatch, which only named `needs-you.sh`'s two suspected call sites) —
  the dispatch explicitly asked for a harness-wide grep of the existence-
  only-guard pattern and to "fix every instance you find, not just these
  two," and `decision-queue.sh`'s `ensure_state_dir` was the one other
  production (non-self-test-fixture, non-fully-rebuilt-every-time) instance
  found. `ensure-cockpit.sh` and `web/**` were explicitly excluded per the
  dispatch (owned by sibling builders).
- 2026-07-29 (decide-and-go, reversible): fixed decision-queue.sh's T17
  `set -e`/`set +e` leak (T17 left errexit permanently enabled for every
  later self-test scenario — a bug, not a restore, since this script never
  sets `-e` anywhere else) in the same commit rather than filing it
  separately, because it directly threatened the correctness of this
  plan's own new T19-T21 scenarios (a mutation-testing run against T21
  silently crashed the whole self-test instead of reporting a clean FAIL,
  which this leak caused).
- 2026-07-29 (decide-and-go, reversible): removed an initially-added
  explicit `!raw.trim()` empty/whitespace check in
  `inbox-routes.js:readNeedsYouLedgerItems` after mutation-testing proved
  it was NOT independently load-bearing — `JSON.parse('')`/`JSON.parse('\n')`
  already throw natively in every JS engine (unlike bash's `jq empty`,
  which has a real vacuous-success trap on the same input shape) — kept
  the code honest about what is genuinely new (the shape-validation check)
  versus what was already covered by JSON.parse's own strictness.

## Definition of Done
- [ ] All 3 tasks checked off
- [ ] All tests pass on both bash interpreters + node (see Closure Contract expected outputs)
- [ ] Linting/formatting clean (no syntax errors — `bash -n`/`node -c` clean on all 5 touched/created files)
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
