#!/bin/bash
# static-trace.sh — 2026-05-11
#
# Auto-detect and trace import / call chains for a list of modified files.
# Designed for Next.js + React + Prisma codebases.
#
# Differs from wire-check-gate.sh's static trace:
#   - wire-check-gate parses plan-declared `**Wire checks:**` arrows and
#     verifies them. Operator-authored chain.
#   - static-trace.sh AUTO-DETECTS each file's role from its path and
#     traces the chain by grepping import statements / fetch calls /
#     Prisma model references. No plan input needed.
#
# Usage:
#   bash static-trace.sh <file> [<file> ...]      # explicit list
#   bash static-trace.sh --git-diff [<base-ref>]  # files vs base-ref
#                                                 # (default: master)
#   git diff --name-only HEAD~3 | bash static-trace.sh   # via stdin
#   bash static-trace.sh --self-test
#
# File-type detection (path-based):
#   src/app/api/**/route.{ts,tsx,js,jsx}  → api-route
#   src/app/**/page.{tsx,jsx,js}          → page
#   src/app/**/layout.{tsx,jsx}           → layout
#   src/components/**/*.{tsx,jsx}         → component
#   {src/,}lib/**/*.{ts,js}               → logic
#   prisma/**/*.prisma                    → prisma-schema
#   anything else                         → unknown (UNTRACEABLE)
#
# Per-type tracing:
#   page/layout    → fetch('/api/...') calls; verify each route file exists
#   api-route      → derive route path; find consumers (UI files that fetch
#                    it); detect imported business logic (lib/)
#   logic          → who imports this file (by basename); what DB ops
#                    (prisma|db).<model>.<op>(...) it performs
#   component      → who imports/renders it; fetch calls it makes
#   prisma-schema  → for each model {} block, count references in src/
#
# Status report per file (first-line status, indented details):
#   CONNECTED   — chain followed end-to-end; relevant downstream/upstream
#                 references exist
#   BROKEN      — chain has a structural gap (page calls /api/X but
#                 src/app/api/X/route.* doesn't exist; component
#                 references function not in any file)
#   ORPHAN      — file exists but no consumers / no DB ops / no
#                 references (dead code candidate, or wired only via
#                 dynamic patterns the trace can't see)
#   UNTRACEABLE — file type not recognized OR chain follows patterns
#                 outside this script's pattern repertoire
#
# Exit codes:
#   0 — all chains CONNECTED, ORPHAN, or UNTRACEABLE (ORPHAN is a
#       warning, not a failure — dead-code suspicion isn't a build break)
#   1 — at least one chain is BROKEN
#   2 — usage error
#
# Self-test: `bash static-trace.sh --self-test` exercises 9 scenarios.

set -u

# ============================================================
# --self-test
# ============================================================

if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT
  # Resolve to absolute path so `cd` in run_in doesn't lose us
  SCRIPT_REL="${BASH_SOURCE[0]}"
  if [[ "${SCRIPT_REL:0:1}" == "/" ]]; then
    SCRIPT="$SCRIPT_REL"
  else
    SCRIPT="$(cd "$(dirname "$SCRIPT_REL")" && pwd)/$(basename "$SCRIPT_REL")"
  fi
  FAILED=0

  init_repo() {
    local root="$1"
    mkdir -p "$root"
    ( cd "$root" && git init -q && git config user.email t@t && git config user.name t ) || true
  }

  run_in() {
    local root="$1"; shift
    ( cd "$root" && bash "$SCRIPT" "$@" )
  }

  # Scenario s1: page fetches /api/foo and route exists → CONNECTED
  ROOT_S1="$TMPDIR_SELFTEST/s1"
  init_repo "$ROOT_S1"
  mkdir -p "$ROOT_S1/src/app/foo" "$ROOT_S1/src/app/api/foo"
  cat > "$ROOT_S1/src/app/foo/page.tsx" <<'F'
"use client";
import { useEffect } from "react";
export default function FooPage() {
  useEffect(() => { fetch('/api/foo').then(r => r.json()); }, []);
  return <div>foo</div>;
}
F
  cat > "$ROOT_S1/src/app/api/foo/route.ts" <<'F'
