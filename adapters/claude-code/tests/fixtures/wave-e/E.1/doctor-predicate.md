# E.1 doctor predicate — session-start-digest.sh

For `harness-doctor.sh` (E.10 implements verbatim; this task builds the hook only,
per specs-e §E.0.1 — doctor edits are E.10-only this wave).

## Predicate 1 — hook exists, is executable, and its self-test passes

**Check command:**

```bash
HOOK="$LIVE_HOME/hooks/session-start-digest.sh"
[[ -f "$HOOK" ]] && bash "$HOOK" --self-test >/dev/null 2>&1
```

**RED condition:** `session-start-digest.sh` is missing from the live mirror, OR
`bash session-start-digest.sh --self-test` exits non-zero.

**Fixture:** a live-home fixture missing the file (RED); a live-home fixture with
the file present and passing self-test (GREEN).

## Predicate 2 — NL-FINDING-021 probe guard present (grep, not execution)

**Check command:**

```bash
grep -q 'NL-FINDING-021' "$REPO_ROOT/adapters/claude-code/attic/principles-compliance-gate.sh" \
  && grep -q 'ALERT_ANOMALY_COUNT' "$REPO_ROOT/adapters/claude-code/attic/principles-compliance-gate.sh"
```

**RED condition:** either grep fails to match — i.e. the emission-site guard
(anomaly-count/health check before the `cat > "$ALERT_FILE"` write) has been
removed or the file no longer names the finding it fixes.

**Fixture:** a copy of the file with the guard block deleted (RED); the real
fixed file (GREEN).

## Predicate 3 — zero unacked pre-2026-07-04 `principles-gate-r3` alerts on the
live machine (§E.1 Done-when, one-time check — not a recurring doctor gate;
E.10's call whether to fold this into a recurring check or leave it as a
point-in-time verification is out of this task's scope)

**Check command:**

```bash
ALERT_DIR="$HOME/.claude/state/external-monitor-alerts"
unacked=0
for f in "$ALERT_DIR"/principles-gate-r3-*.json; do
  [[ -f "$f" ]] || continue
  [[ -f "${f}.acked" ]] || unacked=$((unacked + 1))
done
[[ "$unacked" -eq 0 ]]
```

**RED condition:** `unacked` > 0 — a stale principles-gate-r3 alert survives
without a `.acked` sibling.

**Fixture:** an alert dir with one unacked file (RED); an alert dir where every
file has a `.acked` sibling (GREEN).

**Live result recorded at E.1 ship-time (2026-07-03):** ran
`session-start-digest.sh --ack-finding-021`; acked 33 files (all `.json.acked`
siblings now present — this is 1 higher than the finding's original "32" count
because at least one additional duplicate accumulated between the finding
being filed and this task acking it); verified post-sweep via
`external-monitor-alert-surfacer.sh` (silent — zero unacked); one ledger event
recorded (`gate":"session-start-digest","event":"waiver"`, detail citing
NL-FINDING-021, in `~/.claude/state/signal-ledger.jsonl`).

## Predicate 4 — manifest entry present and schema-valid

**Check command:** (this is what `manifest-check.sh` already covers generically
once the orchestrator merges `manifest-entry.json` into `manifest.json` at
§E.W — no additional doctor code needed beyond the existing manifest-check
invocation.)

```bash
bash "$REPO_ROOT/adapters/claude-code/scripts/manifest-check.sh"
```

**RED condition:** manifest-check reports a RED finding for the
`session-start-digest` entry (missing required field, hook basename not on
disk, coverage mismatch).
