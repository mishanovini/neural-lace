#!/bin/bash
# review-record-gate-lib.sh — SHARED library for the review-before-deploy gate
# (harness-governance-batch-2026-07-15, batch task 2).
#
# WHY THIS EXISTS
#   Design: docs/design-notes/review-record-primitive.md (architecture-reviewer
#   verdict SOUND-WITH-AMENDMENTS, 2026-07-16). Nothing deterministically
#   required a harness change (hook/gate/agent/rule) to carry a `harness-reviewer`
#   PASS before it was committed, merged, or deployed — this failed twice in the
#   model-enforcement workstream (a buggy gate live-synced with zero review; a
#   fix deployed before its re-review returned). This lib is the shared
#   trigger-surface + coverage-check logic BOTH deploy carriers
#   (install.sh hard-block, session-start-auto-install.sh fail-open skip+warn)
#   source, so the surface definition and the covered/uncovered decision live in
#   exactly one place.
#
# TRIGGER SURFACE (Amendment A — path-glob match, manifest is a CROSS-CHECK not
# the source): a file is in-surface iff its path relative to
# adapters/claude-code/ matches:
#   hooks/**/*.sh | scripts/**/*.sh | agents/*.md (top-level only) | config/**
#   | manifest.json | settings.json.template | rules/**
#
# COVERAGE (Amendments D + E): a changed in-surface file is COVERED iff either
#   (a) its {path, blob_sha} appears in the cutover grandfather-manifest.json
#       (pre-cutover content — Amendment E, never needs a review record), OR
#   (b) its {path, blob_sha} appears in the content-keyed index.json with a
#       kind: harness-change-review, verdict: PASS row (Amendment D — the
#       INDEX is the hot-path read; docs/reviews/records/*.json itself is
#       audit-only and is NEVER scanned here).
# Anything else is UNCOVERED. Callers decide what to do about it (install.sh:
# hard block; session-start-auto-install.sh: skip + warn — Amendment F).
#
# API (source this file, then):
#   rrg_in_surface <path>                        -- rc 0 if in-surface
#   rrg_blob_sha_of_file <path>                   -- echo the live git blob sha
#                                                     of a working-tree file
#                                                     (empty + rc 1 if git or
#                                                     the file is unavailable)
#   rrg_blob_sha_of_ref <repo_root> <ref> <path>  -- echo the blob sha of
#                                                     <path> at <ref> (empty +
#                                                     rc 1 if unresolvable)
#   rrg_is_covered <repo_root> <ref-or-empty> <path> <blob_sha>
#                                                  -- rc 0 if covered.
#                                                     ref="" reads the
#                                                     grandfather/index files
#                                                     from the FILESYSTEM at
#                                                     repo_root (install.sh);
#                                                     a non-empty ref reads
#                                                     them via `git show
#                                                     <ref>:<path>`
#                                                     (session-start-auto-
#                                                     install.sh's canonical-
#                                                     content convention).
#
# FAIL-OPEN ON INFRASTRUCTURE FAILURE (not on genuine non-coverage): if git or
# jq is unavailable, or the sha cannot be resolved at all, rrg_is_covered
# returns 1 (not covered) but callers are expected to treat an
# infra-unavailable condition as "cannot verify" and WARN rather than hard-
# block — a missing `jq` binary must never brick every machine's install.
#
# Self-test: bash review-record-gate-lib.sh --self-test   (in-repo scenarios)

# ------------------------------------------------------------
# Trigger surface
# ------------------------------------------------------------

