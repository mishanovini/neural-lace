#!/bin/bash
# harness-hygiene-scan.sh
#
# Classification: Mechanism (hook-enforced pre-commit blocker)
#
# Scans staged git changes (or specified files, or the full tree) against the
# harness denylist at `adapters/claude-code/patterns/harness-denylist.txt`.
# Blocks a commit if any non-exempt file contains content that matches any
# denylist pattern.
#
# Purpose: harness repos (this one) must not ship personal, business, or
# identity-bearing strings. This hook is the last-line mechanical enforcement
# for the harness-hygiene principle. Override with `git commit --no-verify`
# only if you are CERTAIN the match is a legitimate false positive AND you
# have added an explicit exemption (or fixed the content).
#
# INVOCATION MODES
#   1. Pre-commit hook:  harness-hygiene-scan.sh
#                        (no args — reads `git diff --cached --name-only -z`)
#   2. Full-tree scan:   harness-hygiene-scan.sh --full-tree
#                        (scans all tracked files via `git ls-files -z`)
#   3. Specific files:   harness-hygiene-scan.sh path/to/a path/to/b
#                        (scans the listed paths directly)
#   4. Self-test:        harness-hygiene-scan.sh --self-test
#                        (runs internal assertions, prints OK/FAIL, exits)
#   5. Pre-flight check: harness-hygiene-scan.sh --check [path/to/a ...]
#                        (R3.4 Gate Philosophy Law — read-only "would this
#                        block" verdict. Runs the IDENTICAL scan pipeline —
#                        same is_exempt/waiver/denylist/heuristic checks —
#                        as the enforce path via the shared report emitter
#                        `_hhs_print_report`, so --check cannot drift from
#                        what the real gate does. With no path args, checks
#                        the currently staged files, same as mode 1. Exit
#                        code mirrors the verdict: 0 = would-pass, 1 = would
#                        block; nothing is written or blocked by --check
#                        itself — it is advisory only.)
#
# EXEMPT PATHS (never scanned)
#   - The denylist file itself (would match infinitely)
#   - SCRATCHPAD.md (gitignored working memory)
#   - Any file matching *.example, *.example.json, *.example.sh
#     (placeholders are supposed to look placeholder-ish)
#   - docs/decisions/, docs/reviews/, docs/sessions/ ONLY for non-allow-listed
#     paths within those directories. Committed (allow-listed) files
#     (e.g., `docs/decisions/NNN-*.md`, `docs/reviews/YYYY-MM-DD-*.md`,
#     `docs/sessions/YYYY-MM-DD-*.md`) ARE scanned because they ship in the
#     harness repo and must follow the same hygiene rules. Other paths under
#     those directories are gitignored instance artifacts and are exempt.
#   - docs/plans/ is NOT exempt — Neural Lace now commits its own
#     development plans (subject to hygiene like any other committed file).
#
# WAIVER (F.5 waiver-parity audit row 12 / ADR 059 D4 fix): the exemption
# list above is a PLAN-TIME allowlist (known-legitimate files/paths, edited
# out-of-band). It does not help a session that hits a genuine NOVEL
# false-positive at commit time (a denylisted string appearing legitimately
# in, e.g., a test fixture never seen before). For that case, a fresh (<1h)
# structured waiver at .claude/state/harness-hygiene-waiver-*.txt, naming
# BOTH purpose clauses (lib/waiver-purpose-clause.sh) AND the specific
# file(s) it covers, suppresses ONLY the matches on those named files for
# this run (never a blanket suppression of the whole scan). See
# `_hhs_waived_files` below.
#
# EXIT CODES
#   0 — no matches (or denylist missing / not in a git repo — silent no-op)
#   1 — one or more matches detected (denylist or heuristic)
#
# DETECTION LAYERS
#   Layer 1 (denylist) — literal/regex patterns from harness-denylist.txt.
#                         Matches are labeled `[denylist]` in stderr output.
#   Layer 2 (heuristic) — project-specific shape detection inside
#                         `check_heuristics()`. Catches patterns the literal
#                         denylist cannot (project-internal file paths,
#                         repeated capitalized term clusters outside NL
#                         vocabulary). Matches are labeled `[heuristic]`.
#                         Files in NL-prefix paths (`adapters/`, `docs/`,
#                         the synced `~/.claude/` mirror) are exempt from
#                         path-shape detection because plans, decisions,
#                         and rules legitimately cite paths in prose.
#                         Plan files under `docs/plans/*.md` are exempt
#                         from path-shape detection for the same reason.
#   Layer 3 (addendum)  — no-addendum lint (REQ-B10): `Addendum`/`Update:`
#                         ATX headings blocked in `docs/designs/**` +
#                         `docs/plans/**` (`docs/plans/archive/**`
#                         excluded entirely); `Round [0-9]` ATX headings
#                         blocked in `docs/designs/**` ONLY. Case-
#                         insensitive. Matches are labeled `[addendum-lint]`.
#                         See `check_addendum_lint()` below for the full
#                         M-9-narrowed-pattern rationale.
#
# HYGIENE-GATE SAFETY FIX (2026-08-04, self-service-escape incident)
# ============================================================
# Four `bypass_kind=waiver-file` entries against this gate landed in
# workaround-sensor.jsonl with no operator turn: a subagent got BLOCKED,
# read this gate's own block message (which used to print the waiver
# recipe as a fill-in-the-blank command), self-authored the waiver, and
# committed. Both underlying deltas were in fact clean — the gate had
# fired on PRE-EXISTING content in the same files, not on anything the
# commit added. Two compounding defects, both fixed here; a third
# (invisibility) fixed in session-start-digest.sh.
#
# DEFECT 1 — FALSE-FIRE ENGINE (delta-scoping)
# ------------------------------------------------------------
# Pre-commit mode (MODE="staged", the default no-arg invocation
# pre-commit-gate.sh actually runs) used to grep each staged file's
# WHOLE CONTENT on disk, so a commit that never touches a denylisted
# line still blocked because the line was already there. Fixed by
# building a "delta view" per staged file (`_hhs_build_delta_view`):
# same line count as the real file, every line NOT added by the
# currently-staged diff replaced with blank, every ADDED line kept at
# its real new-file line number. Layer 1/2/3 checks run against this
# view for the BLOCK decision — same grep -n plumbing, so line numbers
# in the report stay correct. CHOICE MADE (per the task's own framing
# of the tradeoff): rather than make pre-existing content invisible, a
# file whose delta is clean but whose WHOLE FILE still matches Layer 1
# emits a non-blocking "PRE-EXISTING" notice to stderr.
#
# C1 CORRECTION (harness-review 2026-08-04): the FIRST shipped version of
# this notice claimed pre-existing debt is "caught by the periodic
# full-tree scan" — FALSE on two counts, PROVEN by reading the actual CI
# workflows: (1) nothing in this repo runs `--full-tree` on any schedule —
# `adapters/claude-code/config/schedule-manifest.json` has no entry for
# it, and the `/harness-review` skill that wraps it is operator-invoked,
# never cron'd; (2) the ACTUAL catcher — `.github/workflows/
# secret-backstop.yml` and `.github/workflows/server-side-enforcement.yml`,
# both run on every `push`/`pull_request` and go RED (red CI is stop-and-fix
# here; NOT branch-protection-required — only pr-template-check's validate is) — do NOT call
# `--full-tree` either; they call this script with the diff-range's
# changed files as EXPLICIT ARGS (`bash harness-hygiene-scan.sh
# "${changed[@]}"`), which is mode-3 explicit-file-arg scanning: WHOLE-FILE,
# not delta-scoped, and with NO waiver-marker channel at all (a fresh CI
# runner's checkout has no `.claude/state/`, so a local waiver never
# travels with the push). The true mechanism, stated honestly: a commit
# whose staged delta is clean can still land locally, but if the SAME file
# (still carrying the pre-existing hit) is ever pushed again — even for an
# unrelated edit — push-time CI re-scans that file's WHOLE CONTENT and
# goes RED, with no waiver escape available there. The PRE-EXISTING notice
# and the denylist ESCAPE text both name this real mechanism now, and the
# durable remedies (fix the content, or stage `is_exempt()` in the SAME
# commit) accordingly — not a "something else will catch it later" claim.
# Delta-scoping (or base-ref-diffing) the two CI jobs themselves so THEY
# also stop whole-file-scanning on every push touching an old-debt file is
# a named, NOT-YET-DONE follow-up — see docs/backlog.md
# HYGIENE-GATE-ESCAPE-ACCOUNTABILITY-FOLLOWUPS-2026-08-04 (deliberately not
# attempted in this series: it requires editing untestable-from-here GitHub
# Actions YAML, and getting it wrong risks silently weakening the actual
# security backstop — a worse outcome than shipping the honest messaging
# fix alone).
#
# `--full-tree` (still available, still whole-file, still ONLY run
# on-demand by an operator via the `/harness-review` skill or a direct
# invocation — never automatically) and explicit-file-arg invocations
# (mode 3, which is exactly what the two CI workflows above use) are
# UNCHANGED by this fix — this only touches MODE="staged" (which `--check`
# shares by default, preserving the R3.4 --check/enforce decision-parity
# guarantee).
#
# DEFECT 2 — SELF-SERVICE BYPASS ON A SECURITY-CLASS CONTROL
# ------------------------------------------------------------
# Layer 1 (denylist) matches are personal/business/identity-bearing
# strings — the security class. The self-service structured waiver
# (`harness-hygiene-waiver-*.txt`, Purpose+Because+Files) NO LONGER
# suppresses a Layer 1 match, ever — only Layer 2 (heuristic) and
# Layer 3 (addendum-lint) matches, which genuinely do false-positive on
# novel content and where the existing hatch is proportionate. A
# SEPARATE marker, `harness-hygiene-operator-waiver-*.txt`, honors a
# denylist suppression — same Purpose/Because/Files clauses PLUS a
# required `Operator-Authorized:` clause (>=20 non-whitespace chars,
# not a placeholder).
#
# HONEST TRUST MODEL (read this before treating the split above as a
# hard guarantee): nothing here is structurally unforgeable. An agent's
# own Bash/Write tools can author `harness-hygiene-operator-waiver-*.txt`
# exactly as easily as the old marker — there is no cryptographic or
# out-of-band channel distinguishing "the operator said so in chat" from
# "the agent wrote a file that claims the operator said so". This is the
# IDENTICAL trust model this repo's own `review-record-push-gate`
# manifest entry (`adapters/claude-code/manifest.json`, id
# "review-record-push-gate", `bypass_paths`) already discloses about its
# own override marker: raising the cost and audit legibility of
# self-issuance (a distinctly-named file, an extra required clause,
# same-session ledger surfacing — see Defect 3) is real and worth doing;
# it is NOT the same as making self-issuance impossible. The actual
# guarantee is behavioral (agents are instructed never to author this
# marker without an explicit operator instruction IN THE CURRENT
# CONVERSATION) plus post-hoc auditability (every waiver/operator-waiver
# use is ledgered via `ws_record`/`ledger_emit` and, as of Defect 3,
# surfaced at the next SessionStart). Self-issuing this marker without
# operator say-so is itself a harness-hygiene violation of the same kind
# as writing a false Purpose/Because clause into the plain waiver.
#
# DEFECT 3 — INVISIBILITY (fixed in session-start-digest.sh, not here)
# ------------------------------------------------------------
# workaround-sensor.jsonl bypasses were never surfaced in-session, so
# the four incident rows sat unnoticed for a day. `feed_bypass_surface`
# in `adapters/claude-code/hooks/session-start-digest.sh` (a new feed on
# the existing digest surface, not a new hook) reads that ledger
# directly and prints a `bypass-24h: <gate> <bypass_kind> x<n>` line per
# gate+kind combination active in the last 24h.
#
# DEFECT 4 — THE ESCAPE MUST COST MORE DOWNSTREAM THAN IT SAVES UPSTREAM
# (fixed in lib/workaround-sensor-lib.sh + stop-verdict-dispatcher.sh,
# not here — an operator amendment to this same fix)
# ------------------------------------------------------------
# An append-only ledger row is an audit log, not a deterrent — an agent
# pays nothing for using an escape, so it rationally takes it. Every
# `ws_record` call this gate makes (waiver OR operator-waiver) now OPENS
# a same-session escape obligation on the SAME accountability rail
# `lib/review-chain-lib.sh`'s verify-obligation tracking already built
# (gated-pipeline-master-2026-08 Task 25 / OD-022): the session's own
# Stop chain (`stop-verdict-dispatcher.sh`'s `_svd_escape_naming_check`)
# blocks a DONE/CONTINUING end that does not name every open, unfixed,
# unacknowledged gate escape it used. See
# `lib/workaround-sensor-lib.sh`'s own header for the full lifecycle
# (open / fixed / acknowledged) and its HONESTY CONSTRAINT: this makes a
# self-served escape IMPOSSIBLE TO HIDE (same-turn notice + Stop-blocking
# obligation), not impossible to self-serve — on a single-user machine
# there is no cryptographic boundary between agent and operator.

set -u

# ---------- structured waiver (F.5 waiver-parity audit row 12 / ADR 059 D4)
# ----------------------------------------------------------------------------
# Fresh (<1h) .claude/state/harness-hygiene-waiver-*.txt files, each naming
# BOTH purpose clauses (lib/waiver-purpose-clause.sh) AND a "Files:" line
# listing the repo-relative path(s) the waiver covers (space or newline
# separated). Matches on a listed file are suppressed for this run only —
# this is per-file and per-run, distinct from the plan-time exempt-list
# (is_exempt below), which is a durable, out-of-band, known-legitimate list.
_HHS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=lib/waiver-purpose-clause.sh
source "$_HHS_SELF_DIR/lib/waiver-purpose-clause.sh" 2>/dev/null || true
# shellcheck source=lib/signal-ledger.sh
source "$_HHS_SELF_DIR/lib/signal-ledger.sh" 2>/dev/null || true
# shellcheck source=lib/workaround-sensor-lib.sh
# Workaround-as-sensor law (operator directive, harness-execution-redesign-
# 2026-08 Task 2 deferred remainder): this gate is not yet retrofitted onto
# gate-contract-lib.sh (that retrofit is separately deferred), so it calls
# ws_record directly at its waiver-honored site below rather than going
# through gc_escape_used. Never fails the caller (see that lib's header).
source "$_HHS_SELF_DIR/lib/workaround-sensor-lib.sh" 2>/dev/null || true

# _hhs_waived_files <state-dir>
# Prints, one per line, every repo-relative file path named in a fresh
# (<1h), purpose-clause-valid waiver's "Files:" line(s). Empty output if no
# valid fresh waiver exists (fails closed — same posture as every other
# structured waiver in the harness).
_hhs_waived_files() {
  local state_dir="$1"
  [ -d "$state_dir" ] || return 0
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    fi
    # "Files:" line(s), case-insensitive label, space/comma-separated paths.
    grep -iE '^[[:space:]]*files[[:space:]]*:' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[Ff][Ii][Ll][Ee][Ss][[:space:]]*:[[:space:]]*//' \
      | tr ', ' '\n\n'
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'harness-hygiene-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
}

# ---------- operator-authorized waiver (Defect 2, security-class hits) ---
# Distinct marker (`harness-hygiene-operator-waiver-*.txt`, NOT the plain
# `harness-hygiene-waiver-*.txt` above) that can suppress a Layer 1
# (denylist) match. Requires the SAME Purpose/Because clauses PLUS a
# substantive `Operator-Authorized:` clause. See the file header's HONEST
# TRUST MODEL section — this raises the cost/legibility of self-issuance,
# it does not make it technically unforgeable.

# _hhs_operator_clause_ok <path>
# Returns 0 iff the file carries a non-placeholder `Operator-Authorized:`
# line (>=20 non-whitespace characters after the label). Deliberately the
# same "raise the bar past a one-word touch" idiom as
# waiver_has_purpose_clauses / review-record-push-gate's
# rrg_validate_waiver_reason.
_hhs_operator_clause_ok() {
  local f="$1"
  local line content stripped
  line=$(grep -iE '^[[:space:]]*operator-authorized[[:space:]]*:' "$f" 2>/dev/null | head -1)
  [ -z "$line" ] && return 1
  content=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[Oo]perator-[Aa]uthorized[[:space:]]*:[[:space:]]*//')
  stripped=$(printf '%s' "$content" | tr -d '[:space:]')
  [ "${#stripped}" -ge 20 ]
}

