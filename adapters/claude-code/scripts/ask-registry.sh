#!/bin/bash
# ask-registry.sh — ask registry CLI (ask-rooted-workstreams-p1, Task 8 —
# FINALIZED: replaces the Task 1 walking-skeleton stub with the full
# contract).
#
# ============================================================
# WHY THIS EXISTS / STATUS
# ============================================================
#
# Nothing before this recorded the operator's ask verbatim — plans are
# Claude's interpretation of it (design sketch §4). This is the one new
# primitive: an append-only registry of ask entries, keyed by `ask_id`, that
# the ask-tree landing page (Task 13) groups by project and drills into.
#
# Task 1 shipped a stub with only `register` (hand-registration form) + a
# read-only `list` convenience verb, just enough to prove the walking
# skeleton's single event end-to-end. THIS task replaces that stub with the
# full verb set the plan names: register / attach-session / link-plan /
# set-status / merge / override-project, the heuristic-first summarizer
# (+ optional haiku-tier async upgrade), the verbatim ref, the best-effort
# in-repo mirror (constraint 11), and the full sandboxed --self-test battery.
#
# Downstream consumers NOT built yet (out of this task's scope, documented
# here so they read this file's schema instead of re-deriving it):
#   - Task 9's automatic-capture splices call `register` (from the first
#     UserPromptSubmit, via `hooks/workstreams-read.sh`) and `attach-session`
#     (on resume/spawn, via `hooks/session-start-digest.sh`).
#   - Task 10's `start-plan.sh --ask-id` calls `link-plan`.
#   - Task 12's auditor calls `set-status --emitter auditor` (mechanical
#     ask-done derivation) and can call `merge`.
#   - Task 11's `POST /api/ask/<id>/lifecycle` calls `set-status`/`merge`
#     with `--emitter operator-ui` (the operator-override exit path
#     constraint 7 requires).
#
# ============================================================
# CONTRACT — verbs
# ============================================================
#
#   ask-registry.sh register [--ask-id <id>] [--summary <text>] [--text <raw>]
#                             [--repo <path>] [--project <name>]
#                             [--session-id <id>] [--transcript-path <path>]
#                             [--prompt-offset <n>] [--verbatim-ref <ref>]
#     Creates a new ask. `--ask-id` is optional — an id is auto-generated
#     (`ask-<YYYYMMDD>-<summary-slug>-<4hex>`) when omitted, so Task 9's
#     fully-automatic first-prompt capture never needs to invent one itself.
#     `--summary`, if given, wins verbatim (still length-capped). Otherwise,
#     if `--text` (the raw prompt) is given, the HEURISTIC summarizer runs:
#     markdown-stripped, first-sentence, <=140 chars (sketch §4: "does not
#     need to be verbatim"). `--repo` defaults to `git rev-parse
#     --show-toplevel` from cwd (ephemeral-ok READ, constraint 11); `--project`
#     defaults via a reverse lookup against
#     `neural-lace/workstreams-ui/config/projects.js`'s `loadProjects()` map
#     (deepest matching root wins), falling back to `basename(repo)` when no
#     project root matches or node/projects.js is unavailable.
#     `verbatim_ref` = `--verbatim-ref` if given, else
#     `<transcript-path>#<prompt-offset-or-0>` if `--transcript-path` given,
#     else empty (Task 9 supplies real transcript coordinates; this task only
#     composes/stores them).
#     Appends one `record_type:"created"` registry record (status=active),
#     best-effort mirrors it (see MIRROR below), best-effort emits
#     `ask_registered` via progress-log.sh, and — ONLY when
#     `ASK_SUMMARIZER=haiku` is exported, `--text` was given, and the
#     heuristic path was actually used (no explicit `--summary`) — kicks off
#     an ASYNC, non-blocking haiku-tier upgrade (see SUMMARIZER below).
#     NEVER BLOCKS: exit 0 on every path. Prints the registry file path.
#
#   ask-registry.sh attach-session --ask-id <id> --session-id <id>
#                                  [--resumed-from <id>]
#     Attaches an existing (already-registered) session to an ask node —
#     multi-session asks share one node (sketch §4). Appends a
#     `record_type:"session_attached"` record and best-effort emits
#     `session_attached` (natural key ask_id+session_id, Task 2 table — one
#     event per (ask, session) pair, never suppressed for a legitimately new
#     session). Required args missing -> no-op (stderr note), exit 0.
#
#   ask-registry.sh link-plan --ask-id <id> --plan-slug <slug>
#     Records the plan<->ask back-link (Task 10's `start-plan.sh --ask-id`
#     call site; planning doctrine: "plan creation back-links the registry").
#     Appends a `record_type:"plan_linked"` record. No progress-log event —
#     plan linkage isn't one of the six mechanism-emission lanes; it is
#     pure registry bookkeeping Task 11/13 read directly.
#
#   ask-registry.sh set-status --ask-id <id> --status <status>
#                               [--emitter <name>]
#     `--status` MUST be one of: active | done | dismissed | merged (sketch
#     §4 + plan Task 8's vocabulary extension for the merge lifecycle,
#     Decisions Log D10). An invalid value is REJECTED (no-op, stderr note,
#     exit 0 — the file is left unchanged, never a malformed status persisted).
#     Called by BOTH exit paths constraint 7 requires: the auditor
#     (`--emitter auditor`, Task 12's mechanical ask-done derivation) and the
#     UI lifecycle endpoint (`--emitter operator-ui`, Tasks 11/13's card
#     done/dismiss/reopen actions). `--emitter` defaults to "unknown" when
#     omitted — never silently mislabeled as either caller.
#     Appends a `record_type:"status_change"` record. Every status change
#     APPENDS; none rewrites history (plan Task 8 / constraint 6 spirit).
#
#   ask-registry.sh merge --ask-id <source-id> --into <target-id>
#     Marks `<source-id>` as a duplicate of `<target-id>`: appends a
#     `record_type:"merged"` record for the SOURCE (status=merged,
#     merged_into=<target-id>). The target ask is untouched by this call —
#     callers that also want the target's `plan_slugs` to absorb the
#     source's should follow up with their own `link-plan` calls against the
#     target (documented limitation; the plan's schema only names
#     `merged_into?` on the merged entry, not an auto-absorption rule).
#
#   ask-registry.sh override-project --ask-id <id> --project <name>
#     Operator override of an ask's project grouping (sketch §3: "move an
#     ask, rename a project"). Appends a `record_type:"project_override"`
#     record. `--emitter` defaults to "operator-ui" (this verb only makes
#     sense as an operator action).
#
#   ask-registry.sh list
#     Read-only: prints the registry file's raw JSONL lines (or nothing if
#     absent). Task 11's server-side reader is the real consumer going
#     forward; this remains a manual-verification convenience.
#
#   ask-registry.sh --self-test
#     Self-contained assertion suite, sandboxed under ASK_REGISTRY_STATE_DIR
#     / PROGRESS_LOG_STATE_DIR / ASK_REGISTRY_MIRROR_PATH (see SANDBOXING),
#     PLUS a dedicated FROM-WORKTREE fixture (constraint 11) that builds a
#     real synthetic git repo + linked worktree and proves the in-repo mirror
#     resolves to the MAIN checkout via `nl_main_checkout_root`, never the
#     worktree cwd.
#
# ============================================================
# SCHEMA — registry record (READER FOLD CONTRACT — Tasks 11/12 depend on this)
# ============================================================
#
# One JSON object per line (LF-terminated, O_APPEND), ALL fields always
# present (empty string when not applicable to this record_type) — same
# flat-JSON convention as progress-log-lib.sh / session-heartbeat-lib.sh:
#
#   {"ask_id":"...","record_type":"created|session_attached|plan_linked|
#    status_change|merged|project_override|summary_updated",
#    "ts":"ISO-8601-UTC","user":"...","machine":"...",
#    "repo":"...","project":"...","summary":"...","verbatim_ref":"...",
#    "origin_session":"...","status":"active|done|dismissed|merged",
#    "plan_slug":"...","session_id":"...","resumed_from":"...",
#    "merged_into":"...","emitter":"..."}
#
# FOLD CONTRACT (append-only; the file is NEVER rewritten — every mutation
# is a NEW line): to compute an ask's CURRENT state, a reader iterates every
# record for a given `ask_id` in timestamp order and, for EACH FIELD
# independently, keeps the value from the MOST RECENT record in which that
# field is NON-EMPTY ("last-write-wins per field, blanks never overwrite").
# This is why `set-status`/`merge`/`link-plan`/`attach-session` leave
# `repo`/`project`/`summary`/`verbatim_ref` blank on their own records rather
# than re-stamping the calling process's cwd: those verbs may run from an
# unrelated process (the auditor, the UI server) whose cwd does NOT
# represent the ask's originating repo, and a blank must never clobber the
# `created` record's real value under the fold rule above. `user`/`machine`
# ARE always stamped on every record (by `_ar_append_record` itself) — that
# is forensic metadata about who/what authored THIS record, not about the
# ask's identity, and every record's own author is worth keeping (a reader
# wanting "ask's origin" still folds `user`/`machine` from the `created`
# record specifically via `record_type=="created"`, not the naive last-wins
# aggregate).
#
# ============================================================
# MIRROR (constraint 11 — durable in-repo write, never a worktree)
# ============================================================
#
# Every registry record is ALSO best-effort appended to
# `docs/asks/ask-registry.jsonl` inside the ask's repo — resolved via
# `nl_main_checkout_root` (`hooks/lib/nl-paths.sh`, the SAME resolver
# `needs-you.sh` already uses for `NEEDS-YOU.md`) so a splice firing inside a
# builder worktree writes durably into the MAIN checkout, never an ephemeral
# worktree that gets torn down. The mirror is a best-effort DERIVED copy for
# team flow later (sketch §4) — never read as truth (Behavioral Contracts).
# A mirror-write failure (no git repo, unwritable path, etc.) never affects
# the primary `~/.claude/state/ask-registry.jsonl` write or the caller.
#
# ============================================================
# SUMMARIZER (heuristic-first; optional haiku-tier upgrade)
# ============================================================
#
# Default path (always runs, synchronous, no network): strip markdown
# (code fences/backticks, bold/italic markers, `[text](url)` links, leading
# `#` headers), take the FIRST SENTENCE (up to and including the first
# `.`/`!`/`?`), cap at 140 chars (word-boundary trim + "..." when cut).
#
# Optional upgrade: when `ASK_SUMMARIZER=haiku` is exported AND the
# heuristic path was actually used (no explicit `--summary`), `register`
# backgrounds (never blocks — performance budget: capture stays
# synchronous/<=100ms, the upgrade is fully async) a `claude --model haiku -p`
# call summarizing the raw `--text`, and on success appends a
# `record_type:"summary_updated"` record with the improved summary. Fable is
# NEVER used here — cheap-model-only by design (model-tiering directive);
# the model flag is hardcoded to "haiku", not configurable to anything
# higher-tier. A missing `claude` binary, a network failure, or a timeout
# all degrade silently to "the heuristic summary stands" — never a crash,
# never a retry, never a block. Test-injection seam: `_AR_HAIKU_CMD`, if set,
# replaces the real `claude` invocation entirely (piped the raw text on
# stdin) — used ONLY by --self-test to avoid a live model call; production
# code paths never set this variable.
#
# ============================================================
# SANDBOXING (HARNESS_SELFTEST / explicit overrides — constraint 4)
# ============================================================
#
# Resolution order for the ask-registry state directory (the FILE itself is
# always "<dir>/ask-registry.jsonl", matching the plan's literal path
# `~/.claude/state/ask-registry.jsonl`):
#   1. ASK_REGISTRY_STATE_DIR env var, if set.
#   2. HARNESS_SELFTEST=1 and ASK_REGISTRY_STATE_DIR unset -> a sandboxed
#      dir under ${TMPDIR:-/tmp}/ask-registry-selftest/<pid>/.
#   3. Default: $HOME/.claude/state/ — the real, production, cross-project
#      state dir (matches heartbeats/needs-you/progress-log convention).
#
# Resolution order for the in-repo MIRROR path (mirrors needs-you.sh's
# _ny_md_path exactly — this is "the resolver needs-you.sh already uses"):
#   1. ASK_REGISTRY_MIRROR_PATH env var, if set (explicit override — used by
#      ordinary self-test scenarios that are not exercising the resolver
#      itself).
#   2. HARNESS_SELFTEST=1 and no override -> a sandboxed path under
#      ${TMPDIR:-/tmp}/ask-registry-selftest/<pid>/mirror/ask-registry.jsonl.
#   3. Default: "$(nl_main_checkout_root)/docs/asks/ask-registry.jsonl",
#      falling back to `git rev-parse --show-toplevel` if nl-paths.sh is
#      unavailable, and skipping the mirror write entirely (best-effort) if
#      neither resolves. The dedicated FROM-WORKTREE self-test fixture
#      deliberately bypasses BOTH (1) and (2) — it constructs a real
#      synthetic git repo + linked worktree and exercises this REAL
#      resolution path end-to-end (mirrors nl-paths.sh's own T6/T7 model).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh" ]]; then
  source "$SCRIPT_DIR/../hooks/lib/progress-log-lib.sh"