# rrg_in_surface <path> -- accepts either a path relative to repo root
# (adapters/claude-code/hooks/foo.sh) or already relative to the adapter dir
# (hooks/foo.sh); the adapters/claude-code/ prefix is stripped if present.
rrg_in_surface() {
  local full="$1" rel
  rel="${full#adapters/claude-code/}"
  case "$rel" in
    hooks/*.sh) return 0 ;;
    scripts/*.sh) return 0 ;;
    agents/*.md)
      # top-level only (agents/*.md, not agents/**/*.md) -- no further slash
      # after the agents/ prefix.
      [[ "${rel#agents/}" == */* ]] && return 1
      return 0
      ;;
    config/*) return 0 ;;
    manifest.json) return 0 ;;
    settings.json.template) return 0 ;;
    rules/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------
# Blob sha resolution
# ------------------------------------------------------------

# rrg_blob_sha_of_file <path> -- live git blob sha of a working-tree file's
# CURRENT bytes (does not require the file to be committed or tracked).
rrg_blob_sha_of_file() {
  local path="$1"
  command -v git >/dev/null 2>&1 || return 1
  [[ -f "$path" ]] || return 1
  git hash-object "$path" 2>/dev/null
}

# rrg_blob_sha_of_ref <repo_root> <ref> <relpath-from-repo-root> -- blob sha
# of <relpath> AS OF <ref>, without touching the working tree.
rrg_blob_sha_of_ref() {
  local repo_root="$1" ref="$2" relpath="$3"
  command -v git >/dev/null 2>&1 || return 1
  git -C "$repo_root" rev-parse --verify --quiet "${ref}:${relpath}" 2>/dev/null
}

# ------------------------------------------------------------
# Coverage lookup
# ------------------------------------------------------------

# _rrg_read_json <repo_root> <ref-or-empty> <relpath-from-repo-root>
# ref="" reads from the filesystem; a non-empty ref reads via `git show`.
_rrg_read_json() {
  local repo_root="$1" ref="$2" relpath="$3"
  if [[ -n "$ref" ]]; then
    git -C "$repo_root" show "${ref}:${relpath}" 2>/dev/null
  else
    cat "$repo_root/$relpath" 2>/dev/null
  fi
}

RRG_RECORDS_RELDIR="docs/reviews/records"

# rrg_is_covered <repo_root> <ref-or-empty> <full_relpath> <blob_sha>
#   full_relpath is repo-root-relative, e.g.
#   adapters/claude-code/hooks/model-pin-gate.sh
rrg_is_covered() {
  local repo_root="$1" ref="$2" relpath="$3" sha="$4"
  [[ -z "$sha" ]] && return 1
  command -v jq >/dev/null 2>&1 || return 1

  local gf idx
  gf="$(_rrg_read_json "$repo_root" "$ref" "${RRG_RECORDS_RELDIR}/grandfather-manifest.json")"
  idx="$(_rrg_read_json "$repo_root" "$ref" "${RRG_RECORDS_RELDIR}/index.json")"

  # Bootstrap fail-open: if NEITHER coverage file exists at all on this
  # checkout/ref, the review-before-deploy gate has never been bootstrapped
  # here (a checkout that predates this batch's bootstrap commit, or a
  # throwaway fixture repo with no docs/reviews/records/ at all) --
  # every file is treated as covered rather than blocking/skipping
  # everything. This is Amendment E's "never brick a fresh/stale machine"
  # extended one step further: a checkout where the gate's own bootstrap
  # data doesn't exist yet must not be bricked by the gate either. Distinct
  # from "the files exist but have no matching entry" (a real, correctly-
  # enforced non-coverage case, handled below).
  if [[ -z "$gf" ]] && [[ -z "$idx" ]]; then
    return 0
  fi

  if [[ -n "$gf" ]] && printf '%s' "$gf" | jq -e --arg p "$relpath" --arg s "$sha" \
       '(.entries // [])[] | select(.path == $p and .blob_sha == $s)' >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$idx" ]] && printf '%s' "$idx" | jq -e --arg p "$relpath" --arg s "$sha" \
       '(.entries // [])[] | select(.path == $p and .blob_sha == $s and .kind == "harness-change-review" and .verdict == "PASS")' >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

# rrg_uncovered_reason <repo_root> <ref-or-empty> <full_relpath> <blob_sha>
# echoes a one-line human reason a file is NOT covered (for teaching messages).
rrg_uncovered_reason() {
  local repo_root="$1" ref="$2" relpath="$3" sha="$4"
  if [[ -z "$sha" ]]; then
    printf 'blob_sha unresolvable (git unavailable or file missing)'
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'jq unavailable -- cannot verify review coverage'
    return 0
  fi
  printf 'no PASS harness-change-review record covers %s @ %s (not in grandfather-manifest.json, not in index.json)' "$relpath" "$sha"
}

# ------------------------------------------------------------
# --self-test
# ------------------------------------------------------------
_rrg_self_test() {
  local pass=0 fail=0 tmp
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t rrgself)
  trap 'rm -rf "$tmp"' RETURN

  # ---- in-surface: positive cases ----
  local p
  for p in \
    "adapters/claude-code/hooks/model-pin-gate.sh" \
    "adapters/claude-code/hooks/lib/nl-paths.sh" \
    "adapters/claude-code/scripts/write-evidence.sh" \
    "adapters/claude-code/scripts/dispatch-provenance.sh" \
    "adapters/claude-code/agents/harness-reviewer.md" \
    "adapters/claude-code/config/model-policy.json" \
    "adapters/claude-code/manifest.json" \
    "adapters/claude-code/settings.json.template" \
    "adapters/claude-code/rules/constitution.md" \
    "hooks/lib/merge-scan-lib.sh" \
  ; do
    if rrg_in_surface "$p"; then
      echo "PASS: in-surface($p)"; pass=$((pass+1))
    else
      echo "FAIL: in-surface($p) expected TRUE"; fail=$((fail+1))
    fi
  done

  # ---- in-surface: negative cases ----
  for p in \
    "adapters/claude-code/doctrine/model-selection.md" \
    "adapters/claude-code/skills/foo/SKILL.md" \
    "adapters/claude-code/templates/plan-template.md" \
    "docs/reviews/records/index.json" \
    "adapters/claude-code/agents/sub/nested.md" \
    "docs/backlog.md" \
  ; do
    if rrg_in_surface "$p"; then
      echo "FAIL: in-surface($p) expected FALSE"; fail=$((fail+1))
    else
      echo "PASS: NOT in-surface($p)"; pass=$((pass+1))
    fi
  done

  # ---- blob sha resolution (filesystem) ----
  mkdir -p "$tmp/repo/adapters/claude-code/hooks"
  printf '#!/bin/bash\necho v1\n' > "$tmp/repo/adapters/claude-code/hooks/alpha.sh"
  local sha
  sha=$(rrg_blob_sha_of_file "$tmp/repo/adapters/claude-code/hooks/alpha.sh")
  if [[ -n "$sha" ]] && [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "PASS: blob_sha_of_file resolves a 40-hex sha"; pass=$((pass+1))
  else
    echo "FAIL: blob_sha_of_file (got: '$sha')"; fail=$((fail+1))
  fi

  # ---- coverage: grandfather match ----
  mkdir -p "$tmp/repo/docs/reviews/records"
  printf '{"entries":[{"path":"adapters/claude-code/hooks/alpha.sh","blob_sha":"%s"}]}\n' "$sha" \
    > "$tmp/repo/docs/reviews/records/grandfather-manifest.json"
  printf '{"entries":[]}\n' > "$tmp/repo/docs/reviews/records/index.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "PASS: grandfathered blob is covered"; pass=$((pass+1))
  else
    echo "FAIL: grandfathered blob should be covered"; fail=$((fail+1))
  fi

  # ---- coverage: NOT covered (grandfather + index exist, both empty) ----
  printf '{"entries":[]}\n' > "$tmp/repo/docs/reviews/records/grandfather-manifest.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "FAIL: uncovered blob reported covered"; fail=$((fail+1))
  else
    echo "PASS: uncovered blob reported NOT covered"; pass=$((pass+1))
  fi

  # ---- coverage: bootstrap fail-open (NEITHER file exists at all -- a
  # checkout that predates the gate's own bootstrap, e.g. a throwaway
  # fixture repo) must be treated as COVERED, not blocked ----
  mkdir -p "$tmp/repo-nobootstrap/adapters/claude-code/hooks"
  printf '#!/bin/bash\necho v1\n' > "$tmp/repo-nobootstrap/adapters/claude-code/hooks/alpha.sh"
  local nb_sha
  nb_sha=$(rrg_blob_sha_of_file "$tmp/repo-nobootstrap/adapters/claude-code/hooks/alpha.sh")
  if rrg_is_covered "$tmp/repo-nobootstrap" "" "adapters/claude-code/hooks/alpha.sh" "$nb_sha"; then
    echo "PASS: bootstrap fail-open (no records dir at all -> covered)"; pass=$((pass+1))
  else
    echo "FAIL: bootstrap fail-open should have reported covered"; fail=$((fail+1))
  fi

  # ---- coverage: index PASS match ----
  printf '{"entries":[{"path":"adapters/claude-code/hooks/alpha.sh","blob_sha":"%s","record_id":"hcr-x","kind":"harness-change-review","verdict":"PASS"}]}\n' "$sha" \
    > "$tmp/repo/docs/reviews/records/index.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "PASS: index PASS row covers the file"; pass=$((pass+1))
  else
    echo "FAIL: index PASS row should cover the file"; fail=$((fail+1))
  fi

  # ---- coverage: index REJECT row does NOT cover ----
  printf '{"entries":[{"path":"adapters/claude-code/hooks/alpha.sh","blob_sha":"%s","record_id":"hcr-y","kind":"harness-change-review","verdict":"REJECT"}]}\n' "$sha" \
    > "$tmp/repo/docs/reviews/records/index.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "FAIL: REJECT row should not cover the file"; fail=$((fail+1))
  else
    echo "PASS: REJECT row does not cover the file"; pass=$((pass+1))
  fi

  # ---- coverage: different blob_sha (content changed) is NOT covered by an
  # old PASS record for the same path ----
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "0000000000000000000000000000000000000000"; then
    echo "FAIL: a different blob_sha must not match a stale record"; fail=$((fail+1))
  else
    echo "PASS: changed content (new blob_sha) is not covered by the old record"; pass=$((pass+1))
  fi

  # ---- coverage via git ref (auto-install path) ----
  ( cd "$tmp/repo" && git init -q && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit -q -m init && git branch -M master )
  printf '{"entries":[{"path":"adapters/claude-code/hooks/alpha.sh","blob_sha":"%s","record_id":"hcr-z","kind":"harness-change-review","verdict":"PASS"}]}\n' "$sha" \
    > "$tmp/repo/docs/reviews/records/index.json"
  ( cd "$tmp/repo" && git add -A && git commit -q -m "index update" )
  if rrg_is_covered "$tmp/repo" "master" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "PASS: ref-based coverage lookup (auto-install convention)"; pass=$((pass+1))
  else
    echo "FAIL: ref-based coverage lookup should have matched"; fail=$((fail+1))
  fi

  # ---- rrg_blob_sha_of_ref ----
  local refsha
  refsha=$(rrg_blob_sha_of_ref "$tmp/repo" "master" "adapters/claude-code/hooks/alpha.sh")
  if [[ "$refsha" == "$sha" ]]; then
    echo "PASS: blob_sha_of_ref matches working-tree sha"; pass=$((pass+1))
  else
    echo "FAIL: blob_sha_of_ref (got '$refsha', want '$sha')"; fail=$((fail+1))
  fi

  echo ""
  echo "[review-record-gate-lib self-test] ${pass} passed, ${fail} failed"
  [[ "$fail" -eq 0 ]]
}

# Only self-invoke when this file is EXECUTED directly (bash foo.sh
# --self-test), never when it is `source`d by a caller -- a sourced library
# inherits the CALLER's positional params, so a caller invoked as
# `write-review-record.sh --self-test` would otherwise see this block match
# "$1" too and `exit` mid-source, before the caller's own dispatch ever runs.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  _rrg_self_test
  exit $?
fi
