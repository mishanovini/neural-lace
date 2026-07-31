# E.3 doctor predicate — waiver-density alarm

Per `docs/plans/nl-overhaul-program-2026-07-specs-e.md` §E.0.1 rule 3: the
E.3 builder does NOT edit `harness-doctor.sh` directly; this fragment is the
exact predicate for the E.10 builder to implement verbatim.

## Predicate 1 — script exists + executable

```bash
test -f "$REPO_ROOT/adapters/claude-code/scripts/waiver-density.sh" && \
test -x "$REPO_ROOT/adapters/claude-code/scripts/waiver-density.sh"
```

- **RED condition:** file missing, OR present but not executable
  (`test -x` false — on a fresh checkout before `chmod +x` runs, or if a
  future edit accidentally drops the exec bit).
- **GREEN when:** both conditions true.
- **Fixture for a synthetic RED:** copy the script to a scratch path and
  `chmod -x` it; predicate must report RED against that copy.
  ```bash
  cp "$REPO_ROOT/adapters/claude-code/scripts/waiver-density.sh" /tmp/wd-red-fixture.sh
  chmod -x /tmp/wd-red-fixture.sh
  test -x /tmp/wd-red-fixture.sh && echo "unexpected GREEN" || echo "RED confirmed"
  ```

## Predicate 2 — digest wiring grep