export async function GET() { return Response.json({ ok: true }); }
F
  S1_OUT=$(run_in "$ROOT_S1" src/app/foo/page.tsx 2>&1)
  S1_EXIT=$?
  if [[ $S1_EXIT -eq 0 ]] && echo "$S1_OUT" | grep -q "CONNECTED"; then
    echo "self-test (s1) page-with-existing-api-route: PASS (expected)" >&2
  else
    echo "self-test (s1) page-with-existing-api-route: FAIL (expected CONNECTED, exit 0)" >&2
    echo "exit=$S1_EXIT" >&2
    echo "$S1_OUT" >&2
    FAILED=1
  fi

  # Scenario s2: page fetches /api/missing — no route file → BROKEN, exit 1
  ROOT_S2="$TMPDIR_SELFTEST/s2"
  init_repo "$ROOT_S2"
  mkdir -p "$ROOT_S2/src/app/foo"
  cat > "$ROOT_S2/src/app/foo/page.tsx" <<'F'
"use client";
export default function FooPage() {
  fetch('/api/missing').then(r => r.json());
  return <div>foo</div>;
}
F
  S2_OUT=$(run_in "$ROOT_S2" src/app/foo/page.tsx 2>&1)
  S2_EXIT=$?
  if [[ $S2_EXIT -eq 1 ]] && echo "$S2_OUT" | grep -q "BROKEN"; then
    echo "self-test (s2) page-with-missing-api-route-blocks: PASS (expected)" >&2
  else
    echo "self-test (s2) page-with-missing-api-route-blocks: FAIL (expected BROKEN, exit 1)" >&2
    echo "exit=$S2_EXIT" >&2
    echo "$S2_OUT" >&2
    FAILED=1
  fi

  # Scenario s3: component not imported anywhere → ORPHAN (exit 0 — warning)
  ROOT_S3="$TMPDIR_SELFTEST/s3"
  init_repo "$ROOT_S3"
  mkdir -p "$ROOT_S3/src/components"
  cat > "$ROOT_S3/src/components/UnusedWidget.tsx" <<'F'
export function UnusedWidget() { return <div>nobody uses me</div>; }
F
  S3_OUT=$(run_in "$ROOT_S3" src/components/UnusedWidget.tsx 2>&1)
  S3_EXIT=$?
  if [[ $S3_EXIT -eq 0 ]] && echo "$S3_OUT" | grep -q "ORPHAN"; then
    echo "self-test (s3) unused-component-orphan-warns-only: PASS (expected)" >&2
  else
    echo "self-test (s3) unused-component-orphan-warns-only: FAIL (expected ORPHAN, exit 0)" >&2
    echo "exit=$S3_EXIT" >&2
    echo "$S3_OUT" >&2
    FAILED=1
  fi

  # Scenario s4: random unknown file type → UNTRACEABLE, exit 0
  ROOT_S4="$TMPDIR_SELFTEST/s4"
  init_repo "$ROOT_S4"
  mkdir -p "$ROOT_S4/scripts"
  cat > "$ROOT_S4/scripts/build.sh" <<'F'
#!/bin/bash
echo "building"
F
  S4_OUT=$(run_in "$ROOT_S4" scripts/build.sh 2>&1)
  S4_EXIT=$?
  if [[ $S4_EXIT -eq 0 ]] && echo "$S4_OUT" | grep -q "UNTRACEABLE"; then
    echo "self-test (s4) unknown-file-type-untraceable: PASS (expected)" >&2
  else
    echo "self-test (s4) unknown-file-type-untraceable: FAIL (expected UNTRACEABLE, exit 0)" >&2
    echo "exit=$S4_EXIT" >&2
    echo "$S4_OUT" >&2
    FAILED=1
  fi

  # Scenario s5: api-route consumed by a page → CONNECTED
  ROOT_S5="$TMPDIR_SELFTEST/s5"
  init_repo "$ROOT_S5"
  mkdir -p "$ROOT_S5/src/app/api/users" "$ROOT_S5/src/app/users" "$ROOT_S5/src/lib"
  cat > "$ROOT_S5/src/app/api/users/route.ts" <<'F'
import { listUsers } from "@/lib/users";
export async function GET() { return Response.json(await listUsers()); }
F
  cat > "$ROOT_S5/src/app/users/page.tsx" <<'F'