# _hhs_operator_waived_files <state-dir>
# Prints, one per line, every repo-relative file path named in a fresh
# (<1h), purpose-clause-valid, Operator-Authorized `harness-hygiene-
# operator-waiver-*.txt` marker's "Files:" line(s). Empty output if no
# valid fresh marker exists (fails closed, same posture as the plain
# waiver above).
_hhs_operator_waived_files() {
  local state_dir="$1"
  [ -d "$state_dir" ] || return 0
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if declare -F waiver_has_purpose_clauses >/dev/null 2>&1; then
      waiver_has_purpose_clauses "$f" || continue
    fi
    _hhs_operator_clause_ok "$f" || continue
    grep -iE '^[[:space:]]*files[[:space:]]*:' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*[Ff][Ii][Ll][Ee][Ss][[:space:]]*:[[:space:]]*//' \
      | tr ', ' '\n\n'
  done < <(find "$state_dir" -maxdepth 1 -type f -name 'harness-hygiene-operator-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null)
}

# ---------- self-test ----------------------------------------------------

if [ "${1:-}" = "--self-test" ]; then
  # Arm the shared libs' HARNESS_SELFTEST guard (signal-ledger.sh) for this run and
  # EXPORT it so re-invocations inherit it. Without it the lib resolves its
  # PRODUCTION path and this self-test appends to the operator's real
  # ~/.claude/state/signal-ledger.jsonl. PROVEN behaviorally: clean-HOME probe
  # created .claude/state/signal-ledger.jsonl without it, nothing with it.
  export HARNESS_SELFTEST=1
  TMPDIR_ST=$(mktemp -d)
  # Workaround-as-sensor sandbox (ws_record): an explicit path (rather than
  # relying on HARNESS_SELFTEST's own PID-keyed default) so the W6
  # ledger-row assertion below is deterministic — each W-scenario invokes
  # the scan as a fresh CHILD PROCESS (a new $$), so the default sandbox
  # path would differ per invocation and never be readable back here.
  WS_LEDGER_DIR=$(mktemp -d)
  export WORKAROUND_SENSOR_LEDGER_PATH="$WS_LEDGER_DIR/ledger.jsonl"
  trap 'rm -rf "$TMPDIR_ST" "$WS_LEDGER_DIR"' EXIT

  # Portable fixture aging (macos-portability-2026-07 M4), sourced inside
  # the self-test branch so the scan's normal path is untouched.
  _HHS_PT="$(dirname "${BASH_SOURCE[0]}")/lib/portable-time.sh"
  if ! . "$_HHS_PT" 2>/dev/null; then
    echo "self-test: cannot source $_HHS_PT (needed to backdate fixtures portably)" >&2
    exit 1
  fi

  # Build a minimal denylist
  mkdir -p "$TMPDIR_ST/adapters/claude-code/patterns"
  printf '%s\n' '# test denylist' 'FORBIDDEN_TOKEN' > "$TMPDIR_ST/adapters/claude-code/patterns/harness-denylist.txt"

  # Initialize a temp repo so the script's git rev-parse works
  (
    cd "$TMPDIR_ST" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email "selftest@example.com"
    git config user.name "selftest"
  )

  # Case 1: dirty file with the forbidden token
  DIRTY="$TMPDIR_ST/dirty.txt"
  printf '%s\n' 'line one' 'this line contains FORBIDDEN_TOKEN which should match' 'line three' > "$DIRTY"

  # Case 2: clean file
  CLEAN="$TMPDIR_ST/clean.txt"
  printf '%s\n' 'nothing bad here' 'just words' > "$CLEAN"

  # Case 3: dirty content in docs/plans/ SHOULD match (no longer exempt — NL
  # commits its own plans now, so they're subject to hygiene like any other
  # committed file).
  mkdir -p "$TMPDIR_ST/docs/plans"
  PLAN_FILE="$TMPDIR_ST/docs/plans/foo.md"
  printf '%s\n' 'this plan mentions FORBIDDEN_TOKEN as part of documenting it' > "$PLAN_FILE"

  # Case 4: dirty content in an exempt rule file should NOT match.
  mkdir -p "$TMPDIR_ST/adapters/claude-code/rules"
  EXEMPT_RULE="$TMPDIR_ST/adapters/claude-code/rules/harness-hygiene.md"
  printf '%s\n' 'harness-hygiene rule documents FORBIDDEN_TOKEN as a denylist example' > "$EXEMPT_RULE"

  # Case 5: allow-listed decision file (NNN-*.md) SHOULD be scanned (not exempt).
  mkdir -p "$TMPDIR_ST/docs/decisions"
  DECISION_ALLOWED="$TMPDIR_ST/docs/decisions/001-foo.md"
  printf '%s\n' 'decision NNN-* with FORBIDDEN_TOKEN must be caught' > "$DECISION_ALLOWED"

  # Case 6: non-allow-listed decision file (e.g., draft.md) is gitignored
  # instance artifact — still exempt to support drafts that never ship.
  DECISION_DRAFT="$TMPDIR_ST/docs/decisions/draft.md"
  printf '%s\n' 'draft mentions FORBIDDEN_TOKEN; gitignored, never ships' > "$DECISION_DRAFT"

  # Case 7: allow-listed review file (YYYY-MM-DD-*.md) SHOULD be scanned.
  mkdir -p "$TMPDIR_ST/docs/reviews"
  REVIEW_ALLOWED="$TMPDIR_ST/docs/reviews/2026-05-04-foo.md"
  printf '%s\n' 'review with FORBIDDEN_TOKEN must be caught' > "$REVIEW_ALLOWED"

  # ---- Layer 2 heuristic test fixtures ----

  # Case h1: positive path-shape match. File outside any NL-prefix path
  # mentions a project-internal API path. Should BLOCK with [heuristic] label.
  HEUR_PATH_DIRTY="$TMPDIR_ST/some-doc.md"
  printf '%s\n' 'See the route at app/api/v1/users/ for details.' > "$HEUR_PATH_DIRTY"

  # Case h2: positive cluster match. File mentions a fake project name 5x,
  # not in the NL vocabulary allowlist. Should BLOCK with [heuristic] label.
  HEUR_CLUSTER_DIRTY="$TMPDIR_ST/cluster-doc.md"
  printf '%s\n' \
    'Examplecorp ships a thing.' \
    'Examplecorp also ships another thing.' \
    'Why Examplecorp does this is unclear.' \
    'The Examplecorp engineering team made it work.' \
    'Examplecorp customers are happy.' \
    > "$HEUR_CLUSTER_DIRTY"

  # Case h3: NEGATIVE — NL-prefix path containing a project-internal-looking
  # path-shape should NOT trigger the heuristic (path-shape detection is
  # SKIPPED inside NL-prefix paths because they legitimately cite paths).
  mkdir -p "$TMPDIR_ST/adapters/claude-code/hooks"
  HEUR_NL_PATH="$TMPDIR_ST/adapters/claude-code/hooks/foo.sh"
  printf '%s\n' '# This hook references app/api/v1/users/ as an example.' > "$HEUR_NL_PATH"

  # Case h4: NEGATIVE — vocabulary allowlist token (Promise) appearing 5x
  # should NOT trigger cluster heuristic. Note: this file ALSO must not
  # match the path-shape heuristic, so we keep it path-free.
  HEUR_VOCAB="$TMPDIR_ST/vocab-doc.md"
  printf '%s\n' \
    'Promise me one thing.' \
    'A Promise is a contract.' \
    'Promise resolution is deterministic.' \
    'When a Promise rejects we handle the error.' \
    'Promise.all is the classic combinator.' \
    > "$HEUR_VOCAB"

  # Case h5: NEGATIVE — a clean file with no project-internal shapes and
  # no repeated non-allowlisted clusters should pass cleanly.
  HEUR_CLEAN="$TMPDIR_ST/clean-prose.md"
  printf '%s\n' \
    'This is just some prose.' \
    'Nothing dramatic happens.' \
    'Words appear and then leave.' \
    > "$HEUR_CLEAN"

  # ---- Layer 3 no-addendum lint fixtures (REQ-B10, M-9-narrowed pattern) --
  # Negative fixtures are VERBATIM lines lifted from the live corpus
  # (measured 2026-08-03) so the self-test IS the corpus measurement, not a
  # synthetic stand-in for it.
  mkdir -p "$TMPDIR_ST/docs/designs" "$TMPDIR_ST/docs/plans/archive"

  # A1 — POSITIVE: Addendum heading in a design. Verbatim (pre-integration
  # form) from docs/designs/harness-execution-redesign-considerations-
  # 2026-08-02.md:225.
  ADD_DESIGN_POS="$TMPDIR_ST/docs/designs/addendum-fixture.md"
  printf '%s\n' \
    '# Fixture design' \
    '' \
    '## Addendum — operator dialogue round 2 (2026-08-02, folded post-synthesis)' \
    'Some addendum content here.' \
    > "$ADD_DESIGN_POS"

  # A2 — POSITIVE: Round [0-9] heading in a design. Verbatim from the same
  # golden-case file, line 247.
  ROUND_DESIGN_POS="$TMPDIR_ST/docs/designs/round-fixture.md"
  printf '%s\n' \
    '# Fixture design' \
    '' \
    '## Round 3 revamp (2026-08-02, operator GO)' \
    'Some round-3 content here.' \
    > "$ROUND_DESIGN_POS"

  # A3 — POSITIVE: Update: heading in a design (no live corpus hit exists
  # for this sub-pattern; REQ-B10 requires it regardless of a live hit —
  # synthetic fixture, lowercased to also prove case-insensitivity).
  UPDATE_DESIGN_POS="$TMPDIR_ST/docs/designs/update-fixture.md"
  printf '%s\n' \
    '# Fixture design' \
    '' \
    '### update: 2026-08-03 correction' \
    'Some update content here.' \
    > "$UPDATE_DESIGN_POS"

  # A4 — POSITIVE: Addendum heading in a NON-archived PLAN — the Addendum/
  # Update: pattern covers docs/plans/** too, only docs/plans/archive/**
  # is excluded. Uppercased to also prove case-insensitivity.
  ADD_PLAN_POS="$TMPDIR_ST/docs/plans/addendum-fixture.md"
  printf '%s\n' \
    '# Fixture plan' \
    '' \
    '## ADDENDUM — case-insensitive positive' \
    'Some addendum content here.' \
    > "$ADD_PLAN_POS"

  # A5 — NEGATIVE, verbatim corpus (measured 2026-08-03): Round 3 / Round 4
  # review-round headings inside a non-archived PLAN.
  # docs/plans/review-gate-identity-anchor-2026-07-30.md:249,304. The Round
  # pattern scopes to docs/designs/** ONLY — review-round records are
  # established practice inside plans, not addenda.
  ROUND_PLAN_NEG="$TMPDIR_ST/docs/plans/round-heading-plan-fixture.md"
  printf '%s\n' \
    '# Fixture plan' \
    '' \
    '### Round 3 — harness-reviewer REJECT on `34e69fc` (3 Critical, 2 Major, 1 Minor)' \
    'Review content here.' \
    '' \
    '## Round 4 — evidence (harness-reviewer REJECT on `3ec297a`)' \
    'More review content.' \
    > "$ROUND_PLAN_NEG"

  # A6 — NEGATIVE, verbatim corpus: the archived D.5-addendum heading.
  # docs/plans/archive/nl-overhaul-program-2026-07-evidence.md:1120.
  # docs/plans/archive/** is excluded from scope entirely.
  ADD_ARCHIVE_NEG="$TMPDIR_ST/docs/plans/archive/addendum-archive-fixture.md"
  printf '%s\n' \
    '# Fixture archived plan' \
    '' \
    '## D.5 addendum — literal full-sweep GREEN achieved post-closure (2026-07-03, orchestrator session)' \
    'Archived content here.' \
    > "$ADD_ARCHIVE_NEG"

  # A7 — NEGATIVE control: a clean design with only body-prose mentions of
  # "addendum"/"round 2" (never as a heading) must pass cleanly.
  CLEAN_DESIGN_NEG="$TMPDIR_ST/docs/designs/clean-fixture.md"
  printf '%s\n' \
    '# Fixture design' \
    '' \
    '## Normal section' \
    'This design mentions an addendum in prose, and round 2 of testing,' \
    'but never as a heading, so it must not fire.' \
    > "$CLEAN_DESIGN_NEG"

  SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  # Initialized here (not at its historical spot right before the final
  # assertion block) because the R3.4 --check scenarios below run earlier
  # in the suite now and set FAIL=1 on failure before that spot is reached.
  FAIL=0

  # Invoke from the tmp repo so REPO_ROOT resolves to $TMPDIR_ST.
  # Pass relative paths so the exemption logic sees the repo-relative path,
  # matching how staged paths appear in pre-commit mode.
  set +e
  ST_DIRTY_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_DIRTY_RC=$?
  ST_CLEAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "clean.txt" 2>&1)
  ST_CLEAN_RC=$?

  # ---- R3.4 Gate Philosophy Law: --check parity + message fields ----
  # Placed here (right after the dirty/clean captures, before the heavier
  # heuristic/waiver/codename/secret-layer blocks below) to keep this
  # environment's live subprocess count away from its ceiling — each of
  # these nested invocations forks its own mktemp/awk/grep/sort children,
  # same as every other scenario in this suite.
  #
  # Structured fields: ST_DIRTY_OUT (already captured, normal enforce path)
  # must carry the four fields the doctor's gate-message lint checks for.
  ST_MSGFIELDS_OK=1
  for marker in "WHAT:" "WHY:" "FIX:" "ESCAPE:"; do
    if [[ "$ST_DIRTY_OUT" != *"$marker"* ]]; then
      ST_MSGFIELDS_OK=0
      echo "self-test: FAIL (msg-fields) — BLOCKED output missing '$marker' field" >&2
    fi
  done
  [ "$ST_MSGFIELDS_OK" -eq 1 ] && echo "self-test (msg-fields) structured-block-message: PASS" >&2

  # --check would-block parity: same violating fixture (dirty.txt), --check
  # flag. Proves --check and enforce share the SAME decision (one scan
  # loop, one _hhs_print_report emitter) — no separate code path to drift.
  ST_CHECK_DIRTY_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" --check "dirty.txt" 2>&1)
  ST_CHECK_DIRTY_RC=$?
  ST_CHECK_DIRTY_OK=1
  if [ "$ST_CHECK_DIRTY_RC" -ne 1 ]; then
    ST_CHECK_DIRTY_OK=0
    echo "self-test: FAIL (check-dirty) — --check on violating fixture expected exit 1 (would-block), got $ST_CHECK_DIRTY_RC" >&2
  fi
  if [[ "$ST_CHECK_DIRTY_OUT" != *"WOULD BLOCK"* ]]; then
    ST_CHECK_DIRTY_OK=0
    echo "self-test: FAIL (check-dirty) — --check output missing 'WOULD BLOCK' verdict" >&2
  fi
  if [[ "$ST_CHECK_DIRTY_OUT" != *"advisory only"* ]]; then
    ST_CHECK_DIRTY_OK=0
    echo "self-test: FAIL (check-dirty) — --check output missing advisory-only notice" >&2
  fi
  for marker in "WHAT:" "WHY:" "FIX:" "ESCAPE:"; do
    if [[ "$ST_CHECK_DIRTY_OUT" != *"$marker"* ]]; then
      ST_CHECK_DIRTY_OK=0
      echo "self-test: FAIL (check-dirty-fields) — --check output missing '$marker' field" >&2
    fi
  done
  if [ "$ST_CHECK_DIRTY_OK" -eq 1 ]; then
    echo "self-test (check-dirty) --check-would-block-parity: PASS" >&2
  else
    printf '    %s\n' "$ST_CHECK_DIRTY_OUT" >&2
    FAIL=1
  fi

  # --check would-pass parity: clean fixture, --check flag.
  ST_CHECK_CLEAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" --check "clean.txt" 2>&1)
  ST_CHECK_CLEAN_RC=$?
  ST_CHECK_CLEAN_OK=1
  if [ "$ST_CHECK_CLEAN_RC" -ne 0 ]; then
    ST_CHECK_CLEAN_OK=0
    echo "self-test: FAIL (check-clean) — --check on clean fixture expected exit 0 (would-pass), got $ST_CHECK_CLEAN_RC" >&2
  fi
  if [[ "$ST_CHECK_CLEAN_OUT" != *"would-pass"* ]]; then
    ST_CHECK_CLEAN_OK=0
    echo "self-test: FAIL (check-clean) — --check clean-fixture output missing would-pass verdict" >&2
  fi
  if [ "$ST_CHECK_CLEAN_OK" -eq 1 ]; then
    echo "self-test (check-clean) --check-would-pass-parity: PASS" >&2
  else
    printf '    %s\n' "$ST_CHECK_CLEAN_OUT" >&2
    FAIL=1
  fi

  # Cheap relevance pre-filter: nothing staged, no file args, --check mode
  # -> would-pass ("nothing to scan"), without reaching the denylist-file
  # read or PATTERNS_TMP build (same TMPDIR_ST repo has no staged index —
  # no commits exist yet in it at this point in the suite).
  ST_CHECK_PREFILTER_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" --check 2>&1)
  ST_CHECK_PREFILTER_RC=$?
  ST_CHECK_PREFILTER_OK=1
  if [ "$ST_CHECK_PREFILTER_RC" -ne 0 ]; then
    ST_CHECK_PREFILTER_OK=0
    echo "self-test: FAIL (check-prefilter) — --check with nothing staged expected exit 0, got $ST_CHECK_PREFILTER_RC" >&2
  fi
  if [[ "$ST_CHECK_PREFILTER_OUT" != *"nothing to scan"* ]]; then
    ST_CHECK_PREFILTER_OK=0
    echo "self-test: FAIL (check-prefilter) — --check with nothing staged missing 'nothing to scan' notice" >&2
  fi
  if [ "$ST_CHECK_PREFILTER_OK" -eq 1 ]; then
    echo "self-test (check-prefilter) --check-relevance-prefilter: PASS" >&2
  else
    printf '    %s\n' "$ST_CHECK_PREFILTER_OUT" >&2
    FAIL=1
  fi

  ST_PLAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/plans/foo.md" 2>&1)
  ST_PLAN_RC=$?
  ST_EXEMPT_RULE_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "adapters/claude-code/rules/harness-hygiene.md" 2>&1)
  ST_EXEMPT_RULE_RC=$?
  ST_DECISION_ALLOWED_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/decisions/001-foo.md" 2>&1)
  ST_DECISION_ALLOWED_RC=$?
  ST_DECISION_DRAFT_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/decisions/draft.md" 2>&1)
  ST_DECISION_DRAFT_RC=$?
  ST_REVIEW_ALLOWED_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/reviews/2026-05-04-foo.md" 2>&1)
  ST_REVIEW_ALLOWED_RC=$?

  # ---- Layer 2 heuristic invocations ----
  ST_HEUR_PATH_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_HEUR_PATH_RC=$?
  ST_HEUR_CLUSTER_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "cluster-doc.md" 2>&1)
  ST_HEUR_CLUSTER_RC=$?
  ST_HEUR_NL_PATH_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "adapters/claude-code/hooks/foo.sh" 2>&1)
  ST_HEUR_NL_PATH_RC=$?
  ST_HEUR_VOCAB_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "vocab-doc.md" 2>&1)
  ST_HEUR_VOCAB_RC=$?
  ST_HEUR_CLEAN_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "clean-prose.md" 2>&1)
  ST_HEUR_CLEAN_RC=$?

  # ---- Layer 3 no-addendum lint invocations (REQ-B10) ----
  ST_ADD_DESIGN_POS_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/designs/addendum-fixture.md" 2>&1)
  ST_ADD_DESIGN_POS_RC=$?
  ST_ROUND_DESIGN_POS_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/designs/round-fixture.md" 2>&1)
  ST_ROUND_DESIGN_POS_RC=$?
  ST_UPDATE_DESIGN_POS_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/designs/update-fixture.md" 2>&1)
  ST_UPDATE_DESIGN_POS_RC=$?
  ST_ADD_PLAN_POS_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/plans/addendum-fixture.md" 2>&1)
  ST_ADD_PLAN_POS_RC=$?
  ST_ROUND_PLAN_NEG_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/plans/round-heading-plan-fixture.md" 2>&1)
  ST_ROUND_PLAN_NEG_RC=$?
  ST_ADD_ARCHIVE_NEG_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/plans/archive/addendum-archive-fixture.md" 2>&1)
  ST_ADD_ARCHIVE_NEG_RC=$?
  ST_CLEAN_DESIGN_NEG_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/designs/clean-fixture.md" 2>&1)
  ST_CLEAN_DESIGN_NEG_RC=$?

  # ---- Structured-waiver scenarios (F.5 audit row 12 / ADR 059 D4) ----
  # Reuses some-doc.md (the h1 path-shape HEURISTIC fixture — [heuristic],
  # NOT [denylist]) as the "novel false positive" file the plain
  # self-service waiver covers. Retargeted off dirty.txt (2026-08-04,
  # Defect 2 fix): dirty.txt is a [denylist] (security-class) fixture and
  # the plain waiver no longer suppresses that class at all — see SEC1/SEC2
  # below, which replay the incident against dirty.txt directly.
  ST_WAIVER_STATE="$TMPDIR_ST/.claude/state"
  mkdir -p "$ST_WAIVER_STATE"

  # W1 — waiver-absent-blocks: no waiver file → same as plain heuristic hit (exit 1)
  ST_W1_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_W1_RC=$?

  # W2 — waiver-honored (HEURISTIC class): fresh waiver naming both clauses
  # + Files: some-doc.md
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: some-doc.md is a self-test fixture, not a real leak"
    echo "Files: some-doc.md"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-selftest.txt"
  ST_W2_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_W2_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-selftest.txt"

  # W3 — waiver-stale-rejected: same valid waiver but backdated >1h → BLOCK
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: some-doc.md is a self-test fixture, not a real leak"
    echo "Files: some-doc.md"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt"
  # No `|| true`: an un-aged waiver inverts this scenario silently.
  if ! nl_touch_age "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt" 7200; then
    echo "self-test: could not backdate the stale-waiver fixture" >&2
    exit 1
  fi
  ST_W3_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_W3_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-stale.txt"

  # W4 — regression: waiver naming clauses but a DIFFERENT file → some-doc.md
  # still BLOCKS (per-file scoping actually scopes, not a blanket valve)
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: some other file is a self-test fixture, not a real leak"
    echo "Files: some-other-file.txt"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-otherfile.txt"
  ST_W4_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_W4_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-otherfile.txt"

  # W5 — regression (pin f): non-empty waiver WITHOUT purpose-clause pair,
  # even with a matching Files: line, does NOT open the valve → BLOCK
  echo "Files: some-doc.md" > "$ST_WAIVER_STATE/harness-hygiene-waiver-weak.txt"
  ST_W5_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "some-doc.md" 2>&1)
  ST_W5_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-weak.txt"

  # ---- SEC1/SEC2 (Defect 2 — the incident, replayed as a fixture) ----
  # dirty.txt is a [denylist] (FORBIDDEN_TOKEN) match — the security class.

  # SEC1 — THE INCIDENT: an agent-authored PLAIN waiver (Purpose+Because+
  # Files, exactly the shape the old block message printed as a recipe)
  # against a denylist hit must still BLOCK. This is the exact incident
  # shape from 2026-08-04 (workaround-sensor.jsonl bypass_kind=waiver-file
  # rows against harness-hygiene-scan with no operator turn), replayed here
  # so a regression cannot silently reopen it.
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: dirty.txt is a self-test fixture, not a real leak"
    echo "Files: dirty.txt"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-sec1.txt"
  ST_SEC1_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_SEC1_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-sec1.txt"

  # SEC2 — operator-authorized path: the SEPARATE, distinctly-named
  # harness-hygiene-operator-waiver-*.txt marker, carrying the SAME
  # Purpose/Because clauses PLUS a substantive Operator-Authorized clause,
  # DOES suppress the denylist match.
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: dirty.txt is a self-test fixture, not a real leak"
    echo "Files: dirty.txt"
    echo "Operator-Authorized: yes I reviewed this in chat and it is a fixture, ship it"
  } > "$ST_WAIVER_STATE/harness-hygiene-operator-waiver-sec2.txt"
  ST_SEC2_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_SEC2_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-operator-waiver-sec2.txt"

  # SEC3 — regression: an operator-waiver marker MISSING the
  # Operator-Authorized clause (i.e., structurally identical to the plain
  # waiver, just under the new filename) does NOT open the valve — the
  # extra clause is what's load-bearing, not the filename alone.
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: dirty.txt is a self-test fixture, not a real leak"
    echo "Files: dirty.txt"
  } > "$ST_WAIVER_STATE/harness-hygiene-operator-waiver-sec3.txt"
  ST_SEC3_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_SEC3_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-operator-waiver-sec3.txt"

  # SEC4 — regression: an Operator-Authorized clause that IS a placeholder
  # (too short) does NOT open the valve either.
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: dirty.txt is a self-test fixture, not a real leak"
    echo "Files: dirty.txt"
    echo "Operator-Authorized: yes"
  } > "$ST_WAIVER_STATE/harness-hygiene-operator-waiver-sec4.txt"
  ST_SEC4_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "dirty.txt" 2>&1)
  ST_SEC4_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-operator-waiver-sec4.txt"

  # ---- Delta-scoping scenarios (Defect 1) ----
  # A dedicated fresh repo (distinct from TMPDIR_ST, which has no commits
  # by design up to this point in the suite — see the --check-prefilter
  # comment above) so these staged-mode (no-args) invocations get a real
  # git history to diff against.
  TMPDIR_DELTA="$TMPDIR_ST/delta-repo"
  mkdir -p "$TMPDIR_DELTA/adapters/claude-code/patterns"
  printf '%s\n' '# test denylist' 'FORBIDDEN_TOKEN' > "$TMPDIR_DELTA/adapters/claude-code/patterns/harness-denylist.txt"
  (
    cd "$TMPDIR_DELTA" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email "selftest@example.com"
    git config user.name "selftest"
  )

  # D1 — new hit IN the staged delta -> BLOCK. Commit a clean file, then
  # stage a change that ADDS a denylisted line.
  printf '%s\n' 'clean line one' 'clean line two' > "$TMPDIR_DELTA/f.txt"
  (cd "$TMPDIR_DELTA" && git add f.txt adapters/claude-code/patterns/harness-denylist.txt && git commit -q -m init)
  printf '%s\n' 'clean line one' 'clean line two' 'this line adds FORBIDDEN_TOKEN' > "$TMPDIR_DELTA/f.txt"
  (cd "$TMPDIR_DELTA" && git add f.txt)
  ST_D1_OUT=$(cd "$TMPDIR_DELTA" && bash "$SCRIPT_PATH" 2>&1)
  ST_D1_RC=$?
  (cd "$TMPDIR_DELTA" && git reset -q --hard HEAD)

  # D2 — delta clean, but the WHOLE FILE already had a pre-existing hit ->
  # does NOT block; a PRE-EXISTING notice is emitted. Commit a file that
  # ALREADY contains FORBIDDEN_TOKEN, then stage an UNRELATED line change
  # that never touches the token line.
  printf '%s\n' 'this line has FORBIDDEN_TOKEN already' 'unrelated line' > "$TMPDIR_DELTA/g.txt"
  (cd "$TMPDIR_DELTA" && git add g.txt && git commit -q -m "pre-existing hit")
  printf '%s\n' 'this line has FORBIDDEN_TOKEN already' 'unrelated line CHANGED' > "$TMPDIR_DELTA/g.txt"
  (cd "$TMPDIR_DELTA" && git add g.txt)
  ST_D2_OUT=$(cd "$TMPDIR_DELTA" && bash "$SCRIPT_PATH" 2>&1)
  ST_D2_RC=$?
  (cd "$TMPDIR_DELTA" && git reset -q --hard HEAD)

  # D3 (C2 fix, harness-review 2026-08-04) — a PURE RENAME (git mv, no
  # content change) of a file that already carries a pre-existing hit must
  # NOT block. Before the fix, `git diff --cached -U0 -- <dest-only>`
  # (pathspec-limited to the new path) could not pair the rename, so git
  # showed it as a brand-new file with EVERY line rendered as "added" —
  # reproducing the exact false-fire incident (the first real-world
  # trigger for this whole fix was a plan-archive rename, i.e. a git mv).
  printf '%s\n' 'this line has FORBIDDEN_TOKEN already' 'and another line' > "$TMPDIR_DELTA/rn-old.txt"
  (cd "$TMPDIR_DELTA" && git add rn-old.txt && git commit -q -m "pre-existing hit for rename fixture")
  (cd "$TMPDIR_DELTA" && git mv rn-old.txt rn-new.txt)
  ST_D3_OUT=$(cd "$TMPDIR_DELTA" && bash "$SCRIPT_PATH" 2>&1)
  ST_D3_RC=$?
  (cd "$TMPDIR_DELTA" && git reset -q --hard HEAD)

  # D3b — a RENAME + EDIT: the same pre-existing-hit file, renamed AND with
  # a genuinely new denylisted line added in the same commit. Must BLOCK,
  # and the report must show ONLY the truly-added line (proving old-blob->
  # new-blob pairing, not a fall-back to whole-file scanning).
  printf '%s\n' 'this line has FORBIDDEN_TOKEN already' 'and another line' > "$TMPDIR_DELTA/rn2-old.txt"
  (cd "$TMPDIR_DELTA" && git add rn2-old.txt && git commit -q -m "pre-existing hit for rename+edit fixture")
  (cd "$TMPDIR_DELTA" && git mv rn2-old.txt rn2-new.txt)
  printf '%s\n' 'this line has FORBIDDEN_TOKEN already' 'and another line' 'a brand new FORBIDDEN_TOKEN line' > "$TMPDIR_DELTA/rn2-new.txt"
  (cd "$TMPDIR_DELTA" && git add rn2-new.txt)
  ST_D3B_OUT=$(cd "$TMPDIR_DELTA" && bash "$SCRIPT_PATH" 2>&1)
  ST_D3B_RC=$?
  (cd "$TMPDIR_DELTA" && git reset -q --hard HEAD)

  # D4 (C3 fix, harness-review 2026-08-04) — an ADDED line whose own
  # CONTENT starts with "+" renders as "+++<content>" in the raw diff (the
  # diff's own "+" prefix, plus the content's literal leading "+"s), which
  # the pre-fix awk rule `/^\+\+\+/ { next }` swallowed unconditionally as
  # a false file-header match — silently dropping flagged content on such
  # lines. Must still BLOCK.
  printf '%s\n' 'clean line one' 'clean line two' > "$TMPDIR_DELTA/pp.txt"
  (cd "$TMPDIR_DELTA" && git add pp.txt && git commit -q -m "init for ++ fixture")
  printf '%s\n' 'clean line one' 'clean line two' '++FORBIDDEN_TOKEN' > "$TMPDIR_DELTA/pp.txt"
  (cd "$TMPDIR_DELTA" && git add pp.txt)
  ST_D4_OUT=$(cd "$TMPDIR_DELTA" && bash "$SCRIPT_PATH" 2>&1)
  ST_D4_RC=$?
  (cd "$TMPDIR_DELTA" && git reset -q --hard HEAD)

  # A8 — waiver escape (REQ-B10: "escape = the standard fresh-waiver shape,
  # ledgered"): a fresh waiver naming the Addendum-design fixture suppresses
  # the addendum-lint match too — same per-file waiver gate ahead of every
  # detection layer, no new plumbing needed for this class.
  {
    echo "Purpose: this gate exists to prevent identity-bearing strings shipping"
    echo "Because: docs/designs/addendum-fixture.md is a self-test fixture, not a real addendum"
    echo "Files: docs/designs/addendum-fixture.md"
  } > "$ST_WAIVER_STATE/harness-hygiene-waiver-addendum.txt"
  ST_A8_OUT=$(cd "$TMPDIR_ST" && bash "$SCRIPT_PATH" "docs/designs/addendum-fixture.md" 2>&1)
  ST_A8_RC=$?
  rm -f "$ST_WAIVER_STATE/harness-hygiene-waiver-addendum.txt"

  # ---- Codename-pattern scenarios (nl-issue [47]) ----
  # These run against the REAL shipped denylist (copied verbatim into a
  # second temp repo) so they exercise the actual pattern that ships —
  # including that the whole patterns file still compiles under
  # `grep -iE -f` (one invalid ERE makes grep exit 2, which the scanner
  # reads as "no match": ALL of Layer 1 would silently no-op).
  # One product codename is also a generic electrical-engineering noun; the
  # shipped pattern must catch it standalone (prose either case, file paths,
  # identifiers, end-of-line) but must NOT catch the generic two-word idiom
  # "<word> breaker" / "<word>-breaker", which false-blocked PR #91.
  # Loud SKIP when the real denylist is not reachable (e.g. the script runs
  # from a live ~/.claude copy outside the repo checkout).
  ST_C_SKIP=1
  REAL_ROOT=$(git -C "$(dirname "$SCRIPT_PATH")" rev-parse --show-toplevel 2>/dev/null || true)
  REAL_DENYLIST="$REAL_ROOT/adapters/claude-code/patterns/harness-denylist.txt"
  if [ -n "$REAL_ROOT" ] && [ -f "$REAL_DENYLIST" ]; then
    ST_C_SKIP=0
    TMPDIR_C="$TMPDIR_ST/codename-repo"
    mkdir -p "$TMPDIR_C/adapters/claude-code/patterns"
    cp "$REAL_DENYLIST" "$TMPDIR_C/adapters/claude-code/patterns/harness-denylist.txt"
    (
      cd "$TMPDIR_C" || exit 1
      git init -q . >/dev/null 2>&1
      git config user.email "selftest@example.com"
      git config user.name "selftest"
    )
    # Positives — the codename must still trip in every real leak context:
    printf '%s\n' 'the circuit rollout is delayed'                  > "$TMPDIR_C/c1-prose-lower.md"
    printf '%s\n' 'The Circuit rollout starts tomorrow.'            > "$TMPDIR_C/c2-prose-upper.md"
    printf '%s\n' 'stored under repos/circuit/config.yaml today'    > "$TMPDIR_C/c3-filepath.md"
    printf '%s\n' 'export circuit_env=prod for the test run'        > "$TMPDIR_C/c4-identifier.md"
    printf '%s\n' 'first enable circuit'                            > "$TMPDIR_C/c5-eol.md"
    # Negatives — the generic idiom must NOT trip (nl-issue [47] / PR #91):
    printf '%s\n' 'a circuit breaker guards the spawn path'         > "$TMPDIR_C/c6-idiom-space.md"
    printf '%s\n' 'add a circuit-breaker to the retry loop'         > "$TMPDIR_C/c7-idiom-hyphen.md"
    printf '%s\n' 'The Circuit Breaker pattern is well documented.' > "$TMPDIR_C/c8-idiom-caps.md"
    printf '%s\n' 'plain control prose with nothing special'        > "$TMPDIR_C/c9-clean.md"

    ST_C1_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c1-prose-lower.md" 2>&1); ST_C1_RC=$?
    ST_C2_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c2-prose-upper.md" 2>&1); ST_C2_RC=$?
    ST_C3_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c3-filepath.md" 2>&1); ST_C3_RC=$?
    ST_C4_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c4-identifier.md" 2>&1); ST_C4_RC=$?
    ST_C5_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c5-eol.md" 2>&1); ST_C5_RC=$?
    ST_C6_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c6-idiom-space.md" 2>&1); ST_C6_RC=$?
    ST_C7_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c7-idiom-hyphen.md" 2>&1); ST_C7_RC=$?
    ST_C8_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c8-idiom-caps.md" 2>&1); ST_C8_RC=$?
    ST_C9_OUT=$(cd "$TMPDIR_C" && bash "$SCRIPT_PATH" "c9-clean.md" 2>&1); ST_C9_RC=$?
  fi

  # ---- Machine-local secret-layer scenario (nl-issue [25] / GAP-56) ----
  # The literal credential VALUE relocated out of the shipped denylist must
  # never re-enter this repo's tracked tree. When the machine-local layer
  # (~/.claude/business-patterns.d/*.txt) exists, grep every tracked file of
  # the REAL repo for each of its patterns — zero matches required. Loud
  # SKIP where the layer or the repo checkout is absent (e.g. CI runners).
  ST_D_SKIP=1
  ST_D_OUT=""
  ST_D_RC=1
  BPD_DIR="$HOME/.claude/business-patterns.d"
  if [ -n "$REAL_ROOT" ] && [ -d "$BPD_DIR" ]; then
    BPD_PATS="$TMPDIR_ST/bpd-patterns.txt"
    cat "$BPD_DIR"/*.txt 2>/dev/null | awk '
      { gsub(/\r$/, "") }
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      { print }
    ' > "$BPD_PATS"
    if [ -s "$BPD_PATS" ]; then
      ST_D_SKIP=0
      ST_D_OUT=$(git -C "$REAL_ROOT" grep -I -i -l -E -f "$BPD_PATS" 2>&1)
      ST_D_RC=$?
    fi
  fi

  set -e

  # FAIL was initialized to 0 earlier (see comment above SCRIPT_PATH) so the
  # R3.4 --check scenarios above can accumulate into the same flag.
  if [ "$ST_DIRTY_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on dirty file, got $ST_DIRTY_RC" >&2
    echo "output was:" >&2
    echo "$ST_DIRTY_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_DIRTY_OUT" | grep -q 'FORBIDDEN_TOKEN'; then
    echo "self-test: FAIL — dirty output did not mention the matched token" >&2
    echo "output was:" >&2
    echo "$ST_DIRTY_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_CLEAN_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on clean file, got $ST_CLEAN_RC" >&2
    echo "output was:" >&2
    echo "$ST_CLEAN_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_PLAN_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on docs/plans/foo.md (no longer exempt), got $ST_PLAN_RC" >&2
    echo "(NL commits its own plans now; docs/plans/ is subject to hygiene)" >&2
    echo "output was:" >&2
    echo "$ST_PLAN_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_EXEMPT_RULE_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on exempt rules/harness-hygiene.md, got $ST_EXEMPT_RULE_RC" >&2
    echo "(exemption logic did not trigger; scanner would have blocked a harness-hygiene rule file)" >&2
    echo "output was:" >&2
    echo "$ST_EXEMPT_RULE_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_DECISION_ALLOWED_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on allow-listed docs/decisions/001-foo.md, got $ST_DECISION_ALLOWED_RC" >&2
    echo "(committed decision files MUST be scanned; only gitignored drafts are exempt)" >&2
    echo "output was:" >&2
    echo "$ST_DECISION_ALLOWED_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_DECISION_DRAFT_RC" -ne 0 ]; then
    echo "self-test: FAIL — expected exit 0 on non-allow-listed docs/decisions/draft.md (gitignored), got $ST_DECISION_DRAFT_RC" >&2
    echo "(non-NNN-prefixed files in docs/decisions/ are instance artifacts, still exempt)" >&2
    echo "output was:" >&2
    echo "$ST_DECISION_DRAFT_OUT" >&2
    FAIL=1
  fi
  if [ "$ST_REVIEW_ALLOWED_RC" -ne 1 ]; then
    echo "self-test: FAIL — expected exit 1 on allow-listed docs/reviews/2026-05-04-foo.md, got $ST_REVIEW_ALLOWED_RC" >&2
    echo "(committed review files MUST be scanned)" >&2
    echo "output was:" >&2
    echo "$ST_REVIEW_ALLOWED_OUT" >&2
    FAIL=1
  fi

  # ---- Layer 2 heuristic assertions ----
  # h1: positive path-shape match outside NL-prefix paths must BLOCK with [heuristic] label
  if [ "$ST_HEUR_PATH_RC" -ne 1 ]; then
    echo "self-test: FAIL (h1) — expected exit 1 on path-shape match in some-doc.md, got $ST_HEUR_PATH_RC" >&2
    echo "(file mentions app/api/v1/users/ outside NL-prefix paths and should be blocked)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_PATH_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_HEUR_PATH_OUT" | grep -q '\[heuristic\]'; then
    echo "self-test: FAIL (h1) — path-shape match output did not carry [heuristic] label" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_PATH_OUT" >&2
    FAIL=1
  fi
  # h2: positive cluster match (Examplecorp x5) must BLOCK with [heuristic] label
  if [ "$ST_HEUR_CLUSTER_RC" -ne 1 ]; then
    echo "self-test: FAIL (h2) — expected exit 1 on cluster match in cluster-doc.md, got $ST_HEUR_CLUSTER_RC" >&2
    echo "(file mentions 'Examplecorp' 5+ times, not in NL vocabulary allowlist)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_CLUSTER_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_HEUR_CLUSTER_OUT" | grep -q 'Examplecorp'; then
    echo "self-test: FAIL (h2) — cluster output did not mention the matched token Examplecorp" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_CLUSTER_OUT" >&2
    FAIL=1
  fi
  # h3: NEGATIVE — NL-prefix path with project-internal-looking path-shape must NOT fire path-shape heuristic
  if [ "$ST_HEUR_NL_PATH_RC" -ne 0 ]; then
    echo "self-test: FAIL (h3) — expected exit 0 on NL-prefix file mentioning a path, got $ST_HEUR_NL_PATH_RC" >&2
    echo "(adapters/claude-code/hooks/foo.sh is NL-prefix exempt for path-shape detection)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_NL_PATH_OUT" >&2
    FAIL=1
  fi
  # h4: NEGATIVE — vocabulary token Promise x5 must NOT fire cluster heuristic
  if [ "$ST_HEUR_VOCAB_RC" -ne 0 ]; then
    echo "self-test: FAIL (h4) — expected exit 0 on vocab-doc.md (Promise in allowlist), got $ST_HEUR_VOCAB_RC" >&2
    echo "(Promise appears 5x but is in NL_VOCAB_ALLOWLIST — should not fire)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_VOCAB_OUT" >&2
    FAIL=1
  fi
  # h5: NEGATIVE — clean prose must produce no heuristic matches
  if [ "$ST_HEUR_CLEAN_RC" -ne 0 ]; then
    echo "self-test: FAIL (h5) — expected exit 0 on clean-prose.md, got $ST_HEUR_CLEAN_RC" >&2
    echo "(no project-internal shapes and no repeated non-allowlist clusters)" >&2
    echo "output was:" >&2
    echo "$ST_HEUR_CLEAN_OUT" >&2
    FAIL=1
  fi

  # ---- Layer 3 no-addendum lint assertions (REQ-B10) ----
  # A1: Addendum heading in a design must BLOCK with [addendum-lint] label
  if [ "$ST_ADD_DESIGN_POS_RC" -ne 1 ]; then
    echo "self-test: FAIL (a1) — expected exit 1 on Addendum heading in docs/designs/, got $ST_ADD_DESIGN_POS_RC" >&2
    echo "$ST_ADD_DESIGN_POS_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_ADD_DESIGN_POS_OUT" | grep -q '\[addendum-lint\]'; then
    echo "self-test: FAIL (a1) — Addendum-heading match did not carry the [addendum-lint] label" >&2
    echo "$ST_ADD_DESIGN_POS_OUT" >&2
    FAIL=1
  fi
  # A2: Round [0-9] heading in a design must BLOCK
  if [ "$ST_ROUND_DESIGN_POS_RC" -ne 1 ]; then
    echo "self-test: FAIL (a2) — expected exit 1 on Round-N heading in docs/designs/, got $ST_ROUND_DESIGN_POS_RC" >&2
    echo "$ST_ROUND_DESIGN_POS_OUT" >&2
    FAIL=1
  fi
  # A3: Update: heading in a design must BLOCK (lowercase fixture — also
  # proves case-insensitivity)
  if [ "$ST_UPDATE_DESIGN_POS_RC" -ne 1 ]; then
    echo "self-test: FAIL (a3) — expected exit 1 on lowercase 'update:' heading in docs/designs/, got $ST_UPDATE_DESIGN_POS_RC" >&2
    echo "$ST_UPDATE_DESIGN_POS_OUT" >&2
    FAIL=1
  fi
  # A4: Addendum heading in a NON-archived plan must BLOCK (uppercase
  # fixture — also proves case-insensitivity; pattern covers docs/plans/**)
  if [ "$ST_ADD_PLAN_POS_RC" -ne 1 ]; then
    echo "self-test: FAIL (a4) — expected exit 1 on uppercase 'ADDENDUM' heading in docs/plans/, got $ST_ADD_PLAN_POS_RC" >&2
    echo "$ST_ADD_PLAN_POS_OUT" >&2
    FAIL=1
  fi
  # A5: NEGATIVE — verbatim-corpus Round 3/Round 4 review-round headings
  # inside a non-archived plan must PASS (scope = docs/designs/** only)
  if [ "$ST_ROUND_PLAN_NEG_RC" -ne 0 ]; then
    echo "self-test: FAIL (a5) — Round-N review-round headings inside a plan must NOT fire (scope=docs/designs/ only), expected exit 0, got $ST_ROUND_PLAN_NEG_RC" >&2
    echo "(verbatim from docs/plans/review-gate-identity-anchor-2026-07-30.md:249,304)" >&2
    echo "$ST_ROUND_PLAN_NEG_OUT" >&2
    FAIL=1
  fi
  # A6: NEGATIVE — verbatim-corpus archived Addendum heading must PASS
  # (docs/plans/archive/** excluded from scope entirely)
  if [ "$ST_ADD_ARCHIVE_NEG_RC" -ne 0 ]; then
    echo "self-test: FAIL (a6) — Addendum heading under docs/plans/archive/ must NOT fire (archive excluded from scope), expected exit 0, got $ST_ADD_ARCHIVE_NEG_RC" >&2
    echo "(verbatim from docs/plans/archive/nl-overhaul-program-2026-07-evidence.md:1120)" >&2
    echo "$ST_ADD_ARCHIVE_NEG_OUT" >&2
    FAIL=1
  fi
  # A7: NEGATIVE control — clean design (body-prose mentions only, never a
  # heading) must PASS
  if [ "$ST_CLEAN_DESIGN_NEG_RC" -ne 0 ]; then
    echo "self-test: FAIL (a7) — clean design with only body-prose mentions of addendum/round must PASS, expected exit 0, got $ST_CLEAN_DESIGN_NEG_RC" >&2
    echo "$ST_CLEAN_DESIGN_NEG_OUT" >&2
    FAIL=1
  fi

  # ---- Structured-waiver assertions (F.5 audit row 12 / ADR 059 D4) ----
  # W1: waiver-absent-blocks (some-doc.md, HEURISTIC class)
  if [ "$ST_W1_RC" -ne 1 ]; then
    echo "self-test: FAIL (w1) — waiver-absent expected exit 1, got $ST_W1_RC" >&2
    echo "$ST_W1_OUT" >&2
    FAIL=1
  fi
  # W2: waiver-honored (fresh, both clauses, Files: matches, HEURISTIC class) → ALLOW
  if [ "$ST_W2_RC" -ne 0 ]; then
    echo "self-test: FAIL (w2) — waiver-honored (heuristic class) expected exit 0, got $ST_W2_RC" >&2
    echo "$ST_W2_OUT" >&2
    FAIL=1
  fi
  # W6 (workaround-as-sensor): the SAME W2 waiver-honored run both (a) still
  # honors the waiver identically (asserted above, unchanged) AND (b)
  # appended a row to the workaround-sensor ledger (ws_record) — confirms
  # the operator's workaround-as-sensor law is wired at this gate's own
  # waiver-honored call site, not just a self-tested-in-isolation library.
  if ! grep -q '"gate":"harness-hygiene-scan"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     || ! grep -q '"bypass_kind":"waiver-file"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     || ! grep -q '"command_fingerprint":"file=some-doc.md"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null; then
    echo "self-test: FAIL (w6) — expected a workaround-sensor ledger row for the W2 waiver-honored run" >&2
    echo "  ledger content: $(cat "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null || echo '(missing)')" >&2
    FAIL=1
  fi
  # W3: waiver-stale-rejected (>1h old) → BLOCK
  if [ "$ST_W3_RC" -ne 1 ]; then
    echo "self-test: FAIL (w3) — waiver-stale expected exit 1, got $ST_W3_RC" >&2
    echo "$ST_W3_OUT" >&2
    FAIL=1
  fi
  # W4: waiver names a DIFFERENT file → some-doc.md still BLOCKS (scoping works)
  if [ "$ST_W4_RC" -ne 1 ]; then
    echo "self-test: FAIL (w4) — waiver for a different file must not cover some-doc.md, expected exit 1, got $ST_W4_RC" >&2
    echo "$ST_W4_OUT" >&2
    FAIL=1
  fi
  # W5: non-empty waiver without purpose-clause pair (pin f) → BLOCK
  if [ "$ST_W5_RC" -ne 1 ]; then
    echo "self-test: FAIL (w5) — weak waiver (no purpose-clauses) expected exit 1, got $ST_W5_RC" >&2
    echo "$ST_W5_OUT" >&2
    FAIL=1
  fi

  # ---- SEC1-SEC4 assertions (Defect 2 — the incident, replayed) ----
  # SEC1: agent-authored PLAIN waiver against a [denylist] hit -> still BLOCKED
  if [ "$ST_SEC1_RC" -ne 1 ]; then
    echo "self-test: FAIL (sec1) — INCIDENT REPLAY: a plain self-service waiver against a [denylist] match must still BLOCK, expected exit 1, got $ST_SEC1_RC" >&2
    echo "$ST_SEC1_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_SEC1_OUT" | grep -q 'NOT SELF-WAIVABLE'; then
    echo "self-test: FAIL (sec1) — block message for a [denylist] match must carry the operator-escalation text ('NOT SELF-WAIVABLE'), not the old bare recipe" >&2
    echo "$ST_SEC1_OUT" >&2
    FAIL=1
  fi
  if printf '%s' "$ST_SEC1_OUT" | grep -qF 'harness-hygiene-waiver-$(date'; then
    echo "self-test: FAIL (sec1) — block message must NOT print the old self-service copy-paste recipe when the ONLY match is [denylist]" >&2
    echo "$ST_SEC1_OUT" >&2
    FAIL=1
  fi
  # C6 fix (harness-review 2026-08-04): the NEW operator-waiver marker's
  # recipe must ALSO be absent — the prior version removed the OLD
  # (harness-hygiene-waiver-) recipe but printed an equally-copy-pasteable
  # NEW (harness-hygiene-operator-waiver-) one, which is the same defect in
  # a fancier shape. Pin BOTH the literal mkdir+printf shape and the
  # marker's own runnable filename pattern as absent from the message.
  if printf '%s' "$ST_SEC1_OUT" | grep -qF 'harness-hygiene-operator-waiver-$(date'; then
    echo "self-test: FAIL (sec1/C6) — block message must NOT print a copy-paste recipe for the operator-waiver marker either; it must point to the marker spec location instead" >&2
    echo "$ST_SEC1_OUT" >&2
    FAIL=1
  fi
  if printf '%s' "$ST_SEC1_OUT" | grep -qF 'mkdir -p'; then
    echo "self-test: FAIL (sec1/C6) — block message must NOT print ANY runnable mkdir/printf recipe for a [denylist]-only match" >&2
    echo "$ST_SEC1_OUT" >&2
    FAIL=1
  fi
  # SEC2: operator-authorized waiver (Purpose+Because+Files+Operator-Authorized,
  # distinct filename) DOES suppress the [denylist] match -> ALLOW
  if [ "$ST_SEC2_RC" -ne 0 ]; then
    echo "self-test: FAIL (sec2) — operator-authorized waiver against a [denylist] match expected exit 0 (ALLOW), got $ST_SEC2_RC" >&2
    echo "$ST_SEC2_OUT" >&2
    FAIL=1
  fi
  if ! grep -q '"gate":"harness-hygiene-scan"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     || ! grep -q '"bypass_kind":"operator-waiver-file"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     || ! grep -q '"command_fingerprint":"file=dirty.txt"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null; then
    echo "self-test: FAIL (sec2) — expected a workaround-sensor ledger row with bypass_kind=operator-waiver-file for the SEC2 run" >&2
    echo "  ledger content: $(cat "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null || echo '(missing)')" >&2
    FAIL=1
  fi
  # SEC3: operator-waiver filename but MISSING the Operator-Authorized
  # clause -> still BLOCKED (the clause is load-bearing, not the filename)
  if [ "$ST_SEC3_RC" -ne 1 ]; then
    echo "self-test: FAIL (sec3) — operator-waiver-named file WITHOUT an Operator-Authorized clause must still BLOCK, expected exit 1, got $ST_SEC3_RC" >&2
    echo "$ST_SEC3_OUT" >&2
    FAIL=1
  fi
  # SEC4: Operator-Authorized clause present but a placeholder (<20 chars)
  # -> still BLOCKED
  if [ "$ST_SEC4_RC" -ne 1 ]; then
    echo "self-test: FAIL (sec4) — placeholder Operator-Authorized clause ('yes') must still BLOCK, expected exit 1, got $ST_SEC4_RC" >&2
    echo "$ST_SEC4_OUT" >&2
    FAIL=1
  fi

  # ---- D1/D2 assertions (Defect 1 — delta-scoping) ----
  # D1: a genuinely NEW denylisted line in the staged delta -> BLOCK
  if [ "$ST_D1_RC" -ne 1 ]; then
    echo "self-test: FAIL (d1) — a NEW denylist hit in the staged delta must BLOCK, expected exit 1, got $ST_D1_RC" >&2
    echo "$ST_D1_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_D1_OUT" | grep -q 'FORBIDDEN_TOKEN'; then
    echo "self-test: FAIL (d1) — block output did not mention the newly-added FORBIDDEN_TOKEN line" >&2
    echo "$ST_D1_OUT" >&2
    FAIL=1
  fi
  # D2: delta clean, whole file has a PRE-EXISTING hit -> does NOT block,
  # and the PRE-EXISTING notice is emitted (the false-fire fix).
  if [ "$ST_D2_RC" -ne 0 ]; then
    echo "self-test: FAIL (d2) — a staged delta that never touches the pre-existing denylisted line must NOT block, expected exit 0, got $ST_D2_RC" >&2
    echo "$ST_D2_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_D2_OUT" | grep -qi 'PRE-EXISTING'; then
    echo "self-test: FAIL (d2) — expected a PRE-EXISTING notice for the untouched pre-existing hit" >&2
    echo "$ST_D2_OUT" >&2
    FAIL=1
  fi

  # ---- D3/D3b/D4 assertions (C2 rename fix + C3 ++-evasion fix) ----
  # D3: a PURE RENAME of a file with a pre-existing hit must NOT block.
  if [ "$ST_D3_RC" -ne 0 ]; then
    echo "self-test: FAIL (d3/C2) — a pure rename (git mv, no content change) of a file with a pre-existing hit must NOT block, expected exit 0, got $ST_D3_RC" >&2
    echo "$ST_D3_OUT" >&2
    FAIL=1
  fi
  # D3b: a rename+edit must BLOCK, and the report must show ONLY the truly
  # new line (proving old-blob->new-blob pairing, not whole-file fallback).
  if [ "$ST_D3B_RC" -ne 1 ]; then
    echo "self-test: FAIL (d3b/C2) — a rename PLUS a genuinely new denylist hit must BLOCK, expected exit 1, got $ST_D3B_RC" >&2
    echo "$ST_D3B_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_D3B_OUT" | grep -q 'a brand new FORBIDDEN_TOKEN line'; then
    echo "self-test: FAIL (d3b/C2) — block output did not mention the truly-new added line" >&2
    echo "$ST_D3B_OUT" >&2
    FAIL=1
  fi
  D3B_MATCH_COUNT=$(printf '%s' "$ST_D3B_OUT" | grep -c '^\[denylist\]')
  if [ "$D3B_MATCH_COUNT" -ne 1 ]; then
    echo "self-test: FAIL (d3b/C2) — expected exactly 1 [denylist] match (only the truly-new line), got $D3B_MATCH_COUNT — old-blob->new-blob pairing is not scoping correctly" >&2
    echo "$ST_D3B_OUT" >&2
    FAIL=1
  fi
  # D4: an added line whose CONTENT starts with "+" (renders as "+++..."
  # in the raw diff) must still BLOCK — not be swallowed as a false header.
  if [ "$ST_D4_RC" -ne 1 ]; then
    echo "self-test: FAIL (d4/C3) — an added line starting with '++' must still BLOCK, expected exit 1, got $ST_D4_RC" >&2
    echo "$ST_D4_OUT" >&2
    FAIL=1
  fi
  if ! printf '%s' "$ST_D4_OUT" | grep -q 'FORBIDDEN_TOKEN'; then
    echo "self-test: FAIL (d4/C3) — block output did not mention the ++-prefixed FORBIDDEN_TOKEN line (evaded by the pre-fix awk rule)" >&2
    echo "$ST_D4_OUT" >&2
    FAIL=1
  fi

  # A8 (REQ-B10 escape): waiver-honored — an addendum-lint match is
  # suppressed by the same fresh structured waiver as any other layer, AND
  # ledgered via ws_record at the existing waiver-honored call site.
  if [ "$ST_A8_RC" -ne 0 ]; then
    echo "self-test: FAIL (a8) — waiver-honored addendum-lint match expected exit 0, got $ST_A8_RC" >&2
    echo "$ST_A8_OUT" >&2
    FAIL=1
  fi
  if ! grep -q '"gate":"harness-hygiene-scan"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     || ! grep -q '"bypass_kind":"waiver-file"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null \
     || ! grep -q '"command_fingerprint":"file=docs/designs/addendum-fixture.md"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null; then
    echo "self-test: FAIL (a8) — expected a workaround-sensor ledger row for the addendum-lint waiver-honored run" >&2
    echo "  ledger content: $(cat "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null || echo '(missing)')" >&2
    FAIL=1
  fi

  # ---- Codename-pattern assertions (nl-issue [47]) ----
  if [ "$ST_C_SKIP" -eq 1 ]; then
    echo "self-test: SKIP (c1-c9) — real shipped denylist not reachable from this script location; run from the repo checkout to exercise the codename-pattern scenarios" >&2
  else
    # c1-c5: the codename must trip, and via Layer 1 ([denylist] label) —
    # a heuristic-caused block would be a false pass for the pattern.
    if [ "$ST_C1_RC" -ne 1 ] || ! printf '%s' "$ST_C1_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c1) — lowercase codename in prose must trip the denylist (expected exit 1 + [denylist], got $ST_C1_RC)" >&2
      echo "$ST_C1_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C2_RC" -ne 1 ] || ! printf '%s' "$ST_C2_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c2) — capitalized codename in prose must trip the denylist (expected exit 1 + [denylist], got $ST_C2_RC)" >&2
      echo "$ST_C2_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C3_RC" -ne 1 ] || ! printf '%s' "$ST_C3_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c3) — codename inside a file path must trip the denylist (expected exit 1 + [denylist], got $ST_C3_RC)" >&2
      echo "$ST_C3_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C4_RC" -ne 1 ] || ! printf '%s' "$ST_C4_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c4) — codename inside an identifier must trip the denylist (expected exit 1 + [denylist], got $ST_C4_RC)" >&2
      echo "$ST_C4_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C5_RC" -ne 1 ] || ! printf '%s' "$ST_C5_OUT" | grep -q '\[denylist\]'; then
      echo "self-test: FAIL (c5) — codename at end-of-line must trip the denylist (expected exit 1 + [denylist], got $ST_C5_RC)" >&2
      echo "$ST_C5_OUT" >&2
      FAIL=1
    fi
    # c6-c8: the generic "<word> breaker" idiom must NOT trip (PR #91 class)
    if [ "$ST_C6_RC" -ne 0 ]; then
      echo "self-test: FAIL (c6) — generic '<word> breaker' prose must NOT trip (nl-issue [47]), expected exit 0, got $ST_C6_RC" >&2
      echo "$ST_C6_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C7_RC" -ne 0 ]; then
      echo "self-test: FAIL (c7) — generic '<word>-breaker' prose must NOT trip (nl-issue [47]), expected exit 0, got $ST_C7_RC" >&2
      echo "$ST_C7_OUT" >&2
      FAIL=1
    fi
    if [ "$ST_C8_RC" -ne 0 ]; then
      echo "self-test: FAIL (c8) — capitalized '<Word> Breaker' prose must NOT trip (scan is -i; nl-issue [47]), expected exit 0, got $ST_C8_RC" >&2
      echo "$ST_C8_OUT" >&2
      FAIL=1
    fi
    # c9: clean control — guards against an "everything matches" pathology
    # (e.g. an invalid ERE degrading grep, or an over-broad new pattern).
    if [ "$ST_C9_RC" -ne 0 ]; then
      echo "self-test: FAIL (c9) — clean control file must pass with the full real denylist, expected exit 0, got $ST_C9_RC" >&2
      echo "$ST_C9_OUT" >&2
      FAIL=1
    fi
  fi

  # ---- Machine-local secret-layer assertion (nl-issue [25] / GAP-56) ----
  if [ "$ST_D_SKIP" -eq 1 ]; then
    echo "self-test: SKIP (d) — machine-local ~/.claude/business-patterns.d layer absent or repo checkout not reachable (expected on CI runners)" >&2
  elif [ "$ST_D_RC" -eq 0 ]; then
    echo "self-test: FAIL (d) — a machine-local secret-layer pattern matches tracked file(s) in this repo; the relocated literal (or another local-layer secret) has re-entered the tree:" >&2
    echo "$ST_D_OUT" >&2
    FAIL=1
  elif [ "$ST_D_RC" -ne 1 ]; then
    echo "self-test: FAIL (d) — git grep errored (exit $ST_D_RC) while checking the machine-local secret layer against the tree:" >&2
    echo "$ST_D_OUT" >&2
    FAIL=1
  fi

  if [ "$FAIL" -eq 0 ]; then
    echo "self-test: OK"
    exit 0
  fi
  exit 1
fi

# ---------- --check pre-flight mode (R3.4 Gate Philosophy Law) -----------
# Leading `--check` flag only; consumed here so every mode below (staged /
# --full-tree / explicit files) works identically for both the enforce
# path and the pre-flight path — one file-list assembly, one scan, one
# report emitter (`_hhs_print_report`). No second code path to drift.
CHECK_MODE=0
if [ "${1:-}" = "--check" ]; then
  CHECK_MODE=1
  shift
fi

# ---------- repo discovery -----------------------------------------------

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$REPO_ROOT" ]; then
  # Not in a git repo — silent no-op.
  exit 0
fi

# ---------- cheap relevance pre-filter ------------------------------------
# Assemble the file list to scan FIRST — before reading the denylist file
# or building PATTERNS_TMP (an awk pass + a mktemp) — so an invocation with
# nothing to scan (nothing staged, or explicit paths that don't exist)
# bails before paying that setup cost. Mode selection is unchanged from
# the original ordering: `--full-tree` / explicit file args / staged
# (default) — only WHEN it runs moved earlier.
MODE="staged"
FILE_LIST_TMP=$(mktemp)
trap 'rm -f "$FILE_LIST_TMP"' EXIT

if [ "${1:-}" = "--full-tree" ]; then
  MODE="full-tree"
  (cd "$REPO_ROOT" && git ls-files -z) > "$FILE_LIST_TMP"
elif [ "$#" -gt 0 ]; then
  MODE="files"
  # Pass each argv as null-terminated so filenames with spaces survive.
  for arg in "$@"; do
    printf '%s\0' "$arg"
  done > "$FILE_LIST_TMP"
else
  # Default: staged files for pre-commit (and --check with no path args).
  (cd "$REPO_ROOT" && git diff --cached --name-only -z --diff-filter=ACMR) > "$FILE_LIST_TMP"
fi

if [ ! -s "$FILE_LIST_TMP" ]; then
  if [ "$CHECK_MODE" -eq 1 ]; then
    echo "[harness-hygiene-scan --check] would-pass (nothing to scan)" >&2
  fi
  exit 0
fi

# ---------- rename map (Defect C2 fix, harness-review 2026-08-04) --------
# `git diff --cached -U0 -- <dest-only>` (the ORIGINAL delta-scoping call)
# cannot pair a rename: pathspec-limited to just the destination, git shows
# a pure `git mv` as a brand-new file with EVERY line rendered `+` (added)
# — including lines the rename never touched. For a renamed file that
# already carried a hit, the delta view then equals the WHOLE FILE again,
# reproducing the exact false-fire incident this fix exists to close. Built
# ONCE per run (not per file) via a single `--name-status` pass; maps a
# rename DESTINATION path to its source so the delta-view builder can diff
# old-blob -> new-blob directly (git DOES pair a rename correctly when both
# the old and new pathspecs are given — verified: a pure rename then shows
# zero hunks, a rename+edit shows only the truly-changed lines).
HHS_RENAME_MAP_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$HHS_RENAME_MAP_TMP"' EXIT
if [ "$MODE" = "staged" ]; then
  git -C "$REPO_ROOT" diff --cached -M --name-status -z --diff-filter=R 2>/dev/null | awk '
    BEGIN { RS="\0" }
    { idx++ }
    idx % 3 == 2 { old = $0 }
    idx % 3 == 0 { print $0 "\t" old }
  ' > "$HHS_RENAME_MAP_TMP"
fi

# _hhs_rename_source <dest-repo-relative-path>
# Prints the OLD (source) path and returns 0 if <dest> is a rename
# destination this run; returns 1 (prints nothing) otherwise.
_hhs_rename_source() {
  local dest="$1"
  [ -s "$HHS_RENAME_MAP_TMP" ] || return 1
  awk -F'\t' -v d="$dest" '$1 == d { print $2; found=1; exit } END { exit !found }' "$HHS_RENAME_MAP_TMP"
}

DENYLIST_FILE="$REPO_ROOT/adapters/claude-code/patterns/harness-denylist.txt"
if [ ! -f "$DENYLIST_FILE" ]; then
  echo "harness-hygiene-scan: denylist not found at $DENYLIST_FILE — skipping (this is expected before Phase 2 deploy)" >&2
  exit 0
fi

# ---------- build the regex patterns file grep will read ------------------
# We strip comments and blank lines so grep -f only sees real patterns.
PATTERNS_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$HHS_RENAME_MAP_TMP"' EXIT

awk '
  # skip blank lines and comment-only lines
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }
  { print }
' "$DENYLIST_FILE" > "$PATTERNS_TMP"

# If every line of the denylist was blank/comment, there is nothing to match.
if [ ! -s "$PATTERNS_TMP" ]; then
  exit 0
fi

# ---------- Layer 2: heuristic detection ---------------------------------
#
# check_heuristics() — invoked per file after the denylist scan. Detects
# project-specific content shapes the literal denylist cannot catch.
#
# Two sub-checks:
#   (a) project-internal file-path shapes (e.g., `app/api/v1/users/`,
#       `src/components/MyComponent.tsx`, `supabase/migrations/<14>_<slug>.sql`)
#   (b) repeated capitalized-term clusters: 3+ occurrences of the same
#       `[A-Z][a-z]{4,15}` token within a single file, EXCLUDING tokens in
#       the NL-vocabulary allowlist
#
# Both sub-checks are SKIPPED for files inside known NL-prefix paths.
# See `is_path_shape_exempt` below for the authoritative list — broadly:
# `adapters/`, `principles/`, `patterns/`, `templates/`, `evals/`,
# `.github/`, `docs/`, the synced `~/.claude/` mirror, and well-known
# root prose files (README, CONTRIBUTING, LICENSE, etc.).
#
# Rationale: NL's own documentation legitimately (a) cites path-shapes
# in prose AND (b) discusses domain vocabulary terms repeatedly in the
# same file (e.g., a doc about Acceptance Scenarios says "Acceptance"
# many times). Maintaining an exhaustive vocabulary allowlist for every
# doc-domain term would not converge; the path-prefix exemption is the
# cleaner mechanism. Files OUTSIDE these prefixes (project-instance
# content, downstream consumer code, instance fixtures) face full
# scrutiny.
#
# Args: $1 = repo-relative path, $2 = absolute path
# Side-effects: appends matches to $MATCHES_TMP, increments $MATCH_COUNT
# Returns: 0 always (caller continues regardless).

# NL vocabulary allowlist for cluster detection. Tokens here will not
# trigger the cluster heuristic even if they appear 3+ times in a single
# file. Case-insensitive match. Add new tokens here if a legitimate term
# triggers false positives in practice (typically a JS/TS built-in or
# harness primitive that downstream consumer code uses heavily).
#
# Note: NL's own documentation files are exempted from cluster detection
# entirely via the path-prefix exemption in check_heuristics(); this
# allowlist is for the surviving scan surface (downstream consumer code,
# instance project files), where common JS/TS built-ins might still
# legitimately appear 3+ times.
NL_VOCAB_ALLOWLIST="Neural|Lace|Claude|Anthropic|Build|Doctrine|Generation|Pattern|Mechanism|Status|Mode|Plan|Phase|Hook|Agent|Skill|Decision|Discovery|Backlog|Promise|Object|Array|String|Boolean|Number|Function|Error|Component|Module|Project|Session|Source|Target|Update|Create|Action|Result|Verdict|Worker|Builder|Reviewer|Verifier|Method|Output|Input|Origin|Master|Branch|Commit"

# Returns 0 if the heuristic checks should be SKIPPED for this file
# (file lives inside an NL-prefix path where prose mentions of paths
# AND repeated domain vocabulary are legitimate). Returns 1 if the
# heuristic should run.
#
# Rationale: NL's harness repo is documentation-dense. A doc about
# "Acceptance Scenarios" mentions "Acceptance" 16 times; a rule about
# "Trust" mentions Trust dozens of times; a plan about kanban mentions
# "Kanban" repeatedly. Maintaining an exhaustive vocabulary allowlist
# would not converge. The path-prefix exemption is the cleaner mechanism:
# NL-internal directories are exempt; downstream consumer code (the
# scanner's actual target audience) faces full scrutiny.
is_path_shape_exempt() {
  local path="$1"
  case "$path" in
    # NL-internal harness directories — these legitimately cite paths
    # AND discuss domain vocabulary repeatedly in prose.
    adapters/*|adapters) return 0 ;;
    principles/*|principles) return 0 ;;
    patterns/*|patterns) return 0 ;;
    templates/*|templates) return 0 ;;
    evals/*|evals) return 0 ;;
    .github/*|.github) return 0 ;;
    docs/*|docs) return 0 ;;
    # Build Doctrine integration directories (added 2026-05-05 per
    # Tranche 0b migration). The doctrine layer's vocabulary (Tranche,
    # Engineering, Catalog, Curator, Adversarial, Findings, Mechanical,
    # Orchestrator, Architecture, etc.) is repetitive prose by design;
    # exempting these directories matches the same logic as exempting
    # adapters/ and principles/. Templates dir holds default content
    # that ships with NL and is part of the harness layer, not
    # project-instance content.
    build-doctrine/*|build-doctrine) return 0 ;;
    build-doctrine-templates/*|build-doctrine-templates) return 0 ;;
    build-doctrine-orchestrator/*|build-doctrine-orchestrator) return 0 ;;
    # Conversation-Tree UI module (NL's own product code under neural-lace/).
    # Its domain vocabulary (Dispatch, State, Context, Content, Node, Branch)
    # is repetitive BY DESIGN — the module is literally a tracker of the
    # Dispatch conversation-tree state, so the Layer-2 cluster heuristic
    # false-positives on every file. Structural path-prefix exemption per
    # harness-hygiene.md "How to add false-positive exemptions"; same logic
    # as adapters/ and build-doctrine/. (workstreams-ui, formerly
    # conversation-tree-ui — both exempted during the 2026-05-30 rename window.)
    neural-lace/workstreams-ui/*|neural-lace/workstreams-ui) return 0 ;;
    neural-lace/conversation-tree-ui/*|neural-lace/conversation-tree-ui) return 0 ;;
    # The synced `~/.claude/` mirror (when scanning that tree directly).
    *.claude/*|*/.claude/*) return 0 ;;
    # NL-root prose files (README, CONTRIBUTING, LICENSE, SETUP,
    # CODE_OF_CONDUCT, CHANGELOG) — these are documentation, not
    # project-instance content.
    # .gitattributes added 2026-07-06 (GAP-55): its explanatory comments
    # legitimately repeat platform terms (cluster-heuristic FP); the
    # Layer-1 denylist still scans it.
    README.md|README|CONTRIBUTING.md|LICENSE|LICENSE.md|SETUP.md|CODE_OF_CONDUCT.md|CHANGELOG.md|SECURITY.md|.gitattributes) return 0 ;;
    # `.pr-description.md` is a per-PR transient file consumed by
    # `gh pr create --body-file` (canonical convention per
    # `adapters/claude-code/git-hooks/pre-push-pr-template.sh`). It
    # naturally repeats PR-shape domain vocabulary (Template, Inline,
    # Check, Summary, Mechanism) and discusses paths inside the PR. Same
    # logic as the other root-level prose-file exemptions above.
    .pr-description.md) return 0 ;;
  esac
  return 1
}

check_heuristics() {
  local rel_path="$1"
  local abs_path="$2"

  # NL-prefix paths are exempt from BOTH heuristic sub-checks. NL prose
  # legitimately cites path-shapes AND discusses domain vocabulary
  # repeatedly. See the function-header comment for the full rationale.
  if is_path_shape_exempt "$rel_path"; then
    return 0
  fi

  # ---- (a) project-internal file-path shapes ----
  # Three high-signal path-shape regexes (POSIX ERE — no \d / \w):
  #   - app/api/v<digits>/<slug>/
  #   - src/components/<PascalCase>.tsx
  #   - supabase/migrations/<14-digit>_<slug>.sql
  local heur_pattern='(app/api/v[0-9]+/[a-zA-Z0-9_-]+/)|(src/components/[A-Z][a-zA-Z0-9_]+\.tsx)|(supabase/migrations/[0-9]{14}_[a-zA-Z0-9_-]+\.sql)'
  if heur_out=$(grep -EnIH "$heur_pattern" "$abs_path" 2>/dev/null); then
    while IFS= read -r match_line; do
      [ -z "$match_line" ] && continue
      rest="${match_line#$abs_path:}"
      lineno="${rest%%:*}"
      content="${rest#*:}"
      if [ "${#content}" -gt 120 ]; then
        content="${content:0:117}..."
      fi
      printf '[heuristic] %s\n' "$rel_path:$lineno: $content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$heur_out"
  fi

  # ---- (b) repeated capitalized-term clusters ----
  # Find tokens [A-Z][a-z]{4,15} appearing 3+ times in this file, where
  # NONE of the occurrences match the NL vocabulary allowlist (case-insensitive).
  # Strategy:
  #   1. Extract all [A-Z][a-z]{4,15} tokens from the file.
  #   2. Filter out allowlisted tokens (case-insensitive).
  #   3. Sort + uniq -c to count each remaining token.
  #   4. Keep tokens with count >= 3.
  #   5. For each, find the first line in the file where it appears and
  #      report it.
  local tokens
  tokens=$(grep -oE '[A-Z][a-z]{4,15}' "$abs_path" 2>/dev/null \
    | grep -ivE "^($NL_VOCAB_ALLOWLIST)$" \
    | sort \
    | uniq -c \
    | awk '$1 >= 3 { print $2 }')

  if [ -n "$tokens" ]; then
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      # Locate first occurrence of the token (use word-boundary-ish match).
      first_hit=$(grep -nE "\\b$tok\\b" "$abs_path" 2>/dev/null | head -n 1)
      [ -z "$first_hit" ] && continue
      lineno="${first_hit%%:*}"
      content="${first_hit#*:}"
      if [ "${#content}" -gt 120 ]; then
        content="${content:0:117}..."
      fi
      count=$(grep -oE "\\b$tok\\b" "$abs_path" 2>/dev/null | wc -l | tr -d ' ')
      printf '[heuristic] %s:%s: repeated term "%s" (x%s): %s\n' \
        "$rel_path" "$lineno" "$tok" "$count" "$content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$tokens"
  fi

  return 0
}

# ---------- Layer 3: no-addendum lint (REQ-B10, M-9-narrowed pattern) ----
#
# check_addendum_lint() — a THIRD detection layer, run per file alongside
# Layer 1 (denylist) and Layer 2 (heuristics). Enforces the no-addendum
# convention this design cycle (gated-pipeline-master-2026-08) itself
# establishes: corrections and follow-up review rounds get folded INTO a
# design/plan's body, never bolted on as a trailing "Addendum" / "Update:"
# section a reader has to cross-reference against the sections it amends.
#
# Two sub-patterns, DIFFERENT scope each (M-9 narrowing — the original
# unscoped pattern false-positived on legitimate review-round headings
# inside plans; corpus measured 2026-08-03: 5 heading-level "Round N" hits
# total, 3 of them legitimate review-round records inside non-archived
# plans, 2 in the one design this lint's golden case integrates):
#   (a) `Addendum` / `Update:` heading — docs/designs/** + docs/plans/**,
#       with docs/plans/archive/** EXCLUDED FROM SCOPE ENTIRELY (archives
#       are closed historical records; an archived addendum heading, e.g.
#       "## D.5 addendum" in nl-overhaul-program-2026-07-evidence.md, is a
#       coherent negative fixture, not lint bait).
#   (b) `Round [0-9]` heading — docs/designs/** ONLY. Review-round records
#       are established practice inside plans (e.g. "### Round 3 —
#       harness-reviewer REJECT…") and are NOT addenda — they document a
#       review pass, not a bolted-on correction. Designs don't have this
#       practice, so the pattern is safe to enforce there without a
#       measured false-positive class.
#
# Both patterns are markdown ATX headings only (`^#{1,6}[[:space:]]`), so
# body prose that merely mentions "an addendum" or "round 2 of testing"
# never fires — only a HEADING that opens an addendum/round section does.
# Both are case-insensitive (stated here, per REQ-B10; enforced via `-i`).
_hhs_in_designs() {
  case "$1" in
    docs/designs/*) return 0 ;;
  esac
  return 1
}

# Returns 0 if $1 is inside docs/plans/** EXCLUDING docs/plans/archive/**.
_hhs_in_plans_scoped() {
  case "$1" in
    docs/plans/archive/*) return 1 ;;
    docs/plans/*) return 0 ;;
  esac
  return 1
}

# Shared match-emitter for check_addendum_lint's sub-patterns (one helper
# so both sub-checks report identically and neither drifts). Labeled
# [addendum-lint] to match the [denylist]/[heuristic] label convention.
# Args: $1 = repo-relative path, $2 = absolute path, $3 = ERE pattern.
_hhs_addendum_scan() {
  local rel_path="$1" abs_path="$2" pattern="$3"
  local out
  if out=$(grep -EniIH "$pattern" "$abs_path" 2>/dev/null); then
    while IFS= read -r match_line; do
      [ -z "$match_line" ] && continue
      local rest lineno content
      rest="${match_line#$abs_path:}"
      lineno="${rest%%:*}"
      content="${rest#*:}"
      if [ "${#content}" -gt 120 ]; then
        content="${content:0:117}..."
      fi
      printf '[addendum-lint] %s\n' "$rel_path:$lineno: $content" >> "$MATCHES_TMP"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    done <<< "$out"
  fi
  return 0
}

# Args: $1 = repo-relative path, $2 = absolute path
# Side-effects: appends matches to $MATCHES_TMP, increments $MATCH_COUNT.
# Returns 0 always (caller continues regardless).
check_addendum_lint() {
  local rel_path="$1"
  local abs_path="$2"

  if _hhs_in_designs "$rel_path"; then
    _hhs_addendum_scan "$rel_path" "$abs_path" '^#{1,6}[[:space:]].*(Addendum|Update:)'
    _hhs_addendum_scan "$rel_path" "$abs_path" '^#{1,6}[[:space:]].*Round[[:space:]]+[0-9]'
  elif _hhs_in_plans_scoped "$rel_path"; then
    _hhs_addendum_scan "$rel_path" "$abs_path" '^#{1,6}[[:space:]].*(Addendum|Update:)'
  fi

  return 0
}

# ---------- Defect 1: staged-delta view (false-fire fix) -----------------
#
# _hhs_build_delta_view <rel_path> <abs_path> <out_path> [<rename_source>]
#
# Writes a "delta view" of <rel_path> to <out_path>: a file with the SAME
# line count as <abs_path>, where every line NOT added by the currently-
# staged diff is blank, and every line the diff DID add carries its real
# content at its real (new-file) line number. Layer 1/2/3 checks run
# against this view unchanged (same `grep -n` plumbing as scanning the
# real file), so a match can only fire on content THIS commit introduces
# — a file with no added lines at all (a pure deletion, or a rename with
# no content change) yields an all-blank view, correctly producing zero
# matches. Used only for MODE="staged" (the real pre-commit path and its
# `--check` sibling); `--full-tree` and explicit-file-arg invocations
# keep scanning the real file directly.
#
# RENAME HANDLING (C2 fix, harness-review 2026-08-04): the optional 4th
# arg, when non-empty, is the file's rename SOURCE path (from
# `_hhs_rename_source`). `git diff --cached -U0 -- <dest-only>` cannot pair
# a rename — pathspec-limited to just the destination, git shows a pure
# `git mv` as a brand-new file with EVERY line rendered as added, which
# would make a renamed file that already carried a hit block again on its
# ENTIRE content, reproducing the false-fire incident this fix exists to
# close. Passing BOTH the old and new pathspecs to `git diff` lets git pair
# the rename correctly: a pure rename (no content change) yields zero
# hunks (an all-blank view, correctly producing zero matches); a
# rename+edit yields only the truly-changed hunks.
#
# Known limitation, stated rather than hidden: a file with no trailing
# newline can make `wc -l` undercount by one; the `maxn` tracking below
# (driven off the diff's own hunk line numbers, not just `wc -l`) covers
# the common case of the LAST added line landing past that undercounted
# total, but this is not a byte-exact reconstruction — it is a
# line-number-preserving overlay, which is all Layer 1/2/3 need.
_hhs_build_delta_view() {
  local rel_path="$1" abs_path="$2" out="$3" rename_source="${4:-}"
  local total_lines
  total_lines=$(wc -l < "$abs_path" 2>/dev/null | tr -d ' ')
  [ -z "$total_lines" ] && total_lines=0
  local diff_cmd
  if [ -n "$rename_source" ]; then
    diff_cmd=(git -C "$REPO_ROOT" diff --cached -M -U0 --no-color -- "$rename_source" "$rel_path")
  else
    diff_cmd=(git -C "$REPO_ROOT" diff --cached -U0 --no-color -- "$rel_path")
  fi
  "${diff_cmd[@]}" 2>/dev/null | awk -v n="$total_lines" '
    /^@@/ {
      seen_hunk = 1
      match($0, /\+[0-9]+/)
      lineno = substr($0, RSTART+1, RLENGTH-1) + 0
      next
    }
    # The `+++ b/<path>` / `--- a/<path>` FILE HEADER lines appear ONCE,
    # BEFORE the first @@ hunk marker. Gating this on !seen_hunk (rather
    # than matching /^\+\+\+/ unconditionally, the pre-fix shape) is the
    # C3 fix: an ADDED line whose own CONTENT starts with "+" renders as
    # "+++<content>" in the diff (the diff'"'"'s own "+" prefix, plus a
    # content first-char of "+"), which the unconditional pattern used to
    # swallow as a false file-header match — silently dropping flagged
    # content on such lines from the delta view. After the first @@, a
    # "+++"-looking line is always real added content, never a header.
    !seen_hunk && /^\+\+\+/ { next }
    !seen_hunk && /^---/ { next }
    /^\+/ {
      buf[lineno] = substr($0, 2)
      if (lineno > maxn) maxn = lineno
      lineno++
      next
    }
    /^-/ { next }
    { next }
    END {
      total = (n > maxn) ? n : maxn
      for (i = 1; i <= total; i++) {
        print ((i in buf) ? buf[i] : "")
      }
    }
  ' > "$out"
}

# ---------- exemption check ----------------------------------------------

# Returns 0 if the path should be skipped, 1 otherwise.
is_exempt() {
  local path="$1"

  # The denylist file itself (matches would be infinite)
  case "$path" in
    adapters/claude-code/patterns/harness-denylist.txt) return 0 ;;
  esac

  # Harness-hygiene rule files and scanner internals — these files legitimately
  # name the forbidden patterns in order to document or enforce them. Scanning
  # them would be a self-match loop.
  case "$path" in
    principles/harness-hygiene.md) return 0 ;;
    adapters/claude-code/rules/harness-hygiene.md) return 0 ;;
    adapters/claude-code/doctrine/harness-hygiene-full.md) return 0 ;;
    principles/forward-compatibility.md) return 0 ;;
    adapters/claude-code/git-hooks/pre-commit) return 0 ;;
    adapters/claude-code/hooks/harness-hygiene-scan.sh) return 0 ;;
    adapters/claude-code/hooks/decisions-index-gate.sh) return 0 ;;
  esac

  # Machine-generated operator ledgers (exemption class added 2026-08-03,
  # gated-pipeline session; scoped harness-reviewer confirmation in
  # docs/reviews/ — see the T8 evidence trail). These files are churned by
  # generators (needs-you.sh / backlog regeneration) and accumulate
  # HISTORICAL ask/issue text that can name orgs or hosts; a commit that
  # merely TOUCHES them re-triggers matches on lines the committer did not
  # write and cannot scrub without falsifying the ledger (three occurrences
  # blocked this session: operator-todo checkbox flips, two backlog deltas).
  # The durable fix for the CONTENT belongs to the generators (nl-issues
  # filed 2026-08-03: needs-you/operator-todo writers should not embed org
  # names); exempting the LEDGERS keeps the gate honest at its real target —
  # hand-authored harness source and docs. NOT exempt: any other docs/ file.
  case "$path" in
    docs/backlog.md) return 0 ;;
    docs/operator-todo.md) return 0 ;;
  esac

  # SECRET-SCAN-CI-BACKSTOP-01 fixture files. These deliberately contain
  # AWS's own public documentation placeholder access-key ID
  # (AKIAIOSFODNN7EXAMPLE — never a live credential) so the CI-backstop
  # oracle can be proven locally against a real flagless-shape pattern
  # match, matching pre-push-scan.sh's AKIA[0-9A-Z]{16} regex by design.
  # Same class as sensitive-patterns.local.example (hooks/pre-push-scan.sh
  # header) — a fixture that intentionally names the pattern it tests.
  case "$path" in
    adapters/claude-code/tests/secret-backstop-fixture-check.sh) return 0 ;;
    # Plan archived on closure (2026-07-12) — exemption follows the file;
    # pre-archive path kept for historical-blob rescans.
    docs/plans/secret-scan-ci-backstop-skip.md) return 0 ;;
    docs/plans/archive/secret-scan-ci-backstop-skip.md) return 0 ;;
  esac

  # Instance-specific operations tooling exemptions.
  #
  # These files are intentionally named after the specific downstream product
  # they monitor. They live in neural-lace per the operator's placement
  # directive (orchestrator integration via the generic external-monitor
  # SessionStart surfacer requires the probe + runbook + plan to be
  # co-located with the harness mirror). They are NOT generic harness-kit
  # files; they ARE operations tooling for one specific deployment.
  #
  # The surfacer hook itself (`external-monitor-alert-surfacer.sh`) is generic
  # by design and does NOT need exemption — it reads alerts from any
  # configured directory.
  case "$path" in
    tools/circuit-health-probe.sh) return 0 ;;
    docs/operations/circuit-health-monitor-*.md) return 0 ;;
    docs/plans/circuit-prod-health-monitor.md) return 0 ;;
    docs/plans/archive/circuit-prod-health-monitor.md) return 0 ;;
  esac

  # Workstreams UI (formerly conversation-tree-ui) web client — the operator's
  # own machine-state tracker GUI, co-located with the harness under the same
  # placement directive as the circuit-* operations tooling above. Its
  # repo-grouping block DERIVES the Repo -> Project tree from the operator's
  # REAL git remotes on THIS machine (PROJECT_REPO_DEFAULT / PROJECT_REPOS_MULTI
  # / REPO_ORDER), so it legitimately names the operator's accounts + repos —
  # that mapping IS the feature, and it is overridable per-machine via the
  # served `S.repoMap` or a node's own `.repo` field. NOT a generic harness-kit
  # surface; instance-specific operator tooling, exactly the category the
  # circuit-* exemptions cover. Layer-2 heuristics (path-shape / capitalized-
  # cluster detection) STILL scan these files for NEW leak shapes — only the
  # literal operator-identifier denylist is exempted for this subtree.
  case "$path" in
    neural-lace/workstreams-ui/web/*) return 0 ;;
    neural-lace/conversation-tree-ui/web/*) return 0 ;;
    # scripts/ extension (2026-07-06, GAP-55 sweep, operator triage rubric):
    # the seed/backfill scripts under scripts/ name the operator's projects
    # for the same reason web/ does — the Repo -> Project mapping IS the
    # feature. Same subtree, same class, same Layer-2-still-scans posture.
    neural-lace/workstreams-ui/scripts/*) return 0 ;;
    neural-lace/conversation-tree-ui/scripts/*) return 0 ;;
  esac

  # Public-by-design repo-architecture documentation (operator directive
  # 2026-07-06, GAP-55 triage rubric: benign -> exempt with provenance note;
  # genuinely-private -> redact, which was done separately in the same
  # commit). These specific committed docs DOCUMENT this repo's own
  # two-remote architecture, PR trail, and machine estate — the org/account
  # names and downstream-product references ARE their subject matter, and
  # the operator ruled the mirror public by design (docs/backlog.md
  # HARNESS-GAP-55). File-by-file on purpose: NEW docs are NOT exempt and
  # face the full denylist. The two synthetic-ci entries carry their
  # archive/ twins so plan-lifecycle archiving does not un-exempt them.
  case "$path" in
    docs/discoveries/2026-05-27-neural-lace-fork-deep-dive-and-sync-strategy.md) return 0 ;;
    docs/discoveries/2026-05-30-conv-tree-work-first-reframe-design.md) return 0 ;;
    docs/discoveries/2026-06-02-pt-personal-fork-reconcile-and-adr-renumber.md) return 0 ;;
    docs/discoveries/2026-06-03-workstreams-tree-design-misread-and-repo-tier.md) return 0 ;;
    docs/decisions/039-conv-tree-reconciliation-over-interception.md) return 0 ;;
    docs/plans/archive/ci-server-side-enforcement-2026-05-23.md) return 0 ;;
    docs/plans/archive/git-bestpractices-9-item-initiative-2026-05-29.md) return 0 ;;
    docs/plans/archive/neural-lace-mirror-automation-evidence.md) return 0 ;;
    docs/plans/archive/scope-gate-rebase-exemption.md) return 0 ;;
    docs/plans/archive/windows-scope-gate-drive-letter-fix.md) return 0 ;;
    docs/plans/archive/workstreams-phase-1-2.md) return 0 ;;
    docs/plans/archive/workstreams-phase-3.md) return 0 ;;
    docs/plans/archive/worktree-spawn-primitive.md) return 0 ;;
    docs/plans/archive/workstreams-ui-status-surface-redesign-2026-06-11-evidence/tasks-10-11.evidence.md) return 0 ;;
    docs/plans/nl-overhaul-synthetic-ci-2026-07.md) return 0 ;;
    docs/plans/nl-overhaul-synthetic-ci-2026-07-evidence.md) return 0 ;;
    docs/plans/archive/nl-overhaul-synthetic-ci-2026-07.md) return 0 ;;
    docs/plans/archive/nl-overhaul-synthetic-ci-2026-07-evidence.md) return 0 ;;
  esac

  # Directory-prefix exemptions
  #
  # NOTE: docs/plans/ is NOT exempt. Neural Lace now commits its own
  # development plans (not downstream-project plans), so plan files
  # are subject to the same hygiene checks as any other committed file.
  #
  # decisions/reviews/sessions: directory-level exempt ONLY for paths
  # that are NOT allow-listed by .gitignore. Allow-listed paths are:
  #   - docs/decisions/NNN-*.md  (3-digit prefix)
  #   - docs/reviews/YYYY-MM-DD-*.md
  #   - docs/sessions/YYYY-MM-DD-*.md
  # Allow-listed files ship in the harness repo and must pass hygiene.
  # Non-allow-listed paths (instance artifacts, drafts) remain exempt.
  case "$path" in
    docs/decisions/[0-9][0-9][0-9]-*.md) ;; # NOT exempt — fall through
    docs/reviews/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;; # NOT exempt
    docs/sessions/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;; # NOT exempt
    docs/decisions/*|docs/decisions) return 0 ;;
    docs/reviews/*|docs/reviews|docs/sessions/*|docs/sessions) return 0 ;;
  esac

  case "$path" in
    SCRATCHPAD.md|*/SCRATCHPAD.md) return 0 ;;
  esac

  # Filename-suffix exemptions (example/placeholder files)
  case "$path" in
    *.example|*.example.json|*.example.sh|*.example.txt|*.example.md) return 0 ;;
  esac

  return 1
}

