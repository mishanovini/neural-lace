#!/bin/bash
# manifest-check.sh — validates adapters/claude-code/manifest.json against its
# schema and against the repo (NL Overhaul task C.1, ADR 058 D3).
#
# WHY THIS EXISTS
# ===============
# The manifest is the single machine-readable inventory of every
# enforcement/doctrine unit in the harness. It is only useful if it is TRUE:
# every hook on disk must be claimed by an entry, every claimed hook must
# exist, every wired_template claim must match settings.json.template, and
# every gate that is not template-wired must carry an honest_status naming
# how it actually fires. This script is the mechanical checker for all of
# that, plus the generator for the manifest-derived doctrine/INDEX.md.
#
# SUBCOMMANDS
# ===========
#   check (default) : run checks (a)-(e) below. Exit 0 iff zero RED.
#     (a) manifest parses + validates against schemas/manifest.schema.json
#         (node subset-validator driven by the schema file; jq structural
#         fallback; neither available -> WARN and skip, exit 0 gracefully)
#     (b) hooks[] <-> disk coverage BOTH ways (RED per miss). Disk scope:
#         adapters/claude-code/hooks/*.sh — lib/ is a subdirectory (never
#         matched by the top-level glob) and attic/ is a sibling directory
#         (never scanned).
#     (c) every wired_template:true entry's hooks all appear (by basename)
#         in settings.json.template (RED per miss)
#     (d) doctrine_file existence — WARN (aggregate, naming the missing
#         files) while the doctrine/ era is still building out: either
#         adapters/claude-code/doctrine/ does not exist yet (pre-C.4) or it
#         exists but the generated doctrine/INDEX.md does not (mid-C.4 —
#         parallel clusters land incrementally). RED per missing file once
#         doctrine/INDEX.md exists (written by --gen-index at C.5 step 2,
#         the point the wave-C spec requires full RED enforcement).
#         rules/constitution.md targets are checked strictly (rules/ exists).
#     (e) kind:gate + wired_template:false without a non-empty honest_status
#         -> RED
#   --gen-index     : write adapters/claude-code/doctrine/INDEX.md from the
#                     manifest (one row per entry: id, kind, doctrine link,
#                     hooks, blocking, honest_status). Deterministic (sorted
#                     by id, LC_ALL=C).
#   --self-test     : fixture suite in mktemp -d (HARNESS_SELFTEST=1):
#                     valid manifest GREEN; missing-hook-file RED;
#                     unlisted-disk-hook RED; wired-false-gate-without-
#                     honest_status RED; wired-true-but-not-in-template RED;
#                     gen-index golden compare. Exit 0 iff all pass.
#
# ENV
# ===
#   MANIFEST_CHECK_ROOT      override repo-root resolution (self-test + doctor)
#   MANIFEST_CHECK_MANIFEST  override manifest path (rare; defaults to
#                            <root>/adapters/claude-code/manifest.json)
#
# DEPENDENCIES
# ============
# bash-first. node preferred for schema validation; jq is the structural
# fallback; with neither, check (a)+(b)-(e) parsing is impossible so the
# script WARNs and exits 0 (graceful degradation — a bare-bash machine is
# not blocked by the manifest layer).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

resolve_root() {
  if [[ -n "${MANIFEST_CHECK_ROOT:-}" ]]; then
    printf '%s\n' "$MANIFEST_CHECK_ROOT"
    return 0
  fi
  local root
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  # Script lives at <root>/adapters/claude-code/scripts/ — walk up three.
  root="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  return 1
}

RED_COUNT=0
WARN_COUNT=0

_red() {
  echo "[manifest-check] RED ${1}: ${2}"
  RED_COUNT=$((RED_COUNT + 1))
}

_warn() {
  echo "[manifest-check] WARN ${1}: ${2}"
  WARN_COUNT=$((WARN_COUNT + 1))
}

have_node() { command -v node >/dev/null 2>&1; }
have_jq() { command -v jq >/dev/null 2>&1; }

