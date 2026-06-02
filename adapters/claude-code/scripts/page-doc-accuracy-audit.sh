#!/bin/bash
# page-doc-accuracy-audit.sh — forward-facing page-vs-doc accuracy audit
# (Part B of ADR 046, redesigned 2026-06-01 per Misha: replaces the
# backwards-facing completed-plan walker).
#
# WHY THIS EXISTS
# ===============
# The completion-criteria-gate (Part A) catches INCOMPLETENESS at session
# close, going forward. This audit catches DRIFT on what is already shipped:
# for every LIVE contractor-facing page (per the PageRegistry), does its
# support doc still accurately describe what the page actually does NOW?
#
# It catches: button renames that broke the doc ("Submit" -> "Save"); removed
# sections still described in docs; new features added without doc updates;
# pages shipped with no doc at all. It is FORWARD-FACING — current pages vs
# current docs — NOT a retrospective walk of historical plans/sprints (those
# are messy and don't reflect current useful state).
#
# PROJECT-GENERIC BY DESIGN
# =========================
# Ships in the harness kit (adapters/), scanned by the hygiene gate, so it
# carries NO project identifiers. Parameterized by --project <path> and keys
# off CONVENTIONS (Next.js app-router + a PageRegistry + docs/support/*.mdx),
# not names:
#   <project>/src/lib/page-registry.ts   slug|route|owner|doc_path entries
#   <project>/src/app/**/page.tsx         route components (route groups (x) stripped)
#   <project>/docs/support/<slug>.mdx     contractor-facing docs
#   <project>/src/**                       broad source tree (STALE precision search)
#
# STATIC, BEST-EFFORT (Misha: "start STATIC ... runtime can be a future
# enhancement"). It analyzes route component SOURCE; it does not run the app.
# Component-import sprawl means some page signals live in imported components
# the audit only partially follows — so:
#   - STALE is HIGH-PRECISION: a doc-named UI term is flagged stale ONLY if it
#     appears NOWHERE in the project's src/ tree. Mapping errors cannot cause a
#     false STALE (the cost of a false STALE is high — it tells the operator to
#     "fix" a correct doc).
#   - UNDOCUMENTED is BEST-EFFORT: page labels from the route's source closure
#     not mentioned in the doc. Conservative filters (multi-word / non-common).
#
# SEVERITY
#   STALE   (red)    — doc references UI that no longer exists in src. Actively
#                      misleading. Highest priority. Exit 1 if any found.
#   UNDOC   (yellow) — page has a prominent label the doc never mentions.
#   MISSING (white)  — no doc file for a contractor-facing page.
#   (BEHAVIOR_MISMATCH (orange) — "click X to Y" where code shows X does Z —
#    deferred to a future enhancement; too low-precision for v1.)
#
# USAGE
#   page-doc-accuracy-audit.sh [--project <path>] [--out <path>] [--date YYYY-MM-DD]
#                              [--page-registry <path>] [--support-dir <path>] [--quiet]
#   page-doc-accuracy-audit.sh --self-test
#
#   --out  default <project>/docs/audit/page-doc-accuracy-<date>.md
#
# EXIT CODES
#   0  ran, no STALE findings (UNDOC/MISSING may still be reported)
#   1  ran, >=1 STALE finding (actively-misleading docs)
#   2  usage error
#
# SCHEDULE: weekly (scheduled task) or on-demand. Docs rarely go stale faster.

set -u

PROJECT="."
OUT=""
DATE=""
PAGE_REGISTRY=""
SUPPORT_DIR=""
QUIET=0

if [[ "${1:-}" == "--self-test" ]]; then
  SELFTEST=1
else
  SELFTEST=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)       PROJECT="${2:-}"; shift 2 ;;
      --out)           OUT="${2:-}"; shift 2 ;;
      --date)          DATE="${2:-}"; shift 2 ;;
      --page-registry) PAGE_REGISTRY="${2:-}"; shift 2 ;;
      --support-dir)   SUPPORT_DIR="${2:-}"; shift 2 ;;
      --quiet)         QUIET=1; shift ;;
      -h|--help) sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "page-doc-accuracy-audit: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
fi