The doctor should confirm E.1's `session-start-digest.sh` actually calls
into the waiver-density digest feed (a script existing but never wired is a
silent no-op — the class of defect this predicate exists to catch). As of
this fragment's authoring, `session-start-digest.sh`'s `feed_waiver_density()`
ALREADY contains this exact call (built at E.1, ahead of this task landing —
see that hook's header comment, feed 11), so this predicate should be GREEN
on the live tree the moment E.3 merges; it exists to catch REGRESSION
(the wiring line silently dropped by a later edit), not to gate E.3's own
first landing.

```bash
grep -q "waiver-density.sh" "$REPO_ROOT/adapters/claude-code/hooks/session-start-digest.sh" 2>/dev/null
```

- **RED condition:** `session-start-digest.sh` exists but does NOT
  reference `waiver-density.sh` anywhere (grep exit 1) — i.e., the wiring
  was silently dropped by a later edit.
- **GREEN when:** grep exit 0 (the digest hook's source references the
  script by name — the exact call shape,
  `bash "$cwd/scripts/waiver-density.sh" --digest-line`, is E.1's contract;
  this predicate only checks the wiring line is present, not its exact
  arguments).
- **Absence tolerance:** if `session-start-digest.sh` does not exist yet on
  some other branch/checkout state, this predicate must not fire RED for a
  missing FILE — that is E.1's own doctor predicate's concern. This
  predicate is scoped to "the digest hook exists AND fails to mention
  waiver-density.sh."
  ```bash
  if [[ -f "$REPO_ROOT/adapters/claude-code/hooks/session-start-digest.sh" ]]; then
    grep -q "waiver-density.sh" "$REPO_ROOT/adapters/claude-code/hooks/session-start-digest.sh" \
      || echo "RED: digest exists but does not wire waiver-density.sh"
  fi
  ```
- **Fixture for a synthetic RED:** write a scratch copy of the digest hook
  with the `waiver-density.sh` line stripped; predicate must report RED
  against that copy, GREEN against the real file.

## Predicate 3 — ADR 059 D7 auto-demotion boundary (informational, not RED/GREEN gated)

This predicate exists to catch scope creep in the OPPOSITE direction from
predicates 1/2: waiver-density.sh must NEVER WRITE to `manifest.json` (that
auto-demotion mechanism is task F.5, explicitly out of scope here per the
spec). A future accidental edit of manifest.json by this script would be a
silent, hard-to-notice escalation of a detect-and-file tool into an
auto-mutating one. NOTE: the script's own header comment textually MENTIONS
"manifest.json" (prose explaining this exact scope boundary), so the
predicate must grep for a WRITE pattern, not any mention of the filename, or
it self-triggers a false RED against its own documentation.

```bash
! grep -E -q '>[^>]*manifest\.json|sed\s+-i[^|]*manifest\.json' \
  "$REPO_ROOT/adapters/claude-code/scripts/waiver-density.sh"
```

- **RED condition:** the script contains a shell redirect (`>`/`>>`),
  in-place `sed -i`, or `jq ... >` pattern targeting a path ending in
  `manifest.json` — a signal that ADR 059 D7 auto-demotion logic (F.5's job)
  has been pulled forward into this task's script without the F.5 review
  that scope requires.
- **GREEN when:** no write pattern found (grep exit 1, negated to 0 by the
  `!`) — textual mentions of "manifest.json" in comments/prose (as in this
  script's own header, explaining the boundary) do NOT trigger RED.
- **Fixture for a synthetic RED:** append a line like
  `echo '{}' > "$REPO_ROOT/adapters/claude-code/manifest.json"` to a scratch
  copy of the script; predicate must report RED against that copy, GREEN
  against the real file. Verified at authoring time on both cases: the real
  script greps clean (exit 1, despite its header prose mentioning
  "manifest.json" twice with no `>`/`sed -i` on those lines) and a
  fixture copy with the write line appended greps RED (exit 0).

## Predicate 4 (informational, not RED/GREEN gated) — manifest entry present

`manifest-entry.json` in this directory is the fragment E.10 merges into
`adapters/claude-code/manifest.json` at §E.W. Once merged,
`manifest-check.sh` (existing tool) is the freshness oracle for "does the
manifest know about this surface" — no NEW doctor logic needed for that
half; only predicates 1-3 above are E.3-specific additions to
`harness-doctor.sh --full`.

## Consumption contract (for E.1 / E.5 builders and reviewers)

This is the exact interface `waiver-density.sh` exposes to its two
consumers, restated here so E.10 (doctor), and anyone reviewing E.1/E.5's
wiring, can verify against a single source of truth without re-reading the
script:

- **E.1 (`session-start-digest.sh`) consumes:**
  `bash "$cwd/scripts/waiver-density.sh" --digest-line`
  (already implemented in `feed_waiver_density()`, feed 11 — see that hook's
  header comment).
  - Prints NOTHING if no gate's trailing-7-day waiver count is >= the alarm
    threshold (default 3) — tolerate-absent / quiet-feed contract. E.1 takes
    the first line of stdout verbatim.
  - Otherwise prints exactly one line:
    `waiver-density: <gate> <N> waivers/7d -> fix-or-retire item filed`
    for the single gate with the HIGHEST in-window waiver count (ties broken
    alphabetically by gate name).
  - Side effect (not on stdout): for EVERY gate at/above threshold (not just
    the reported max), idempotently appends a
    `WAIVER-DENSITY-<GATE>-<yyyymmdd>` entry to `docs/backlog.md` (resolved
    via `hooks/lib/nl-paths.sh`'s `nl_repo_root()`; override via
    `WAIVER_DENSITY_BACKLOG_PATH` for sandboxing). Idempotent per gate per
    calendar day (grep for the exact ID before appending).

- **E.5 (`harness-kpis.sh`) consumes:**
  `bash scripts/waiver-density.sh --report` — a read-only markdown table of
  EVERY gate with >=1 waiver in the trailing 7-day window (gate name,
  waivers/7d count, over-threshold YES/no), sorted by count descending. This
  mode performs NO backlog side effect (safe to call repeatedly / on a
  read-only reporting cadence). E.5 is expected to embed this table verbatim
  in its own KPI report's waiver-density section.

- **Sandboxing env vars (self-tests / E.1 / E.5's own `--self-test` fixtures
  should use these, never the real machine state):**
  - `SIGNAL_LEDGER_PATH` — overrides the ledger file location (same variable
    `lib/signal-ledger.sh` and every ledger writer already uses — this
    script shares that exact resolution, never introduces a second env var
    for the same file).
  - `WAIVER_DENSITY_BACKLOG_PATH` — overrides the escalation-append backlog
    file.
  - `HARNESS_SELFTEST=1` — if neither override above is set, routes the
    ledger read to `${TMPDIR:-/tmp}/signal-ledger-selftest/<pid>.jsonl`
    automatically (delegates to `lib/signal-ledger.sh`'s own
    `_signal_ledger_path` when sourced, so this script and every ledger
    writer can never disagree about "the ledger").
  - `WAIVER_DENSITY_THRESHOLD` (default 3) / `WAIVER_DENSITY_WINDOW_DAYS`
    (default 7) — override the alarm threshold / window size, primarily for
    self-test scenarios that want a different boundary without waiting real
    wall-clock days.

## Scope boundary (restated per the spec)

ADR 059 D7 auto-DEMOTION (a manifest.json `blocking:true` -> `false` flip
once a gate crosses its own waiver threshold) is explicitly OUT OF SCOPE for
this script — that lands at task F.5. `waiver-density.sh` only detects
(reads the ledger) and files (appends a backlog entry); it never edits
`manifest.json` or any gate's blocking behavior. Predicate 3 above is the
mechanical tripwire for this boundary.