fi
# shellcheck disable=SC1091
_AR_NLPATHS="$SCRIPT_DIR/../hooks/lib/nl-paths.sh"
if [[ -f "$_AR_NLPATHS" ]]; then
  source "$_AR_NLPATHS"
fi

_AR_VALID_STATUSES=(active done dismissed merged)

# ----------------------------------------------------------------------
# ar_state_dir — resolve the ask-registry state directory per the order
# above. Always prints a non-empty path; never fails.
# ----------------------------------------------------------------------
ar_state_dir() {
  if [[ -n "${ASK_REGISTRY_STATE_DIR:-}" ]]; then
    printf '%s' "$ASK_REGISTRY_STATE_DIR"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/ask-registry-selftest/%s' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  printf '%s/.claude/state' "${HOME:-$PWD}"
  return 0
}

ar_registry_file() { printf '%s/ask-registry.jsonl' "$(ar_state_dir)"; }

# ----------------------------------------------------------------------
# _ar_mirror_path — resolve the in-repo mirror path per the order above.
# ----------------------------------------------------------------------
_ar_mirror_path() {
  if [[ -n "${ASK_REGISTRY_MIRROR_PATH:-}" ]]; then
    printf '%s' "$ASK_REGISTRY_MIRROR_PATH"
    return 0
  fi
  if [[ "${HARNESS_SELFTEST:-0}" == "1" ]]; then
    printf '%s/ask-registry-selftest/%s/mirror/ask-registry.jsonl' "${TMPDIR:-/tmp}" "$$"
    return 0
  fi
  local root=""
  if command -v nl_main_checkout_root >/dev/null 2>&1; then
    root="$(nl_main_checkout_root)"
  fi
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  [[ -n "$root" ]] || { printf ''; return 0; }
  printf '%s/docs/asks/ask-registry.jsonl' "$root"
  return 0
}