# ---------- scan each file -----------------------------------------------
# (file list already assembled by the cheap relevance pre-filter above —
# MODE / FILE_LIST_TMP are set there)

MATCH_COUNT=0
DENYLIST_MATCH_COUNT=0
OTHER_MATCH_COUNT=0
WAIVED_COUNT=0
WARN_COUNT=0
MATCHES_TMP=$(mktemp)
WARN_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$HHS_RENAME_MAP_TMP" "$MATCHES_TMP" "$WARN_TMP"' EXIT

# Structured-waiver files (F.5 audit row 12 / ADR 059 D4). Computed once per
# run; state dir resolves relative to REPO_ROOT so pre-commit invocations
# (which run with cwd=REPO_ROOT) and the self-test's own tmp repos agree.
HHS_STATE_DIR="${CLAUDE_STATE_DIR:-$REPO_ROOT/.claude/state}"
HHS_WAIVED_FILES_TMP=$(mktemp)
HHS_OPERATOR_WAIVED_FILES_TMP=$(mktemp)
trap 'rm -f "$PATTERNS_TMP" "$FILE_LIST_TMP" "$HHS_RENAME_MAP_TMP" "$MATCHES_TMP" "$WARN_TMP" "$HHS_WAIVED_FILES_TMP" "$HHS_OPERATOR_WAIVED_FILES_TMP"' EXIT
_hhs_waived_files "$HHS_STATE_DIR" > "$HHS_WAIVED_FILES_TMP" 2>/dev/null || true
_hhs_operator_waived_files "$HHS_STATE_DIR" > "$HHS_OPERATOR_WAIVED_FILES_TMP" 2>/dev/null || true

