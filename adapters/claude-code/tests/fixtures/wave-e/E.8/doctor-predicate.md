# E.8 doctor predicate — nl-issue capture loop

Per `docs/plans/nl-overhaul-program-2026-07-specs-e.md` §E.0.1 rule 3: the
E.8 builder does NOT edit `harness-doctor.sh` directly; this fragment is the
exact predicate for the E.10 builder to implement verbatim.

## Predicate 1 — capture script exists + executable

```bash
test -f "$REPO_ROOT/adapters/claude-code/scripts/nl-issue.sh" && \
test -x "$REPO_ROOT/adapters/claude-code/scripts/nl-issue.sh"
```

- **RED condition:** file missing, OR present but not executable
  (`test -x` false — on a fresh checkout before `chmod +x` runs, or if a
  future edit accidentally drops the exec bit).
- **GREEN when:** both conditions true.
- **Fixture for a synthetic RED:** copy the script to a scratch path and
  `chmod -x` it; predicate must report RED against that copy.
  ```bash
  cp "$REPO_ROOT/adapters/claude-code/scripts/nl-issue.sh" /tmp/nli-red-fixture.sh
  chmod -x /tmp/nli-red-fixture.sh
  test -x /tmp/nli-red-fixture.sh && echo "unexpected GREEN" || echo "RED confirmed"
  ```

## Predicate 2 — digest wiring grep

The doctor should confirm E.1's `session-start-digest.sh` actually calls
into the nl-issue digest feed (a script existing but never wired is a
silent no-op, the class of defect this predicate exists to catch).

```bash
grep -q "nl-issue.sh" "$REPO_ROOT/adapters/claude-code/hooks/session-start-digest.sh" 2>/dev/null
```

- **RED condition:** `session-start-digest.sh` exists but does NOT
  reference `nl-issue.sh` anywhere (grep exit 1) — i.e., E.1 shipped without
  wiring this feed in, or a later edit silently dropped the call.
- **GREEN when:** grep exit 0 (the digest hook's source references the
  script by name — the exact call shape, e.g. `nl-issue.sh --digest-feed`
  vs some other invocation, is E.1's contract; this predicate only checks
  the wiring line is present, not its exact arguments).
- **Absence tolerance:** if `session-start-digest.sh` does not exist yet
  (e.g. doctor run before E.1 merges), this predicate must not fire RED for
  a missing FILE — that is a different, pre-existing "digest hook not yet
  built" condition tracked by E.1's own doctor predicate. This predicate is
  scoped to "the digest hook exists AND fails to mention nl-issue.sh."
  ```bash
  if [[ -f "$REPO_ROOT/adapters/claude-code/hooks/session-start-digest.sh" ]]; then
    grep -q "nl-issue.sh" "$REPO_ROOT/adapters/claude-code/hooks/session-start-digest.sh" \
      || echo "RED: digest exists but does not wire nl-issue.sh"
  fi
  ```
- **Fixture for a synthetic RED:** write a scratch copy of the digest hook
  with the `nl-issue.sh` line stripped; predicate must report RED against
  that copy, GREEN against the real file once E.1/E.W wiring lands.

## Predicate 3 (informational, not RED/GREEN gated) — manifest entry present

`manifest-entry.json` in this directory is the fragment E.10 merges into
`adapters/claude-code/manifest.json` at §E.W. Once merged, `manifest-check.sh`
(existing tool) is the freshness oracle for "does the manifest know about
this surface" — no NEW doctor logic needed for that half; only predicates 1
and 2 above are E.8-specific additions to `harness-doctor.sh --full`.

## Consumption contract (for E.1 / E.5 builders and reviewers)

This is the exact interface `nl-issue.sh` exposes to its two consumers,
restated here so E.10 (doctor), and anyone reviewing E.1/E.5's wiring, can
verify against a single source of truth without re-reading the script:

- **E.1 (`session-start-digest.sh`) consumes:**
  `bash ~/.claude/scripts/nl-issue.sh --digest-feed`
  - Prints NOTHING if the ledger is absent, empty, or has 0 untriaged
    entries (tolerate-absent contract — E.1 must not error or emit a blank
    line for this feed when nl-issue.sh has never been run on the machine).
  - Otherwise prints one line:
    `<N> untriaged nl-issue(s), oldest <D>d old -> nl-issue.sh --list --untriaged`
  - When N > 5 OR D > 7, prints a SECOND line prefixed `ESCALATION:` and, as
    a side effect (not on stdout), idempotently appends
    `NL-ISSUES-TRIAGE-<yyyymmdd>` to `docs/backlog.md` (resolved via
    `hooks/lib/nl-paths.sh`'s `nl_repo_root`, override via
    `NL_ISSUES_BACKLOG_PATH` for sandboxing).
  - E.1 prefixes its own icon + feed-name per its own line-economy rule;
    nl-issue.sh's output is the count/age/escalation text only.

- **E.5 (`harness-kpis.sh`) consumes:**
  `bash ~/.claude/scripts/nl-issue.sh --list` (full ledger, human-readable,
  one line per entry: `[<n>] <triage_status> <project> <ts> (x<count>) <text>`)
  and `bash ~/.claude/scripts/nl-issue.sh --list --untriaged` (filtered).
  E.5's "this week's conversions" section is derived by E.5 itself filtering
  `--list` output for `triaged_ts` values inside the reporting window — no
  additional nl-issue.sh verb is needed for that; the full listing already
  carries `triage_status`, `triage_ref`, and `triaged_ts` per entry.

- **Sandboxing env vars (self-tests / E.1 / E.5's own `--self-test` fixtures
  should use these, never the real machine state):**
  - `NL_ISSUES_PATH` — overrides the ledger file location.
  - `NL_ISSUES_BACKLOG_PATH` — overrides the escalation-append backlog file.
  - `HARNESS_SELFTEST=1` — if neither override above is set, routes the
    ledger to `${TMPDIR:-/tmp}/nl-issues-selftest/<pid>.jsonl` automatically
    (same pattern as `lib/signal-ledger.sh`).