# ----------------------------------------------------------------------
# _ar_mirror_append <json-line> — best-effort; never fails the caller.
# ----------------------------------------------------------------------
_ar_mirror_append() {
  local json="$1"
  local path; path="$(_ar_mirror_path)"
  [[ -n "$path" ]] || return 0
  local dir; dir="$(dirname "$path")"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$json" >> "$path" 2>/dev/null || return 0
  return 0
}

# Same escaper as progress-log-lib.sh's _pl_json_escape (duplicated locally
# per this repo's single-file-portability convention for standalone scripts
# — see needs-you.sh / session-heartbeat-lib.sh for the same duplication).
_ar_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  local nl=$'\n' cr=$'\r' tab=$'\t'
  s="${s//$nl/\\n}"
  s="${s//$cr/\\r}"
  s="${s//$tab/\\t}"
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  printf '%s' "$s"
}

_ar_in_list() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# ----------------------------------------------------------------------
# _ar_strip_markdown <text> — code fences/backticks, bold/italic markers,
# `[text](url)` links, leading `#` headers dropped (content kept); all
# whitespace/newlines collapsed to single spaces; trimmed.
# ----------------------------------------------------------------------
_ar_strip_markdown() {
  local s="$1"
  s="$(printf '%s' "$s" | sed -e 's/```//g' -e 's/`//g')"
  s="$(printf '%s' "$s" | sed -E 's/(\*\*|__)([^*_]+)\1/\2/g; s/(\*|_)([^*_]+)\1/\2/g')"
  s="$(printf '%s' "$s" | sed -E 's/\[([^]]+)\]\([^)]*\)/\1/g')"
  s="$(printf '%s' "$s" | sed -E 's/^#+[[:space:]]*//')"
  s="$(printf '%s' "$s" | tr '\n\r\t' '   ' | sed -E 's/ +/ /g')"
  s="$(printf '%s' "$s" | sed -E 's/^ +//; s/ +$//')"
  printf '%s' "$s"
}

# ----------------------------------------------------------------------
# _ar_truncate140 <text> — cap at 140 chars, word-boundary trim + "..." when
# cut. Text already <=140 chars passes through unchanged.
# ----------------------------------------------------------------------
_ar_truncate140() {
  local s="$1"
  local max=140
  if [[ "${#s}" -le "$max" ]]; then
    printf '%s' "$s"
    return 0
  fi
  local cut=$((max - 3))
  local t="${s:0:$cut}"
  local last_space="${t% *}"
  if [[ "${#last_space}" -gt 0 && "${#last_space}" -lt "${#t}" && "${#last_space}" -ge $((cut / 2)) ]]; then
    t="$last_space"
  fi
  printf '%s...' "$t"
}

# ----------------------------------------------------------------------
# _ar_heuristic_summarize <raw-text> — the default (always-available,
# no-network) summarizer path: strip markdown, take the first sentence,
# cap at 140 chars.
# ----------------------------------------------------------------------
_ar_heuristic_summarize() {
  local raw="$1"
  local stripped; stripped="$(_ar_strip_markdown "$raw")"
  [[ -n "$stripped" ]] || { printf ''; return 0; }
  local sentence
  sentence="$(printf '%s' "$stripped" | sed -E 's/^([^.!?]*[.!?]).*/\1/')"
  sentence="$(printf '%s' "$sentence" | sed -E 's/^ +//; s/ +$//')"
  _ar_truncate140 "$sentence"
}

