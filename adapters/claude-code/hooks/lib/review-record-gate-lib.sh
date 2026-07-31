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
#   hooks/**/*.{sh,js,ts,py,ps1} | scripts/**/*.{sh,js,ts,py,ps1}
#   | git-hooks/** | schemas/*.json | install.sh | sync.sh
#   | agents/*.md (top-level only) | config/**
#   | manifest.json | settings.json.template | rules/**
#
# TRIGGER SURFACE, CARRIER-CHAIN CLOSURE (Amendment H, 2026-07-30 —
# harness-reviewer CRITICAL 3). A review gate's trigger surface is derived from
# the gate's CARRIER CHAIN, not from a hand-written path list: every link that
# can decide whether the gate runs, or change what it decides, must itself be
# reviewed. The chain is
#   dispatcher (git-hooks/pre-push)
#     -> gate      (hooks/review-record-push-gate.sh)
#     -> lib       (hooks/lib/review-record-gate-lib.sh)
#     -> schema    (schemas/manifest.schema.json)
#     -> installer (install.sh, sync.sh)
# Before this amendment `rrg_in_surface` returned NOT-COVERED for FOUR of those
# five links, so the file that decides whether the review gate runs at all was
# itself unreviewable. MEASURED cost of closing it (tracked files, 2026-07-30):
# git-hooks/* = 5, schemas/*.json = 11, install.sh + sync.sh = 2, non-.sh code
# under hooks/ + scripts/ = 10 -- 283 -> 311 in-surface files (+9.9%).
#
# NON-.sh MEMBERS ARE MATCHED BY EXTENSION, NOT BY THE EXECUTABLE BIT. The
# reviewer's suggested "cover executable non-.sh members" rule was MEASURED
# against the real tree first and rejected: all 13 tracked non-.sh files under
# hooks/ and scripts/ are mode 100644, including the live
# hooks/lib/workstreams-task-bridge.js that motivated the finding
# (`git ls-files -s 'adapters/claude-code/hooks/*' 'adapters/claude-code/scripts/*'
# | grep -v '\.sh$'`). A mode-bit rule would have matched ZERO files and shipped
# as enforcement theatre. The extension list matches the 10 real code members
# and deliberately excludes the 3 non-code ones (*.md docs, *.example template).
#
# DEFERRED, with its cost measured rather than asserted: doctrine/** is 89
# tracked files (`git ls-files 'adapters/claude-code/doctrine/*' | wc -l`), a
# +31% expansion of the surface on its own, and doctrine is prose that changes
# far more often than the code that enforces it. It is the one arm where the
# merge-friction cost is genuinely large, so it stays OUT this pass and is
# tracked in docs/backlog.md rather than silently dropped.
#
# TRIGGER SURFACE, product side (Amendment G, 2026-07-30 — the cockpit was
# never reviewed: 0 of 255 review records ever covered it, measured via
# `jq -r '.entries[].path' docs/reviews/records/index.json | grep -c
# workstreams-ui`). Additive, repo-root-relative (no adapters/claude-code/
# prefix to strip): a file is ALSO in-surface iff its path matches:
#   neural-lace/workstreams-ui/server/**/*.js
#   | neural-lace/workstreams-ui/web/**/*.js
# INCLUDES *.selftest.js deliberately (see docs/harness-improvements/
# cockpit-review-surface-and-verification-gaps.md): a false-green self-test
# is the same failure class as unreviewed product code, proven the same day
# by cockpit.selftest.js's R17-DRAG-2 (a source-text regex that passed while
# the optimistic drag move it claimed to cover was a live no-op).
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
  # Amendment G (cockpit product surface) matches the REPO-ROOT-RELATIVE
  # path directly -- checked BEFORE the adapters/claude-code/ prefix strip
  # below, since these paths never carry that prefix and stripping is a
  # no-op for them anyway. Case-pattern `*` matches `/` (the same property
  # Amendment A's hooks/*.sh already relies on to match hooks/lib/*.sh), so
  # both arms are recursive with no `**` token needed.
  case "$full" in
    neural-lace/workstreams-ui/server/*.js) return 0 ;;
    neural-lace/workstreams-ui/web/*.js) return 0 ;;
  esac
  rel="${full#adapters/claude-code/}"
  case "$rel" in
    hooks/*.sh) return 0 ;;
    scripts/*.sh) return 0 ;;
    # Amendment H: non-.sh CODE members of the same two trees. Matched by
    # extension because the executable bit is 644 on every one of them in the
    # real tree (see the header) -- a mode-bit rule would match nothing.
    hooks/*.js|hooks/*.ts|hooks/*.py|hooks/*.ps1) return 0 ;;
    scripts/*.js|scripts/*.ts|scripts/*.py|scripts/*.ps1) return 0 ;;
    # Amendment H: the rest of the carrier chain. git-hooks/* is unfiltered
    # because its load-bearing members are EXTENSIONLESS (pre-push, pre-commit,
    # post-commit, pre-merge-commit) -- an extension filter would miss the
    # dispatcher that decides whether this gate runs at all.
    git-hooks/*) return 0 ;;
    schemas/*.json) return 0 ;;
    install.sh) return 0 ;;
    sync.sh) return 0 ;;
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

RRG_MANIFEST_RELPATH="adapters/claude-code/manifest.json"
ZERO_SHA_RRG="0000000000000000000000000000000000000000"

# ------------------------------------------------------------
# Harness-repo identity — anchored OUTSIDE the actor's write set
# ------------------------------------------------------------
#
# GATE IDENTITY MUST NOT BE ANCHORED ON PUSHER-MUTABLE STATE (harness-reviewer
# CRITICAL 1, 2026-07-30). PROVEN end-to-end against a real bare remote through
# the real dispatcher: THREE separate controls all decided "is this the harness
# repo?" by reading the ONE working-tree file adapters/claude-code/manifest.json
#   - review-record-push-gate.sh's scope test
#   - _rrg_is_harness_repo (which scopes the C2-B bootstrap fail-open)
#   - git-hooks/pre-push's M8 missing-gate block arm
# so `git rm -f adapters/claude-code/manifest.json`, in the SAME push that added
# an unreviewed hook, took the push from rc=1 + "PUSH BLOCKED" to rc=0 with ZERO
# gate output, and landed the unreviewed file on the remote. One command
# disarmed all three at once, and the deletion was itself never reviewed because
# the file enumeration used --diff-filter=ACMR, which excludes D.
#
# CLASS: gate-identity-anchored-on-pusher-mutable-state -- a control that
# decides whether it applies by reading a file the gated actor can delete in the
# same operation. GENERALIZATION: every scope/applicability test in every gate
# must anchor on state outside the actor's write set FOR THAT OPERATION.
#
# The anchors below are ordered strongest-first. The check is a monotone OR: an
# anchor can only ever make identity MORE certain, never less, so a genuinely
# foreign repo (no manifest at any anchor) still matches nothing and stays
# un-gated -- the false-positive budget that Scenario 11 pins is preserved.
#   1. remote_sha        -- what the REMOTE actually has right now. The pushing
#                           actor cannot rewrite it with this push; git itself
#                           supplies it from the ref negotiation.
#   2. remote-tracking   -- refs/remotes/<remote>/<branch>, the last observed
#                           remote state. Not written by the push being gated.
#   3. HEAD              -- the committed tree. Survives a working-tree `rm`,
#                           though not a `git rm` + commit.
#   4. working tree      -- the original, weakest test. Kept LAST so behaviour
#                           is unchanged for every caller that has no ref to
#                           offer (install.sh), but it can no longer be the
#                           ONLY thing consulted.
#
# rrg_harness_identity <repo_root> [ref ...] -- rc 0 iff any anchor carries the
# manifest. Echoes the anchor that matched (for the caller's message).
rrg_harness_identity() {
  local repo_root="$1"; shift
  local ref
  if command -v git >/dev/null 2>&1 \
     && git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    # Caller-supplied anchors first (remote_sha, remote-tracking refs, ...).
    for ref in "$@"; do
      [[ -n "$ref" ]] || continue
      [[ "$ref" == "$ZERO_SHA_RRG" ]] && continue
      if git -C "$repo_root" cat-file -e "${ref}:${RRG_MANIFEST_RELPATH}" 2>/dev/null; then
        printf '%s' "$ref"; return 0
      fi
    done
    if git -C "$repo_root" cat-file -e "HEAD:${RRG_MANIFEST_RELPATH}" 2>/dev/null; then
      printf 'HEAD'; return 0
    fi
    # The origin-tracked ref, for callers that have no push refline to offer
    # (install.sh, session-start-auto-install.sh, rrg_is_covered). This is what
    # keeps the C2-B bootstrap fail-open scoped even when the manifest has
    # already been deleted from both HEAD and the working tree.
    local _r _b
    for _r in $(git -C "$repo_root" remote 2>/dev/null); do
      for _b in master main; do
        if git -C "$repo_root" cat-file -e "refs/remotes/${_r}/${_b}:${RRG_MANIFEST_RELPATH}" 2>/dev/null; then
          printf 'refs/remotes/%s/%s' "$_r" "$_b"; return 0
        fi
      done
    done
  fi
  if [[ -f "$repo_root/$RRG_MANIFEST_RELPATH" ]]; then
    printf 'working-tree'; return 0
  fi
  return 1
}

# rrg_remote_tracking_refs <repo_root> <remote_ref> -- echo the remote-tracking
# refs that correspond to <remote_ref> (e.g. refs/heads/master ->
# refs/remotes/origin/master for every configured remote), one per line. These
# are identity anchors the push being gated does not write.
rrg_remote_tracking_refs() {
  local repo_root="$1" remote_ref="$2" branch r
  command -v git >/dev/null 2>&1 || return 1
  branch="${remote_ref#refs/heads/}"
  [[ -n "$branch" ]] || return 1
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    printf 'refs/remotes/%s/%s\n' "$r" "$branch"
  done < <(git -C "$repo_root" remote 2>/dev/null)
}

# _rrg_is_harness_repo <repo_root> <ref-or-empty> -- rc 0 iff this repo is the
# harness repo itself (the repo whose OWN gate this is). Used to scope the
# bootstrap fail-open below: "the harness repo has no coverage database" is a
# DEFECT, while "some unrelated fixture/product repo has none" is the ordinary
# case the fail-open exists to serve.
#
# ANCHORED VIA rrg_harness_identity (CRITICAL 1). Previously this read ONLY
# <ref> (at push time, the pusher's own local_sha) or only the working tree --
# both inside the actor's write set, so deleting manifest.json re-opened the
# C2-B fail-open this function exists to close. The caller's ref is now just the
# FIRST anchor tried, not the only one.
_rrg_is_harness_repo() {
  local repo_root="$1" ref="$2"
  rrg_harness_identity "$repo_root" "$ref" >/dev/null 2>&1
}

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
  #
  # SCOPED TO NON-HARNESS REPOS (harness-reviewer C2-B, 2026-07-30). PROVEN
  # bypass before this scoping: `git rm` BOTH coverage files in the same push
  # that adds an unreviewed hook took the gate from rc=1 to rc=0 -- deleting
  # the evidence database was a complete, one-command escape. The fail-open's
  # legitimate purpose is a checkout that never HAD the database; a repo
  # carrying adapters/claude-code/manifest.json IS the harness repo, where a
  # missing coverage database is a defect, not a pre-bootstrap state. There,
  # absence resolves toward NOT-COVERED (this file's own "bailouts resolve
  # toward block" principle) so the caller blocks and says why.
  if [[ -z "$gf" ]] && [[ -z "$idx" ]]; then
    if _rrg_is_harness_repo "$repo_root" "$ref"; then
      return 1
    fi
    return 0
  fi

  # GRANDFATHER ARM, BOUND TO ITS OWN cutover_ref (harness-reviewer C2-A,
  # 2026-07-30). PROVEN bypass before this binding: committing a self-authored
  # {path, blob_sha} row for brand-new unreviewed content into
  # grandfather-manifest.json IN THE SAME PUSH took the gate from rc=1 to
  # rc=0. A grandfather row's ONLY legitimate meaning is "this exact content
  # already existed at the recorded cutover point", and that is mechanically
  # checkable rather than taken on trust: the row verifies iff the path
  # actually carried that blob AT cutover_ref. Self-authored rows for new
  # content cannot satisfy it, because the blob did not exist there.
  # VERIFIED against live data 2026-07-30: all 275 real rows verify, so the
  # false-positive rate on legitimate content is zero, not merely expected to
  # be low.
  # RESIDUAL, NAMED not closed: an actor who ALSO rewrites cutover_ref to
  # their own commit satisfies this check. That escalation is far more
  # conspicuous (it must survive harness-doctor.sh's
  # review-grandfather-integrity check, which re-derives the ENTIRE manifest
  # at the claimed cutover_ref and byte-compares) but it is post-hoc
  # detection, not pre-push prevention. Enumerated in manifest.json's
  # review-record-push-gate.bypass_paths.
  if [[ -n "$gf" ]] && printf '%s' "$gf" | jq -e --arg p "$relpath" --arg s "$sha" \
       '(.entries // [])[] | select(.path == $p and .blob_sha == $s)' >/dev/null 2>&1; then
    local _cutover _at_cutover
    _cutover="$(printf '%s' "$gf" | jq -r '.cutover_ref // empty' 2>/dev/null)"
    if [[ -n "$_cutover" ]] && command -v git >/dev/null 2>&1; then
      _at_cutover="$(git -C "$repo_root" rev-parse --verify --quiet "${_cutover}:${relpath}" 2>/dev/null)"
      if [[ "$_at_cutover" == "$sha" ]]; then
        return 0
      fi
    fi
    # The row did not verify against its own cutover_ref -- do NOT honor it.
    # Fall through to the index arm, which may still legitimately cover this
    # content via a real PASS review record.
  fi

  if [[ -n "$idx" ]] && printf '%s' "$idx" | jq -e --arg p "$relpath" --arg s "$sha" \
       '(.entries // [])[] | select(.path == $p and .blob_sha == $s and .kind == "harness-change-review" and .verdict == "PASS")' >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

# ------------------------------------------------------------
# Shared waiver/authorization-reason validation
# ------------------------------------------------------------

# rrg_validate_waiver_reason <reason> -- rc 0 iff <reason> is a substantive,
# non-placeholder operator-authorization reason: >=20 chars (after
# whitespace-stripping) and not on the placeholder denylist. Shared by every
# gate/script that consumes an operator-authorized reason string, so the bar
# cannot drift between callers.
#
# review-record-commit-gate.sh (the now-ADVISORY commit-time gate,
# adapters/claude-code/doctrine/deterministic-process.md) predates this
# extraction and keeps its OWN inline copy of the same check -- deliberately
# left untouched rather than refactored to call this, to avoid touching a
# 900+-line, 20+-scenario self-tested file for a change with zero behavior
# delta there. This function is the ONE shared copy for every NEW caller:
# review-record-push-gate.sh (the authoritative pre-push gate) and
# scripts/authorize-review-record-push-override.sh (the operator-facing
# authorization writer it consumes).
rrg_validate_waiver_reason() {
  local reason="$1"
  [[ -z "$reason" ]] && return 1
  [[ "${#reason}" -ge 20 ]] || return 1
  case "$(printf '%s' "$reason" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    x|test|testing|temp|tmp|skip|bypass|because|na|n/a|bypassbypassbypassbypass)
      return 1 ;;
  esac
  return 0
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
    "neural-lace/workstreams-ui/server/roadmap-routes.js" \
    "neural-lace/workstreams-ui/web/roadmap.js" \
    "neural-lace/workstreams-ui/server/roadmap-routes.selftest.js" \
    "neural-lace/workstreams-ui/web/cockpit.selftest.js" \
    "neural-lace/workstreams-ui/server/lib/nested/deep.js" \
    "neural-lace/workstreams-ui/web/components/widget.js" \
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
    "neural-lace/workstreams-ui/README.md" \
    "neural-lace/workstreams-ui/server/package.json" \
    "neural-lace/workstreams-ui/attic/responsive.selftest.js" \
    "neural-lace/other-project/web/app.js" \
    "workstreams-ui/web/roadmap.js" \
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
  # The fixture is a REAL git repo with a REAL cutover commit, because the
  # grandfather arm now verifies each row against the manifest's own
  # cutover_ref (harness-reviewer C2-A). A fixture that skipped that -- as the
  # first version of this scenario did -- would only prove the jq row-match,
  # the half that was never broken, and would have stayed green against the
  # exact bypass this binding closes. Author-written fixtures that model less
  # than the real artifact are this codebase's recurring trap.
  mkdir -p "$tmp/repo/docs/reviews/records"
  ( cd "$tmp/repo" && git init -q . && git config user.email t@example.com \
      && git config user.name T && git add -A && git commit -q -m "cutover" ) >/dev/null 2>&1
  local cutover_sha
  cutover_sha=$(cd "$tmp/repo" && git rev-parse HEAD)
  printf '{"cutover_ref":"%s","entries":[{"path":"adapters/claude-code/hooks/alpha.sh","blob_sha":"%s"}]}\n' \
    "$cutover_sha" "$sha" > "$tmp/repo/docs/reviews/records/grandfather-manifest.json"
  printf '{"entries":[]}\n' > "$tmp/repo/docs/reviews/records/index.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "PASS: grandfathered blob (verified at cutover_ref) is covered"; pass=$((pass+1))
  else
    echo "FAIL: grandfathered blob should be covered"; fail=$((fail+1))
  fi

  # ---- coverage: a SELF-AUTHORED grandfather row for content that never
  # existed at cutover_ref must NOT be honored (harness-reviewer C2-A; the
  # PROVEN bypass was committing exactly this row in the same push) ----
  printf '#!/bin/bash\necho unreviewed\n' > "$tmp/repo/adapters/claude-code/hooks/evil.sh"
  local evil_sha
  evil_sha=$(rrg_blob_sha_of_file "$tmp/repo/adapters/claude-code/hooks/evil.sh")
  printf '{"cutover_ref":"%s","entries":[{"path":"adapters/claude-code/hooks/evil.sh","blob_sha":"%s"}]}\n' \
    "$cutover_sha" "$evil_sha" > "$tmp/repo/docs/reviews/records/grandfather-manifest.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/evil.sh" "$evil_sha"; then
    echo "FAIL: a self-authored grandfather row for post-cutover content was honored"; fail=$((fail+1))
  else
    echo "PASS: self-authored grandfather row rejected (blob absent at cutover_ref)"; pass=$((pass+1))
  fi

  # ---- coverage: a grandfather manifest with NO cutover_ref cannot be
  # verified, so its rows are not honored (removing the field must not become
  # its own bypass) ----
  printf '{"entries":[{"path":"adapters/claude-code/hooks/alpha.sh","blob_sha":"%s"}]}\n' "$sha" \
    > "$tmp/repo/docs/reviews/records/grandfather-manifest.json"
  if rrg_is_covered "$tmp/repo" "" "adapters/claude-code/hooks/alpha.sh" "$sha"; then
    echo "FAIL: a cutover_ref-less grandfather manifest was honored"; fail=$((fail+1))
  else
    echo "PASS: cutover_ref-less grandfather manifest is not honored"; pass=$((pass+1))
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
  # fixture repo) must be treated as COVERED, not blocked. NOTE this fixture
  # has NO adapters/claude-code/manifest.json, so it is NOT the harness repo
  # -- that is what keeps the fail-open available to it (see the next
  # scenario for the harness-repo case, which must behave oppositely) ----
  mkdir -p "$tmp/repo-nobootstrap/adapters/claude-code/hooks"
  printf '#!/bin/bash\necho v1\n' > "$tmp/repo-nobootstrap/adapters/claude-code/hooks/alpha.sh"
  local nb_sha
  nb_sha=$(rrg_blob_sha_of_file "$tmp/repo-nobootstrap/adapters/claude-code/hooks/alpha.sh")
  if rrg_is_covered "$tmp/repo-nobootstrap" "" "adapters/claude-code/hooks/alpha.sh" "$nb_sha"; then
    echo "PASS: bootstrap fail-open (no records dir, non-harness repo -> covered)"; pass=$((pass+1))
  else
    echo "FAIL: bootstrap fail-open should have reported covered"; fail=$((fail+1))
  fi

  # ---- coverage: the SAME missing-database state in the HARNESS repo (it
  # carries adapters/claude-code/manifest.json) must NOT fail open
  # (harness-reviewer C2-B: `git rm` of both coverage files took the live
  # push gate from rc=1 to rc=0) ----
  mkdir -p "$tmp/repo-harness-nodb/adapters/claude-code/hooks"
  printf '#!/bin/bash\necho v1\n' > "$tmp/repo-harness-nodb/adapters/claude-code/hooks/alpha.sh"
  printf '{"schema_version":1,"entries":[]}\n' > "$tmp/repo-harness-nodb/adapters/claude-code/manifest.json"
  local hn_sha
  hn_sha=$(rrg_blob_sha_of_file "$tmp/repo-harness-nodb/adapters/claude-code/hooks/alpha.sh")
  if rrg_is_covered "$tmp/repo-harness-nodb" "" "adapters/claude-code/hooks/alpha.sh" "$hn_sha"; then
    echo "FAIL: deleting the coverage database in the HARNESS repo failed open"; fail=$((fail+1))
  else
    echo "PASS: missing coverage database in the harness repo is NOT covered"; pass=$((pass+1))
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

  # ---- rrg_validate_waiver_reason ----
  if rrg_validate_waiver_reason "production is down and this cannot wait for review"; then
    echo "PASS: substantive reason validates"; pass=$((pass+1))
  else
    echo "FAIL: substantive reason should validate"; fail=$((fail+1))
  fi
  if rrg_validate_waiver_reason "short"; then
    echo "FAIL: a <20-char reason should be rejected"; fail=$((fail+1))
  else
    echo "PASS: a <20-char reason is rejected"; pass=$((pass+1))
  fi
  if rrg_validate_waiver_reason "bypass bypass bypass bypass"; then
    echo "FAIL: a placeholder-shaped (but long) reason should be rejected"; fail=$((fail+1))
  else
    echo "PASS: a placeholder-shaped reason is rejected despite length"; pass=$((pass+1))
  fi
  if rrg_validate_waiver_reason ""; then
    echo "FAIL: an empty reason should be rejected"; fail=$((fail+1))
  else
    echo "PASS: an empty reason is rejected"; pass=$((pass+1))
  fi

  # ---- Amendment H: THE CARRIER CHAIN IS COVERED (harness-reviewer CRITICAL
  # 3). Asserted as a CHAIN, not as individual paths, because the finding was
  # not "one path was missed" -- it was "the surface was a hand-written list
  # that had drifted from the set of files that can decide whether the gate
  # runs". Every link below can disarm or alter the gate; if any one of them
  # is out-of-surface, it can be changed with no review record. ----
  local link
  for link in \
    "adapters/claude-code/git-hooks/pre-push" \
    "adapters/claude-code/hooks/review-record-push-gate.sh" \
    "adapters/claude-code/hooks/lib/review-record-gate-lib.sh" \
    "adapters/claude-code/schemas/manifest.schema.json" \
    "adapters/claude-code/manifest.json" \
    "adapters/claude-code/install.sh" \
    "adapters/claude-code/sync.sh" \
  ; do
    if rrg_in_surface "$link"; then
      echo "PASS: carrier-chain link in-surface($link)"; pass=$((pass+1))
    else
      echo "FAIL: carrier-chain link NOT in-surface($link) — it can be changed unreviewed"; fail=$((fail+1))
    fi
  done

  # ---- Amendment H: non-.sh CODE members of hooks/ and scripts/. These are
  # mode 100644 in the real tree, so an executable-bit rule would miss every
  # one of them (that is why the rule is extension-based). ----
  for p in \
    "adapters/claude-code/hooks/lib/workstreams-task-bridge.js" \
    "adapters/claude-code/scripts/blocking-budget-check.js" \
    "adapters/claude-code/scripts/audit-consistency.ts" \
    "adapters/claude-code/scripts/validate-links.ts" \
    "adapters/claude-code/scripts/install-limit-resume-task.ps1" \
    "adapters/claude-code/git-hooks/pre-commit" \
    "adapters/claude-code/git-hooks/post-commit" \
    "adapters/claude-code/schemas/evidence.schema.json" \
  ; do
    if rrg_in_surface "$p"; then
      echo "PASS: in-surface($p)"; pass=$((pass+1))
    else
      echo "FAIL: in-surface($p) expected TRUE"; fail=$((fail+1))
    fi
  done

  # ---- Amendment H: NON-code neighbours of those same trees stay OUT, so the
  # expansion is the measured +28 files and not an accidental sweep of docs. ----
  for p in \
    "adapters/claude-code/scripts/schedule-weekly-eval.md" \
    "adapters/claude-code/scripts/spawn-worktree-selftest-evidence.md" \
    "adapters/claude-code/hooks/sensitive-patterns.local.example" \
    "adapters/claude-code/doctrine/deterministic-process.md" \
  ; do
    if rrg_in_surface "$p"; then
      echo "FAIL: in-surface($p) expected FALSE (surface expansion overshot)"; fail=$((fail+1))
    else
      echo "PASS: NOT in-surface($p)"; pass=$((pass+1))
    fi
  done

  # ---- CRITICAL 1: harness identity resolves from anchors OUTSIDE the actor's
  # write set. The fixture models the exact PROVEN attack: a commit that
  # carries the manifest, then a commit that `git rm`s it. At the second
  # commit the working tree, the index AND HEAD have all lost the file -- the
  # only surviving evidence is the earlier commit, which stands in here for
  # the remote_sha the push cannot rewrite. ----
  local IDR="$tmp/repo-identity"
  mkdir -p "$IDR/adapters/claude-code/hooks"
  printf '{"schema_version":1,"entries":[]}\n' > "$IDR/adapters/claude-code/manifest.json"
  printf '#!/bin/bash\n' > "$IDR/adapters/claude-code/hooks/keep.sh"
  ( cd "$IDR" && git init -q . && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit -q -m "with manifest" ) >/dev/null 2>&1
  local ID_WITH; ID_WITH=$(cd "$IDR" && git rev-parse HEAD 2>/dev/null)
  ( cd "$IDR" && git rm -q -f adapters/claude-code/manifest.json \
      && git commit -q -m "drop manifest" ) >/dev/null 2>&1

  if [[ ! -f "$IDR/adapters/claude-code/manifest.json" ]]; then
    echo "PASS: identity fixture really deleted the manifest (worktree + HEAD)"; pass=$((pass+1))
  else
    echo "FAIL: identity fixture did not delete the manifest — the scenario proves nothing"; fail=$((fail+1))
  fi

  local anchor
  anchor="$(rrg_harness_identity "$IDR" "$ID_WITH" 2>/dev/null)"
  if [[ "$anchor" == "$ID_WITH" ]]; then
    echo "PASS: identity survives manifest deletion via a pre-deletion anchor"; pass=$((pass+1))
  else
    echo "FAIL: manifest deletion defeated harness identity (anchor='$anchor')"; fail=$((fail+1))
  fi

  if rrg_harness_identity "$IDR" "" >/dev/null 2>&1; then
    echo "FAIL: identity claimed with NO surviving anchor at all"; fail=$((fail+1))
  else
    echo "PASS: no anchor anywhere -> not the harness repo (foreign-repo FP budget)"; pass=$((pass+1))
  fi

  # A genuinely foreign repo must stay un-identified, or every gate that scopes
  # on this function starts false-positiving on unrelated repos.
  local FGN="$tmp/repo-foreign"
  mkdir -p "$FGN/src"
  printf 'x\n' > "$FGN/src/app.js"
  ( cd "$FGN" && git init -q . && git config user.email t@example.com && git config user.name T \
      && git add -A && git commit -q -m base ) >/dev/null 2>&1
  if rrg_harness_identity "$FGN" "" >/dev/null 2>&1; then
    echo "FAIL: a foreign repo was identified as the harness repo"; fail=$((fail+1))
  else
    echo "PASS: foreign repo is not the harness repo"; pass=$((pass+1))
  fi

  # ---- C2-B stays closed at the LIB layer too: _rrg_is_harness_repo consulted
  # with the post-deletion ref must still say "harness repo" when an earlier
  # anchor survives, otherwise the bootstrap fail-open re-opens exactly as the
  # reviewer proved. ----
  if _rrg_is_harness_repo "$IDR" "$ID_WITH"; then
    echo "PASS: _rrg_is_harness_repo honours a surviving pre-deletion anchor"; pass=$((pass+1))
  else
    echo "FAIL: _rrg_is_harness_repo lost identity — C2-B re-opens on manifest deletion"; fail=$((fail+1))
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