"use client";
export default function Page() {
  fetch('/api/users').then(r => r.json());
  return <div />;
}
F
  cat > "$ROOT_S5/src/lib/users.ts" <<'F'
export async function listUsers() { return []; }
F
  S5_OUT=$(run_in "$ROOT_S5" src/app/api/users/route.ts 2>&1)
  S5_EXIT=$?
  if [[ $S5_EXIT -eq 0 ]] && echo "$S5_OUT" | grep -q "CONNECTED"; then
    echo "self-test (s5) api-route-with-consumer-and-logic: PASS (expected)" >&2
  else
    echo "self-test (s5) api-route-with-consumer-and-logic: FAIL (expected CONNECTED)" >&2
    echo "exit=$S5_EXIT" >&2
    echo "$S5_OUT" >&2
    FAILED=1
  fi

  # Scenario s6: api-route with no consumer → ORPHAN
  ROOT_S6="$TMPDIR_SELFTEST/s6"
  init_repo "$ROOT_S6"
  mkdir -p "$ROOT_S6/src/app/api/orphan"
  cat > "$ROOT_S6/src/app/api/orphan/route.ts" <<'F'
export async function GET() { return Response.json({}); }
F
  S6_OUT=$(run_in "$ROOT_S6" src/app/api/orphan/route.ts 2>&1)
  S6_EXIT=$?
  if [[ $S6_EXIT -eq 0 ]] && echo "$S6_OUT" | grep -q "ORPHAN"; then
    echo "self-test (s6) api-route-with-no-consumer-orphan: PASS (expected)" >&2
  else
    echo "self-test (s6) api-route-with-no-consumer-orphan: FAIL (expected ORPHAN)" >&2
    echo "exit=$S6_EXIT" >&2
    echo "$S6_OUT" >&2
    FAILED=1
  fi

  # Scenario s7: prisma schema with referenced model → CONNECTED
  ROOT_S7="$TMPDIR_SELFTEST/s7"
  init_repo "$ROOT_S7"
  mkdir -p "$ROOT_S7/prisma" "$ROOT_S7/src/lib"
  cat > "$ROOT_S7/prisma/schema.prisma" <<'F'
generator client { provider = "prisma-client-js" }
model User {
  id Int @id @default(autoincrement())
  email String @unique
}
F
  cat > "$ROOT_S7/src/lib/users.ts" <<'F'
import { prisma } from "./db";
export async function listUsers() { return prisma.user.findMany(); }
F
  S7_OUT=$(run_in "$ROOT_S7" prisma/schema.prisma 2>&1)
  S7_EXIT=$?
  if [[ $S7_EXIT -eq 0 ]] && echo "$S7_OUT" | grep -q "CONNECTED"; then
    echo "self-test (s7) prisma-model-with-references: PASS (expected)" >&2
  else
    echo "self-test (s7) prisma-model-with-references: FAIL (expected CONNECTED)" >&2
    echo "exit=$S7_EXIT" >&2
    echo "$S7_OUT" >&2
    FAILED=1
  fi

  # Scenario s8: dynamic route segment — component fetches /api/users/123,
  # actual route is at src/app/api/users/[id]/route.ts → CONNECTED
  ROOT_S8="$TMPDIR_SELFTEST/s8"
  init_repo "$ROOT_S8"
  mkdir -p "$ROOT_S8/src/app/api/users/[id]" "$ROOT_S8/src/components" "$ROOT_S8/src/app/users"
  cat > "$ROOT_S8/src/app/api/users/[id]/route.ts" <<'F'
export async function GET() { return Response.json({}); }
F
  cat > "$ROOT_S8/src/components/UserCard.tsx" <<'F'
"use client";
export function UserCard({ id }: { id: string }) {
  fetch(`/api/users/${id}`).then(r => r.json());
  return <div>user</div>;
}
F
  cat > "$ROOT_S8/src/app/users/page.tsx" <<'F'