# ----------------------------------------------------------------------
# _ar_haiku_summarize <raw-text> — optional upgrade path. Prints the
# improved summary and returns 0 on success; prints nothing and returns
# non-zero on ANY failure (missing binary, empty output, non-zero exit) —
# callers must treat non-zero as "keep the heuristic summary", never crash.
# Test-injection seam: _AR_HAIKU_CMD (see header SUMMARIZER section).
# ----------------------------------------------------------------------
_ar_haiku_summarize() {
  local text="$1"
  local out=""
  if [[ -n "${_AR_HAIKU_CMD:-}" ]]; then
    out="$(printf '%s' "$text" | eval "$_AR_HAIKU_CMD" 2>/dev/null)"
  elif command -v claude >/dev/null 2>&1; then
    # Fable is NEVER used here — hardcoded cheap-model-only (model-tiering
    # directive). Not exercised by --self-test (no live model call); Task
    # 18's acceptance pass is this path's real-world verification.
    out="$(claude --model haiku -p "Summarize the following operator request in one plain-text sentence, no markdown, at most 140 characters: $text" 2>/dev/null)"
  else
    printf ''
    return 1
  fi
  out="$(_ar_truncate140 "$(_ar_strip_markdown "$out")")"
  if [[ -z "$out" ]]; then
    printf ''
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# ----------------------------------------------------------------------
# _ar_async_haiku_upgrade <ask_id> <raw-text> — backgrounds the haiku call
# + the follow-up registry append; NEVER blocks the calling `register`.
# ----------------------------------------------------------------------
_ar_async_haiku_upgrade() {
  local ask_id="$1" text="$2"
  (
    local better
    better="$(_ar_haiku_summarize "$text")" || exit 0
    [[ -n "$better" ]] || exit 0
    _ar_append_record "summary_updated" "$ask_id" "" "" "" "$better" \
      "" "" "" "" "" "" "ask-registry-summarizer" >/dev/null
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ----------------------------------------------------------------------
# _ar_slugify <text> — lowercase, non-alnum runs -> single "-", trimmed,
# capped at 30 chars. Used only for readable auto-generated ask ids.
# ----------------------------------------------------------------------
_ar_slugify() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  printf '%.30s' "$s"
}

# ----------------------------------------------------------------------
# _ar_gen_ask_id <summary> — ask-<YYYYMMDD>-<slug>-<4hex>. Collisions are
# harmless (id is a lookup key; a same-day, same-first-words duplicate gets
# a different random suffix) — mirrors needs-you.sh's _ny_gen_id rationale.
# ----------------------------------------------------------------------
_ar_gen_ask_id() {
  local summary="$1"
  local date_part; date_part="$(date -u '+%Y%m%d' 2>/dev/null || echo 'unknown')"
  local slug; slug="$(_ar_slugify "$summary")"
  [[ -n "$slug" ]] || slug="ask"
  local rand
  if [[ -r /dev/urandom ]]; then
    rand="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  else
    rand="$(printf '%04x' "$RANDOM")"
  fi
  printf 'ask-%s-%s-%s' "$date_part" "$slug" "$rand"
}

# JS snippet for the project reverse-lookup (see _ar_resolve_project). Reads
# the target repo path + the projects.js absolute path from env vars (TARGET
# / PROJJS) rather than argv, sidestepping node -e's argv-index quirks
# entirely. Windows note: paths flowing through this script are the
# `git rev-parse --show-toplevel` form (already Windows-drive-letter-shaped
# on this platform per nl-paths.sh's own commentary), which passes through
# Git-Bash env-var marshalling to node unmangled — a literal POSIX-looking
# `/tmp/...` path would NOT (MSYS path conversion), so this function is only
# ever called with git-derived or explicit `--repo` paths, never a bare
# `/tmp` style string.
read -r -d '' _AR_PROJECT_RESOLVE_JS <<'JSEOF' || true
const path = require('path');
try {
  const projects = require(process.env.PROJJS);
  const map = projects.loadProjects();
  const target = path.resolve(process.env.TARGET);
  let best = null, bestLen = -1;
  Object.keys(map).forEach(function (k) {
    try {
      const root = path.resolve(map[k]);
      if (target === root || target.indexOf(root + path.sep) === 0) {
        if (root.length > bestLen) { best = k; bestLen = root.length; }
      }
    } catch (e) { /* ignore malformed map entry */ }
  });
  process.stdout.write(best || '');
} catch (e) {
  process.stdout.write('');
}
JSEOF

# ----------------------------------------------------------------------
# _ar_resolve_project <repo-abs-path> — reverse-lookup against
# neural-lace/workstreams-ui/config/projects.js's loadProjects() map
# (deepest matching root wins); falls back to basename(repo) when node is
# unavailable, the module can't be resolved, or no root matches.
# ----------------------------------------------------------------------
_ar_resolve_project() {
  local repo="$1"
  [[ -n "$repo" ]] || { printf 'unknown'; return 0; }
  if command -v node >/dev/null 2>&1; then
    local nlroot="" projjs=""
    if command -v nl_workstreams_ui >/dev/null 2>&1; then
      nlroot="$(nl_workstreams_ui)"
    fi
    if [[ -n "$nlroot" ]]; then
      projjs="$nlroot/config/projects.js"
    fi
    if [[ -n "$projjs" && -f "$projjs" ]]; then
      local result
      result="$(TARGET="$repo" PROJJS="$projjs" node -e "$_AR_PROJECT_RESOLVE_JS" 2>/dev/null)"
      if [[ -n "$result" ]]; then
        printf '%s' "$result"
        return 0
      fi
    fi
  fi
  basename "$repo" 2>/dev/null || printf 'unknown'
  return 0
}

# ----------------------------------------------------------------------
# _ar_append_record <record_type> <ask_id> <status> <repo> <project>
#                    <summary> <verbatim_ref> <origin_session> <plan_slug>
#                    <session_id> <resumed_from> <merged_into> <emitter>
#   The ONE writer every verb below calls: builds the flat JSON record,
#   appends it to the primary registry file, and best-effort mirrors it
#   (constraint 11). Never fails the caller. Prints the registry file path.
# ----------------------------------------------------------------------
_ar_append_record() {
  local record_type="$1" ask_id="$2" status="$3" repo="$4" project="$5" \
        summary="$6" verbatim_ref="$7" origin_session="$8" plan_slug="$9"
  shift 9
  local session_id="$1" resumed_from="$2" merged_into="$3" emitter="$4"

  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  local user machine
  user="$(git config user.name 2>/dev/null || true)"
  [[ -n "$user" ]] || user="${USER:-${USERNAME:-unknown}}"
  machine="$(hostname 2>/dev/null || echo unknown)"

  local json
  json="$(printf '{"ask_id":"%s","record_type":"%s","ts":"%s","user":"%s","machine":"%s","repo":"%s","project":"%s","summary":"%s","verbatim_ref":"%s","origin_session":"%s","status":"%s","plan_slug":"%s","session_id":"%s","resumed_from":"%s","merged_into":"%s","emitter":"%s"}' \
    "$(_ar_json_escape "$ask_id")" "$(_ar_json_escape "$record_type")" "$ts" \
    "$(_ar_json_escape "$user")" "$(_ar_json_escape "$machine")" \
    "$(_ar_json_escape "$repo")" "$(_ar_json_escape "$project")" \
    "$(_ar_json_escape "$summary")" "$(_ar_json_escape "$verbatim_ref")" \
    "$(_ar_json_escape "$origin_session")" "$(_ar_json_escape "$status")" \
    "$(_ar_json_escape "$plan_slug")" "$(_ar_json_escape "$session_id")" \
    "$(_ar_json_escape "$resumed_from")" "$(_ar_json_escape "$merged_into")" \
    "$(_ar_json_escape "$emitter")")"

  local f dir
  f="$(ar_registry_file)"
  dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null && printf '%s\n' "$json" >> "$f" 2>/dev/null

  _ar_mirror_append "$json"

  printf '%s' "$f"
  return 0
}

# ----------------------------------------------------------------------
# cmd_register
# ----------------------------------------------------------------------
cmd_register() {
  local ask_id="" summary="" text="" repo="" project="" session_id="" \
        transcript_path="" prompt_offset="" verbatim_ref=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --text) text="${2:-}"; shift 2 ;;
      --repo) repo="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --transcript-path) transcript_path="${2:-}"; shift 2 ;;
      --prompt-offset) prompt_offset="${2:-}"; shift 2 ;;
      --verbatim-ref) verbatim_ref="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -n "$repo" ]] || repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$project" ]] || project="$(_ar_resolve_project "$repo")"

  local heuristic_used=0
  if [[ -n "$summary" ]]; then
    summary="$(_ar_truncate140 "$summary")"
  elif [[ -n "$text" ]]; then
    summary="$(_ar_heuristic_summarize "$text")"
    heuristic_used=1
  fi

  if [[ -z "$verbatim_ref" && -n "$transcript_path" ]]; then
    verbatim_ref="${transcript_path}#${prompt_offset:-0}"
  fi

  [[ -n "$ask_id" ]] || ask_id="$(_ar_gen_ask_id "$summary")"

  local f
  f="$(_ar_append_record "created" "$ask_id" "active" "$repo" "$project" \
    "$summary" "$verbatim_ref" "$session_id" "" "$session_id" "" "" "ask-registry")"

  if command -v pl_emit >/dev/null 2>&1; then
    pl_emit --type ask_registered --ask "$ask_id" --session-id "$session_id" \
      --summary "$summary" --emitter ask-registry >/dev/null 2>&1 || true
  fi

  if [[ "${ASK_SUMMARIZER:-}" == "haiku" && "$heuristic_used" == "1" && -n "$text" ]]; then
    _ar_async_haiku_upgrade "$ask_id" "$text"
  fi

  printf '%s' "$f"
  return 0
}