# ------------------------------------------------------------
# extract_stream <manifest> — normalized pipe-delimited stream:
#   E|id|kind|doctrine_or_-|wired01|selftest01|blocking01|budget|honest01
#   H|id|hook-basename
# Emitted by node when available, else jq. Caller must have verified one
# of the two exists.
# ------------------------------------------------------------
extract_stream() {
  local manifest="$1"
  if have_node; then
    node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const e of m.entries || []) {
  const honest = (typeof e.honest_status === "string" && e.honest_status.trim().length > 0) ? "1" : "0";
  console.log(["E", e.id, e.kind, e.doctrine_file || "-",
    e.wired_template ? "1" : "0", e.selftest ? "1" : "0",
    e.blocking ? "1" : "0", e.budget_class, honest].join("|"));
  for (const h of e.hooks || []) console.log(["H", e.id, h].join("|"));
}' "$manifest" 2>/dev/null
  else
    jq -r '
.entries[] as $e |
(["E", $e.id, $e.kind, ($e.doctrine_file // "-"),
  (if $e.wired_template then "1" else "0" end),
  (if $e.selftest then "1" else "0" end),
  (if $e.blocking then "1" else "0" end),
  $e.budget_class,
  (if (($e.honest_status // "") | length) > 0 then "1" else "0" end)] | join("|")),
((($e.hooks // [])[]) | "H|\($e.id)|\(.)")' "$manifest" 2>/dev/null
  fi
}

# ------------------------------------------------------------
# validate_schema <manifest> <schema> — check (a). Emits RED lines itself.
# ------------------------------------------------------------
validate_schema() {
  local manifest="$1" schema="$2"

  if [[ ! -f "$schema" ]]; then
    _warn "schema" "schema file not found at ${schema} — schema validation skipped"
    return 0
  fi

  if have_node; then
    local out rc
    out="$(node -e '
const fs = require("fs");
let manifest, schema;
try { manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
catch (err) { console.log("parse|manifest does not parse as JSON: " + err.message); process.exit(1); }
try { schema = JSON.parse(fs.readFileSync(process.argv[2], "utf8")); }
catch (err) { console.log("parse|schema does not parse as JSON: " + err.message); process.exit(1); }

const problems = [];
const entrySchema = schema.properties.entries.items;
const allowedKeys = Object.keys(entrySchema.properties);
const requiredKeys = entrySchema.required;
const enumOf = (k) => (entrySchema.properties[k] && entrySchema.properties[k].enum) || null;
const kindEnum = enumOf("kind");
const budgetEnum = enumOf("budget_class");
const eventsEnum = entrySchema.properties.events.items.enum;

// top level
for (const k of Object.keys(manifest)) {
  if (!Object.keys(schema.properties).includes(k)) problems.push(`top-level unknown key '"'"'${k}'"'"'`);
}
if (manifest.schema_version !== 1) problems.push("schema_version must be 1");
if (!Array.isArray(manifest.entries) || manifest.entries.length < 1) problems.push("entries must be a non-empty array");

const seen = new Set();
for (const e of manifest.entries || []) {
  const id = e && e.id ? e.id : "<no-id>";
  if (typeof e !== "object" || e === null) { problems.push("non-object entry"); continue; }
  if (seen.has(id)) problems.push(`duplicate id '"'"'${id}'"'"'`);
  seen.add(id);
  for (const k of Object.keys(e)) {
    if (!allowedKeys.includes(k)) problems.push(`${id}: unknown key '"'"'${k}'"'"' (additionalProperties: false)`);
  }
  for (const k of requiredKeys) {
    if (!(k in e)) problems.push(`${id}: missing required key '"'"'${k}'"'"'`);
  }
  if (typeof e.id !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(e.id || "")) problems.push(`${id}: id must be kebab-case`);
  if (kindEnum && !kindEnum.includes(e.kind)) problems.push(`${id}: kind '"'"'${e.kind}'"'"' not in ${JSON.stringify(kindEnum)}`);
  if (e.doctrine_file !== null && e.doctrine_file !== undefined) {
    if (typeof e.doctrine_file !== "string" || !/^(doctrine\/[A-Za-z0-9._-]+\.md|rules\/constitution\.md)$/.test(e.doctrine_file))
      problems.push(`${id}: doctrine_file '"'"'${e.doctrine_file}'"'"' is neither null, doctrine/<name>.md, nor rules/constitution.md`);
  }
  if (!Array.isArray(e.hooks)) problems.push(`${id}: hooks must be an array`);
  else for (const h of e.hooks) {
    if (typeof h !== "string" || !/^[A-Za-z0-9._-]+\.sh$/.test(h)) problems.push(`${id}: hook '"'"'${h}'"'"' is not a .sh basename`);
  }
  if (!Array.isArray(e.events)) problems.push(`${id}: events must be an array`);
  else for (const ev of e.events) {
    if (!eventsEnum.includes(ev)) problems.push(`${id}: event '"'"'${ev}'"'"' not in the events enum`);
  }
  for (const bk of ["wired_template", "selftest", "blocking"]) {
    if (typeof e[bk] !== "boolean") problems.push(`${id}: ${bk} must be a boolean`);
  }
  if (typeof e.jit_triggers !== "object" || e.jit_triggers === null ||
      !Array.isArray(e.jit_triggers.paths) || !Array.isArray(e.jit_triggers.keywords) ||
      Object.keys(e.jit_triggers).some(k => !["paths", "keywords"].includes(k)))
    problems.push(`${id}: jit_triggers must be {paths: [], keywords: []}`);
  if (budgetEnum && !budgetEnum.includes(e.budget_class)) problems.push(`${id}: budget_class '"'"'${e.budget_class}'"'"' not in ${JSON.stringify(budgetEnum)}`);
  if (e.kind === "gate" && e.wired_template === false &&
      !(typeof e.honest_status === "string" && e.honest_status.trim().length > 0))
    problems.push(`${id}: kind gate with wired_template false REQUIRES a non-empty honest_status`);
  if ("honest_status" in e && e.honest_status !== null && typeof e.honest_status !== "string")
    problems.push(`${id}: honest_status must be a string or null`);
}
if (problems.length) {
  for (const p of problems.slice(0, 30)) console.log("schema|" + p);
  process.exit(1);
}
process.exit(0);
' "$manifest" "$schema" 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      while IFS='|' read -r tag detail; do
        [[ -z "$tag" ]] && continue
        _red "$tag" "$detail"
      done <<< "$out"
      return 1
    fi
    return 0
  fi

  if have_jq; then
    if ! jq empty "$manifest" 2>/dev/null; then
      _red "parse" "manifest does not parse as JSON"
      return 1
    fi
    local bad
    bad="$(jq -r '
def req: ["id","kind","doctrine_file","hooks","events","wired_template","selftest","jit_triggers","blocking","budget_class"];
def kinds: ["gate","writer","surfacer","pattern","convention"];
def budgets: ["stop","session-start","pretool","posttool","none"];
def evs: ["Stop","SessionStart","PreToolUse","PostToolUse","UserPromptSubmit","TaskCreated","TaskCompleted","precommit","prepush","manual"];
def allowed: req + ["honest_status"];
[ .entries[] |
  ( (req - keys) | map(. as $k | "missing required key \($k)") ) +
  ( (keys - allowed) | map(. as $k | "unknown key \($k)") ) +
  ( if (kinds | index(.kind)) then [] else ["bad kind \(.kind)"] end ) +
  ( if (budgets | index(.budget_class)) then [] else ["bad budget_class \(.budget_class)"] end ) +
  ( [ (.events // [])[] | select(evs | index(.) | not) | "bad event \(.)" ] ) +
  ( if .kind == "gate" and .wired_template == false and (((.honest_status // "") | length) == 0)
    then ["gate with wired_template false lacks honest_status"] else [] end )
  | map("\(.)") | .[] // empty
] | .[0:30] | .[]' "$manifest" 2>/dev/null)"
    if [[ -n "$bad" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _red "schema" "$line"
      done <<< "$bad"
      return 1
    fi
    return 0
  fi

  _warn "schema" "neither node nor jq available — schema validation skipped"
  return 0
}

# ------------------------------------------------------------
# run_check — subcommand: check
# ------------------------------------------------------------
run_check() {
  local root="$1"
  local ac="${root}/adapters/claude-code"
  local manifest="${MANIFEST_CHECK_MANIFEST:-${ac}/manifest.json}"
  local schema="${ac}/schemas/manifest.schema.json"
  local template="${ac}/settings.json.template"
  local hooks_dir="${ac}/hooks"
  local doctrine_dir="${ac}/doctrine"

  if [[ ! -f "$manifest" ]]; then
    _red "manifest" "manifest not found at ${manifest}"
    return 1
  fi

  if ! have_node && ! have_jq; then
    _warn "deps" "neither node nor jq available — manifest checks skipped (graceful degradation)"
    echo "[manifest-check] SKIPPED — no JSON parser available"
    return 0
  fi

  # (a) schema
  validate_schema "$manifest" "$schema"

  # If the manifest doesn't even parse, the stream below is empty — bail
  # out on what we have rather than cascading noise.
  local stream
  stream="$(extract_stream "$manifest")"
  if [[ -z "$stream" ]]; then
    _red "parse" "could not extract entries from the manifest (parse failure?)"
    echo "[manifest-check] FAILED — ${RED_COUNT} red, ${WARN_COUNT} warn"
    return 1
  fi

  # (b) hooks -> disk
  local manifest_hooks
  manifest_hooks="$(printf '%s\n' "$stream" | awk -F'|' '$1=="H"{print $3}' | LC_ALL=C sort -u)"
  while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    if [[ ! -f "${hooks_dir}/${h}" ]]; then
      _red "hooks-exist" "manifest references hook '${h}' but ${hooks_dir}/${h} does not exist"
    fi
  done <<< "$manifest_hooks"

  # (b) disk -> hooks (top-level *.sh only; lib/ is a subdir, attic/ a sibling)
  local f base
  for f in "$hooks_dir"/*.sh; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    if ! printf '%s\n' "$manifest_hooks" | grep -qx "$base"; then
      _red "hooks-coverage" "disk hook '${base}' appears in no manifest entry's hooks[]"
    fi
  done

  # (c) wired_template:true entries' hooks all present in the template
  if [[ -f "$template" ]]; then
    local wired_ids id
    wired_ids="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E" && $5=="1"{print $2}')"
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      while IFS= read -r h; do
        [[ -z "$h" ]] && continue
        if ! grep -qF "$h" "$template"; then
          _red "wired-template" "entry '${id}' claims wired_template true but hook '${h}' does not appear in settings.json.template"
        fi
      done <<< "$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="H" && $2==want{print $3}')"
    done <<< "$wired_ids"
  else
    _warn "wired-template" "settings.json.template not found at ${template} — wired_template claims unverified"
  fi

  # (d) doctrine_file existence. Era detection: full RED enforcement begins
  # when the generated doctrine/INDEX.md exists (written by --gen-index at
  # C.5 step 2 — the point the wave-C spec requires "fully RED-enforcing").
  # Before that (pre-C.4: no doctrine/ dir; mid-C.4: dir exists but parallel
  # clusters are still landing) missing doctrine/ targets aggregate to ONE
  # WARN that names them.
  local doctrine_enforcing=0
  [[ -f "${doctrine_dir}/INDEX.md" ]] && doctrine_enforcing=1
  local doctrine_missing_count=0 doctrine_missing_names=""
  while IFS='|' read -r tag id kind doctrine rest; do
    [[ "$tag" == "E" ]] || continue
    [[ "$doctrine" == "-" ]] && continue
    if [[ "$doctrine" == doctrine/* ]]; then
      if [[ ! -f "${ac}/${doctrine}" ]]; then
        if [[ "$doctrine_enforcing" -eq 1 ]]; then
          _red "doctrine-file" "entry '${id}' names ${doctrine} but it does not exist (doctrine/INDEX.md exists, so this is enforcing)"
        else
          doctrine_missing_count=$((doctrine_missing_count + 1))
          doctrine_missing_names="${doctrine_missing_names}${doctrine} "
        fi
      fi
    else
      # rules/constitution.md — checked strictly.
      if [[ ! -f "${ac}/${doctrine}" ]]; then
        _red "doctrine-file" "entry '${id}' names ${doctrine} but it does not exist"
      fi
    fi
  done <<< "$stream"
  if [[ "$doctrine_missing_count" -gt 0 ]]; then
    local uniq_missing
    uniq_missing="$(printf '%s\n' $doctrine_missing_names | LC_ALL=C sort -u | paste -sd ' ' -)"
    _warn "doctrine-file" "doctrine buildout in progress (no generated doctrine/INDEX.md yet) — ${doctrine_missing_count} doctrine_file reference(s) unresolved (RED once C.5's --gen-index lands): ${uniq_missing}"
  fi

  # (e) gate + wired_template false + no honest_status
  while IFS='|' read -r tag id kind doctrine wired selftest blocking budget honest; do
    [[ "$tag" == "E" ]] || continue
    if [[ "$kind" == "gate" && "$wired" == "0" && "$honest" == "0" ]]; then
      _red "honest-status" "entry '${id}' is a gate with wired_template false and no honest_status — name how it actually fires or which Wave lands its wiring"
    fi
  done <<< "$stream"

  local n_entries n_hooks
  n_entries="$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"' | wc -l | tr -d '[:space:]')"
  n_hooks="$(printf '%s\n' "$manifest_hooks" | grep -c . || true)"
  if [[ "$RED_COUNT" -eq 0 ]]; then
    echo "[manifest-check] GREEN — ${n_entries} entries, ${n_hooks} hooks covered, ${WARN_COUNT} warn"
    return 0
  else
    echo "[manifest-check] FAILED — ${RED_COUNT} red, ${WARN_COUNT} warn (${n_entries} entries)"
    return 1
  fi
}

# ------------------------------------------------------------
# run_gen_index — subcommand: --gen-index
# ------------------------------------------------------------
run_gen_index() {
  local root="$1"
  local ac="${root}/adapters/claude-code"
  local manifest="${MANIFEST_CHECK_MANIFEST:-${ac}/manifest.json}"
  local doctrine_dir="${ac}/doctrine"

  if [[ ! -f "$manifest" ]]; then
    echo "[manifest-check] ERROR: manifest not found at ${manifest}" >&2
    return 2
  fi
  if ! have_node && ! have_jq; then
    echo "[manifest-check] ERROR: --gen-index needs node or jq" >&2
    return 2
  fi

  local stream
  stream="$(extract_stream "$manifest")"
  if [[ -z "$stream" ]]; then
    echo "[manifest-check] ERROR: could not extract entries from the manifest" >&2
    return 2
  fi

  mkdir -p "$doctrine_dir"
  local out="${doctrine_dir}/INDEX.md"
  {
    echo "# Doctrine INDEX — generated from manifest.json by manifest-check.sh --gen-index"
    echo ""
    echo "Do not hand-edit: regenerate with \`bash adapters/claude-code/scripts/manifest-check.sh --gen-index\`."
    echo ""
    echo "| id | kind | doctrine | hooks | blocking | honest_status |"
    echo "|---|---|---|---|---|---|"
    # Deterministic: entries sorted by id (LC_ALL=C).
    while IFS='|' read -r tag id kind doctrine wired selftest blocking budget honest; do
      [[ "$tag" == "E" ]] || continue
      local doc_cell hooks_cell blocking_cell honest_cell
      case "$doctrine" in
        -) doc_cell="—" ;;
        doctrine/*) doc_cell="[${doctrine}](${doctrine#doctrine/})" ;;
        *) doc_cell="[${doctrine}](../${doctrine})" ;;
      esac
      hooks_cell="$(printf '%s\n' "$stream" | awk -F'|' -v want="$id" '$1=="H" && $2==want{print $3}' | LC_ALL=C sort | paste -sd ',' - | sed 's/,/, /g')"
      [[ -z "$hooks_cell" ]] && hooks_cell="—"
      [[ "$blocking" == "1" ]] && blocking_cell="yes" || blocking_cell="no"
      if [[ "$honest" == "1" ]]; then
        # Re-read the honest_status text (stream carries only presence).
        if have_node; then
          honest_cell="$(node -e '
const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const e = (m.entries || []).find(x => x.id === process.argv[2]);
process.stdout.write((e && e.honest_status) ? String(e.honest_status) : "");' "$manifest" "$id" 2>/dev/null)"
        else
          honest_cell="$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .honest_status // ""' "$manifest" 2>/dev/null)"
        fi
        [[ -z "$honest_cell" ]] && honest_cell="—"
      else
        honest_cell="—"
      fi
      echo "| ${id} | ${kind} | ${doc_cell} | ${hooks_cell} | ${blocking_cell} | ${honest_cell} |"
    done <<< "$(printf '%s\n' "$stream" | awk -F'|' '$1=="E"' | LC_ALL=C sort -t'|' -k2,2)"
  } > "$out"
  echo "[manifest-check] wrote ${out}"
  return 0
}

# ============================================================
# --self-test
# ============================================================
run_self_test() {
  local SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
  local REAL_SCHEMA="$SCRIPT_DIR/../schemas/manifest.schema.json"
  if [[ ! -f "$REAL_SCHEMA" ]]; then
    echo "self-test: cannot resolve real schema at ${REAL_SCHEMA}" >&2
    return 2
  fi
  if ! have_node && ! have_jq; then
    echo "self-test: SKIP — neither node nor jq available (graceful-degradation environment)" >&2
    return 0
  fi

  export HARNESS_SELFTEST=1
  local PASSED=0 FAILED=0
  # NOT local: the EXIT trap fires after this function's scope is gone.
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t manifest-check)
  if [[ -z "$TMPROOT" || ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    return 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Fixture builder: a mini repo root with two hooks, a template wiring one
  # of them, and the real schema copied in.
  _fixture() {
    local dir="$1"
    mkdir -p "$dir/adapters/claude-code/hooks" "$dir/adapters/claude-code/schemas" "$dir/adapters/claude-code/rules"
    cp "$REAL_SCHEMA" "$dir/adapters/claude-code/schemas/manifest.schema.json"
    printf '#!/bin/bash\n# --self-test stub\nexit 0\n' > "$dir/adapters/claude-code/hooks/a-gate.sh"
    printf '#!/bin/bash\nexit 0\n' > "$dir/adapters/claude-code/hooks/b-pending.sh"
    printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/a-gate.sh"}]}]}}\n' \
      > "$dir/adapters/claude-code/settings.json.template"
  }

  _valid_manifest() {
    cat <<'EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "a-gate",
      "kind": "gate",
      "doctrine_file": "doctrine/a.md",
      "hooks": ["a-gate.sh"],
      "events": ["Stop"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": { "paths": ["docs/plans/"], "keywords": [] },
      "blocking": true,
      "budget_class": "stop"
    },
    {
      "id": "b-pending",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["b-pending.sh"],
      "events": ["precommit"],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "invoked via a chain script; not directly wired",
      "budget_class": "none"
    }
  ]
}
EOF
  }

  _assert() {
    local label="$1" want_rc="$2" got_rc="$3" grep_pattern="${4:-}" output="${5:-}"
    local ok=1
    [[ "$got_rc" != "$want_rc" ]] && ok=0
    if [[ -n "$grep_pattern" ]] && ! printf '%s' "$output" | grep -q "$grep_pattern"; then ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
      echo "self-test (${label}): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test (${label}): FAIL (rc=${got_rc}, expected ${want_rc}, pattern='${grep_pattern}')" >&2
      printf '%s\n' "$output" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  local D OUT RC

  # S1 — valid manifest: GREEN (doctrine/ absent -> WARN only)
  D="$TMPROOT/s1"; _fixture "$D"
  _valid_manifest > "$D/adapters/claude-code/manifest.json"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s1-valid-green" 0 "$RC" "GREEN" "$OUT"

  # S2 — manifest lists a hook that does not exist on disk: RED
  D="$TMPROOT/s2"; _fixture "$D"
  _valid_manifest | sed 's/"a-gate\.sh"/"ghost.sh"/' > "$D/adapters/claude-code/manifest.json"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s2-missing-hook-red" 1 "$RC" "RED hooks-exist" "$OUT"

  # S3 — disk hook not listed in any entry: RED
  D="$TMPROOT/s3"; _fixture "$D"
  _valid_manifest > "$D/adapters/claude-code/manifest.json"
  printf '#!/bin/bash\nexit 0\n' > "$D/adapters/claude-code/hooks/stray.sh"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s3-unlisted-disk-hook-red" 1 "$RC" "RED hooks-coverage" "$OUT"

  # S4 — gate with wired_template false and NO honest_status: RED
  D="$TMPROOT/s4"; _fixture "$D"
  _valid_manifest | grep -v '"honest_status"' | sed 's/"blocking": true,$/"blocking": true,/' > "$D/adapters/claude-code/manifest.json"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s4-gate-no-honest-status-red" 1 "$RC" "honest" "$OUT"

  # S5 — wired_template true but hook absent from the template: RED
  D="$TMPROOT/s5"; _fixture "$D"
  _valid_manifest > "$D/adapters/claude-code/manifest.json"
  printf '{"hooks":{}}\n' > "$D/adapters/claude-code/settings.json.template"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s5-wired-claim-not-in-template-red" 1 "$RC" "RED wired-template" "$OUT"

  # S6 — gen-index golden compare (deterministic output)
  D="$TMPROOT/s6"; _fixture "$D"
  _valid_manifest > "$D/adapters/claude-code/manifest.json"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" --gen-index 2>&1)"; RC=$?
  local GOLDEN="$TMPROOT/golden-index.md"
  cat > "$GOLDEN" <<'EOF'
# Doctrine INDEX — generated from manifest.json by manifest-check.sh --gen-index

Do not hand-edit: regenerate with `bash adapters/claude-code/scripts/manifest-check.sh --gen-index`.

| id | kind | doctrine | hooks | blocking | honest_status |
|---|---|---|---|---|---|
| a-gate | gate | [doctrine/a.md](a.md) | a-gate.sh | yes | — |
| b-pending | gate | — | b-pending.sh | yes | invoked via a chain script; not directly wired |
EOF
  if [[ $RC -eq 0 ]] && diff -q "$D/adapters/claude-code/doctrine/INDEX.md" "$GOLDEN" >/dev/null 2>&1; then
    echo "self-test (s6-gen-index-golden): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (s6-gen-index-golden): FAIL (rc=${RC})" >&2
    diff "$D/adapters/claude-code/doctrine/INDEX.md" "$GOLDEN" >&2 || true
    FAILED=$((FAILED + 1))
  fi

  # S7 — enforcing era: doctrine/INDEX.md exists and a doctrine_file target
  # is missing: RED
  D="$TMPROOT/s7"; _fixture "$D"
  _valid_manifest > "$D/adapters/claude-code/manifest.json"
  mkdir -p "$D/adapters/claude-code/doctrine"
  printf '# generated index stub\n' > "$D/adapters/claude-code/doctrine/INDEX.md"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s7-doctrine-enforcing-red" 1 "$RC" "RED doctrine-file" "$OUT"

  # S8 — mid-C.4 transition: doctrine/ exists but no generated INDEX.md and
  # a doctrine_file target is missing: GREEN with an aggregate WARN naming it
  D="$TMPROOT/s8"; _fixture "$D"
  _valid_manifest > "$D/adapters/claude-code/manifest.json"
  mkdir -p "$D/adapters/claude-code/doctrine"
  OUT="$(MANIFEST_CHECK_ROOT="$D" bash "$SELF" check 2>&1)"; RC=$?
  _assert "s8-doctrine-transition-warn-green" 0 "$RC" "WARN doctrine-file.*doctrine/a.md" "$OUT"

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed" >&2
  [[ "$FAILED" -gt 0 ]] && return 1
  return 0
}

# ============================================================
# main
# ============================================================
case "${1:-check}" in
  --self-test)
    run_self_test
    exit $?
    ;;
  --gen-index)
    ROOT="$(resolve_root)" || { echo "[manifest-check] ERROR: cannot resolve repo root" >&2; exit 2; }
    run_gen_index "$ROOT"
    exit $?
    ;;
  check|--check|"")
    ROOT="$(resolve_root)" || { echo "[manifest-check] ERROR: cannot resolve repo root" >&2; exit 2; }
    run_check "$ROOT"
    exit $?
    ;;
  *)
    echo "usage: manifest-check.sh [check|--gen-index|--self-test]" >&2
    exit 2
    ;;
esac