import { UserCard } from "@/components/UserCard";
export default function Page() { return <UserCard id="1" />; }
F
  S8_OUT=$(run_in "$ROOT_S8" src/components/UserCard.tsx 2>&1)
  S8_EXIT=$?
  if [[ $S8_EXIT -eq 0 ]] && echo "$S8_OUT" | grep -q "CONNECTED"; then
    echo "self-test (s8) dynamic-segment-route-resolution: PASS (expected)" >&2
  else
    echo "self-test (s8) dynamic-segment-route-resolution: FAIL (expected CONNECTED)" >&2
    echo "exit=$S8_EXIT" >&2
    echo "$S8_OUT" >&2
    FAILED=1
  fi

  # Scenario s9: multiple files mix — one BROKEN, one CONNECTED → exit 1
  ROOT_S9="$TMPDIR_SELFTEST/s9"
  init_repo "$ROOT_S9"
  mkdir -p "$ROOT_S9/src/app/good" "$ROOT_S9/src/app/api/good" "$ROOT_S9/src/app/bad"
  cat > "$ROOT_S9/src/app/good/page.tsx" <<'F'
fetch('/api/good');
export default function P() { return null; }
F
  cat > "$ROOT_S9/src/app/api/good/route.ts" <<'F'
export async function GET() { return Response.json({}); }
F
  cat > "$ROOT_S9/src/app/bad/page.tsx" <<'F'
fetch('/api/does-not-exist');
export default function P() { return null; }
F
  S9_OUT=$(run_in "$ROOT_S9" src/app/good/page.tsx src/app/bad/page.tsx 2>&1)
  S9_EXIT=$?
  if [[ $S9_EXIT -eq 1 ]] && echo "$S9_OUT" | grep -q "BROKEN" && echo "$S9_OUT" | grep -q "CONNECTED"; then
    echo "self-test (s9) mixed-batch-one-broken-fails-overall: PASS (expected)" >&2
  else
    echo "self-test (s9) mixed-batch-one-broken-fails-overall: FAIL (expected exit 1 with both BROKEN+CONNECTED)" >&2
    echo "exit=$S9_EXIT" >&2
    echo "$S9_OUT" >&2
    FAILED=1
  fi

  if [[ $FAILED -eq 0 ]]; then
    echo "static-trace --self-test: all scenarios matched expectations" >&2
    exit 0
  else
    echo "static-trace --self-test: one or more scenarios failed" >&2
    exit 1
  fi
fi

# ============================================================
# Argument parsing
# ============================================================

FILES=()

if [[ "${1:-}" == "--git-diff" ]]; then
  BASE_REF="${2:-master}"
  if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
    # Fall back to last 5 commits if base ref invalid
    BASE_REF="HEAD~5"
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    FILES+=("$line")
  done < <(git diff --name-only "$BASE_REF" 2>/dev/null)