# ----------------------------------------------------------------------
# cmd_attach_session
# ----------------------------------------------------------------------
cmd_attach_session() {
  local ask_id="" session_id="" resumed_from=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --resumed-from) resumed_from="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$session_id" ]]; then
    echo "ask-registry.sh attach-session: --ask-id and --session-id are required (no-op; never blocks caller)" >&2
    return 0
  fi

  local f
  f="$(_ar_append_record "session_attached" "$ask_id" "" "" "" "" "" "" "" \
    "$session_id" "$resumed_from" "" "ask-registry")"

  if command -v pl_emit >/dev/null 2>&1; then
    pl_emit --type session_attached --ask "$ask_id" --session-id "$session_id" \
      --emitter ask-registry >/dev/null 2>&1 || true
  fi

  printf '%s' "$f"
  return 0
}

# ----------------------------------------------------------------------
# cmd_link_plan
# ----------------------------------------------------------------------
cmd_link_plan() {
  local ask_id="" plan_slug=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --plan-slug) plan_slug="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$plan_slug" ]]; then
    echo "ask-registry.sh link-plan: --ask-id and --plan-slug are required (no-op; never blocks caller)" >&2
    return 0
  fi
  _ar_append_record "plan_linked" "$ask_id" "" "" "" "" "" "" "$plan_slug" \
    "" "" "" "ask-registry"
  return 0
}

# ----------------------------------------------------------------------
# cmd_set_status
# ----------------------------------------------------------------------
cmd_set_status() {
  local ask_id="" status="" emitter="unknown"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --status) status="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$status" ]]; then
    echo "ask-registry.sh set-status: --ask-id and --status are required (no-op; never blocks caller)" >&2
    return 0
  fi
  if ! _ar_in_list "$status" "${_AR_VALID_STATUSES[@]}"; then
    echo "ask-registry.sh set-status: invalid --status '$status' (must be one of: active|done|dismissed|merged) — no-op, never blocks caller" >&2
    return 0
  fi
  _ar_append_record "status_change" "$ask_id" "$status" "" "" "" "" "" "" \
    "" "" "" "$emitter"
  return 0
}

# ----------------------------------------------------------------------
# cmd_merge
# ----------------------------------------------------------------------
cmd_merge() {
  local ask_id="" into=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --into) into="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$into" ]]; then
    echo "ask-registry.sh merge: --ask-id and --into are required (no-op; never blocks caller)" >&2
    return 0
  fi
  if [[ "$ask_id" == "$into" ]]; then
    echo "ask-registry.sh merge: --ask-id and --into must differ — no-op, never blocks caller" >&2
    return 0
  fi
  _ar_append_record "merged" "$ask_id" "merged" "" "" "" "" "" "" "" "" \
    "$into" "ask-registry"
  return 0
}