_hhs_is_waived() {
  local path="$1"
  [ -s "$HHS_WAIVED_FILES_TMP" ] || return 1
  grep -qFx "$path" "$HHS_WAIVED_FILES_TMP" 2>/dev/null
}

_hhs_is_operator_waived() {
  local path="$1"
  [ -s "$HHS_OPERATOR_WAIVED_FILES_TMP" ] || return 1
  grep -qFx "$path" "$HHS_OPERATOR_WAIVED_FILES_TMP" 2>/dev/null
}

# Read the null-delimited file list.
while IFS= read -r -d '' rel_path; do
  [ -z "$rel_path" ] && continue

  # Resolve to absolute path for reading
  if [ "${rel_path:0:1}" = "/" ]; then
    abs_path="$rel_path"
    # For exemption check, try to make it relative to REPO_ROOT
    case "$abs_path" in
      "$REPO_ROOT"/*) check_path="${abs_path#$REPO_ROOT/}" ;;
      *) check_path="$abs_path" ;;
    esac
  else
    abs_path="$REPO_ROOT/$rel_path"
    check_path="$rel_path"
  fi

  # Skip missing files (e.g., deleted from working tree but staged before amend)
  [ -f "$abs_path" ] || continue

  # Skip exempt paths
  if is_exempt "$check_path"; then
    continue
  fi

  regular_waived=0
  operator_waived=0
  _hhs_is_waived "$check_path" && regular_waived=1
  _hhs_is_operator_waived "$check_path" && operator_waived=1

  # Defect 1: for MODE="staged" (the real pre-commit path and its --check
  # sibling), build a delta view and scan THAT for the block decision.
  # --full-tree and explicit-file-arg invocations keep scanning the real
  # file directly (scan_target == abs_path).
  scan_target="$abs_path"
  is_delta_scoped=0
  DELTA_VIEW_TMP=""
  if [ "$MODE" = "staged" ]; then
    is_delta_scoped=1
    DELTA_VIEW_TMP=$(mktemp)
    rename_source=""
    rename_source=$(_hhs_rename_source "$check_path" 2>/dev/null || true)
    _hhs_build_delta_view "$check_path" "$abs_path" "$DELTA_VIEW_TMP" "$rename_source"
    scan_target="$DELTA_VIEW_TMP"
  fi

  file_match_count_before=$MATCH_COUNT
  layer1_waiver_logged=0

  # ---- Layer 1: denylist scan (delta-scoped target) ----
  # A denylist match is the SECURITY class (Defect 2): the plain
  # self-service waiver (regular_waived) NEVER suppresses it — only an
  # operator-authorized waiver (operator_waived) can. Run grep with:
  #   -i case-insensitive  -E extended regex  -n line numbers
  #   -I skip binary files -H always print filename -f patterns from file
  if grep_out=$(grep -iEnIHf "$PATTERNS_TMP" "$scan_target" 2>/dev/null); then
    if [ "$operator_waived" -eq 1 ]; then
      WAIVED_COUNT=$((WAIVED_COUNT + 1))
      layer1_waiver_logged=1
      command -v ledger_emit >/dev/null 2>&1 && ledger_emit "harness-hygiene-scan" "waiver" "file=$check_path"
      declare -F ws_record >/dev/null 2>&1 && ws_record "harness-hygiene-scan" "operator-waiver-file" "file=$check_path"
      printf '[harness-hygiene-scan] NOTICE: operator-authorized waiver used for a DENYLIST match on %s.\n      This opened (or refreshed) a same-session escape obligation (Defect 4) —\n      the next DONE/CONTINUING terminal marker must name "harness-hygiene-scan"\n      (or the underlying content must actually be fixed / operator-\n      acknowledged) or Stop will block. See stop-verdict-dispatcher.sh /\n      lib/workaround-sensor-lib.sh ws_open_escape_obligations.\n' "$check_path" >&2
    else
      while IFS= read -r match_line; do
        [ -z "$match_line" ] && continue
        rest="${match_line#$scan_target:}"
        lineno="${rest%%:*}"
        content="${rest#*:}"
        if [ "${#content}" -gt 120 ]; then
          content="${content:0:117}..."
        fi
        printf '[denylist] %s\n' "$check_path:$lineno: $content" >> "$MATCHES_TMP"
        MATCH_COUNT=$((MATCH_COUNT + 1))
        DENYLIST_MATCH_COUNT=$((DENYLIST_MATCH_COUNT + 1))
      done <<< "$grep_out"
    fi
  fi

  # ---- Layer 2 + 3: heuristic / addendum-lint (delta-scoped target) ----
  # Suppressible by EITHER the plain self-service waiver or the operator
  # waiver — these are the classes where the existing self-service hatch
  # is proportionate (genuine novel-content false positives). Guards
  # against double-logging a file Layer 1 already logged above
  # (layer1_waiver_logged) — an operator-waived file with BOTH a denylist
  # AND a heuristic match must only open/refresh ONE escape obligation.
  if [ "$regular_waived" -eq 1 ]; then
    WAIVED_COUNT=$((WAIVED_COUNT + 1))
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "harness-hygiene-scan" "waiver" "file=$check_path"
    declare -F ws_record >/dev/null 2>&1 && ws_record "harness-hygiene-scan" "waiver-file" "file=$check_path"
    printf '[harness-hygiene-scan] NOTICE: self-service waiver used for %s.\n      This opened (or refreshed) a same-session escape obligation (Defect 4) —\n      the next DONE/CONTINUING terminal marker must name "harness-hygiene-scan"\n      (or the underlying content must actually be fixed / operator-\n      acknowledged) or Stop will block.\n' "$check_path" >&2
  elif [ "$operator_waived" -eq 1 ] && [ "$layer1_waiver_logged" -ne 1 ]; then
    WAIVED_COUNT=$((WAIVED_COUNT + 1))
    command -v ledger_emit >/dev/null 2>&1 && ledger_emit "harness-hygiene-scan" "waiver" "file=$check_path"
    declare -F ws_record >/dev/null 2>&1 && ws_record "harness-hygiene-scan" "operator-waiver-file" "file=$check_path"
    printf '[harness-hygiene-scan] NOTICE: operator-authorized waiver used for %s.\n      This opened (or refreshed) a same-session escape obligation (Defect 4).\n' "$check_path" >&2
  elif [ "$operator_waived" -eq 1 ]; then
    :  # already logged once above (layer1_waiver_logged) — no second event
  else
    other_before=$MATCH_COUNT
    check_heuristics "$check_path" "$scan_target"
    check_addendum_lint "$check_path" "$scan_target"
    OTHER_MATCH_COUNT=$((OTHER_MATCH_COUNT + (MATCH_COUNT - other_before)))
  fi

  # ---- Whole-file WARN (Defect 1, delta-scoped mode only) ----
  # If this file's delta contributed NO Layer-1 match but the WHOLE FILE
  # on disk still has one, pre-existing hygiene debt exists that this
  # commit does not touch. Not blocking here — but PROVEN not silently
  # absorbed elsewhere either (C1 fix, harness-review 2026-08-04): the two
  # push-time CI checks that go RED (NOT branch-protection-required; .github/workflows/secret-backstop.yml,
  # .github/workflows/server-side-enforcement.yml) scan every changed
  # file's WHOLE CONTENT on every push with no waiver channel, so this
  # exact debt goes RED at push time the next time the file is touched at
  # all. Scoped to Layer 1 only (the security-relevant class this defect
  # is about) — stated rather than silently generalized.
  if [ "$is_delta_scoped" -eq 1 ] && [ "$operator_waived" -ne 1 ] \
     && [ "$MATCH_COUNT" -eq "$file_match_count_before" ]; then
    if grep -qiEf "$PATTERNS_TMP" "$abs_path" 2>/dev/null; then
      printf 'PRE-EXISTING hygiene match in %s not touched by this change (not blocking) -- run --full-tree to review.\n' "$check_path" >> "$WARN_TMP"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  fi

  [ -n "$DELTA_VIEW_TMP" ] && rm -f "$DELTA_VIEW_TMP"
done < "$FILE_LIST_TMP"

# ---------- pre-existing-content notice (Defect 1, non-blocking) ---------
if [ "$WARN_COUNT" -gt 0 ]; then
  {
    echo ""
    echo "---- harness-hygiene-scan: pre-existing content notice (non-blocking) ----"
    cat "$WARN_TMP"
    echo "(Not blocking here: the staged delta for the file(s) above does not"
    echo " touch the flagged line(s). This is NOT the end of it, though --"
    echo " push-time CI (.github/workflows/secret-backstop.yml and"
    echo " server-side-enforcement.yml, run per push/PR and go RED — not branch-protection-required — both WHOLE-FILE,"
    echo " with NO waiver channel) will re-scan this file's full content on"
    echo " the next push that touches it at all, and will go RED. Fix it now:"
    echo " remove/scrub the flagged content, or -- if it is a known-legitimate"
    echo " durable case -- add the file to is_exempt() in this script, staged"
    echo " in the SAME commit as the change that would otherwise trip CI."
    echo " ('bash adapters/claude-code/hooks/harness-hygiene-scan.sh"
    echo " --full-tree' remains available for an operator-run, on-demand,"
    echo " whole-repo audit -- it is not scheduled or automatic.)"
    echo "----------------------------------------------------------------------"
  } >&2
fi

# ---------- report (R3.4 Gate Philosophy Law — one shared emitter) -------
#
# _hhs_print_report — the ONE structured-message emitter, called by BOTH
# the enforce path and --check with the same MATCHES_TMP/MATCH_COUNT
# computed by the identical scan loop above. Fields: WHAT / WHY / FIX /
# ESCAPE (doctor-lintable). The ESCAPE field's CONTENT branches on whether
# any [denylist] (Layer 1 / security-class) match is present (Defect 2):
# a denylist-only or mixed batch gets the operator-escalation text, which
# points at this script's own header + function comments as the marker
# spec rather than printing ANY runnable mkdir/printf recipe (C6 fix,
# harness-review 2026-08-04 — the first shipped version of this branch
# removed the OLD self-service recipe but printed an equally-copy-pasteable
# NEW one for the operator-waiver marker, which was the same defect wearing
# an extra field; pinned by the SEC1 self-test scenario's `mkdir -p` /
# `harness-hygiene-operator-waiver-$(date` absence checks). A heuristic/
# addendum-lint-only batch keeps the original copy-pasteable waiver recipe
# unchanged — that class remains genuinely self-service by design.

if [ "$MATCH_COUNT" -eq 0 ]; then
  if [ "$CHECK_MODE" -eq 1 ]; then
    echo "[harness-hygiene-scan --check] would-pass (0 matches)" >&2
  fi
  exit 0
fi

_hhs_print_report() {
  local check_mode="$1"
  local header
  if [ "$MODE" = "full-tree" ]; then
    header="HARNESS HYGIENE SCAN — FULL TREE — $MATCH_COUNT MATCHES"
  elif [ "$check_mode" -eq 1 ]; then
    header="HARNESS HYGIENE SCAN — [--check] WOULD BLOCK — $MATCH_COUNT MATCHES"
  else
    header="HARNESS HYGIENE SCAN — BLOCKED"
  fi

  {
    echo ""
    echo "================================================================"
    echo "$header"
    echo "================================================================"
    echo ""
    echo "WHAT: The following content matches patterns in the harness denylist"
    echo "      (or the project-shape/repeated-term heuristics, or the"
    echo "      no-addendum/no-round-heading lint — REQ-B10):"
    echo ""
    cat "$MATCHES_TMP"
    echo ""
    echo "WHY:  Harness repos must not ship personal, business, or identity-"
    echo "      bearing strings. This scan is the last-line mechanical"
    echo "      enforcement for the harness-hygiene principle."
    echo ""
    echo "FIX:  Fix the content, or — if the match is legitimate and durable —"
    echo "      add the file to is_exempt() in this scanner (with a comment"
    echo "      naming the exemption class) and stage both in the same commit."
    echo "      [addendum-lint] hits: fold the addendum/round section INTO the"
    echo "      body at the place it corrects, then delete the heading — see"
    echo "      REQ-B10 / docs/plans/gated-pipeline-master-2026-08.md Task 19."
    echo ""
    if [ "$DENYLIST_MATCH_COUNT" -gt 0 ]; then
      echo "ESCAPE: at least one match above is [denylist] — the SECURITY CLASS"
      echo "      (personal/business/identity-bearing strings). This class is"
      echo "      NOT SELF-WAIVABLE by an agent, ever. Stop and escalate to the"
      echo "      operator IN THIS CONVERSATION:"
      echo "        1. Quote the matched [denylist] line(s) above verbatim."
      echo "        2. Ask: is this content safe to ship, or must it be removed?"
      echo "        3. ONLY IF the operator explicitly authorizes it in chat, an"
      echo "           operator-authorized marker MAY suppress it — but this"
      echo "           message deliberately does NOT hand you a fill-in-the-"
      echo "           blank command for it (C6 fix, harness-review 2026-08-04:"
      echo "           the prior version DID, which just made the recipe fancier"
      echo "           rather than actually removing it). Read this script's own"
      echo "           header ('DEFECT 2' section) and the"
      echo "           _hhs_operator_waived_files / _hhs_operator_clause_ok"
      echo "           function comments a few hundred lines below it, in"
      echo "           adapters/claude-code/hooks/harness-hygiene-scan.sh, for"
      echo "           the exact required marker filename pattern and fields —"
      echo "           that IS the spec; nothing here restates it as a runnable"
      echo "           command."
      echo "      HONEST TRUST MODEL: nothing above is a structural barrier — an"
      echo "      agent's own Bash/Write tools CAN still author that marker"
      echo "      without any operator turn ever happening (same disclosure"
      echo "      this repo's review-record-push-gate manifest entry already"
      echo "      makes about its own override marker). NOT printing a copy-"
      echo "      paste recipe here does not change that — it only removes the"
      echo "      zero-effort path. The distinct filename, the extra"
      echo "      Operator-Authorized clause, and same-session ledger surfacing"
      echo "      (session-start-digest.sh's bypass-24h feed, plus a same-session"
      echo "      Stop-time obligation naming this gate) raise the COST and AUDIT"
      echo "      LEGIBILITY of self-issuance; they do NOT make it unforgeable."
      echo "      Self-issuing this marker without operator say-so IN THIS"
      echo "      CONVERSATION is a harness-hygiene violation in its own right."
      if [ "$OTHER_MATCH_COUNT" -gt 0 ]; then
        echo ""
        echo "      For the NON-denylist ([heuristic]/[addendum-lint]) match(es)"
        echo "      in the SAME batch above, the standard self-service waiver"
        echo "      still applies — see below."
      fi
      echo ""
    fi
    if [ "$OTHER_MATCH_COUNT" -gt 0 ]; then
      [ "$DENYLIST_MATCH_COUNT" -eq 0 ] && echo "ESCAPE: a fresh (<1h), per-file, ledger-logged structured waiver —"
      [ "$DENYLIST_MATCH_COUNT" -gt 0 ] && echo "      (self-service waiver for the non-denylist matches above):"
      echo "      suppresses matches on ONLY the named file(s), this run, NEVER"
      echo "      a blanket suppression of the whole scan. Cost: the waiver ages"
      echo "      out in 1h, is logged to the signal ledger, and still requires"
      echo "      naming BOTH purpose clauses honestly (a false clause is a"
      echo "      harness-hygiene violation in its own right). Use only for a"
      echo "      genuine NOVEL false-positive, not a known-legitimate file"
      echo "      (those get the durable is_exempt() remedy above instead):"
      echo "        mkdir -p $HHS_STATE_DIR && \\"
      echo "        { printf 'Purpose: this gate exists to prevent <X>\\n'; \\"
      echo "          printf 'Because: <Y>\\n'; \\"
      echo "          printf 'Files: <repo-relative-path> [<repo-relative-path> ...]\\n'; \\"
      echo "        } > $HHS_STATE_DIR/harness-hygiene-waiver-\$(date +%s).txt"
      echo "      Re-run the commit after writing the waiver. (git commit"
      echo "      --no-verify skips only the git-native hook layer, cannot"
      echo "      bypass this scan's PreToolUse wiring, and is prohibited"
      echo "      without operator say-so — constitution §7.)"
      echo ""
    fi
    echo "Denylist: adapters/claude-code/patterns/harness-denylist.txt"
    echo "Rule: principles/harness-hygiene.md"
    echo "This gate: ~/.claude/hooks/harness-hygiene-scan.sh (source: adapters/claude-code/hooks/harness-hygiene-scan.sh)"
    if [ "$check_mode" -eq 1 ]; then
      echo "[--check mode: advisory only, no side effects — re-run without"
      echo " --check to see this enforced for real at commit time]"
    fi
    echo "================================================================"
  } >&2
}

_hhs_print_report "$CHECK_MODE"

exit 1
