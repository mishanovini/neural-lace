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
#   hooks/** | scripts/** | git-hooks/**   (all three UNFILTERED, minus three
#       exact-path non-code exemptions -- see rrg_in_surface)
#   | schemas/*.json | install.sh | sync.sh
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
# THE THREE CARRIER TREES ARE UNFILTERED (hooks/, scripts/, git-hooks/), minus
# an exact-path exemption list of three non-code files. Amendment H originally
# shipped an EXTENSION ALLOWLIST for hooks/ and scripts/ while this header
# claimed carrier-chain derivation -- the two disagreed, and the header was the
# one that was wrong (harness-reviewer MAJOR 2, round 3). It is now literally
# true: membership is decided by the tree a file lives in, not by a list of
# extensions someone remembered to write down. MEASURED at the time of the
# change: identical 311-file in-surface set either way, so the correction cost
# nothing today and buys drift-resistance tomorrow. See rrg_in_surface's own
# comment for the exemption list and how to re-derive it.
#
# NON-.sh MEMBERS ARE NOT MATCHED BY THE EXECUTABLE BIT. The reviewer's
# suggested "cover executable non-.sh members" rule was MEASURED
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

# ===========================================================================
# PATH NORMALISATION — the predicate's equivalence relation must be at least
# as wide as the DELIVERY LAYER's (harness-reviewer CRITICAL, round 5).
# ===========================================================================
#
# THE CLASS, stated so it generalizes past this gate: a membership predicate
# that decides from a path STRING answers a question about the string. The
# surface it protects is realised by a DELIVERY LAYER -- a filesystem checkout
# -- which collapses whole families of byte-distinct strings onto ONE file. If
# the predicate's equivalence relation is NARROWER than the delivery layer's,
# every string in the gap is a silent hole: the predicate says OUT, the gate
# stays quiet, and the delivery layer puts the file INSIDE the protected
# directory anyway.
#
# This is the SAME class as round 4's CRITICAL 2, which asked the predicate
# about git's C-quoted RENDERING of a path rather than the path. There the
# gap was between the enumerator and the predicate; here it is between the
# predicate and the checkout. Both breach the same headline claim.
#
# PROVEN end-to-end against a real bare remote with git-hooks/pre-push
# installed as the actual pre-push hook, BEFORE this fix:
#   BLOB=$(printf '#!/bin/bash\necho INJECTED\n' | git hash-object -w --stdin)
#   git update-index --add --cacheinfo 100755,$BLOB,adapters/claude-code/Hooks/injected.sh
#   git commit && git push
# returned rc=0 with ZERO gate bytes and LANDED on the remote. `git clone` +
# `git checkout master` then materialised it at
#   adapters/claude-code/hooks/injected.sh   (mode 755)
# inside the real carrier directory, beside review-record-push-gate.sh itself.
# `git update-index --cacheinfo` is what makes it reachable: it writes the
# index entry directly, so the capital-H path never has to survive a
# case-insensitive working tree. Same silent rc=0 for Git-Hooks/pre-push,
# SCRIPTS/evil.sh, adapters/Claude-Code/hooks/evil.sh and Manifest.json --
# and, re-probed here, for EVERY ONE of the thirteen surface arms, not just
# the five reported.
#
# WHICH EQUIVALENCES THIS FILESYSTEM ACTUALLY COLLAPSES -- MEASURED on the
# APFS volume this repo lives on, by creating two byte-distinct names and
# checking whether the second overwrote the first (scratch probe, 2026-07-30):
#   ASCII case          hooks_x    vs Hooks_x           COLLAPSED
#   Unicode case        café_x     vs CAFÉ_X            COLLAPSED
#   long s   U+017F     scripts_a  vs ſcripts_a         COLLAPSED
#   Kelvin   U+212A     hooks_y    vs hooKs_y           COLLAPSED
#   NFC vs NFD          café_z     vs cafe+U0301_z      COLLAPSED
#   trailing dot        trail.sh   vs trail.sh.         DISTINCT
#   trailing space      sp.sh      vs "sp.sh "          DISTINCT
#
# WHAT THAT MEANS FOR THIS PREDICATE, derived rather than assumed. Every
# string this predicate tests against is PURE ASCII (hooks/, scripts/,
# git-hooks/, schemas/, agents/, config/, rules/, install.sh, sync.sh,
# manifest.json, settings.json.template, adapters/claude-code/,
# neural-lace/workstreams-ui/{server,web}/). Therefore:
#   - ASCII case IS exploitable -> closed by the fold below.
#   - Unicode case is exploitable ONLY through the two code points whose
#     simple case-fold IS an ASCII letter: U+017F LATIN SMALL LETTER LONG S
#     -> "s" and U+212A KELVIN SIGN -> "k". That set is complete, not a
#     sample: U+212B ANGSTROM folds to U+00E5 (not ASCII) and the fullwidth
#     forms fold to fullwidth, not ASCII. Every surface string contains an
#     "s" or a "k", so both are live -> closed by the two substitutions below.
#   - NFC/NFD is collapsed by the filesystem but is NOT exploitable here:
#     canonical decomposition never maps a non-ASCII sequence onto a BARE
#     ASCII string (é -> e + U+0301 is LONGER, not equal to "e"), so no
#     normalisation variant of a pure-ASCII prefix exists. Tested anyway
#     (self-test n1/n2) so the claim is pinned rather than argued.
#   - Trailing dot / trailing space are a WINDOWS-checkout equivalence; this
#     filesystem keeps them distinct (measured above) and no Windows checkout
#     of this repo exists to test against. NOT closed here, enumerated in
#     manifest.json bypass_paths[16](vi) rather than dropped.
#
# WHY ONLY THE INJECTION DIRECTION MATTERS. There are two directions: INJECT a
# new case-variant path with no lowercase competitor, or CLOBBER an existing
# in-surface file by pushing a case variant of it. The CLOBBER direction is
# NOT exploitable and that is MEASURED, not assumed: 0 of the 311 in-surface
# canonical paths contain an uppercase ASCII letter (and 0 contain a non-ASCII
# byte), so the all-lowercase real path always sorts last in the index and
# wins the checkout race. Re-derive with scripts-free bash: source this lib,
# pipe `git ls-files` through rrg_in_surface, and count matches of
# *[ABCDEFGHIJKLMNOPQRSTUVWXYZ]*. The exploitable direction is INJECTION.
#
# RULE FOR THE NEXT GATE (extends the enumeration rule in
# review-record-push-gate.sh's own header): every harness consumer of git path
# output must disable quoting AND use NUL separation before feeding a path to
# a predicate, AND normalise the path to the DELIVERY FILESYSTEM's equivalence
# class before the predicate decides membership. Enumerating correctly and
# then asking the wrong equivalence relation is the same bug one layer down.
# The harness-wide sibling audit is filed as PATH-EQUIVALENCE-CLASS-01 in
# docs/backlog.md with its full enumeration.
# ---------------------------------------------------------------------------