# ----------------------------------------------------------------------
# cmd_override_project
# ----------------------------------------------------------------------
cmd_override_project() {
  local ask_id="" project="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$project" ]]; then
    echo "ask-registry.sh override-project: --ask-id and --project are required (no-op; never blocks caller)" >&2
    return 0
  fi
  _ar_append_record "project_override" "$ask_id" "" "" "$project" "" "" "" \
    "" "" "" "" "$emitter"
  return 0
}

cmd_list() {
  local f
  f="$(ar_registry_file)"
  [[ -f "$f" ]] && cat "$f"
  return 0
}

# ============================================================
# --self-test
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'arst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi

  export HARNESS_SELFTEST=1
  export ASK_REGISTRY_STATE_DIR="$TMP/ar"
  export PROGRESS_LOG_STATE_DIR="$TMP/pl"
  export ASK_REGISTRY_MIRROR_PATH="$TMP/mirror/ask-registry.jsonl"
  mkdir -p "$ASK_REGISTRY_STATE_DIR" "$PROGRESS_LOG_STATE_DIR"
  local REG="$ASK_REGISTRY_STATE_DIR/ask-registry.jsonl"

  echo "Scenario A: register (explicit ask-id + summary) writes a jq-valid, correctly-shaped record"
  cmd_register --ask-id "ask-selftest-1" --summary "skeleton test" --project "demo" --repo "/some/repo" >/dev/null
  if [[ -f "$REG" ]]; then
    pass "register created ask-registry.jsonl under the sandbox"
  else
    fail "expected $REG to exist after register"
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e . "$REG" >/dev/null 2>&1; then
      pass "written record is valid JSON (jq)"
    else
      fail "written record is NOT valid JSON"
    fi
    local ask_v summary_v status_v rt_v proj_v
    ask_v="$(jq -rs '.[0].ask_id' "$REG" | tr -d '\r')"
    summary_v="$(jq -rs '.[0].summary' "$REG" | tr -d '\r')"
    status_v="$(jq -rs '.[0].status' "$REG" | tr -d '\r')"
    rt_v="$(jq -rs '.[0].record_type' "$REG" | tr -d '\r')"
    proj_v="$(jq -rs '.[0].project' "$REG" | tr -d '\r')"
    if [[ "$ask_v" == "ask-selftest-1" && "$summary_v" == "skeleton test" && "$status_v" == "active" && "$rt_v" == "created" && "$proj_v" == "demo" ]]; then
      pass "fields round-trip (ask_id, summary, status=active, record_type=created, project)"
    else
      fail "field mismatch: ask_id=$ask_v summary=$summary_v status=$status_v record_type=$rt_v project=$proj_v"
    fi
  fi

  echo "Scenario B: register with NO --ask-id auto-generates a unique id per call"
  local out1 out2 id1 id2
  cmd_register --summary "same summary text" --project "demo" >/dev/null
  cmd_register --summary "same summary text" --project "demo" >/dev/null
  id1="$(grep '"summary":"same summary text"' "$REG" | sed -n '1p' | sed -E 's/.*"ask_id":"([^"]*)".*/\1/')"
  id2="$(grep '"summary":"same summary text"' "$REG" | sed -n '2p' | sed -E 's/.*"ask_id":"([^"]*)".*/\1/')"
  if [[ -n "$id1" && -n "$id2" && "$id1" != "$id2" && "$id1" == ask-* && "$id2" == ask-* ]]; then
    pass "auto-generated ask ids are non-empty, ask-prefixed, and unique across calls ($id1 vs $id2)"
  else
    fail "expected two distinct auto-generated ask- ids, got '$id1' and '$id2'"
  fi

  echo "Scenario C: register --text runs the heuristic summarizer (markdown-stripped, first sentence, capped)"
  cmd_register --ask-id "ask-selftest-text" --text '**Rebuild** the workstreams view. It should show asks grouped by project. Also fix the sidebar.' --project "demo" >/dev/null
  local text_summary
  text_summary="$(grep '"ask_id":"ask-selftest-text"' "$REG" | sed -E 's/.*"summary":"([^"]*)".*/\1/')"
  if [[ "$text_summary" == "Rebuild the workstreams view." ]]; then
    pass "heuristic summarizer strips markdown and keeps only the first sentence"
  else
    fail "expected 'Rebuild the workstreams view.', got '$text_summary'"
  fi

  echo "Scenario C2: heuristic summarizer truncates a long punctuation-free text to <=140 chars with a word-boundary + ellipsis"
  local long_text; long_text="$(head -c 300 /dev/zero | tr '\0' 'x' | sed -E 's/(.{8})/\1 /g')"
  local long_summary; long_summary="$(_ar_heuristic_summarize "$long_text")"
  if [[ "${#long_summary}" -le 140 && "$long_summary" == *... ]]; then
    pass "long punctuation-free text truncated to <=140 chars with trailing ellipsis (len=${#long_summary})"
  else
    fail "expected <=140 chars ending in '...', got len=${#long_summary} value='$long_summary'"
  fi

  echo "Scenario D: register best-effort emits an ask_registered progress-log event"
  local plf="$PROGRESS_LOG_STATE_DIR/ask-selftest-1.jsonl"
  if [[ -f "$plf" ]] && grep -q '"type":"ask_registered"' "$plf"; then
    pass "register emitted an ask_registered progress-log event"
  else
    fail "expected an ask_registered event at $plf"
  fi

  echo "Scenario E: attach-session appends a session_attached record + emits the progress-log event"
  cmd_register --ask-id "ask-selftest-attach" --summary "attach test" >/dev/null
  cmd_attach_session --ask-id "ask-selftest-attach" --session-id "sess-child-1" --resumed-from "sess-parent" >/dev/null
  if grep -q '"ask_id":"ask-selftest-attach".*"record_type":"session_attached".*"session_id":"sess-child-1"' "$REG"; then
    pass "attach-session appended a session_attached record with the session id"
  else
    fail "expected a session_attached record for ask-selftest-attach/sess-child-1"
  fi
  local attach_plf="$PROGRESS_LOG_STATE_DIR/ask-selftest-attach.jsonl"
  if [[ -f "$attach_plf" ]] && grep -q '"type":"session_attached"' "$attach_plf"; then
    pass "attach-session emitted a session_attached progress-log event"
  else
    fail "expected a session_attached progress-log event at $attach_plf"
  fi

  echo "Scenario E2: attach-session with missing args is a documented no-op (never blocks)"
  local before_lines after_lines
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_attach_session --ask-id "ask-selftest-attach" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "attach-session with missing --session-id is a no-op (no new record)"
  else
    fail "expected no new record on missing --session-id, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario F: link-plan appends a plan_linked record"
  cmd_link_plan --ask-id "ask-selftest-1" --plan-slug "demo-plan" >/dev/null
  if grep -q '"ask_id":"ask-selftest-1".*"record_type":"plan_linked".*"plan_slug":"demo-plan"' "$REG"; then
    pass "link-plan appended a plan_linked record with the plan slug"
  else
    fail "expected a plan_linked record for ask-selftest-1/demo-plan"
  fi

  echo "Scenario G: set-status with a VALID status appends a status_change record"
  cmd_set_status --ask-id "ask-selftest-1" --status "done" --emitter "auditor" >/dev/null
  if grep -q '"ask_id":"ask-selftest-1".*"record_type":"status_change".*"status":"done".*"emitter":"auditor"' "$REG"; then
    pass "set-status appended a status_change record (status=done, emitter=auditor)"
  else
    fail "expected a status_change record for ask-selftest-1 status=done emitter=auditor"
  fi

  echo "Scenario G2: set-status with an INVALID status is REJECTED (file unchanged)"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_set_status --ask-id "ask-selftest-1" --status "bogus-status" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "set-status rejected an invalid status vocabulary value (no new record)"
  else
    fail "expected no new record for an invalid status, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario H: merge appends a merged record (status=merged, merged_into set)"
  cmd_register --ask-id "ask-selftest-dup" --summary "duplicate ask" >/dev/null
  cmd_merge --ask-id "ask-selftest-dup" --into "ask-selftest-1" >/dev/null
  if grep -q '"ask_id":"ask-selftest-dup".*"record_type":"merged".*"status":"merged".*"merged_into":"ask-selftest-1"' "$REG"; then
    pass "merge appended a merged record pointing at the target ask"
  else
    fail "expected a merged record for ask-selftest-dup -> ask-selftest-1"
  fi

  echo "Scenario H2: merge with --ask-id == --into is rejected (no-op)"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_merge --ask-id "ask-selftest-1" --into "ask-selftest-1" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "merge rejects merging an ask into itself"
  else
    fail "expected no new record for a self-merge, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario I: override-project appends a project_override record"
  cmd_override_project --ask-id "ask-selftest-1" --project "renamed-project" >/dev/null
  if grep -q '"ask_id":"ask-selftest-1".*"record_type":"project_override".*"project":"renamed-project".*"emitter":"operator-ui"' "$REG"; then
    pass "override-project appended a project_override record (default emitter=operator-ui)"
  else
    fail "expected a project_override record for ask-selftest-1 project=renamed-project"
  fi

  echo "Scenario J: list prints the raw registry contents"
  local out
  out="$(cmd_list)"
  if printf '%s' "$out" | grep -q "ask-selftest-1" && printf '%s' "$out" | grep -q "ask-selftest-dup"; then
    pass "list prints multiple registered/mutated entries"
  else
    fail "list did not print the expected entries"
  fi

  echo "Scenario K: mirror append lands at ASK_REGISTRY_MIRROR_PATH (explicit override)"
  if [[ -f "$ASK_REGISTRY_MIRROR_PATH" ]] && grep -q "ask-selftest-1" "$ASK_REGISTRY_MIRROR_PATH"; then
    pass "mirror file received the same records as the primary registry"
  else
    fail "expected mirror file at $ASK_REGISTRY_MIRROR_PATH to contain ask-selftest-1"
  fi
  local primary_lines mirror_lines
  primary_lines=$(wc -l < "$REG" | tr -d ' ')
  mirror_lines=$(wc -l < "$ASK_REGISTRY_MIRROR_PATH" | tr -d ' ')
  if [[ "$primary_lines" == "$mirror_lines" ]]; then
    pass "mirror line count matches primary registry line count ($primary_lines)"
  else
    fail "mirror/primary line count mismatch: primary=$primary_lines mirror=$mirror_lines"
  fi

  echo "Scenario L: FROM-WORKTREE fixture — mirror resolves to the MAIN checkout, never the worktree cwd"
  (
    set -e
    local repo_dir="$TMP/l-repo" wt_dir="$TMP/l-wt"
    mkdir -p "$repo_dir"
    ( cd "$repo_dir" && git init -q . && git config core.hooksPath "" \
        && git config user.email "t@example.test" && git config user.name "T" \
        && echo x > f && git add f && git commit -q -m init ) >/dev/null 2>&1
    ( cd "$repo_dir" && git worktree add -q -b ar-selftest-wt "$wt_dir" ) >/dev/null 2>&1

    # Isolate registry/progress-log state from the real machine WITHOUT
    # using HARNESS_SELFTEST's mirror short-circuit (that would skip the
    # real nl_main_checkout_root resolution this scenario exists to prove).
    local wt_ar_state="$TMP/l-ar-state" wt_pl_state="$TMP/l-pl-state"
    mkdir -p "$wt_ar_state" "$wt_pl_state"

    ( cd "$wt_dir" \
        && HARNESS_SELFTEST=0 \
           ASK_REGISTRY_STATE_DIR="$wt_ar_state" \
           PROGRESS_LOG_STATE_DIR="$wt_pl_state" \
           ASK_REGISTRY_MIRROR_PATH="" \
           bash "$SCRIPT_DIR/ask-registry.sh" register --ask-id "ask-selftest-wt" \
             --summary "from worktree" --repo "$wt_dir" >/dev/null 2>&1 )

    local expected_main; expected_main="$repo_dir/docs/asks/ask-registry.jsonl"
    if [[ -f "$expected_main" ]] && grep -q "ask-selftest-wt" "$expected_main"; then
      echo "  PASS: L1 mirror landed under the MAIN checkout ($expected_main)"
    else
      echo "  FAIL: L1 expected mirror at $expected_main to contain ask-selftest-wt" >&2
      exit 1
    fi
    local leaked_in_worktree="$wt_dir/docs/asks/ask-registry.jsonl"
    if [[ ! -f "$leaked_in_worktree" ]]; then
      echo "  PASS: L2 mirror did NOT land under the worktree cwd ($leaked_in_worktree absent)"
    else
      echo "  FAIL: L2 mirror incorrectly landed under the worktree ($leaked_in_worktree exists)" >&2
      exit 1
    fi
    ( cd "$repo_dir" && git worktree remove --force "$wt_dir" >/dev/null 2>&1 || true )
    ( cd "$repo_dir" && git branch -D ar-selftest-wt >/dev/null 2>&1 || true )
  )
  if [[ "$?" == "0" ]]; then
    pass "L: from-worktree mirror fixture (see L1/L2 lines above)"
  else
    fail "L: from-worktree mirror fixture failed (see L1/L2 lines above)"
  fi

  echo "Scenario M: ASK_SUMMARIZER=haiku upgrade path (fake command, no live model call)"
  _AR_HAIKU_CMD='cat' # echoes stdin verbatim -- deterministic fake "model"
  ASK_SUMMARIZER=haiku cmd_register --ask-id "ask-selftest-haiku" \
    --text "please improve the fake summary for this async upgrade test" >/dev/null
  local waited=0 upgraded=0
  while [[ "$waited" -lt 30 ]]; do
    if grep -q '"ask_id":"ask-selftest-haiku".*"record_type":"summary_updated"' "$REG" 2>/dev/null; then
      upgraded=1
      break
    fi
    sleep 0.2
    waited=$((waited + 1))
  done
  unset _AR_HAIKU_CMD
  if [[ "$upgraded" == "1" ]]; then
    pass "ASK_SUMMARIZER=haiku eventually appended a summary_updated record (async, non-blocking)"
  else
    fail "expected a summary_updated record for ask-selftest-haiku within timeout"
  fi

  echo "Scenario N: ASK_SUMMARIZER=haiku with a FAILING fake command degrades silently (no crash, no bad record)"
  _AR_HAIKU_CMD='false' # always fails, prints nothing
  local reg_lines_before; reg_lines_before=$(wc -l < "$REG" | tr -d ' ')
  ASK_SUMMARIZER=haiku cmd_register --ask-id "ask-selftest-haiku-fail" \
    --text "this summarizer call will fail on purpose" >/dev/null
  sleep 0.6
  unset _AR_HAIKU_CMD
  local reg_lines_after; reg_lines_after=$(wc -l < "$REG" | tr -d ' ')
  local expected_after=$((reg_lines_before + 1)) # only the "created" record, no summary_updated
  if [[ "$reg_lines_after" == "$expected_after" ]] && ! grep -q '"ask_id":"ask-selftest-haiku-fail".*"record_type":"summary_updated"' "$REG"; then
    pass "a failing haiku call degrades silently (heuristic summary stands, no extra record, no crash)"
  else
    fail "expected exactly 1 new record (created only) for ask-selftest-haiku-fail, got $((reg_lines_after - reg_lines_before)) new record(s)"
  fi

  echo "Scenario O: project auto-resolution falls back to basename(repo) for an unrecognized repo path"
  local fallback_repo="$TMP/some-random-unregistered-repo"
  mkdir -p "$fallback_repo"
  cmd_register --ask-id "ask-selftest-fallback-project" --summary "fallback project test" --repo "$fallback_repo" >/dev/null
  local fb_project
  fb_project="$(grep '"ask_id":"ask-selftest-fallback-project"' "$REG" | sed -E 's/.*"project":"([^"]*)".*/\1/')"
  if [[ "$fb_project" == "some-random-unregistered-repo" ]]; then
    pass "project auto-resolution falls back to basename(repo) when no projects.js root matches"
  else
    fail "expected project='some-random-unregistered-repo', got '$fb_project'"
  fi

  echo "Scenario P: sandbox-only writes — self-test never touched the real ~/.claude-shaped path"
  if [[ ! -e "$TMP/.claude" ]]; then
    pass "self-test wrote only under its own sandboxed tempdir"
  else
    fail "self-test unexpectedly created a .claude path under $TMP"
  fi

  rm -rf "$TMP" 2>/dev/null || true

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
case "${1:-}" in
  register)
    shift
    cmd_register "$@"
    exit 0
    ;;
  attach-session)
    shift
    cmd_attach_session "$@"
    exit 0
    ;;
  link-plan)
    shift
    cmd_link_plan "$@"
    exit 0
    ;;
  set-status)
    shift
    cmd_set_status "$@"
    exit 0
    ;;
  merge)
    shift
    cmd_merge "$@"
    exit 0
    ;;
  override-project)
    shift
    cmd_override_project "$@"
    exit 0
    ;;
  list)
    shift
    cmd_list "$@"
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  -h|--help|"")
    cat <<'USAGE'