# Common single-word button labels that docs rarely name individually — excluded
# from UNDOCUMENTED to keep it signal (STALE still checks them via src presence).
COMMON_BTN_RE='^(Save|Cancel|Close|Delete|Edit|Back|Next|Submit|OK|Okay|Yes|No|Continue|Confirm|Done|Add|Remove|Apply|Reset|Clear|Loading|Saving|Export|Import|Search|Filter|Refresh|Retry|Send|Open|View|More|Less|Show|Hide|Up|Down|Copy|Paste|Undo|Redo|Select|Toggle|Enable|Disable|Start|Stop|Pause|Play|Skip|Sign|Log|Menu|Home|Settings|Help)$'

# ------------------------------------------------------------
# normalize_route <app-relative-path-without-page.tsx>
# Strips (route group) segments, collapses //, ensures leading /.
# ------------------------------------------------------------
normalize_route() {
  local p="$1"
  # remove "(group)" path segments
  p="$(printf '%s' "$p" | sed -E 's#\([^/]*\)/##g; s#/\([^/]*\)##g')"
  # collapse duplicate slashes, strip trailing slash
  p="$(printf '%s' "$p" | sed -E 's#//+#/#g; s#/$##')"
  [[ "$p" != /* ]] && p="/$p"
  [[ "$p" == "/" || -z "$p" ]] && p="/"
  printf '%s' "$p"
}

# ------------------------------------------------------------
# build_route_map <project>  ->  emits "route\tfile" lines
# ------------------------------------------------------------
build_route_map() {
  local proj="$1" appdir="$proj/src/app" f rel route
  [[ -d "$appdir" ]] || return 0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rel="${f#"$appdir"/}"          # e.g. (dashboard)/contacts/page.tsx
    rel="${rel%/page.tsx}"          # e.g. (dashboard)/contacts
    [[ "$rel" == "page.tsx" ]] && rel=""   # app/page.tsx -> root
    route="$(normalize_route "$rel")"
    printf '%s\t%s\n' "$route" "$f"
  done < <(find "$appdir" -name 'page.tsx' -type f 2>/dev/null)
}

# Section-heading words too generic to count as an "undocumented feature".
COMMON_HEADING_RE='^(What you see|What you can do|What you see on this page|Common questions|Overview|Settings|Details|Summary|Actions|Filters|Search|Loading|Error|Results|Notes|Help|Status|Auto|Manual|Cold|Warm|Hot|Emergency|Filtered|All|None|Active|Inactive|New|Recent|Today|Yesterday)$'

# A "label-shaped" string: 1-4 Title-leading words, no trailing prose/punctuation.
# Filters truncated sentence fragments ("any item in the recent activi", "into Alerts").
LABEL_SHAPE_RE='^[A-Z][A-Za-z0-9]+([ /&-][A-Za-z0-9]+){0,3}$'

# ------------------------------------------------------------
# route_source_set <project> <page.tsx> -> echoes a space-list of source files:
# the page + its DIRECT one-level local imports (resolved). Deliberately does
# NOT glob whole feature dirs — that was both slow (9-min runs) and the source
# of UNDOCUMENTED noise. Headings come from the page + its imported sections.
# ------------------------------------------------------------
route_source_set() {
  local proj="$1" page="$2"
  local files="$page"
  [[ -f "$page" ]] || { printf '%s' "$page"; return; }
  local dir; dir="$(dirname "$page")"
  local imp resolved cand
  while IFS= read -r imp; do
    [[ -z "$imp" ]] && continue
    if [[ "$imp" == @/* ]]; then resolved="$proj/src/${imp#@/}"
    elif [[ "$imp" == ./* || "$imp" == ../* ]]; then resolved="$dir/$imp"
    else continue; fi
    for cand in "$resolved.tsx" "$resolved/index.tsx" "$resolved.ts"; do
      [[ -f "$cand" ]] && { files="$files $cand"; break; }
    done
  done < <(grep -oE "from[[:space:]]+['\"][^'\"]+['\"]" "$page" 2>/dev/null | sed -E "s/.*['\"]([^'\"]+)['\"]/\1/")
  printf '%s' "$files"
}

# ------------------------------------------------------------
# extract_page_headings <source-files...>  ->  newline list of <h1..h3> texts.
# Headings are the page's "prominent features" — far more reliable than trying
# to scrape every button label (which produced 224 noise hits / page-set).
# ------------------------------------------------------------
extract_page_headings() {
  local flat
  flat="$(cat "$@" 2>/dev/null | tr '\n' ' ')"
  printf '%s' "$flat" \
    | grep -oE '<h[1-3][^>]*>[[:space:]]*[A-Z][^<>{}]{1,40}' 2>/dev/null \
    | sed -E 's/<h[1-3][^>]*>[[:space:]]*//; s/[[:space:]]+$//' \
    | sed -E 's/[[:space:]]+/ /g' \
    | awk 'NF' | sort -u
}

# ------------------------------------------------------------
# extract_doc_ui_terms <doc.mdx>  ->  newline list of UI terms the doc CLAIMS,
# for the STALE check. ONLY **bold** terms that are label-shaped and NOT Q&A
# questions (those start with a quote). High-precision by construction: the
# earlier "click X" prose extractor produced sentence fragments and is removed.
# ------------------------------------------------------------
extract_doc_ui_terms() {
  local doc="$1" flat
  flat="$(cat "$doc" 2>/dev/null | tr '\n' ' ')"
  printf '%s' "$flat" \
    | grep -oE '\*\*[A-Z][A-Za-z0-9 &/-]{1,30}\*\*' 2>/dev/null \
    | sed -E 's/^\*\*//; s/\*\*$//; s/[[:space:]]+$//' \
    | grep -E "$LABEL_SHAPE_RE" 2>/dev/null \
    | awk 'NF' | sort -u
}

# ------------------------------------------------------------
# term_in_src <term>  -> 0 if the literal term appears anywhere in src/.
# Uses the prebuilt single-file SRC_INDEX (one concatenated blob of all source
# text) so each check is one in-file grep rather than a full tree-walk — the
# difference between seconds and minutes on a real codebase.
# ------------------------------------------------------------
term_in_src() {
  local term="$1"
  [[ -n "${SRC_INDEX:-}" && -f "$SRC_INDEX" ]] || return 0   # no index -> don't false-STALE
  grep -qF -- "$term" "$SRC_INDEX" 2>/dev/null
}

# ============================================================
# Core audit
# ============================================================
run_audit() {
  local proj="$1" date_stamp="$2" preg="$3" supdir="$4"
  [[ -z "$preg" ]] && preg="$proj/src/lib/page-registry.ts"
  [[ -z "$supdir" ]] && supdir="$proj/docs/support"
  local stale_total=0 undoc_total=0 missing_total=0 audited=0 pages_with_issues=0
  local body=""   # accumulates per-page sections

  # Parse registry: slug|route|owner|doc_path (emit at closing brace; any order).
  local entries
  entries="$(awk '
    function pick(line,  s){ match(line,/:[[:space:]]*[\x27"][^\x27"]+[\x27"]/); s=substr(line,RSTART,RLENGTH); sub(/:[[:space:]]*[\x27"]/,"",s); sub(/[\x27"].*/,"",s); return s }
    /^[[:space:]]*\{/ { slug="";route="";owner="";doc="" }
    /[[:space:]]*slug:[[:space:]]*[\x27"]/     { slug=pick($0) }
    /[[:space:]]*route:[[:space:]]*[\x27"]/    { route=pick($0) }
    /[[:space:]]*owner:[[:space:]]*[\x27"]/    { owner=pick($0) }
    /[[:space:]]*doc_path:[[:space:]]*[\x27"]/ { doc=pick($0) }
    /^[[:space:]]*\},?[[:space:]]*$/ { if(slug!="") { print slug "|" route "|" owner "|" doc; slug="" } }
  ' "$preg" 2>/dev/null)"

  local route_map; route_map="$(build_route_map "$proj")"

  # Build the single-file source index ONCE (all .ts/.tsx/.js/.jsx text
  # concatenated) so STALE's broad-src check is one in-file grep per term.
  SRC_INDEX="$(mktemp 2>/dev/null || echo "$proj/.pda-src-index")"
  find "$proj/src" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \
    -exec cat {} + > "$SRC_INDEX" 2>/dev/null || true

  local slug route owner doc
  while IFS='|' read -r slug route owner doc; do
    [[ -z "$slug" ]] && continue
    # SKIP platform-internal routes (audit log, platform console, impersonation...).
    [[ "$owner" != "org" ]] && continue
    audited=$((audited+1))

    local page_issues=""

    # Resolve doc path (registry doc_path, else slug convention).
    local docfile=""
    if [[ -n "$doc" && -f "$proj/$doc" ]]; then docfile="$proj/$doc"
    elif [[ -f "$supdir/$slug.mdx" ]]; then docfile="$supdir/$slug.mdx"; fi

    if [[ -z "$docfile" ]]; then
      missing_total=$((missing_total+1))
      page_issues="${page_issues}- ⚪ **MISSING_DOC** — no support doc for \`$route\` (expected \`${doc:-docs/support/$slug.mdx}\`).\n"
      body="${body}### \`$route\` (\`$slug\`)\n${page_issues}\n"
      pages_with_issues=$((pages_with_issues+1))
      continue
    fi

    # Resolve the page component + source closure.
    local page; page="$(printf '%s' "$route_map" | awk -F'\t' -v r="$route" '$1==r{print $2; exit}')"
    local srcset=""
    [[ -n "$page" ]] && srcset="$(route_source_set "$proj" "$page")"

    # --- STALE (high-precision; mapping-independent broad src search) ---
    local term
    while IFS= read -r term; do
      [[ -z "$term" ]] && continue
      [[ "${#term}" -lt 3 ]] && continue
      if ! term_in_src "$term"; then
        stale_total=$((stale_total+1))
        page_issues="${page_issues}- 🔴 **STALE** — doc references \`$term\` but it appears nowhere in \`src/\` (renamed/removed?). Fix the doc or confirm the page.\n"
      fi
    done < <(extract_doc_ui_terms "$docfile")

    # --- UNDOCUMENTED (best-effort; page HEADINGS vs doc text) ---
    # Page section headings are the "prominent features". A heading the doc never
    # mentions is a real undocumented-feature signal; button labels were too noisy.
    if [[ -n "$srcset" ]]; then
      local doctext; doctext="$(tr '[:upper:]' '[:lower:]' < "$docfile" 2>/dev/null | tr '\n' ' ')"
      local head undoc_count=0
      while IFS= read -r head; do
        [[ -z "$head" ]] && continue
        [[ "${#head}" -lt 4 ]] && continue
        printf '%s' "$head" | grep -qiE "$COMMON_HEADING_RE" && continue   # generic section words
        local lc; lc="$(printf '%s' "$head" | tr '[:upper:]' '[:lower:]')"
        if ! printf '%s' "$doctext" | grep -qF -- "$lc"; then
          [[ "$undoc_count" -ge 6 ]] && continue   # cap per page
          undoc_total=$((undoc_total+1)); undoc_count=$((undoc_count+1))
          page_issues="${page_issues}- 🟡 **UNDOCUMENTED** — page section \`$head\` is not mentioned in the doc.\n"
        fi
      done < <(extract_page_headings $srcset)
    elif [[ -z "$page" ]]; then
      page_issues="${page_issues}- ⚪ note — route component not found under \`src/app/\` for \`$route\` (UNDOCUMENTED check skipped; STALE still ran).\n"
    fi

    if [[ -n "$page_issues" ]]; then
      pages_with_issues=$((pages_with_issues+1))
      body="${body}### \`$route\` (\`$slug\`)\n${page_issues}\n"
    fi
  done <<< "$entries"

  # ---- Report ----
  echo "# Page-vs-Doc Accuracy Audit — $date_stamp"
  echo ""
  echo "Generated by \`page-doc-accuracy-audit.sh\` (ADR 046, Part B). For every LIVE"
  echo "contractor-facing page (PageRegistry \`owner: 'org'\`), checks whether its"
  echo "support doc still accurately describes the page **as it exists now**."
  echo "STATIC + best-effort: STALE is high-precision (doc-named term absent from all"
  echo "of \`src/\`); UNDOCUMENTED is best-effort (route source closure vs doc text)."
  echo ""
  echo "Project audited: \`$(basename "$proj")\`"
  echo ""
  echo "## Executive summary"
  echo ""
  echo "- Contractor-facing pages audited: **$audited** (platform/admin routes skipped)"
  echo "- Pages with ≥1 issue: **$pages_with_issues**"
  echo "- 🔴 STALE (doc references removed/renamed UI — actively misleading): **$stale_total**"
  echo "- 🟡 UNDOCUMENTED (page feature not covered by the doc): **$undoc_total**"
  echo "- ⚪ MISSING_DOC (no doc at all): **$missing_total**"
  echo ""
  if [[ "$stale_total" -eq 0 && "$undoc_total" -eq 0 && "$missing_total" -eq 0 ]]; then
    echo "_No issues found — every audited page's doc matches its current UI (within"
    echo "the limits of static analysis)._"
    echo ""
  else
    echo "## Per-page findings"
    echo ""
    printf '%b' "$body"
  fi
  echo "## Notes & limitations"
  echo ""
  echo "- **STALE is the priority class** — it means a doc tells contractors to use UI that no longer exists. Exit code is 1 when any STALE is found."
  echo "- UNDOCUMENTED is best-effort: component-import sprawl means some page labels come from imported components the audit only partially follows; treat 🟡 as a prompt to confirm, not a confirmed gap."
  echo "- BEHAVIOR_MISMATCH (doc says \"click X to Y\" but code shows X does Z) is a future enhancement — too low-precision for static v1."
  echo "- Runtime (Playwright against the deployed app) is a future enhancement; this v1 is static-only."
  echo ""

  [[ -n "${SRC_INDEX:-}" ]] && rm -f "$SRC_INDEX" 2>/dev/null || true
  printf '%s' "$stale_total" > "${AUDIT_STALECOUNT_FILE:-/dev/null}"
  if [[ "$stale_total" -gt 0 ]]; then return 1; fi
  return 0
}

# ============================================================
# --self-test
# ============================================================
if [[ "$SELFTEST" -eq 1 ]]; then
  PASS=0; FAIL=0
  ok(){ if [[ "$1" == "$2" ]]; then echo "PASS  $3"; PASS=$((PASS+1)); else echo "FAIL  $3 (want '$2' got '$1')"; FAIL=$((FAIL+1)); fi; }
  has(){ if printf '%s' "$1" | grep -qF -- "$2"; then echo "PASS  $3"; PASS=$((PASS+1)); else echo "FAIL  $3 (missing '$2')"; FAIL=$((FAIL+1)); fi; }
  hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then echo "FAIL  $3 (unexpected '$2')"; FAIL=$((FAIL+1)); else echo "PASS  $3"; PASS=$((PASS+1)); fi; }

  T=$(mktemp -d 2>/dev/null || mktemp -d -t pda)
  P="$T/proj"
  mkdir -p "$P/src/app/(dashboard)/widgets" "$P/src/app/(dashboard)/orphan" "$P/src/app/(admin)/console" \
           "$P/src/components/widgets" "$P/src/lib" "$P/docs/support"

  # Route component: imports a feature component holding the buttons.
  cat > "$P/src/app/(dashboard)/widgets/page.tsx" <<'EOF'
import { WidgetActions } from '@/components/widgets/widget-actions';
export default function WidgetsPage() {
  return (
    <div>
      <h2 className="text-2xl font-bold">
        Widgets
      </h2>
      <WidgetActions />
    </div>
  );
}
EOF
  cat > "$P/src/components/widgets/widget-actions.tsx" <<'EOF'
export function WidgetActions() {
  return (
    <div>
      <h3 className="text-lg font-semibold">Bulk Actions</h3>
      <button type="button">Frobnicate</button>
      <button type="button">Add Widget</button>
    </div>
  );
}
EOF
  # Doc: references a button "Sprocket" that exists NOWHERE in src -> STALE.
  #      mentions "Widgets" heading but NOT "Add Widget" -> UNDOCUMENTED.
  cat > "$P/docs/support/widgets.mdx" <<'EOF'
---
title: Widgets
---
## What you see on this page
The Widgets list. Click the **Sprocket** button to do the thing.
EOF

  # An org route with NO doc -> MISSING_DOC.
  cat > "$P/src/app/(dashboard)/orphan/page.tsx" <<'EOF'
export default function OrphanPage() { return <h2 className="text-2xl font-bold">Orphan</h2>; }
EOF

  # Platform route -> must be SKIPPED.
  cat > "$P/src/app/(admin)/console/page.tsx" <<'EOF'
export default function ConsolePage() { return <h2>Console</h2>; }
EOF

  cat > "$P/src/lib/page-registry.ts" <<'EOF'
const PAGES: readonly PageEntry[] = [
  {
    slug: 'widgets',
    route: '/widgets',
    doc_path: 'docs/support/widgets.mdx',
    owner: 'org',
    nav_label: 'Widgets',
  },
  {
    slug: 'orphan',
    route: '/orphan',
    doc_path: 'docs/support/orphan.mdx',
    owner: 'org',
    nav_label: 'Orphan',
  },
  {
    slug: 'console',
    route: '/admin/console',
    doc_path: 'docs/support/console.mdx',
    owner: 'platform',
    nav_label: 'Console',
  },
];
EOF

  out="$(AUDIT_STALECOUNT_FILE="$T/sc" run_audit "$P" "2026-06-01" "" ""; echo "rc=$?")"
  rc="$(printf '%s' "$out" | tail -1)"

  ok "$rc" "rc=1" "STALE present -> exit 1"
  has "$out" "STALE" "report has a STALE finding"
  has "$out" "Sprocket" "STALE names the removed term (Sprocket)"
  has "$out" "MISSING_DOC" "orphan route -> MISSING_DOC"
  has "$out" "UNDOCUMENTED" "report has an UNDOCUMENTED finding"
  has "$out" "Bulk Actions" "UNDOCUMENTED names the page-only heading (Bulk Actions)"
  # route-group resolution worked (widgets section present, keyed by /widgets)
  has "$out" "\`/widgets\`" "route-group route /widgets resolved + audited"
  # platform route skipped: console must not appear as an audited section
  hasnt "$out" "/admin/console" "platform route /admin/console skipped"
  # 'Widgets' heading IS in the doc -> must NOT be flagged undocumented
  hasnt "$out" "page section \`Widgets\`" "documented heading not flagged undocumented"
  # 'Frobnicate' exists in src -> must NOT be STALE (only Sprocket is)
  hasnt "$out" "references \`Frobnicate\`" "in-src term not falsely STALE"

  # Clean project: doc covers everything, no stale -> exit 0, no issues.
  P2="$T/clean"; mkdir -p "$P2/src/app/(dashboard)/widgets" "$P2/src/lib" "$P2/docs/support"
  cat > "$P2/src/app/(dashboard)/widgets/page.tsx" <<'EOF'
export default function WidgetsPage(){ return (<div><h2 className="text-2xl font-bold">Widgets</h2><button>Add Widget</button></div>); }
EOF
  cat > "$P2/docs/support/widgets.mdx" <<'EOF'
---
title: Widgets
---
## What you see on this page
The Widgets list. Use Add Widget to create a new one.
EOF
  cat > "$P2/src/lib/page-registry.ts" <<'EOF'
const PAGES: readonly PageEntry[] = [
  {
    slug: 'widgets',
    route: '/widgets',
    doc_path: 'docs/support/widgets.mdx',
    owner: 'org',
    nav_label: 'Widgets',
  },
];
EOF
  out2="$(AUDIT_STALECOUNT_FILE="$T/sc2" run_audit "$P2" "2026-06-01" "" ""; echo "rc=$?")"
  rc2="$(printf '%s' "$out2" | tail -1)"
  ok "$rc2" "rc=0" "clean project -> exit 0"
  has "$out2" "No issues found" "clean project reports no issues"

  # No registry at all -> graceful (0 audited, exit 0).
  P3="$T/empty"; mkdir -p "$P3/src"
  out3="$(AUDIT_STALECOUNT_FILE="$T/sc3" run_audit "$P3" "2026-06-01" "" ""; echo "rc=$?")"
  rc3="$(printf '%s' "$out3" | tail -1)"
  ok "$rc3" "rc=0" "no registry -> graceful exit 0"
  has "$out3" "audited: **0**" "no registry -> 0 pages audited"

  rm -rf "$T"
  echo ""
  echo "self-test: $PASS pass, $FAIL fail"
  if [[ "$FAIL" -gt 0 ]]; then echo "self-test: FAIL"; exit 1; fi
  echo "self-test: OK $PASS/$PASS"
  exit 0
fi

# ============================================================
# Normal path
# ============================================================
if [[ ! -d "$PROJECT" ]]; then echo "page-doc-accuracy-audit: --project '$PROJECT' is not a directory" >&2; exit 2; fi
PROJECT="$(cd "$PROJECT" && pwd)"
[[ -z "$DATE" ]] && DATE="$(date -u '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')"
[[ -z "$OUT" ]] && OUT="$PROJECT/docs/audit/page-doc-accuracy-$DATE.md"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true

SCFILE="$(mktemp 2>/dev/null || echo "$PROJECT/.pda-stalecount")"
AUDIT_STALECOUNT_FILE="$SCFILE" run_audit "$PROJECT" "$DATE" "$PAGE_REGISTRY" "$SUPPORT_DIR" > "$OUT"
RC=$?
STALE="$(cat "$SCFILE" 2>/dev/null || echo 0)"
rm -f "$SCFILE" 2>/dev/null || true

if [[ "$QUIET" -ne 1 ]]; then
  echo "page-doc-accuracy-audit: report written to $OUT"
  echo "page-doc-accuracy-audit: STALE findings (exit-blocking): ${STALE:-0}"
  [[ "$RC" -ne 0 ]] && echo "page-doc-accuracy-audit: STALE docs present — fix the actively-misleading docs (see report)." >&2
fi
exit "$RC"