_RRG_UPPER="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_RRG_LOWER="abcdefghijklmnopqrstuvwxyz"
_RRG_FOLDED=""

# _rrg_casefold <path> -- result in the GLOBAL _RRG_FOLDED (deliberately not
# echoed: a command substitution would fork a subshell per candidate path, and
# this runs once per changed file on every push).
#
# PURE BASH, NO FORK, bash 3.2.57-SAFE. `${v,,}` is banned by the portability
# floor -- which is precisely why this exists -- and `tr` was rejected for two
# reasons beyond the fork: BSD `tr` under a UTF-8 locale mangles multi-byte
# input with [:upper:], and byte-wise `tr 'A-Z' 'a-z'` cannot express the two
# multi-byte -> single-byte foldings above. 26 parameter expansions on a short
# string are microseconds; measured at 400 folds in under one second on
# /bin/bash 3.2.57.
#
# GLOB METACHARACTERS IN THE INPUT ARE SAFE: the PATTERN in each substitution
# is a single fixed ASCII letter, so a path containing * ? [ ] or a backslash
# passes through byte-identical (pinned by self-test cf7-cf10).
_rrg_casefold() {
  local s="$1" i=0
  # The two non-ASCII code points whose simple case-fold is an ASCII letter.
  s="${s//$'\xc5\xbf'/s}"   # U+017F LATIN SMALL LETTER LONG S -> s
  s="${s//$'\xe2\x84\xaa'/k}"  # U+212A KELVIN SIGN            -> k
  while [ "$i" -lt 26 ]; do
    s="${s//${_RRG_UPPER:$i:1}/${_RRG_LOWER:$i:1}}"
    i=$((i+1))
  done
  _RRG_FOLDED="$s"
}