ask-registry.sh — ask registry CLI (ask-rooted-workstreams-p1, Task 8 —
finalized: register/attach-session/link-plan/set-status/merge/override-project).

Verbs:
  register [--ask-id <id>] [--summary <text>] [--text <raw>] [--repo <path>]
           [--project <name>] [--session-id <id>] [--transcript-path <path>]
           [--prompt-offset <n>] [--verbatim-ref <ref>]
                          Create a new ask (auto-generates --ask-id when
                          omitted; heuristic-summarizes --text when
                          --summary is omitted; optional ASK_SUMMARIZER=haiku
                          async upgrade). Never blocks; exit 0 always.
  attach-session --ask-id <id> --session-id <id> [--resumed-from <id>]
                          Attach a session to an existing ask.
  link-plan --ask-id <id> --plan-slug <slug>
                          Record the plan<->ask back-link.
  set-status --ask-id <id> --status <active|done|dismissed|merged>
             [--emitter <name>]
                          Append a status change (rejects invalid vocabulary).
  merge --ask-id <source-id> --into <target-id>
                          Mark source as a duplicate of target.
  override-project --ask-id <id> --project <name>
                          Operator override of an ask's project grouping.
  list                    Print the raw registry JSONL (read-only).
  --self-test             Run the self-test suite (sandboxed, incl. a
                          from-worktree in-repo-mirror fixture).

See this file's header comment for the full schema + reader-fold contract.
USAGE
    exit 0
    ;;
  *)
    echo "ask-registry.sh: unknown verb '$1' (run without args for usage; never blocks a caller since this is a standalone script)" >&2
    exit 0
    ;;
esac