elif [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    [[ -z "$arg" ]] && continue
    FILES+=("$arg")
  done
elif [[ ! -t 0 ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    FILES+=("$line")
  done
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "static-trace: no files to analyze" >&2
  echo "Usage: bash static-trace.sh <file> [<file>...]" >&2
  echo "       bash static-trace.sh --git-diff [<base-ref>]" >&2
  echo "       git diff --name-only | bash static-trace.sh" >&2
  exit 0
fi

# ============================================================
# Repo root
# ============================================================

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Prefer rg when available (faster + better default ignores)
HAS_RG=0
if command -v rg >/dev/null 2>&1; then HAS_RG=1; fi

# ============================================================
# File-type detection
# ============================================================

detect_type() {
  local f="$1"
  if   [[ "$f" =~ ^src/app/api/.+/route\.(ts|tsx|js|jsx)$ ]]; then echo "api-route"
  elif [[ "$f" =~ ^src/app/.+/page\.(tsx|jsx|js)$ ]]; then echo "page"
  elif [[ "$f" =~ ^src/app/.+/layout\.(tsx|jsx)$ ]]; then echo "layout"
  elif [[ "$f" =~ ^src/components/.+\.(tsx|jsx)$ ]]; then echo "component"
  elif [[ "$f" =~ ^components/.+\.(tsx|jsx)$ ]]; then echo "component"
  elif [[ "$f" =~ ^(src/)?lib/.+\.(ts|js)$ ]]; then echo "logic"
  elif [[ "$f" =~ ^prisma/.+\.prisma$ ]]; then echo "prisma-schema"
  else echo "unknown"
  fi
}

# ============================================================
# Helper: extract fetch / axios / api-client routes from a file
# ============================================================

extract_fetch_routes() {
  local file="$1"
  # fetch('/api/...'), fetch("/api/..."), fetch(`/api/...`)
  # Backtick template literals: extract literal prefix up to first ${
  {
    grep -oE "fetch\((['\"\`])[^'\"\`\$]+" "$file" 2>/dev/null \
      | sed -E "s/^fetch\(['\"\`]//"
    grep -oE "(axios|apiClient|api)\.(get|post|put|patch|delete)\((['\"\`])[^'\"\`\$]+" "$file" 2>/dev/null \
      | sed -E "s/^[^(]+\((['\"\`])//"
  } | grep -E "^/api/" | sort -u
}

# ============================================================
# Helper: resolve an API path to a route file (handle dynamic [seg])
# ============================================================
# /api/users/123 → src/app/api/users/[id]/route.ts (if literal doesn't exist)
# /api/foo/bar   → src/app/api/foo/bar/route.ts
# Returns the resolved file path on stdout; empty if none found.

resolve_route_file() {
  local route_path="$1"  # e.g. /api/users/123 OR /api/users/ (trailing-/
                         # signals truncated template literal)
  local trailing_dynamic=0
  if [[ "${route_path: -1}" == "/" ]]; then
    trailing_dynamic=1
    route_path="${route_path%/}"
  fi

  # Try exact match first
  if [[ $trailing_dynamic -eq 0 ]]; then
    for ext in ts tsx js jsx; do
      if [[ -f "$REPO_ROOT/src/app${route_path}/route.${ext}" ]]; then
        echo "src/app${route_path}/route.${ext}"
        return 0
      fi
    done
  fi

  # Walk segments; replace each with [seg] candidates if literal misses
  IFS='/' read -r -a SEGS <<< "$route_path"
  # SEGS[0] is empty (leading /), SEGS[1] is "api"
  local cand="src/app"
  local i
  for (( i=1; i<${#SEGS[@]}; i++ )); do
    local seg="${SEGS[i]}"
    [[ -z "$seg" ]] && continue
    if [[ -d "$REPO_ROOT/$cand/$seg" ]]; then
      cand="$cand/$seg"
    else
      # Look for any [..] dynamic segment under cand
      local dyn
      dyn=$(find "$REPO_ROOT/$cand" -maxdepth 1 -type d -name '[*' 2>/dev/null | head -1)
      if [[ -n "$dyn" ]]; then
        cand="$cand/$(basename "$dyn")"
      else
        return 1
      fi
    fi
  done

  # Found cand. If trailing-dynamic was signaled, descend one more level
  # into a dynamic-segment child looking for route.*
  if [[ $trailing_dynamic -eq 1 ]]; then
    local dyn
    dyn=$(find "$REPO_ROOT/$cand" -maxdepth 1 -type d -name '[*' 2>/dev/null | head -1)
    if [[ -n "$dyn" ]]; then
      cand="${dyn#$REPO_ROOT/}"
    fi
  fi

  for ext in ts tsx js jsx; do
    if [[ -f "$REPO_ROOT/$cand/route.${ext}" ]]; then
      echo "${cand}/route.${ext}"
      return 0
    fi
  done

  # Final fall-back: even without trailing-dynamic, try a dynamic child
  # (handles literal numeric-style segments e.g. /api/users/123 where
  # walk found `users` as literal but `123` was substituted via [id])
  if [[ $trailing_dynamic -eq 0 ]]; then
    local dyn
    dyn=$(find "$REPO_ROOT/$cand" -maxdepth 1 -type d -name '[*' 2>/dev/null | head -1)
    if [[ -n "$dyn" ]]; then
      for ext in ts tsx js jsx; do
        if [[ -f "$dyn/route.${ext}" ]]; then
          echo "${dyn#$REPO_ROOT/}/route.${ext}"
          return 0
        fi
      done
    fi
  fi

  return 1
}

# ============================================================
# Helper: search for a literal pattern across src/, app/, components/
# ============================================================

search_repo() {
  local pattern="$1"
  shift
  local globs=("$@")
  if [[ $HAS_RG -eq 1 ]]; then
    local rg_args=(-l --no-messages "$pattern")
    for g in "${globs[@]}"; do rg_args+=(--glob "$g"); done
    # Limit search to common code dirs that exist
    local roots=()
    for d in src app components lib pages; do
      [[ -d "$REPO_ROOT/$d" ]] && roots+=("$REPO_ROOT/$d")
    done
    [[ ${#roots[@]} -eq 0 ]] && return 0
    rg "${rg_args[@]}" "${roots[@]}" 2>/dev/null \
      | sed "s|^$REPO_ROOT/||"
  else
    local find_args=()
    for g in "${globs[@]}"; do
      find_args+=(-o -name "$g")
    done
    # Drop leading -o
    find_args=("${find_args[@]:1}")
    local roots=()
    for d in src app components lib pages; do
      [[ -d "$REPO_ROOT/$d" ]] && roots+=("$REPO_ROOT/$d")
    done
    [[ ${#roots[@]} -eq 0 ]] && return 0
    find "${roots[@]}" -type f \( "${find_args[@]}" \) -print0 2>/dev/null \
      | xargs -0 grep -l -E "$pattern" 2>/dev/null \
      | sed "s|^$REPO_ROOT/||"
  fi
}

# ============================================================
# Trace: page / layout
# ============================================================

trace_page() {
  local f="$1"
  local routes
  routes=$(extract_fetch_routes "$REPO_ROOT/$f")

  if [[ -z "$routes" ]]; then
    # No fetch — could be server-component rendering. Check imports.
    local has_imports
    has_imports=$(grep -cE "^import " "$REPO_ROOT/$f" 2>/dev/null || echo 0)
    if [[ "$has_imports" =~ ^[0-9]+$ ]] && [[ $has_imports -gt 0 ]]; then
      echo "UNTRACEABLE: server-side page (no client fetch); $has_imports import(s) detected"
      return 0
    fi
    echo "ORPHAN: page makes no API calls and imports nothing"
    return 0
  fi

  local broken=0
  local report=""
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    local resolved
    resolved=$(resolve_route_file "$r" 2>/dev/null) || resolved=""
    if [[ -n "$resolved" ]]; then
      report+="    ✓ $r → $resolved"$'\n'
    else
      report+="    ✗ $r → no matching route file under src/app/api/"$'\n'
      broken=1
    fi
  done <<< "$routes"

  if [[ $broken -eq 1 ]]; then
    echo "BROKEN: at least one API call has no route file"
    printf '%s' "$report"
    return 1
  fi
  echo "CONNECTED:"
  printf '%s' "$report"
  return 0
}

# ============================================================
# Trace: api-route
# ============================================================

trace_api_route() {
  local f="$1"
  local route_path
  route_path=$(echo "$f" | sed -E 's|^src/app(/api/.+)/route\.(ts|tsx|js|jsx)$|\1|')
  if [[ "$route_path" == "$f" ]]; then
    echo "UNTRACEABLE: cannot derive route path from $f"
    return 0
  fi

  # Convert dynamic segments [id] → regex .+ for consumer search
  # /api/users/[id] → search for fetch.../api/users/<anything> (excluding /)
  local route_search
  route_search=$(echo "$route_path" | sed -E 's|/\[[^]]+\]|/[^/'\''`"]+|g')

  local consumers
  consumers=$(search_repo "['\"\\\`]${route_search}([^a-zA-Z0-9_]|\$)" '*.tsx' '*.ts' '*.jsx' '*.js' 2>/dev/null \
              | grep -v "^${f}$" | head -20)

  # Detect imports of business logic from this route
  local lib_imports
  lib_imports=$(grep -E "^import .* from ['\"]" "$REPO_ROOT/$f" 2>/dev/null \
                | grep -oE "['\"][^'\"]+['\"]" \
                | sed "s/['\"]//g" \
                | grep -E "(/lib/|^@/lib/|^lib/)" \
                | sort -u | head -10)

  if [[ -z "$consumers" ]]; then
    echo "ORPHAN: $route_path"
    echo "    No UI file fetches this route (searched for ${route_search})"
    if [[ -n "$lib_imports" ]]; then
      echo "    Note: route imports business logic but is not consumed:"
      echo "$lib_imports" | sed 's/^/      /'
    fi
    return 0
  fi

  echo "CONNECTED:"
  echo "    Route: $route_path"
  echo "    Consumed by:"
  echo "$consumers" | head -10 | sed 's/^/      /'
  if [[ -n "$lib_imports" ]]; then
    echo "    Imports business logic:"
    echo "$lib_imports" | sed 's/^/      /'
  fi
  return 0
}

# ============================================================
# Trace: logic (src/lib/**)
# ============================================================

trace_logic() {
  local f="$1"
  # Stem without extension
  local stem
  stem=$(basename "$f" | sed -E 's/\.(ts|tsx|js|jsx)$//')

  # Importers: search for `from "...<stem>"` or `from '..../<stem>'`
  local importers
  importers=$(search_repo "from ['\"\\\`][^'\"\\\`]*${stem}['\"\\\`]" '*.tsx' '*.ts' '*.jsx' '*.js' 2>/dev/null \
              | grep -v "^${f}$" | head -10)

  # DB ops via Prisma client: prisma.<model>.<op>(...) or db.<model>.<op>(...)
  local db_ops
  db_ops=$(grep -oE "(prisma|db)\.[a-z][a-zA-Z0-9_]+\.(findUnique|findUniqueOrThrow|findFirst|findMany|create|createMany|update|updateMany|delete|deleteMany|upsert|count|aggregate|groupBy)" "$REPO_ROOT/$f" 2>/dev/null \
           | sort -u | head -10)

  if [[ -z "$importers" ]] && [[ -z "$db_ops" ]]; then
    echo "ORPHAN: not imported anywhere AND no DB operations"
    return 0
  fi

  echo "CONNECTED:"
  if [[ -n "$importers" ]]; then
    echo "    Imported by:"
    echo "$importers" | sed 's/^/      /'
  else
    echo "    No importers (utility/internal-only)"
  fi
  if [[ -n "$db_ops" ]]; then
    echo "    DB operations:"
    echo "$db_ops" | sed 's/^/      /'
  fi
  return 0
}

# ============================================================
# Trace: component
# ============================================================

trace_component() {
  local f="$1"
  local stem
  stem=$(basename "$f" | sed -E 's/\.(tsx|jsx|ts|js)$//')

  # Importers — by stem
  local importers
  importers=$(search_repo "from ['\"\\\`][^'\"\\\`]*${stem}['\"\\\`]" '*.tsx' '*.ts' '*.jsx' '*.js' 2>/dev/null \
              | grep -v "^${f}$" | head -10)
  # If no import-style importers, look for direct JSX usage
  if [[ -z "$importers" ]]; then
    importers=$(search_repo "<${stem}[ />]" '*.tsx' '*.jsx' 2>/dev/null \
                | grep -v "^${f}$" | head -10)
  fi

  # Component's own fetches
  local fetches
  fetches=$(extract_fetch_routes "$REPO_ROOT/$f")

  local broken=0
  local fetch_report=""
  if [[ -n "$fetches" ]]; then
    while IFS= read -r r; do
      [[ -z "$r" ]] && continue
      local resolved
      resolved=$(resolve_route_file "$r" 2>/dev/null) || resolved=""
      if [[ -n "$resolved" ]]; then
        fetch_report+="      ✓ $r → $resolved"$'\n'
      else
        fetch_report+="      ✗ $r → no matching route file"$'\n'
        broken=1
      fi
    done <<< "$fetches"
  fi

  if [[ $broken -eq 1 ]]; then
    echo "BROKEN: component fetches an API route that doesn't exist"
    if [[ -n "$importers" ]]; then
      echo "    Used by:"
      echo "$importers" | head -5 | sed 's/^/      /'
    fi
    echo "    Fetches:"
    printf '%s' "$fetch_report"
    return 1
  fi

  if [[ -z "$importers" ]]; then
    echo "ORPHAN: component not imported / rendered anywhere"
    if [[ -n "$fetches" ]]; then
      echo "    Component does fetch APIs but is not used:"
      printf '%s' "$fetch_report"
    fi
    return 0
  fi

  echo "CONNECTED:"
  echo "    Used by:"
  echo "$importers" | head -10 | sed 's/^/      /'
  if [[ -n "$fetches" ]]; then
    echo "    Fetches:"
    printf '%s' "$fetch_report"
  fi
  return 0
}

# ============================================================
# Trace: prisma-schema
# ============================================================

trace_prisma() {
  local f="$1"
  local models
  models=$(grep -oE "^model[[:space:]]+[A-Z][A-Za-z0-9_]+" "$REPO_ROOT/$f" 2>/dev/null | awk '{print $2}')
  if [[ -z "$models" ]]; then
    echo "UNTRACEABLE: no model definitions found in $f"
    return 0
  fi

  local total_refs=0
  local report=""
  local orphan_models=""
  while IFS= read -r model; do
    [[ -z "$model" ]] && continue
    # PascalCase → camelCase: User → user, OrderLine → orderLine
    local lower="$(echo "${model:0:1}" | tr '[:upper:]' '[:lower:]')${model:1}"
    local refs
    refs=$(search_repo "(prisma|db)\.${lower}\." '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null | wc -l | tr -cd '[:digit:]')
    refs=${refs:-0}
    if [[ $refs -gt 0 ]]; then
      report+="    $model: $refs file(s) reference prisma.${lower}.*"$'\n'
    else
      orphan_models+="$model "
    fi
    total_refs=$((total_refs + refs))
  done <<< "$models"

  if [[ $total_refs -eq 0 ]]; then
    echo "ORPHAN: no model references found in src/"
    echo "    Models defined: $(echo "$models" | tr '\n' ' ')"
    return 0
  fi

  echo "CONNECTED:"
  printf '%s' "$report"
  if [[ -n "$orphan_models" ]]; then
    echo "    (Note: these models defined but unreferenced: $orphan_models)"
  fi
  return 0
}

# ============================================================
# Main loop
# ============================================================

TOTAL=0
COUNT_CONNECTED=0
COUNT_BROKEN=0
COUNT_ORPHAN=0
COUNT_UNTRACEABLE=0
EXIT_CODE=0

echo "═══════════════ static-trace ═══════════════"
echo "Repo root: $REPO_ROOT"
echo "Files:     ${#FILES[@]}"
echo ""

for f in "${FILES[@]}"; do
  TOTAL=$((TOTAL + 1))
  # Normalize: strip leading ./
  f="${f#./}"

  # Treat deleted files as UNTRACEABLE (cannot grep their content)
  if [[ ! -f "$REPO_ROOT/$f" ]] && [[ ! -f "$f" ]]; then
    echo "[$f]"
    echo "  UNTRACEABLE: file does not exist (deleted? renamed?)"
    echo ""
    COUNT_UNTRACEABLE=$((COUNT_UNTRACEABLE + 1))
    continue
  fi

  type=$(detect_type "$f")
  echo "[$f] type=$type"

  result=""
  rc=0
  case "$type" in
    page|layout)   result=$(trace_page "$f")       ; rc=$? ;;
    api-route)     result=$(trace_api_route "$f")  ; rc=$? ;;
    logic)         result=$(trace_logic "$f")      ; rc=$? ;;
    component)     result=$(trace_component "$f")  ; rc=$? ;;
    prisma-schema) result=$(trace_prisma "$f")     ; rc=$? ;;
    *)             result="UNTRACEABLE: file type not recognized" ; rc=0 ;;
  esac

  status_line=$(echo "$result" | head -1)
  echo "$result" | sed 's/^/  /'
  echo ""

  case "$status_line" in
    BROKEN*)      COUNT_BROKEN=$((COUNT_BROKEN + 1))         ; EXIT_CODE=1 ;;
    ORPHAN*)      COUNT_ORPHAN=$((COUNT_ORPHAN + 1)) ;;
    CONNECTED*)   COUNT_CONNECTED=$((COUNT_CONNECTED + 1)) ;;
    UNTRACEABLE*) COUNT_UNTRACEABLE=$((COUNT_UNTRACEABLE + 1)) ;;
    *)            COUNT_UNTRACEABLE=$((COUNT_UNTRACEABLE + 1)) ;;
  esac
done

echo "═══════════════ summary ═══════════════"
echo "  Total files:  $TOTAL"
echo "  CONNECTED:    $COUNT_CONNECTED"
echo "  BROKEN:       $COUNT_BROKEN"
echo "  ORPHAN:       $COUNT_ORPHAN  (warning, not blocking)"
echo "  UNTRACEABLE:  $COUNT_UNTRACEABLE"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "  Verdict:      PASS"
else
  echo "  Verdict:      FAIL — at least one BROKEN chain"
fi

exit $EXIT_CODE