# rrg_in_surface <path> -- accepts either a path relative to repo root
# (adapters/claude-code/hooks/foo.sh) or already relative to the adapter dir
# (hooks/foo.sh); the adapters/claude-code/ prefix is stripped if present.
#
# TWO PATH VARIABLES, AND THEY ARE NOT INTERCHANGEABLE:
#   rel  -- the ORIGINAL bytes. Used ONLY by the exact-path EXEMPTION arms
#           (the `return 1`s). An exemption must NOT be widenable by case:
#           if `hooks/Sensitive-Patterns.local.example` could match the
#           exemption, an attacker would re-open by case exactly the hole the
#           exact-path rule exists to close.
#   lrel -- the FOLDED bytes. Used by every INCLUSION arm (the `return 0`s).
#           Folding here can only ever make the surface WIDER, which is the
#           safe direction.
# The strip is done on BOTH, because `adapters/Claude-Code/hooks/evil.sh`
# defeats a case-sensitive strip and would otherwise reach no arm at all.
rrg_in_surface() {
  local full="$1" rel lfull lrel
  _rrg_casefold "$full"; lfull="$_RRG_FOLDED"
  # Amendment G (cockpit product surface) matches the REPO-ROOT-RELATIVE
  # path directly -- checked BEFORE the adapters/claude-code/ prefix strip
  # below, since these paths never carry that prefix and stripping is a
  # no-op for them anyway. Case-pattern `*` matches `/` (the same property
  # Amendment A's hooks/*.sh already relies on to match hooks/lib/*.sh), so
  # both arms are recursive with no `**` token needed. Matched on the FOLDED
  # path: `neural-lace/workstreams-ui/Server/x.js` was PROBED OUT before this
  # fix, and the cockpit tree lives on the same case-insensitive checkout.
  case "$lfull" in
    neural-lace/workstreams-ui/server/*.js) return 0 ;;
    neural-lace/workstreams-ui/web/*.js) return 0 ;;
  esac
  rel="${full#adapters/claude-code/}"
  lrel="${lfull#adapters/claude-code/}"
  # EXEMPTIONS FIRST, AND CASE-SENSITIVELY, on the ORIGINAL bytes. A case
  # variant of an exempted path therefore falls THROUGH to the inclusion arms
  # below and lands IN surface -- the safe direction, pinned by self-test
  # cs-ex1..cs-ex3.
  case "$rel" in
    hooks/sensitive-patterns.local.example) return 1 ;;
    scripts/schedule-weekly-eval.md) return 1 ;;
    scripts/spawn-worktree-selftest-evidence.md) return 1 ;;
  esac
  case "$lrel" in
    # ------------------------------------------------------------
    # CARRIER-CHAIN ARMS: UNFILTERED, WITH AN EXACT-PATH EXEMPTION LIST.
    # (harness-reviewer MAJOR 2, round 3.)
    #
    # All three trees are matched WHOLESALE. The previous revision filtered
    # hooks/ and scripts/ by extension (.sh/.js/.ts/.py/.ps1) while leaving
    # git-hooks/ unfiltered, and the header above called the result "derived
    # from the gate's CARRIER CHAIN, not from a hand-written path list" -- a
    # claim that was FALSE for two of the three arms. An extension allowlist IS
    # a hand-written list. It covered the tree of the day by coincidence and
    # silently omitted anything else: hooks/lib/evil.mjs, hooks/lib/evil.cjs,
    # hooks/evil.rb, hooks/evil.pl, hooks/evil.lua were each PROBED and
    # confirmed NOT-COVERED under the old arms. Today's tree happened to be
    # fully covered, so the defect was never a present-day hole -- it was the
    # absence of the very drift-resistance the header advertised.
    #
    # Unfiltered + exemptions inverts the drift risk in the SAFE direction: a
    # new file of any kind under these trees is IN surface by default, and
    # falling OUT requires an explicit edit to the list below -- an edit which
    # is itself in-surface, since this lib is a carrier-chain link. The old
    # shape failed the other way: a new extension fell out silently, with no
    # edit and no reviewer ever seeing it.
    #
    # CORRECTED 2026-07-30 (harness-reviewer CRITICAL, round 5). "A new file of
    # ANY KIND under these trees is IN surface by default" was FALSE as written
    # for the second time: false for C-quoted paths until round 4, and false
    # for CASE VARIANTS until this commit -- `adapters/claude-code/Hooks/x.sh`
    # answered OUT while landing inside this very directory on checkout. The
    # sentence is true now only because these arms are matched on $lrel, the
    # CASE-FOLDED path (see the normalisation header above). Twice burned: a
    # by-default claim is a claim about EVERY string the delivery layer maps
    # into the tree, not about every string the author happened to picture.
    #
    # git-hooks/ additionally CANNOT be extension-filtered at all: its
    # load-bearing members are EXTENSIONLESS (pre-push, pre-commit, post-commit,
    # pre-merge-commit) -- including the dispatcher that decides whether this
    # gate runs at all.
    #
    # EXEMPTIONS ARE EXACT PATHS, NEVER PATTERNS. `scripts/*.md` would exempt a
    # class forever; three named files must each be re-justified when touched.
    # Re-derive the list (it should print exactly these three):
    #   git ls-files 'adapters/claude-code/hooks/*' 'adapters/claude-code/scripts/*' \
    #     | grep -vE '\.(sh|js|ts|py|ps1)$'
    # MEASURED, not assumed: on today's tree this predicate selects exactly the
    # SAME 311 files as the extension-filtered version -- zero newly covered,
    # zero newly dropped. A pure drift-resistance change at zero present-day
    # false-positive cost. Self-test scenarios h1-h6 pin both halves.
    # ------------------------------------------------------------
    # NOTE the three exact-path exemptions are NOT repeated here. They are
    # tested above, against the UNFOLDED bytes, on purpose: repeating them in
    # this folded `case` would let `hooks/Sensitive-Patterns.local.example`
    # fold onto an exemption and fall OUT of surface -- re-opening by case
    # exactly the widening the exact-path rule exists to prevent.
    hooks/*) return 0 ;;
    scripts/*) return 0 ;;
    git-hooks/*) return 0 ;;
    # schemas/ is the fourth carrier-chain tree and gets the SAME treatment for
    # the SAME reason (consistency was the point of MAJOR 2, so fixing only the
    # two arms that were reported would repeat the Minor finding's mistake of
    # applying a rule to the reported instance alone). `schemas/*.json` was an
    # extension allowlist too: a `schemas/x.yaml` was PROBED and confirmed
    # NOT-COVERED. MEASURED: schemas/ holds 11 tracked files, all .json, so
    # unfiltering it is again a zero-delta, drift-resistance-only change
    # (`git ls-files 'adapters/claude-code/schemas/*' | grep -v '\.json$'`
    # prints nothing).
    schemas/*) return 0 ;;
    install.sh) return 0 ;;
    sync.sh) return 0 ;;
    agents/*.md)
      # top-level only (agents/*.md, not agents/**/*.md) -- no further slash
      # after the agents/ prefix.
      #
      # THIS STRIP MUST USE THE FOLDED PATH. It read $rel in the first draft of
      # this fix and `adapters/claude-code/Agents/x.md` came back OUT while
      # every other arm had gone IN: the arm matched on $lrel, then the strip
      # failed on $rel's capital A, left the whole string intact, saw its
      # remaining slash and returned 1. A folded arm with an unfolded body is
      # the same predicate/delivery mismatch one level down.
      [[ "${lrel#agents/}" == */* ]] && return 1
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
  # expansion is the measured +28 files and not an accidental sweep of docs.
  # These three are the EXACT-PATH exemption list in rrg_in_surface; this loop
  # is what keeps the list honest when someone unfilters another tree. ----
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

  # ---- MAJOR 2 (round 3): DRIFT-RESISTANCE. The header claims the surface is
  # derived from the CARRIER CHAIN rather than a hand-written path list. That
  # claim is only true if a file the list's author never thought of is covered
  # anyway. Each path below was PROBED against the previous extension-allowlist
  # arms and came back NOT-COVERED; every one of them can execute or configure
  # a carrier-chain link, so each was a silent future hole. This loop is the
  # difference between "covered today" and "stays covered as the tree drifts".
  # NOTE these are HYPOTHETICAL paths -- they deliberately do not exist in the
  # tree, because the property under test is about files not yet written. ----
  for p in \
    "adapters/claude-code/hooks/lib/evil.mjs" \
    "adapters/claude-code/hooks/lib/evil.cjs" \
    "adapters/claude-code/hooks/evil.rb" \
    "adapters/claude-code/scripts/evil.pl" \
    "adapters/claude-code/scripts/evil.lua" \
    "adapters/claude-code/schemas/x.yaml" \
  ; do
    if rrg_in_surface "$p"; then
      echo "PASS: drift-resistant in-surface($p) — a new extension is covered by default"; pass=$((pass+1))
    else
      echo "FAIL: in-surface($p) expected TRUE — the surface is still an extension allowlist, not carrier-chain-derived"; fail=$((fail+1))
    fi
  done

  # ---- ...and the exemption mechanism must be EXACT-PATH, not a pattern: a
  # sibling .md under scripts/ that is NOT on the list stays IN surface. If this
  # goes red, someone widened an exemption into a class and reopened the hole
  # the exact-path rule exists to prevent. ----
  for p in \
    "adapters/claude-code/scripts/some-new-doc.md" \
    "adapters/claude-code/hooks/another.local.example" \
  ; do
    if rrg_in_surface "$p"; then
      echo "PASS: non-exempted sibling stays in-surface($p) — exemptions are exact paths, not patterns"; pass=$((pass+1))
    else
      echo "FAIL: in-surface($p) expected TRUE — an exemption was widened into a pattern"; fail=$((fail+1))
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

  # ---- CRITICAL (round 5): PATH CASE. The surface arms are matched on a
  # case-INSENSITIVE delivery layer, so a case variant that the predicate calls
  # OUT still lands INSIDE the protected directory on checkout. Each path below
  # was PROVEN to push rc=0 with the gate SILENT before the fold landed; the
  # first four are the reviewer's own reported list, the rest are the other
  # nine arms, which were never reported and were broken identically. ----
  for p in \
    "adapters/claude-code/Hooks/x.sh" \
    "adapters/claude-code/Git-Hooks/pre-push" \
    "adapters/claude-code/SCRIPTS/x.sh" \
    "adapters/Claude-Code/hooks/x.sh" \
    "adapters/claude-code/Manifest.json" \
    "adapters/claude-code/HOOKS/lib/x.sh" \
    "adapters/claude-code/GIT-HOOKS/pre-push" \
    "adapters/claude-code/Schemas/x.json" \
    "adapters/claude-code/Install.sh" \
    "adapters/claude-code/Sync.sh" \
    "adapters/claude-code/Agents/x.md" \
    "adapters/claude-code/Config/x.json" \
    "adapters/claude-code/Rules/x.md" \
    "adapters/claude-code/Settings.json.template" \
    "ADAPTERS/CLAUDE-CODE/hooks/x.sh" \
    "Neural-Lace/workstreams-ui/server/x.js" \
    "neural-lace/workstreams-ui/Web/x.js" \
  ; do
    if rrg_in_surface "$p"; then
      echo "PASS: case-variant in-surface($p)"; pass=$((pass+1))
    else
      echo "FAIL: case-variant OUT of surface($p) — it lands inside the real directory on a case-insensitive checkout"; fail=$((fail+1))
    fi
  done

  # ---- ...and the two non-ASCII code points whose simple case-fold IS an
  # ASCII letter. MEASURED: this APFS volume collapses both onto the ASCII
  # name, so they are live injection paths, not theory. ----
  if rrg_in_surface "$(printf 'adapters/claude-code/\xc5\xbfcripts/x.sh')"; then
    echo "PASS: U+017F long-s variant of scripts/ is in-surface"; pass=$((pass+1))
  else
    echo "FAIL: U+017F long-s variant of scripts/ is OUT — APFS folds it onto scripts/"; fail=$((fail+1))
  fi
  if rrg_in_surface "$(printf 'adapters/claude-code/hoo\xe2\x84\xaas/x.sh')"; then
    echo "PASS: U+212A Kelvin variant of hooks/ is in-surface"; pass=$((pass+1))
  else
    echo "FAIL: U+212A Kelvin variant of hooks/ is OUT — APFS folds it onto hooks/"; fail=$((fail+1))
  fi

  # ---- cs-ex1..cs-ex3: EXEMPTIONS ARE CASE-SENSITIVE. The exact three paths
  # stay OUT (asserted above); a CASE VARIANT of each must be IN, or an
  # attacker widens an exemption by case -- the exact failure the exact-path
  # rule exists to prevent, re-entering through the door this fix opened. ----
  for p in \
    "adapters/claude-code/hooks/Sensitive-Patterns.local.example" \
    "adapters/claude-code/scripts/Schedule-Weekly-Eval.md" \
    "adapters/claude-code/SCRIPTS/spawn-worktree-selftest-evidence.md" \
  ; do
    if rrg_in_surface "$p"; then
      echo "PASS: case-variant of an exemption is NOT exempt ($p)"; pass=$((pass+1))
    else
      echo "FAIL: a case variant widened an exemption ($p)"; fail=$((fail+1))
    fi
  done

  # ---- FALSE-POSITIVE BUDGET: folding widens the surface, so the arms that
  # must stay OUT are re-asserted in their case-variant form too. If doctrine/
  # or templates/ start matching, the fold has swallowed a tree. ----
  for p in \
    "adapters/claude-code/Doctrine/x.md" \
    "adapters/claude-code/Templates/plan-template.md" \
    "adapters/claude-code/Skills/foo/SKILL.md" \
    "adapters/claude-code/Agents/sub/nested.md" \
    "Neural-Lace/other-project/web/app.js" \
  ; do
    if rrg_in_surface "$p"; then
      echo "FAIL: fold overshot — $p should stay OUT of surface"; fail=$((fail+1))
    else
      echo "PASS: NOT in-surface($p) — fold did not swallow a neighbouring tree"; pass=$((pass+1))
    fi
  done

  # ---- n1/n2: NFC vs NFD. This filesystem COLLAPSES them (measured), but the
  # dimension is NOT exploitable against these arms, because canonical
  # decomposition never maps a non-ASCII sequence onto a BARE ASCII string.
  # Pinned rather than argued: an NFD path must behave EXACTLY as its NFC form
  # does -- both OUT here, since neither is under a surface tree. If a future
  # arm ever contains a non-ASCII character these two go red together and the
  # claim gets re-derived instead of inherited. ----
  local nfc nfd r1 r2
  nfc="$(printf 'adapters/claude-code/caf\xc3\xa9/x.sh')"
  nfd="$(printf 'adapters/claude-code/cafe\xcc\x81/x.sh')"
  if rrg_in_surface "$nfc"; then r1=IN; else r1=OUT; fi
  if rrg_in_surface "$nfd"; then r2=IN; else r2=OUT; fi
  if [[ "$r1" == "$r2" ]]; then
    echo "PASS: NFC and NFD forms agree ($r1) — no normalisation-shaped split"; pass=$((pass+1))
  else
    echo "FAIL: NFC=$r1 but NFD=$r2 — a normalisation variant changes the verdict"; fail=$((fail+1))
  fi
  if [[ "$r1" == "OUT" ]]; then
    echo "PASS: the NFC/NFD probe pair is genuinely outside the surface (the test is not vacuous the other way)"; pass=$((pass+1))
  else
    echo "FAIL: NFC/NFD probe unexpectedly in-surface — re-derive the non-exploitability argument"; fail=$((fail+1))
  fi

  # ---- cf1..cf10: the fold itself. Glob metacharacters and non-ASCII bytes
  # must pass through BYTE-IDENTICAL: mangling a path here would reintroduce
  # round 4's CRITICAL 2 (a predicate answering about a string that is not the
  # path) from the opposite side. ----
  local fin fwant
  _rrg_casefold "adapters/claude-code/Hooks/X.SH"; fin="$_RRG_FOLDED"
  [[ "$fin" == "adapters/claude-code/hooks/x.sh" ]] \
    && { echo "PASS: fold lowercases ASCII"; pass=$((pass+1)); } \
    || { echo "FAIL: fold ASCII (got '$fin')"; fail=$((fail+1)); }
  for fwant in 'hooks/back\slash.sh' 'hooks/two words.sh' 'hooks/star*.sh' 'hooks/brack[et].sh' 'hooks/q?.sh'; do
    _rrg_casefold "$fwant"
    [[ "$_RRG_FOLDED" == "$fwant" ]] \
      && { echo "PASS: fold is byte-identical on a metacharacter path ($fwant)"; pass=$((pass+1)); } \
      || { echo "FAIL: fold mangled '$fwant' -> '$_RRG_FOLDED'"; fail=$((fail+1)); }
  done
  fwant="$(printf 'adapters/claude-code/hooks/pr\xc3\xa9-push.sh')"
  _rrg_casefold "$fwant"
  [[ "$_RRG_FOLDED" == "$fwant" ]] \
    && { echo "PASS: fold leaves a non-ASCII (UTF-8) path byte-identical"; pass=$((pass+1)); } \
    || { echo "FAIL: fold mangled non-ASCII bytes"; fail=$((fail+1)); }

  # ---- MUTATION PROOF: reverting the fold must RE-OPEN the push. A mutation
  # proof that does not make its own attack pass again proves nothing, so this
  # asserts BOTH that the mutation applied AND that the mutant is exploitable.
  # Executed in a SUBSHELL against a mutated COPY, so the live definition in
  # this process is untouched. ----
  local MUTLIB="$tmp/mutant-lib.sh"
  sed 's#^  _rrg_casefold "\$full"; lfull="\$_RRG_FOLDED"#  lfull="$full"#' "${BASH_SOURCE[0]}" > "$MUTLIB"
  if grep -q '^  lfull="\$full"$' "$MUTLIB"; then
    echo "PASS: mutation applied (the fold call is gone from the mutant)"; pass=$((pass+1))
    local mut_rc
    mut_rc=$( . "$MUTLIB" >/dev/null 2>&1; rrg_in_surface "adapters/claude-code/Hooks/injected.sh"; echo $? )
    if [[ "$mut_rc" != "0" ]]; then
      echo "PASS: MUTATION-PROOF — without the fold, Hooks/injected.sh is OUT of surface again (the attack re-opens)"; pass=$((pass+1))
    else
      echo "FAIL: mutant still reports the case variant IN — this proof proves nothing"; fail=$((fail+1))
    fi
  else
    echo "FAIL: mutation did not apply — the mutation proof is vacuous"; fail=$((fail+1))
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
