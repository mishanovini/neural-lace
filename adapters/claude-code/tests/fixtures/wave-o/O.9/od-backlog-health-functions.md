# O.9 → O.3 splice fragment: `od_backlog_health` (contract C4)

Per specs-o §O.0.3 contract C4 and §O.9 deliverable 1, this fragment ships the
**complete, reviewed** bash implementation of the `od_backlog_health` oracle for
the orchestrator to splice into `adapters/claude-code/hooks/lib/observability-derive.sh`
(owned by O.3; O.9 does not create or edit that file directly — see §O.0.1 rule 2
and the CRITICAL PARALLELISM note in this task's dispatch).

The implementation below is the **row-parsing / position-anchored terminal-marker
detection / age-tier / adds-vs-terminal** logic extracted verbatim from the live
`feed_backlog_accountability` algorithm in `session-start-digest.sh` (the 87f357f
fix — position-anchored R1-R4 terminal-marker rules, replacing the naive
whole-line scan that falsely skipped open rows referencing another row's
terminal state, e.g. GH-AUTH-AUTOSWITCH-WORKORG-01). It is now THE ONE
implementation (CANONICAL-COUNTERS-01); all three BACKLOG-LOOP-01 consumers
(session-start-digest.sh, plan-edit-validator.sh, harness-kpis.sh) re-point to
it in this same wave (O.9 deliverables 1-4).

## Design: one oracle, JSON contract, per-consumer rendering

The three consumers need three different *views* of the same underlying data
(digest: one-line overdue proposals; KPI: markdown tables; absorption
validator: just open-row id+text for surface matching). Rather than force one
rendering shape on all three (which would re-introduce drift the moment one
consumer needs a tweak), `od_backlog_health` emits a canonical JSON document —
row-level facts plus pre-computed summary counts — and each consumer's
existing rendering code (unchanged) consumes that JSON instead of re-deriving
row facts from a raw grep of `docs/backlog.md`.

This is the DERIVE-DON'T-MAINTAIN law in practice: ONE parse of the backlog
file, ONE terminal-marker algorithm, ONE age-tier policy — three renderers.

## Signature (per C4)

```
od_backlog_health [--json]
```

- No args / `--json`: both modes print the same JSON document to stdout (the
  function has no separate "human" mode of its own — C4 says "every function
  has a `--json` mode"; the human-readable renderings live in the three
  *consumers*, which is where the different presentational needs actually
  are). Every count line a caller derives from this JSON must name the oracle
  inline per CANONICAL-COUNTERS-01, e.g. `"3 high-priority open rows (oracle:
  od_backlog_health)"`.
- `BACKLOG_MD_PATH` env override resolves the backlog file (fixtures /
  self-tests); default is `<repo_root>/docs/backlog.md` via `nl_repo_root` if
  sourced, else `git rev-parse --show-toplevel`, else `$PWD`.
- `BACKLOG_TIER_HIGH_DAYS` / `BACKLOG_TIER_MEDIUM_DAYS` / `BACKLOG_TIER_LOW_DAYS`
  env overrides (default 7/30/90) — same knobs `feed_backlog_accountability`
  already exposes; preserved so existing digest fixtures keep working
  unchanged after the re-point.
- `BACKLOG_HEALTH_WINDOW_DAYS` env override (default 7) for the adds-vs-terminal
  flow window (KPI's `KPI_WINDOW_DAYS`/`window_days` param maps to this).

## JSON schema

```json
{
  "schema": 1,
  "oracle": "od_backlog_health",
  "generated_at": "2026-07-06T00:00:00Z",
  "backlog_path": "/abs/path/docs/backlog.md",
  "window_days": 7,
  "rows": [
    {
      "id": "HIGH-OVERDUE-01",
      "line": "- **HIGH-OVERDUE-01 — fixture high crossed** (added 2026-06-28; `priority:high`). Prose body.",
      "terminal": false,
      "added": "2026-06-28",
      "added_epoch": 1782000000,
      "age_days": 8,
      "priority_label": "high",
      "priority": "high",
      "threshold_days": 7,
      "is_overdue": true,
      "terminal_date": null,
      "terminal_epoch": null,
      "terminal_in_window": false
    }
  ],
  "summary": {
    "open_total": 1,
    "terminal_total": 0,
    "priority_counts": {"high": 1, "medium": 0, "low": 0, "unlabeled": 0},
    "age_tiers": {"0_7": 0, "8_30": 1, "31_90": 0, "over_90": 0, "undated": 0},
    "overdue_ids": ["HIGH-OVERDUE-01"],
    "adds_in_window": 0,
    "terminal_in_window": 0,
    "terminal_undated": 0
  }
}
```

Field notes (so no consumer needs to re-derive policy):
- `priority_label` is the RAW parsed `priority:` value, or `""` if absent.
- `priority` is the RESOLVED value used for tiering/counting: defaults to
  `"low"` when `priority_label` is empty (matches the digest's existing
  least-nag posture — line 879 of the pre-refactor `feed_backlog_accountability`:
  `[[ -z "$prio" ]] && prio="low"`). The KPI script's separate `unlabeled`
  bucket is preserved via `priority_label == ""`, NOT via `priority` — this
  is the one deliberate divergence point between the two pre-existing
  consumers, and the oracle carries BOTH fields so neither loses information.
- `is_overdue` = row not terminal AND `age_days > threshold_days` (threshold
  from the row's resolved `priority`). This is exactly the digest's overdue
  predicate.
- `terminal` uses the position-anchored R1-R4 rules verbatim (see function
  body below) — this is the 87f357f fix, the single most important piece of
  this extraction.
- `terminal_date`/`terminal_epoch`/`terminal_in_window` mirror harness-kpis.sh's
  existing transition-date extraction (date adjacent to the terminal marker).
- `overdue_ids` is oldest-first (by `age_days` descending) — the digest's own
  proposal ordering; consumers that cap/paginate can slice this array directly
  instead of re-sorting.

## Bash implementation (paste verbatim into observability-derive.sh)

```bash
# ============================================================
# od_backlog_health — contract C4, THE backlog oracle (O.9,
# CANONICAL-COUNTERS-01). Pure read, zero state writes.
#
# Row-parsing + position-anchored terminal-marker detection lifted
# verbatim from session-start-digest.sh's feed_backlog_accountability
# (the 87f357f fix). See adapters/claude-code/tests/fixtures/wave-o/O.9/
# od-backlog-health-functions.md for the full design note + JSON schema.
# ============================================================

_od_backlog_path() {
  if [[ -n "${BACKLOG_MD_PATH:-}" ]]; then
    printf '%s' "$BACKLOG_MD_PATH"
    return 0
  fi
  local root
  if command -v nl_repo_root >/dev/null 2>&1; then
    root="$(nl_repo_root)"
  else
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  printf '%s/docs/backlog.md' "$root"
}

_od_backlog_date_epoch() {
  local d="$1"
  date -u -d "$d" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null \
    || echo ""
}

# _od_backlog_row_is_terminal <row line> -> 0 (terminal) / 1 (open).
# POSITION-ANCHORED marker detection (87f357f): a naive whole-line grep
# falsely skips OPEN rows whose prose merely REFERENCES another row's
# terminal state (live example: GH-AUTH-AUTOSWITCH-WORKORG-01, an open
# 35d-overdue row, was invisible because its prose says "distinct from
# HARNESS-GAP-12 (IMPLEMENTED 2026-05-04)"). Four rules match every
# terminal form observed in the live backlog and nothing else:
#   R1  UPPERCASE marker inside the bold TITLE span
#   R2  "** — MARKER" immediately after the title close
#   R3  bold-paren annotation, case-insensitive
#   R4  bold annotation opening with optional qualifier + UPPERCASE marker
# R1/R2/R4 are case-SENSITIVE: lowercase title prose describes SUBJECT
# MATTER, not row state.
_OD_BACKLOG_TERM_U='(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)'
_od_backlog_row_is_terminal() {
  local line="$1"
  printf '%s' "$line" | grep -qE "^- \*\*[^*]*\b${_OD_BACKLOG_TERM_U}\b" && return 0
  printf '%s' "$line" | grep -qE "\*\*[[:space:]]+(—|--?)[[:space:]]+${_OD_BACKLOG_TERM_U}\b" && return 0
  printf '%s' "$line" | grep -qiE '\*\*\((dispositioned|implemented|absorbed|closed|superseded|wontfix)\b' && return 0
  printf '%s' "$line" | grep -qE "\*\*((PARTIALLY|LARGELY)[[:space:]]+)?${_OD_BACKLOG_TERM_U}\b" && return 0
  return 1
}

# od_backlog_health [--json] — contract C4. Emits the canonical JSON
# document (rows + summary) for every consumer to render from. Requires
# node (falls back to an honest empty-rows JSON with a "degraded" flag if
# node is unavailable, matching the digest's existing node-optional
# posture for seen.jsonl — see _seen_lookup/_seen_bump).
od_backlog_health() {
  local backlog; backlog="$(_od_backlog_path)"
  local tier_high="${BACKLOG_TIER_HIGH_DAYS:-7}"
  local tier_medium="${BACKLOG_TIER_MEDIUM_DAYS:-30}"
  local tier_low="${BACKLOG_TIER_LOW_DAYS:-90}"
  local window_days="${BACKLOG_HEALTH_WINDOW_DAYS:-7}"
  local now; now="$(date -u +%s)"
  local now_iso; now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local window_start=$((now - window_days * 86400))

  if [[ ! -f "$backlog" ]]; then
    if command -v node >/dev/null 2>&1; then
      node -e '
        var doc = {schema:1, oracle:"od_backlog_health", generated_at:process.argv[1],
          backlog_path:process.argv[2], window_days:Number(process.argv[3]), rows:[],
          summary:{open_total:0, terminal_total:0,
            priority_counts:{high:0,medium:0,low:0,unlabeled:0},
            age_tiers:{"0_7":0,"8_30":0,"31_90":0,over_90:0,undated:0},
            overdue_ids:[], adds_in_window:0, terminal_in_window:0, terminal_undated:0},
          note:"no backlog file at backlog_path"};
        process.stdout.write(JSON.stringify(doc));
      ' "$now_iso" "$backlog" "$window_days"
    else
      printf '{"schema":1,"oracle":"od_backlog_health","degraded":"node unavailable","rows":[],"summary":{}}'
    fi
    printf '\n'
    return 0
  fi

  # Build a JSONL of per-row facts (one line each), then hand the whole
  # thing to node for the final summary/JSON assembly — same division of
  # labor as the rest of this hook family (bash parses text with grep/sed,
  # node assembles JSON; see _seen_bump's identical pattern).
  local rows_tmp; rows_tmp="$(mktemp 2>/dev/null || mktemp -t odbacklog)"
  trap 'rm -f "$rows_tmp"' RETURN

  local line id added added_epoch age_days prio_label prio threshold is_terminal term_date term_epoch
  while IFS= read -r line; do
    id="$(printf '%s' "$line" | grep -oE '^- \*\*[A-Z][A-Z0-9-]{3,}' | sed 's/^- \*\*//')"
    [[ -z "$id" ]] && continue

    added="$(printf '%s' "$line" | grep -oE 'added [0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1 | sed 's/^added //')"
    added_epoch=""
    [[ -n "$added" ]] && added_epoch="$(_od_backlog_date_epoch "$added")"
    age_days=""
    [[ -n "$added_epoch" ]] && age_days=$(( (now - added_epoch) / 86400 ))

    prio_label="$(printf '%s' "$line" | grep -oE 'priority:(high|medium|low)' | head -n1 | sed 's/^priority://')"
    prio="$prio_label"
    [[ -z "$prio" ]] && prio="low"
    case "$prio" in
      high)   threshold="$tier_high" ;;
      medium) threshold="$tier_medium" ;;
      *)      threshold="$tier_low" ;;
    esac

    is_terminal="false"
    term_date=""
    term_epoch=""
    if _od_backlog_row_is_terminal "$line"; then
      is_terminal="true"
      term_date="$(printf '%s' "$line" \
        | grep -oiE "${_OD_BACKLOG_TERM_U}[^0-9]{0,12}[0-9]{4}-[0-9]{2}-[0-9]{2}" \
        | head -n1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
      [[ -n "$term_date" ]] && term_epoch="$(_od_backlog_date_epoch "$term_date")"
    fi

    # Emit one JSON row fact via node (keeps quoting/escaping correct for
    # arbitrary prose in $line).
    node -e '
      var a = process.argv.slice(1);
      var row = {id:a[0], line:a[1], terminal: a[2] === "true",
        added: a[3] || null, added_epoch: a[4] ? Number(a[4]) : null,
        age_days: a[5] ? Number(a[5]) : null,
        priority_label: a[6] || "", priority: a[7],
        threshold_days: Number(a[8]),
        terminal_date: a[9] || null,
        terminal_epoch: a[10] ? Number(a[10]) : null};
      process.stdout.write(JSON.stringify(row) + "\n");
    ' "$id" "$line" "$is_terminal" "$added" "$added_epoch" "$age_days" \
      "$prio_label" "$prio" "$threshold" "$term_date" "$term_epoch" >> "$rows_tmp" 2>/dev/null
  done < <(grep -E '^- \*\*[A-Z]' "$backlog" 2>/dev/null)

  if ! command -v node >/dev/null 2>&1; then
    printf '{"schema":1,"oracle":"od_backlog_health","degraded":"node unavailable","rows":[],"summary":{}}\n'
    rm -f "$rows_tmp"
    return 0
  fi

  node -e '
    "use strict";
    var fs = require("fs");
    var rowsPath = process.argv[1], backlogPath = process.argv[2];
    var nowIso = process.argv[3], windowDays = Number(process.argv[4]);
    var windowStart = Number(process.argv[5]);
    var raw = "";
    try { raw = fs.readFileSync(rowsPath, "utf8"); } catch (e) {}
    var rows = raw.split("\n").filter(Boolean).map(function (l) {
      try { return JSON.parse(l); } catch (e) { return null; }
    }).filter(Boolean);

    var summary = {
      open_total: 0, terminal_total: 0,
      priority_counts: {high:0, medium:0, low:0, unlabeled:0},
      age_tiers: {"0_7":0, "8_30":0, "31_90":0, over_90:0, undated:0},
      overdue_ids: [], adds_in_window: 0, terminal_in_window: 0, terminal_undated: 0
    };
    var overdue = [];

    rows.forEach(function (r) {
      if (r.added_epoch !== null && r.added_epoch >= windowStart) {
        summary.adds_in_window++;
      }
      if (r.terminal) {
        summary.terminal_total++;
        if (r.terminal_epoch !== null) {
          if (r.terminal_epoch >= windowStart) summary.terminal_in_window++;
        } else {
          summary.terminal_undated++;
        }
        r.is_overdue = false;
        r.terminal_in_window = (r.terminal_epoch !== null && r.terminal_epoch >= windowStart);
        return;
      }
      summary.open_total++;
      var pl = r.priority_label || "";
      if (pl === "high") summary.priority_counts.high++;
      else if (pl === "medium") summary.priority_counts.medium++;
      else if (pl === "low") summary.priority_counts.low++;
      else summary.priority_counts.unlabeled++;

      if (r.age_days === null) {
        summary.age_tiers.undated++;
      } else if (r.age_days <= 7) summary.age_tiers["0_7"]++;
      else if (r.age_days <= 30) summary.age_tiers["8_30"]++;
      else if (r.age_days <= 90) summary.age_tiers["31_90"]++;
      else summary.age_tiers.over_90++;

      r.is_overdue = (r.age_days !== null && r.age_days > r.threshold_days);
      r.terminal_in_window = false;
      if (r.is_overdue) overdue.push(r);
    });

    overdue.sort(function (a, b) { return (b.age_days||0) - (a.age_days||0); });
    summary.overdue_ids = overdue.map(function (r) { return r.id; });

    var doc = {
      schema: 1, oracle: "od_backlog_health", generated_at: nowIso,
      backlog_path: backlogPath, window_days: windowDays,
      rows: rows, summary: summary
    };
    process.stdout.write(JSON.stringify(doc));
  ' "$rows_tmp" "$backlog" "$now_iso" "$window_days" "$window_start"
  printf '\n'

  rm -f "$rows_tmp"
  trap - RETURN
  return 0
}
```

## Self-test scenarios this fragment's functions must keep passing (O.9 ran these against the shim; re-run identically once spliced)

1. Fixture backlog with high/medium/low rows each just-under and
   just-over their tier threshold → `is_overdue` true only for the
   over-threshold rows, `overdue_ids` oldest-first.
2. Terminal rows in all four observed forms (`[CLOSED ...]` title-span,
   `** — IMPLEMENTED ...`, `**(absorbed by ...)**`, `**SUPERSEDED ...**`)
   → `terminal: true`, excluded from `open_total`/`priority_counts`/
   `age_tiers`.
3. **87f357f regression**: an OPEN row whose prose references another
   row's terminal state (e.g. `**This is distinct from OTHER-GAP-99
   (IMPLEMENTED 2026-01-01).**`) → `terminal: false`, counted as open and
   overdue if its own age crosses its own tier.
4. No backlog file → `rows: []`, all summary counts 0, no crash.
5. `node` unavailable → degraded JSON, no crash (matches the digest's
   existing node-optional posture elsewhere in this hook family).

## Orchestrator integration checklist

1. Paste the "Bash implementation" block above into
   `adapters/claude-code/hooks/lib/observability-derive.sh` (verbatim —
   already reviewed against the 87f357f source).
2. Confirm `od_backlog_health` and `od_backlog_health --json` are
   identical (per C4, the function has no separate human-mode of its
   own — both flag states print the same JSON).
3. Re-run this task's three consumer self-tests
   (`session-start-digest.sh --self-test`, `plan-edit-validator.sh
   --self-test`, `harness-kpis.sh --self-test`) against the now-real
   `observability-derive.sh` — O.9 already re-pointed all three via the
   guarded-source + feature-detect pattern (see
   `tests/fixtures/wave-o/O.9/od-backlog-shim.sh` for exactly what the
   real lib now needs to satisfy structurally: the shim IS this same
   code, so a green shim run is a strong predictor of a green real-lib
   run — but re-run for real, don't take the predictor as the proof).
4. Add the `nl backlog` CLI subcommand (C5, O.3's own deliverable) —
   out of scope for this fragment, just calls `od_backlog_health --json`
   per the C5 spec.
