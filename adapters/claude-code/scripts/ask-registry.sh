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
# ============================================================
# ASK SLAs (accountable-estate-program-2026-07 Task 2 — deadline/
# default-action/SLA-readout verbs. Design §2's `operator-ask` fields:
# "what, why, deadline, default-action (what happens/doesn't if
# unanswered), SLA state. Hard cap <=5 open; re-surfaced every brief until
# closed; breaching SLA escalates visually, never silently expires."
# ============================================================
#
#   ask-registry.sh set-deadline --ask-id <id> --deadline <iso8601>
#                                 [--emitter <name>]
#     Sets/updates the ask's deadline. `--deadline` MUST parse as a
#     timestamp (`date -u -d`/BSD `-j -f` fallback, same parser family as
#     estate-brief.sh's `_eb_age_str`); an unparseable value is REJECTED
#     (no-op, stderr note, exit 0 — never a malformed deadline persisted).
#     The parsed value is NORMALIZED to canonical `%Y-%m-%dT%H:%M:%SZ`
#     before it is stored, so every downstream jq reader (this file's own
#     `sla` verb, estate-janitor.sh's ask-fold, estate-brief.sh's SLA
#     panel) can rely on `fromdateiso8601` parsing it without a second
#     format dialect to support. Appends a `record_type:"deadline_set"`
#     record. `--emitter` defaults to "operator-ui".
#
#   ask-registry.sh clear-deadline --ask-id <id> [--emitter <name>]
#     Removes a previously-set deadline (the ask goes back to "no
#     deadline"). Appends a `record_type:"deadline_cleared"` record. See
#     DEADLINE FOLD below — this verb only works BECAUSE deadline folding
#     is record-type-ordered, not plain last-non-empty-wins (a blank
#     `deadline` field would otherwise never be able to overwrite an
#     earlier non-blank one under this file's normal fold rule).
#
#   ask-registry.sh set-default-action --ask-id <id> --default-action <text>
#                                       [--emitter <name>]
#     Records what should happen if the deadline passes unanswered (e.g.
#     "DEMOTE" or "proceed with recommendation X") — DATA describing a
#     disposition, applied as data only this slice (constraint: T2 ships
#     visibility, not automatic enforcement of the disposition). Text is
#     capped at 140 chars (same `_ar_truncate140` convention as summaries/
#     titles). Appends a `record_type:"default_action_set"` record.
#     `--emitter` defaults to "operator-ui".
#
#   ask-registry.sh sla [--now <iso8601>] [--due-soon-hours <n>]
#     Read-only SLA read-out: folds every ACTIVE ask's deadline +
#     default_action (see DEADLINE FOLD / SCHEMA below) and prints one
#     tab-separated row per ask — `ask_id, sla_state, deadline,
#     default_action, summary` — sorted soonest-deadline-first (undated
#     asks last). `sla_state` is one of: `overdue` (deadline < now) |
#     `due-soon` (0 <= deadline-now <= --due-soon-hours, default 48,
#     env-overridable via ESTATE_ASK_SLA_DUE_SOON_HOURS) | `ok` (deadline
#     further out) | `no-deadline`. `--now` overrides "current time" for
#     deterministic manual/CI probing; defaults to the real wall clock.
#     Degrades to an honest stderr note (never a crash) when jq is
#     missing or the registry file does not exist yet.
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
#    status_change|merged|project_override|summary_updated|
#    amendment_candidate|candidate_classified|amended|deadline_set|
#    deadline_cleared|default_action_set|requirement_recorded|
#    invariant_declared|invariant_verdict",
#    "ts":"ISO-8601-UTC","user":"...","machine":"...",
#    "repo":"...","project":"...","summary":"...","verbatim_ref":"...",
#    "origin_session":"...","status":"active|done|dismissed|merged",
#    "plan_slug":"...","session_id":"...","resumed_from":"...",
#    "merged_into":"...","emitter":"...",
#    "title_source":"auto|operator|","candidate_id":"cand-...|",
#    "classification":"pending|amendment|noise|detached|",
#    "deadline":"ISO-8601-UTC|","default_action":"...",
#    "requirement_id":"req-...|","verbatim":"...","invariant_id":"inv-N|",
#    "invariant_text":"...","invariant_verdict":"holds|violated|unverifiable|",
#    "evidence_ref":"..."}
#
# ============================================================
# OPERATOR-REQUIREMENT LEDGER (requirement_id / verbatim / invariant_* /
# evidence_ref — BINDING reader contract)
# ============================================================
#
# WHY THIS EXISTS (the golden case, 2026-07-28/29). Every verifier in this
# harness checks delivered work against a PLAN. Nothing checked it against the
# operator's actual words. Two real failures followed, both from the same
# mechanism: the agent treated the operator's sentence as a GOAL TO DISCHARGE
# rather than a SPECIFICATION WITH INVARIANTS, satisfied the verb, and stopped
# reading.
#   (1) "Fable is supposed to always fail back to Opus." -> a gate was built
#       that BLOCKED the dispatch and told the caller to use Opus. It satisfied
#       "use Opus" and destroyed "automatically".
#   (2) "I don't want the agents to pin Opus. Opus is a fallback, not the
#       primary option." -> 21 agents were permanently repinned to Opus. It
#       satisfied "use Opus as a fallback" and destroyed "Fable is primary".
# In both, ONE sentence carried TWO invariants and the build preserved one.
# The ledger's whole job is to make the second invariant survive as a
# separately checkable statement that a verifier must return a verdict on.
#
# THREE RECORD TYPES:
#   requirement_recorded — the operator's sentence stored VERBATIM in
#       `verbatim` (never a paraphrase, never sentence-split, NOT passed
#       through the 140-char summariser; capped only at _AR_VERBATIM_MAX to
#       bound a pathological paste). `requirement_id` groups the family.
#   invariant_declared — ONE separately-checkable statement extracted from
#       that sentence, in `invariant_text`, addressed by `invariant_id`
#       (inv-1, inv-2, ... sequential within a requirement).
#   invariant_verdict — a verifier's per-invariant judgement in
#       `invariant_verdict` (holds|violated|unverifiable) with its citation in
#       `evidence_ref`.
#
# VERDICT FOLD (BINDING): for each (requirement_id, invariant_id) pair, sort
# `invariant_verdict` records by [ts, append-index] and take the LAST. `ts`
# has one-second resolution and a re-verification routinely lands in the same
# second as the verdict it supersedes, so ts alone is not a total order; the
# append-index makes the tiebreak EXPLICIT rather than leaning on jq's
# documented sort stability (measured stable on jq-1.7.1 here, but that is a
# property of the reader, not of this contract). ABSENCE of any verdict record
# is NOT a pass — it folds to `unverified`, which is the exact state the two
# golden-case failures were in.
#
# FOLD-FIELD ABSTENTION (BINDING — formerly "SUMMARY-FIELD ABSTENTION",
# widened 2026-07-29 after harness-reviewer Major 6): all three ledger record
# types write an EMPTY value for EVERY field that ANY reader folds
# last-non-empty-wins. Not just `summary`. The rule is stated over the FOLD
# LIST, not over a hand-maintained field-by-field list, because the original
# per-field phrasing is what let the bug in: the author guarded `summary` and
# `title_source` and missed `verbatim_ref`, a sibling in the very same fold
# array — so `record-requirement --verbatim-ref X` silently REPLACED the ask's
# pointer to the original operator prompt.
#
# THE FOLD LIST, enumerated FROM THE READERS (re-derive it from these three
# call sites, never from memory, whenever a reader changes):
#     repo, project, verbatim_ref, status   -- server/derive-lib.js:110
#                                              server/auditor.js:302
#                                              (literal `['repo','project',
#                                               'verbatim_ref','status']`)
#     summary, title_source                 -- the TITLE PRECEDENCE fold below
#                                              (derive-lib.js / auditor.js /
#                                               server/requests-routes.js:147)
#     verbatim_ref                          -- server/requests-routes.js:148
# => { repo, project, verbatim_ref, status, summary, title_source }
#
# A ledger record's ONLY job is to carry the ledger fields (requirement_id,
# verbatim, invariant_*, evidence_ref) plus the `ask_id` that files it. It
# describes the OPERATOR'S WORDS; it is not an assertion about the ask's repo,
# project, lifecycle status, title, or transcript pointer, so writing any of
# those would be a claim the verb never had grounds to make. Enforced two ways:
# every ledger verb passes "" positionally, AND self-test Scenario RL8 asserts
# the whole list generically (add a field to the fold list -> add it to RL8's
# list, not to six separate assertions).
#
# The title_source/candidate_id/classification fields are the
# cockpit-roadmap-redesign Task 2 (A2/A3/I6) additions; `deadline` and
# `default_action` are the accountable-estate-program-2026-07 Task 2
# additions — all always present, empty when not applicable; pre-existing
# records simply lack them and readers MUST treat a missing `title_source`
# as "auto" (legacy records are all machine-captured) and a missing/empty
# `deadline`/`default_action` as "none set".
#
# DEADLINE FOLD (BINDING on every reader — the deadline-equivalent of the
# title precedence exception above): `deadline` does NOT follow plain
# last-non-empty-wins. A reader folds ONLY the records whose `record_type`
# is `deadline_set` or `deadline_cleared`, sorted by `ts`, and takes the
# LAST one: if it is `deadline_set`, the ask's deadline is that record's
# `deadline` value; if it is `deadline_cleared`, the ask has NO deadline —
# REGARDLESS of any earlier `deadline_set` record's value. This carve-out
# exists for the same reason as the title exception: plain
# last-non-empty-wins can never represent "the deadline was explicitly
# removed" (a blank field would just be skipped, per the fold rule's own
# "blanks never overwrite" clause), so clearing needs its own record_type
# rather than a blank `deadline` on a generic record. `default_action`
# has NO such carve-out — it folds via plain last-non-empty-wins like
# `repo`/`project`, via any record (typically `default_action_set`) that
# carries a non-empty value.
#
# FOLD CONTRACT (append-only; the file is NEVER rewritten — every mutation
# is a NEW line): to compute an ask's CURRENT state, a reader iterates every
# record for a given `ask_id` in timestamp order and, for EACH FIELD
# independently, keeps the value from the MOST RECENT record in which that
# field is NON-EMPTY ("last-write-wins per field, blanks never overwrite").
#
# TITLE PRECEDENCE EXCEPTION (A3 — BINDING on every reader): the `summary`
# field (the item's TITLE) does NOT follow plain last-non-empty-wins.
# Operator-sourced title records (`title_source:"operator"`) ALWAYS outrank
# auto-sourced ones (`"auto"` or missing) REGARDLESS of timestamp — an
# async distiller re-run landing after an operator edit must never clobber
# it. Within the same source class, last-non-empty-wins as usual. Plain
# last-non-empty-wins is PROVEN insufficient here: capture t0 -> operator
# edit t1 -> async distiller lands t2>t1 would silently revert the
# operator's own edit (the exact race the architecture review's F3 names).
# The writer side also defends (see _ar_async_haiku_upgrade), but the fold
# rule is the contract.
#
# TITLE-BEARING RECORD TYPES (task-verifier FAIL fix — BINDING on every
# reader): the title-precedence fold above applies ONLY to `record_type
# == "created"` (the birth summary) and `record_type == "summary_updated"`
# (both the async distiller's auto upgrade AND `set-title`'s operator
# write — see cmd_set_title below). Every OTHER record_type that happens to
# carry a non-empty `summary` — most notably `candidate_classified` and
# `amended` (the A2 amendment timeline: `summary` there holds a distilled
# AMENDMENT LABEL, with `title_source` left empty) — is NOT title-bearing
# and MUST NOT be read into the folded title/title_source by any reader. A
# reader that tested "any non-empty summary" against ALL record_types (the
# original derive-lib.js/roadmap-routes.js bug this note documents) let an
# amendment label silently replace the ask's title.
#
# AMENDMENT TIMELINE (A2 — three buildable layers, honestly labeled):
#   (a) mechanical capture: `capture-candidate` appends EVERY operator
#       prompt of an ask-attached session (post-first) as an
#       `amendment_candidate` — transcript ref + minted candidate_id,
#       NEVER the raw text; classification starts "pending".
#   (b) classification: the SAME async off-hot-path LLM lane as the title
#       distiller (gate: ASK_SUMMARIZER=haiku) appends a
#       `candidate_classified` verdict (amendment + distilled label, or
#       noise). A failed/absent classifier leaves the candidate PENDING —
#       a named honest state, never a guess.
#   (c) correction: operator `detach-candidate` (classification=detached,
#       the I6 affordance) / `classify-candidate` re-marks; plus the
#       explicit `amend` verb as the model-invoked supplement (labeled
#       memory-dependent). Timeline fold: a candidate's CURRENT
#       classification is the LATEST candidate_classified record for its
#       candidate_id, else its birth "pending".
# HONEST LIMIT (state this in UI copy where the timeline renders):
# amendment detection is BEST-EFFORT classification, not a guarantee — no
# hook sees intent (UserPromptSubmit carries raw text only), and the
# `amend` verb fires only when a session remembers to call it.
#
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
# --- portable bounded subprocess (plan macos-portability-2026-07, M3) -----
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "ask-registry: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

_AR_VALID_STATUSES=(active done dismissed merged)
# Amendment-candidate classification vocabulary (cockpit-roadmap-redesign
# Task 2, A2/I6; `promoted` added 2026-07-30 — see DETERMINISTIC CLASSIFIER
# below). pending is the birth state stamped by capture-candidate itself;
# these four are the only values classify-candidate accepts.
#   amendment — the prompt changed/extended the ask's scope or direction
#   noise     — conversational (acks, questions, tangents); hidden by default
#   detached  — operator correction: "not an amendment" (I6 detach)
#   promoted  — the prompt was a SUBSTANTIVELY DIFFERENT request; it was
#               spun off into its own top-level ask (record_type "created")
#               rather than staying buried as a pending amendment of an
#               unrelated parent forever. `summary` on the candidate_classified
#               record holds the NEW ask_id it became (not a distilled label).
_AR_VALID_CLASSIFICATIONS=(amendment noise detached promoted)

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
# _ar_timeout_claude <seconds> <prompt...> — BOUNDED cheap-model fork.
# Added 2026-07-22 (harness-review Major): both async lanes forked
# `env -u CLAUDECODE claude --model haiku -p ...` with NO time bound. While
# the lane was dormant (ASK_SUMMARIZER unset by every caller) that cost
# nothing; workstreams-read.sh now DEFAULTS it on for every operator prompt in
# an ask-attached session, which turns a dormant unbounded fork into a live
# one that nothing reaps if it hangs. Async is not the same as bounded.
# House pattern borrowed from supervisor-tick.sh's `_st_run`. That pattern
# used to degrade to an UNBOUNDED call when `timeout` was absent — which is
# every stock Mac, since `timeout` is GNU coreutils. For a fork of a live
# model that is the worst possible degradation: the one call most likely to
# hang is the one that loses its bound. Both now route through
# nl_run_bounded (hooks/lib/portable-timeout.sh), which is bounded on every
# platform (plan macos-portability-2026-07, M3).
# `--model haiku -p` is BAKED IN here, not passed by callers (2026-07-22
# re-review of be037a7, Critical: the first extraction let call sites drop
# the flags — the lane forked the DEFAULT model with no print flag). This
# file's contract is hardcoded-cheap-model-only; a helper named *_claude
# that could fork anything else is the defect class, so the helper makes
# it unexpressable. AR_DRYRUN_ARGV=1 prints the argv instead of forking
# (self-test seam: the suite asserts the real invocation shape without
# ever risking a live model call).
# ----------------------------------------------------------------------
_ar_timeout_claude() {
  local secs="$1"; shift
  if [[ "${AR_DRYRUN_ARGV:-0}" == "1" ]]; then
    printf '%s ' "nl_run_bounded" "${secs}s" "env" "-u" "CLAUDECODE" "claude" "--model" "haiku" "-p" "$@"
    printf '\n'
    return 0
  fi
  nl_run_bounded "${secs}s" env -u CLAUDECODE claude --model haiku -p "$@"
}

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
# _ar_normalize_iso8601 <text> — parses <text> as a timestamp (GNU `date
# -d`, falling back to BSD `date -j -f '%Y-%m-%dT%H:%M:%SZ'`, the same
# parser family as estate-brief.sh's `_eb_age_str`) and prints it
# reformatted to canonical `%Y-%m-%dT%H:%M:%SZ` UTC. Prints nothing and
# returns 1 on ANY unparseable input — callers must treat that as
# rejection (no-op), never store the raw unparsed text. Normalizing at
# write time (rather than storing whatever the caller typed) guarantees
# every downstream jq reader's `fromdateiso8601` (this file's `sla` verb,
# estate-janitor.sh's ask-fold, estate-brief.sh's SLA panel) can parse
# every stored deadline without a second format dialect to support.
# ----------------------------------------------------------------------
_ar_normalize_iso8601() {
  local ts="$1"
  [[ -n "$ts" ]] || return 1
  local out
  out="$(date -u -d "$ts" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  if [[ -z "$out" ]]; then
    out="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  fi
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
  return 0
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
    # env -u CLAUDECODE: this lane is typically spawned from a hook INSIDE a
    # Claude Code session, where the CLI's nested-session guard refuses to
    # launch (PROVEN 2026-07-19: rc=1, stderr "cannot be launched inside
    # another Claude Code session", stdout empty — so degradation was silent
    # but the lane was DEAD from any hook context). The guard's own message
    # names unsetting CLAUDECODE as the bypass; a failure here still
    # degrades silently (empty stdout -> return 1).
    out="$(_ar_timeout_claude 20 "Summarize the following operator request in one plain-text sentence, no markdown, at most 140 characters: $text" 2>/dev/null)"
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
# _ar_has_operator_title <ask_id> — 0 (true) when the registry already
# holds an operator-sourced title record for this ask. Used by the async
# distiller as a WRITER-SIDE defense (A3): the binding rule remains the
# reader fold's operator-beats-auto precedence — this check just avoids
# appending records the fold would discard anyway, and protects any legacy
# reader that has not learned the precedence rule yet.
# ----------------------------------------------------------------------
_ar_has_operator_title() {
  local ask_id="$1"
  local f; f="$(ar_registry_file)"
  [[ -f "$f" ]] || return 1
  grep -q '"ask_id":"'"$(_ar_json_escape "$ask_id")"'".*"title_source":"operator"' "$f" 2>/dev/null
}

# ----------------------------------------------------------------------
# _ar_async_haiku_upgrade <ask_id> <raw-text> — backgrounds the haiku call
# + the follow-up registry append; NEVER blocks the calling `register`.
# A3 (cockpit-roadmap-redesign Task 2): the upgrade record stamps
# title_source=auto, and the append is SKIPPED entirely when an operator
# title already exists — a distiller (re-)run must never clobber an
# operator edit, regardless of timestamps.
# ----------------------------------------------------------------------
_ar_async_haiku_upgrade() {
  local ask_id="$1" text="$2"
  (
    local better
    better="$(_ar_haiku_summarize "$text")" || exit 0
    [[ -n "$better" ]] || exit 0
    _ar_has_operator_title "$ask_id" && exit 0
    _ar_append_record "summary_updated" "$ask_id" "" "" "" "$better" \
      "" "" "" "" "" "" "ask-registry-summarizer" "auto" "" "" >/dev/null
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ----------------------------------------------------------------------
# _ar_gen_candidate_id — cand-<YYYYMMDDTHHMMSS>-<4hex>. Identity for one
# timeline candidate row, so classification + operator correction (detach)
# can reference it. Collisions are as harmless as ask-id collisions.
# ----------------------------------------------------------------------
_ar_gen_candidate_id() {
  local ts_part; ts_part="$(date -u '+%Y%m%dT%H%M%S' 2>/dev/null || echo 'unknown')"
  local rand
  if [[ -r /dev/urandom ]]; then
    rand="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  else
    rand="$(printf '%04x' "$RANDOM")"
  fi
  printf 'cand-%s-%s' "$ts_part" "$rand"
}

# ----------------------------------------------------------------------
# _ar_classify_candidate_text <raw-text> — the classification half of the
# SAME async off-hot-path LLM lane the title distiller uses (A2 layer (b)).
# Prints EITHER "amendment: <one-line label>" OR "noise" on success; prints
# nothing and returns non-zero on ANY failure — callers must treat failure
# as "the candidate stays pending" (a named honest state), never crash.
# Cheap-model-only, same as the summarizer (model-tiering directive).
# Test-injection seam: _AR_CLASSIFY_CMD (self-test only; piped the raw
# text on stdin) — production code paths never set this variable.
# ----------------------------------------------------------------------
_ar_classify_candidate_text() {
  local text="$1"
  local out=""
  if [[ -n "${_AR_CLASSIFY_CMD:-}" ]]; then
    out="$(printf '%s' "$text" | eval "$_AR_CLASSIFY_CMD" 2>/dev/null)"
  elif command -v claude >/dev/null 2>&1; then
    # env -u CLAUDECODE: same nested-session-guard bypass as
    # _ar_haiku_summarize above (hook-spawned lane; failure degrades
    # silently to "candidate stays pending").
    out="$(_ar_timeout_claude 20 "You label operator prompts inside an ongoing request thread. Reply with EXACTLY 'amendment: <one plain-text sentence label, max 140 chars>' if the prompt changes, extends, or re-scopes the ongoing request; reply with EXACTLY 'noise' if it is conversational (acknowledgement, question, status check, tangent that changes nothing). The prompt: $text" 2>/dev/null)"
  else
    printf ''
    return 1
  fi
  out="$(_ar_strip_markdown "$out")"
  [[ -n "$out" ]] || { printf ''; return 1; }
  printf '%s' "$out"
  return 0
}

# ----------------------------------------------------------------------
# _ar_async_classify_candidate <ask_id> <candidate_id> <raw-text> —
# backgrounds classification + the candidate_classified append; NEVER
# blocks the calling `capture-candidate`. Unparseable model output (neither
# an "amendment"-prefixed line nor "noise") degrades to pending — the
# classifier writes a verdict record ONLY when it actually has one.
# ----------------------------------------------------------------------
_ar_async_classify_candidate() {
  local ask_id="$1" candidate_id="$2" text="$3"
  (
    local verdict
    verdict="$(_ar_classify_candidate_text "$text")" || exit 0
    [[ -n "$verdict" ]] || exit 0
    local lower; lower="$(printf '%s' "$verdict" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" == amendment* ]]; then
      local label=""
      case "$verdict" in *:*) label="${verdict#*:}" ;; esac
      label="$(printf '%s' "$label" | sed -E 's/^ +//; s/ +$//')"
      label="$(_ar_truncate140 "$label")"
      _ar_append_record "candidate_classified" "$ask_id" "" "" "" "$label" \
        "" "" "" "" "" "" "ask-registry-classifier" "" "$candidate_id" "amendment" >/dev/null
    elif [[ "$lower" == noise* ]]; then
      _ar_append_record "candidate_classified" "$ask_id" "" "" "" "" \
        "" "" "" "" "" "" "ask-registry-classifier" "" "$candidate_id" "noise" >/dev/null
    fi
    exit 0
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ----------------------------------------------------------------------
# DETERMINISTIC CLASSIFIER (2026-07-30 — URGENT operator-facing defect fix)
#
# PROVEN root cause: the LLM lane above (_ar_classify_candidate_text via
# `claude --model haiku`) hangs EVERY TIME it runs from a hook firing inside
# an already-live Claude Code session — `env -u CLAUDECODE claude --model
# haiku -p ...` does not fail fast; it hangs until nl_run_bounded's 20s
# bound kills it (reproduced directly: `timeout 25 env -u CLAUDECODE claude
# --model haiku -p "..." </dev/null` -> rc=124). Zero of the 114 real
# amendment_candidate records captured 2026-07-28..30 on this machine ever
# got a candidate_classified verdict — the LLM lane's own self-tests never
# caught this because they inject a FAKE _AR_CLASSIFY_CMD instead of ever
# shelling out to the real `claude` binary.
#
# This is the deterministic replacement: no model call, no network, no hang
# risk. It resolves both the candidate's and the parent ask's REAL verbatim
# text from their Claude Code session transcripts (workstreams-ui/server/
# verbatim-resolver.js — the registry itself never stores raw text, by this
# file's own long-standing design; resolution happens transiently here, in
# memory, never persisted) and classifies by lexical overlap:
#   - near-zero overlap + a substantive candidate -> "new-topic": the
#     candidate is spun off into its OWN top-level ask (record_type
#     "created") instead of staying buried as a pending amendment of an
#     unrelated parent forever (the operator's core complaint: a long
#     session accumulates dozens of unrelated requests, all silently filed
#     under the session's FIRST ask because pl_ask_id_for_session derives
#     ask_id 1:1 from session_id for the session's whole lifetime).
#   - a short/conversational candidate -> "noise" (hidden by default, same
#     as the pre-existing LLM-path vocabulary).
#   - otherwise -> "amendment" (extends the parent ask).
# A candidate whose text cannot be resolved (transcript missing/unreadable,
# timestamp out of tolerance) is left UNTOUCHED here — it falls through,
# SEQUENTIALLY (never as a second parallel writer — see LANE SEQUENCING on
# `_ar_async_deterministic_classify_candidate` below), to the (empirically
# dead, but still wired for the day the CLI's nested-session bug is fixed)
# LLM attempt, an honest degrade identical to today's behavior for anything
# this new path cannot decide.
# ----------------------------------------------------------------------
_ar_resolver_cli_path() {
  if [[ -n "${ASK_VERBATIM_RESOLVER_OVERRIDE:-}" ]]; then
    printf '%s' "$ASK_VERBATIM_RESOLVER_OVERRIDE"
    return 0
  fi
  # Prefer the copy that ships in the SAME checkout as this ask-registry.sh
  # (SCRIPT_DIR-relative: adapters/claude-code/scripts -> repo root ->
  # neural-lace/workstreams-ui/server/). Guarantees version parity between
  # this file's classifier wiring and the resolver's CLI contract, and —
  # unlike nl_workstreams_ui, which resolves via the per-machine
  # ~/.claude/local/nl-repo-path config and so points at the MAIN checkout
  # even when this script is running from a builder's worktree — it finds a
  # worktree-local resolver BEFORE that worktree is ever merged.
  local local_path="$SCRIPT_DIR/../../../neural-lace/workstreams-ui/server/verbatim-resolver.js"
  if [[ -f "$local_path" ]]; then
    printf '%s' "$local_path"
    return 0
  fi
  local ui_root=""
  if command -v nl_workstreams_ui >/dev/null 2>&1; then
    ui_root="$(nl_workstreams_ui)"
  fi
  [[ -n "$ui_root" ]] || { printf ''; return 0; }
  printf '%s/server/verbatim-resolver.js' "$ui_root"
}

# ----------------------------------------------------------------------
# _ar_async_deterministic_classify_candidate <ask_id> <candidate_id>
#   <verbatim_ref> <capture_ts> <session_id> <raw_text>
# Backgrounds resolution + classification + (on a confident verdict) the
# candidate_classified append, or a full `register` for a promoted
# new-topic candidate; NEVER blocks the calling `capture-candidate`.
# Degrades silently (leaves the candidate untouched, honest pending) on ANY
# failure: missing node, missing resolver script, missing registry file,
# unresolvable text, or a malformed JSON reply.
#
# LANE SEQUENCING (harness-reviewer Major 1, 2026-07-30): the (empirically
# 100%-dead-in-production) LLM lane is invoked HERE, sequentially, ONLY when
# this function's own resolution genuinely fails — never as a second,
# independently-scheduled writer racing this one on the same candidate_id
# fold key. Two async lanes appending candidate_classified for the SAME
# candidate_id under a latest-wins fold is a real corruption surface: if the
# CLI's nested-session bug is ever fixed upstream, an LLM verdict landing
# ~20s after a `promoted` deterministic verdict would silently override it,
# orphaning the freshly-registered top-level ask. Sequencing here (instead
# of `cmd_capture_candidate` firing both independently) makes that
# structurally impossible: the LLM attempt only ever runs AFTER this
# function has already given up, in the SAME subshell, never in parallel.
# ----------------------------------------------------------------------
_ar_async_deterministic_classify_candidate() {
  local ask_id="$1" candidate_id="$2" verbatim_ref="$3" capture_ts="$4" session_id="$5" raw_text="${6:-}"
  (
    _ar_llm_fallback() {
      if [[ "${ASK_SUMMARIZER:-}" == "haiku" && -n "$raw_text" ]]; then
        _ar_async_classify_candidate "$ask_id" "$candidate_id" "$raw_text"
      fi
    }
    command -v node >/dev/null 2>&1 || { _ar_llm_fallback; exit 0; }
    command -v jq >/dev/null 2>&1 || { _ar_llm_fallback; exit 0; }
    local resolver; resolver="$(_ar_resolver_cli_path)"
    [[ -n "$resolver" && -f "$resolver" ]] || { _ar_llm_fallback; exit 0; }
    local reg_file; reg_file="$(ar_registry_file)"
    [[ -f "$reg_file" ]] || { _ar_llm_fallback; exit 0; }

    local verdict_json
    verdict_json="$(nl_run_bounded 15s node "$resolver" classify "$reg_file" "$ask_id" "$verbatim_ref" "$capture_ts" 2>/dev/null)" || { _ar_llm_fallback; exit 0; }
    [[ -n "$verdict_json" ]] || { _ar_llm_fallback; exit 0; }
    local vok; vok="$(printf '%s' "$verdict_json" | jq -r '.ok // false' 2>/dev/null)"
    if [[ "$vok" != "true" ]]; then
      # Unresolved candidate text — the deterministic path has nothing to
      # decide on. Fall through to the LLM attempt (sequential, same
      # subshell) exactly as this function's header describes.
      _ar_llm_fallback
      exit 0
    fi

    local classification candidate_text
    classification="$(printf '%s' "$verdict_json" | jq -r '.classification // ""' 2>/dev/null)"
    candidate_text="$(printf '%s' "$verdict_json" | jq -r '.candidate_text // ""' 2>/dev/null)"
    [[ -n "$classification" ]] || exit 0

    case "$classification" in
      noise)
        _ar_append_record "candidate_classified" "$ask_id" "" "" "" "" \
          "" "" "" "" "" "" "ask-registry-classifier-deterministic" "" "$candidate_id" "noise" >/dev/null
        ;;
      new-topic)
        [[ -n "$candidate_text" ]] || exit 0
        local promo_summary; promo_summary="$(_ar_heuristic_summarize "$candidate_text")"
        [[ -n "$promo_summary" ]] || exit 0
        local new_ask_id; new_ask_id="$(_ar_gen_ask_id "$promo_summary")"
        cmd_register --ask-id "$new_ask_id" --summary "$promo_summary" \
          --session-id "$session_id" --verbatim-ref "$verbatim_ref" >/dev/null
        _ar_append_record "candidate_classified" "$ask_id" "" "" "" "$new_ask_id" \
          "" "" "" "" "" "" "ask-registry-classifier-deterministic" "" "$candidate_id" "promoted" >/dev/null
        ;;
      amendment)
        local label=""
        [[ -n "$candidate_text" ]] && label="$(_ar_heuristic_summarize "$candidate_text")"
        _ar_append_record "candidate_classified" "$ask_id" "" "" "" "$label" \
          "" "" "" "" "" "" "ask-registry-classifier-deterministic" "" "$candidate_id" "amendment" >/dev/null
        ;;
      *)
        exit 0
        ;;
    esac
    exit 0
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
#                    [<title_source>] [<candidate_id>] [<classification>]
#                    [<deadline>] [<default_action>]
#   The ONE writer every verb below calls: builds the flat JSON record,
#   appends it to the primary registry file, and best-effort mirrors it
#   (constraint 11). Never fails the caller. Prints the registry file path.
#   The ELEVEN trailing args are optional (three from cockpit-roadmap-
#   redesign Task 2, two from accountable-estate-program-2026-07 Task 2, and
#   SIX from the operator-requirement ledger): existing 13-arg call sites keep
#   working; the JSON always emits all 27 fields (empty when not applicable —
#   the flat all-fields convention).
# ----------------------------------------------------------------------
_ar_append_record() {
  local record_type="$1" ask_id="$2" status="$3" repo="$4" project="$5" \
        summary="$6" verbatim_ref="$7" origin_session="$8" plan_slug="$9"
  shift 9
  local session_id="$1" resumed_from="$2" merged_into="$3" emitter="$4"
  local title_source="${5:-}" candidate_id="${6:-}" classification="${7:-}"
  local deadline="${8:-}" default_action="${9:-}"
  # operator-requirement-ledger additions (SIX trailing optional args; every
  # pre-existing 13/18/21-arg call site keeps working unchanged).
  local requirement_id="${10:-}" verbatim="${11:-}" invariant_id="${12:-}"
  local invariant_text="${13:-}" invariant_verdict="${14:-}" evidence_ref="${15:-}"

  # ------------------------------------------------------------------
  # NON-EMPTY ask_id IS A STORE INVARIANT (harness-reviewer Critical 1,
  # 2026-07-29). `ask_id` is the GROUPING KEY of this store, not a field:
  # every reader groups by it. A record with ask_id "" does not describe a
  # missing ask — it silently JOINS a phantom one. PROVEN blast radius:
  # estate-janitor.sh's _ej_collect_asks does `group_by(.ask_id)` with no
  # guard, so all empty-id records across all time collapse into ONE
  # "active" ask that (a) can never be closed, because `set-status` itself
  # requires a non-empty --ask-id, and (b) never ages out, because its
  # folded last_ts refreshes on every subsequent empty-id write. It then
  # renders as a blank row in `estate-brief` and in `sla` forever. Sixteen
  # such records reached the shared store before this guard existed.
  #
  # The guard lives HERE, at the ONE writer every verb calls, and not in
  # the verbs: twelve verbs guarded `-z "$ask_id"` correctly and the two
  # newest did not, which is the recurring shape of a per-caller
  # convention. A writer-side invariant cannot be reintroduced by a
  # future verb author who simply does not know the convention exists.
  #
  # Honouring the never-blocks-caller contract: this refuses the WRITE and
  # returns 0 while printing NOTHING on stdout (callers capture the
  # registry path from stdout, so an empty capture is the in-band signal)
  # and a loud, actionable line on stderr.
  # ------------------------------------------------------------------
  if [[ -z "$ask_id" ]]; then
    echo "ask-registry.sh: REFUSING to append a '$record_type' record with an empty ask_id — ask_id is this store's grouping key and an empty one collapses into an uncloseable phantom ask in every reader (estate-janitor/estate-brief/sla). No record written; caller not blocked." >&2
    return 0
  fi

  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  local user machine
  user="$(git config user.name 2>/dev/null || true)"
  [[ -n "$user" ]] || user="${USER:-${USERNAME:-unknown}}"
  machine="$(hostname 2>/dev/null || echo unknown)"

  local json
  json="$(printf '{"ask_id":"%s","record_type":"%s","ts":"%s","user":"%s","machine":"%s","repo":"%s","project":"%s","summary":"%s","verbatim_ref":"%s","origin_session":"%s","status":"%s","plan_slug":"%s","session_id":"%s","resumed_from":"%s","merged_into":"%s","emitter":"%s","title_source":"%s","candidate_id":"%s","classification":"%s","deadline":"%s","default_action":"%s","requirement_id":"%s","verbatim":"%s","invariant_id":"%s","invariant_text":"%s","invariant_verdict":"%s","evidence_ref":"%s"}' \
    "$(_ar_json_escape "$ask_id")" "$(_ar_json_escape "$record_type")" "$ts" \
    "$(_ar_json_escape "$user")" "$(_ar_json_escape "$machine")" \
    "$(_ar_json_escape "$repo")" "$(_ar_json_escape "$project")" \
    "$(_ar_json_escape "$summary")" "$(_ar_json_escape "$verbatim_ref")" \
    "$(_ar_json_escape "$origin_session")" "$(_ar_json_escape "$status")" \
    "$(_ar_json_escape "$plan_slug")" "$(_ar_json_escape "$session_id")" \
    "$(_ar_json_escape "$resumed_from")" "$(_ar_json_escape "$merged_into")" \
    "$(_ar_json_escape "$emitter")" "$(_ar_json_escape "$title_source")" \
    "$(_ar_json_escape "$candidate_id")" "$(_ar_json_escape "$classification")" \
    "$(_ar_json_escape "$deadline")" "$(_ar_json_escape "$default_action")" \
    "$(_ar_json_escape "$requirement_id")" "$(_ar_json_escape "$verbatim")" \
    "$(_ar_json_escape "$invariant_id")" "$(_ar_json_escape "$invariant_text")" \
    "$(_ar_json_escape "$invariant_verdict")" "$(_ar_json_escape "$evidence_ref")")"

  local f dir
  f="$(ar_registry_file)"
  dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null && printf '%s\n' "$json" >> "$f" 2>/dev/null

  _ar_mirror_append "$json"

  # cockpit-roadmap-redesign Task 7 (A5 iii): every registry append is a
  # publish-worthy state change — touch the coordination dirty marker at
  # THIS writer seam (the ONE writer every verb calls), so the GUI's own
  # delegated CLI writes (lifecycle, title edits) and every future verb are
  # covered without any hook splice. pl_mark_coord_dirty lives in
  # progress-log-lib.sh (sourced above when present); guarded so a missing
  # lib never breaks an append (never-blocks contract). Verbs that ALSO call
  # pl_emit double-touch the marker — harmless (idempotent overwrite).
  if declare -F pl_mark_coord_dirty >/dev/null 2>&1; then
    pl_mark_coord_dirty "ask-registry:$record_type"
  fi

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

  # title_source=auto ALWAYS on created records: registration is machine
  # capture (hooks) even when --summary is verbatim; the operator's own
  # title path is `set-title`, which stamps operator (A3).
  local f
  f="$(_ar_append_record "created" "$ask_id" "active" "$repo" "$project" \
    "$summary" "$verbatim_ref" "$session_id" "" "$session_id" "" "" "ask-registry" \
    "auto" "" "")"

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
# cmd_merge — now accepts --emitter (cockpit-roadmap-redesign Task 2,
# closing the follow-up server.js:1044-1050 documents: the UI's merge
# delegation could not label itself operator-ui). Default stays
# "ask-registry" so every existing flagless caller is byte-identical.
# ----------------------------------------------------------------------
cmd_merge() {
  local ask_id="" into="" emitter="ask-registry"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --into) into="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
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
    "$into" "$emitter"
  return 0
}

# ----------------------------------------------------------------------
# cmd_set_title — the operator's title edit path (A3, round 3: auto-name
# always, operator-editable always, no confirm ceremony). Appends a
# summary_updated record with title_source=operator; the reader fold's
# operator-beats-auto precedence makes this edit permanent against any
# later distiller re-run. The UI's title edit MUST delegate here (the same
# one-writer-implementation discipline as the lifecycle endpoint,
# server.js runAskRegistryCli) — never write the registry directly.
# ----------------------------------------------------------------------
cmd_set_title() {
  local ask_id="" title="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$title" ]]; then
    echo "ask-registry.sh set-title: --ask-id and a non-empty --title are required (no-op; never blocks caller)" >&2
    return 0
  fi
  title="$(_ar_truncate140 "$title")"
  _ar_append_record "summary_updated" "$ask_id" "" "" "" "$title" "" "" "" \
    "" "" "" "$emitter" "operator" "" ""
  return 0
}

# ----------------------------------------------------------------------
# cmd_capture_candidate — A2 layer (a), mechanical capture: append one
# operator prompt of an ask-attached session as a timeline CANDIDATE.
# Stores the transcript ref + minted candidate_id ONLY — never the raw
# text (the registry stays small). Classification (layer (b), 2026-07-30
# update) is now UNCONDITIONAL and gate-free: `_ar_async_deterministic_
# classify_candidate` always attempts the deterministic (no model call)
# classifier first, sequentially falling back to the ASK_SUMMARIZER=haiku
# LLM lane (the SAME gate as the title distiller — proven dead in
# production, kept wired as a fallback) ONLY when its own resolution
# genuinely fails — see that function's own LANE SEQUENCING comment for
# why the two lanes never run as independent, racing writers. --text, when
# given, is passed through for that fallback and otherwise unused (the
# deterministic lane resolves its own text from the transcript). A
# candidate neither lane can decide stays classification=pending: a named
# honest state, never a guess.
# ----------------------------------------------------------------------
cmd_capture_candidate() {
  local ask_id="" candidate_id="" session_id="" verbatim_ref="" text=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --candidate-id) candidate_id="${2:-}"; shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --verbatim-ref) verbatim_ref="${2:-}"; shift 2 ;;
      --text) text="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$verbatim_ref" ]]; then
    echo "ask-registry.sh capture-candidate: --ask-id and --verbatim-ref are required (no-op; never blocks caller)" >&2
    return 0
  fi
  [[ -n "$candidate_id" ]] || candidate_id="$(_ar_gen_candidate_id)"
  local capture_ts; capture_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo 'unknown')"
  _ar_append_record "amendment_candidate" "$ask_id" "" "" "" "" \
    "$verbatim_ref" "" "" "$session_id" "" "" "ask-capture" \
    "" "$candidate_id" "pending"
  # Deterministic classification (2026-07-30 fix) ALWAYS attempted — no
  # model call, no ASK_SUMMARIZER gate needed (that gate is specifically
  # about the LLM lane, invoked ONLY as a sequential fallback INSIDE this
  # same call when resolution genuinely fails — see LANE SEQUENCING on
  # `_ar_async_deterministic_classify_candidate`'s own header: two
  # independently-scheduled async writers appending candidate_classified
  # for the same candidate_id under a latest-wins fold is a real corruption
  # surface, so `$text` is threaded through here rather than the old
  # separate `_ar_async_classify_candidate` call site racing this one).
  # Runs async/backgrounded so a slow/growing transcript never adds latency
  # to this hot UserPromptSubmit-adjacent path.
  _ar_async_deterministic_classify_candidate "$ask_id" "$candidate_id" "$verbatim_ref" "$capture_ts" "$session_id" "$text"
  return 0
}

# ----------------------------------------------------------------------
# cmd_classify_candidate — A2 layers (b)+(c): the classification verdict
# writer, used by the async lane (emitter=ask-registry-classifier) and by
# operator corrections (emitter=operator-ui). Vocabulary-validated; the
# LATEST candidate_classified record for a candidate_id wins at fold time.
# ----------------------------------------------------------------------
cmd_classify_candidate() {
  local ask_id="" candidate_id="" classification="" summary="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --candidate-id) candidate_id="${2:-}"; shift 2 ;;
      --classification) classification="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$candidate_id" || -z "$classification" ]]; then
    echo "ask-registry.sh classify-candidate: --ask-id, --candidate-id and --classification are required (no-op; never blocks caller)" >&2
    return 0
  fi
  if ! _ar_in_list "$classification" "${_AR_VALID_CLASSIFICATIONS[@]}"; then
    echo "ask-registry.sh classify-candidate: invalid --classification '$classification' (must be one of: amendment|noise|detached|promoted) — no-op, never blocks caller" >&2
    return 0
  fi
  [[ -n "$summary" ]] && summary="$(_ar_truncate140 "$summary")"
  _ar_append_record "candidate_classified" "$ask_id" "" "" "" "$summary" \
    "" "" "" "" "" "" "$emitter" "" "$candidate_id" "$classification"
  return 0
}

# ----------------------------------------------------------------------
# cmd_detach_candidate — I6's detach affordance: operator marks an
# auto-captured row "not an amendment". Thin wrapper over
# classify-candidate (classification=detached); the correction record is
# durable and available to future classifier improvement — today's
# classifier does NOT consume it live (best-effort honesty, stated).
# ----------------------------------------------------------------------
cmd_detach_candidate() {
  local ask_id="" candidate_id="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --candidate-id) candidate_id="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  cmd_classify_candidate --ask-id "$ask_id" --candidate-id "$candidate_id" \
    --classification "detached" --emitter "$emitter"
  return 0
}

# ----------------------------------------------------------------------
# cmd_amend — A2 layer (c)'s explicit verb: the model-invoked supplement
# for when a session KNOWS the conversation amended the ask (labeled
# memory-dependent — it fires only when the model remembers to call it,
# which is exactly why it supplements rather than replaces the mechanical
# capture lane). Appends a first-class `amended` record: classification=
# amendment at birth, label from --summary (verbatim, capped) or
# heuristic-distilled from --text. Text is never stored raw.
# ----------------------------------------------------------------------
cmd_amend() {
  local ask_id="" text="" summary="" session_id="" verbatim_ref="" emitter="model"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --text) text="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --verbatim-ref) verbatim_ref="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" ]]; then
    echo "ask-registry.sh amend: --ask-id is required (no-op; never blocks caller)" >&2
    return 0
  fi
  local label=""
  if [[ -n "$summary" ]]; then
    label="$(_ar_truncate140 "$summary")"
  elif [[ -n "$text" ]]; then
    label="$(_ar_heuristic_summarize "$text")"
  fi
  if [[ -z "$label" ]]; then
    echo "ask-registry.sh amend: one of --summary or --text (non-empty) is required (no-op; never blocks caller)" >&2
    return 0
  fi
  local candidate_id; candidate_id="$(_ar_gen_candidate_id)"
  _ar_append_record "amended" "$ask_id" "" "" "" "$label" \
    "$verbatim_ref" "" "" "$session_id" "" "" "$emitter" \
    "" "$candidate_id" "amendment"
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

# ----------------------------------------------------------------------
# cmd_set_deadline — accountable-estate-program-2026-07 Task 2. Validates
# + normalizes --deadline (see _ar_normalize_iso8601); an unparseable
# value is REJECTED (no-op, stderr note, exit 0 — never a malformed
# deadline persisted, same discipline as set-status's vocabulary check).
# ----------------------------------------------------------------------
cmd_set_deadline() {
  local ask_id="" deadline="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --deadline) deadline="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$deadline" ]]; then
    echo "ask-registry.sh set-deadline: --ask-id and --deadline are required (no-op; never blocks caller)" >&2
    return 0
  fi
  local normalized
  if ! normalized="$(_ar_normalize_iso8601 "$deadline")"; then
    echo "ask-registry.sh set-deadline: --deadline '$deadline' is not a parseable timestamp — no-op, never blocks caller" >&2
    return 0
  fi
  _ar_append_record "deadline_set" "$ask_id" "" "" "" "" "" "" "" \
    "" "" "" "$emitter" "" "" "" "$normalized" ""
  return 0
}

# ----------------------------------------------------------------------
# cmd_clear_deadline — appends deadline_cleared; see DEADLINE FOLD in the
# header SCHEMA section for why this needs its own record_type rather
# than a blank deadline on a generic record.
# ----------------------------------------------------------------------
cmd_clear_deadline() {
  local ask_id="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" ]]; then
    echo "ask-registry.sh clear-deadline: --ask-id is required (no-op; never blocks caller)" >&2
    return 0
  fi
  _ar_append_record "deadline_cleared" "$ask_id" "" "" "" "" "" "" "" \
    "" "" "" "$emitter" "" "" "" "" ""
  return 0
}

# ----------------------------------------------------------------------
# cmd_set_default_action — records the disposition to apply if the
# deadline passes unanswered, AS DATA (this slice ships visibility only;
# no automatic side-effect reads/acts on this field yet — Program rule 3
# of docs/plans/accountable-estate-program-2026-07.md's binding rules is
# observe-first before any enforcement flip, same discipline as the
# admission lib's T3/T6 split).
# ----------------------------------------------------------------------
cmd_set_default_action() {
  local ask_id="" default_action="" emitter="operator-ui"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --default-action) default_action="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ -z "$ask_id" || -z "$default_action" ]]; then
    echo "ask-registry.sh set-default-action: --ask-id and a non-empty --default-action are required (no-op; never blocks caller)" >&2
    return 0
  fi
  default_action="$(_ar_truncate140 "$default_action")"
  _ar_append_record "default_action_set" "$ask_id" "" "" "" "" "" "" "" \
    "" "" "" "$emitter" "" "" "" "" "$default_action"
  return 0
}

# ----------------------------------------------------------------------
# cmd_sla — read-only SLA read-out (accountable-estate-program-2026-07
# Task 2). Folds every ACTIVE ask's deadline (DEADLINE FOLD rule) +
# default_action (plain last-non-empty-wins) and prints one TSV row per
# ask: ask_id, sla_state, deadline, default_action, summary — sorted
# soonest-deadline-first (undated last). Honest degrade (stderr note,
# exit 0, never a crash) when jq is missing or no registry exists yet.
# ----------------------------------------------------------------------
cmd_sla() {
  local now_override="" due_soon_hours="${ESTATE_ASK_SLA_DUE_SOON_HOURS:-48}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --now) now_override="${2:-}"; shift 2 ;;
      --due-soon-hours) due_soon_hours="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ "$due_soon_hours" =~ ^[0-9]+$ ]] || due_soon_hours=48

  local f; f="$(ar_registry_file)"
  if [[ ! -f "$f" ]]; then
    echo "ask-registry.sh sla: no registry file at $f (no asks registered yet)" >&2
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ask-registry.sh sla: jq is not available; cannot compute SLA states" >&2
    return 0
  fi

  local now_epoch=""
  if [[ -n "$now_override" ]]; then
    now_epoch="$(date -u -d "$now_override" '+%s' 2>/dev/null)"
    [[ -n "$now_epoch" ]] || now_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$now_override" '+%s' 2>/dev/null)"
  fi
  if [[ -z "$now_epoch" ]]; then
    now_epoch="$(date -u '+%s' 2>/dev/null || echo 0)"
  fi

  printf 'ask_id\tsla_state\tdeadline\tdefault_action\tsummary\n'
  # Same failed-read-is-not-an-empty-read guard as _ar_invariant_rows
  # (harness-reviewer Critical 2 sweep — "apply to any other jq reader over
  # this store"). A torn line here used to render as a header with no rows,
  # i.e. "nothing is overdue" — the SLA read-out's worst possible lie. The two
  # pre-existing degrade paths above (no registry / no jq) keep their
  # documented exit 0 because those are KNOWN-EMPTY states; an unparseable
  # store is a different thing and gets the same CANNOT-EVALUATE 4 the ledger
  # uses. No caller reads this exit code programmatically (estate-janitor
  # folds the JSONL itself), so this only ever adds signal.
  local _sla _slarc
  _sla="$(jq -s -r --argjson now "$now_epoch" --argjson duesoon "$due_soon_hours" '
    group_by(.ask_id) | map(
      (map(select(.ts != null and .ts != "")) | sort_by(.ts)) as $s |
      {
        ask_id: $s[0].ask_id,
        status: ([$s[] | select((.status // "") != "")][-1].status // "active"),
        summary: (
          (([$s[] | select((.record_type=="created" or .record_type=="summary_updated") and .title_source=="operator" and ((.summary // "") != ""))])[-1].summary) //
          (([$s[] | select((.record_type=="created" or .record_type=="summary_updated") and ((.summary // "") != ""))])[-1].summary) // ""
        ),
        deadline: (
          ([$s[] | select(.record_type=="deadline_set" or .record_type=="deadline_cleared")][-1]) as $dl |
          if $dl == null then "" elif $dl.record_type=="deadline_cleared" then "" else ($dl.deadline // "") end
        ),
        default_action: ([$s[] | select((.default_action // "") != "")][-1].default_action // "")
      }
    )
    | map(select(.status=="active"))
    | map(. + {
        _epoch: ((.deadline // "") as $d | if $d == "" then null else ($d | try fromdateiso8601 catch null) end)
      })
    | map(. + {
        sla_state: (
          if ._epoch == null then "no-deadline"
          elif ._epoch < $now then "overdue"
          elif (._epoch - $now) <= ($duesoon * 3600) then "due-soon"
          else "ok" end
        )
      })
    | sort_by([(if ._epoch == null then 1 else 0 end), (._epoch // 0)])
    | .[]
    | "\(.ask_id)\t\(.sla_state)\t\(.deadline)\t\(.default_action)\t\(.summary)"
  ' "$f")"; _slarc=$?
  if [[ "$_slarc" != "0" ]]; then
    echo "ask-registry.sh sla: jq exited $_slarc reading $f — the SLA table CANNOT be computed (a torn/truncated JSONL line does this). An empty table here would read as 'nothing is overdue'; it is not. NOT a pass." >&2
    return 4
  fi
  [[ -n "$_sla" ]] && printf '%s\n' "$_sla"
  return 0
}

# ======================================================================
# OPERATOR-REQUIREMENT LEDGER — verbs
# See the SCHEMA header's "OPERATOR-REQUIREMENT LEDGER" block for the golden
# case, the VERDICT FOLD rule, and the SUMMARY-FIELD ABSTENTION rule.
# ======================================================================

# Hard cap on a stored verbatim requirement. Deliberately large: the point of
# the ledger is that the operator's sentence survives UNPARAPHRASED, so this
# bounds a pathological paste and nothing else. It is NOT _ar_truncate140 —
# that helper sentence-splits and ellipsises, which is precisely the lossy
# step the ledger exists to prevent.
_AR_VERBATIM_MAX=4000
_AR_INVARIANT_MAX=600

# _ar_truncate_hard <max> <text> — CHARACTER-count cap, no sentence logic, no
# ellipsis-on-word-boundary. Content-preserving by construction.
#
# CHARACTERS, NOT BYTES (comment corrected 2026-07-29, harness-reviewer
# Major 5): `${#s}` and `${s:0:$max}` count CHARACTERS under a UTF-8 locale
# (bytes only under LC_ALL=C). The header used to call this a "byte-count cap",
# which understates the real ceiling by up to 4x on multibyte input — a 4000-
# character cap admits ~16000 bytes of emoji. The bound is therefore stated in
# characters and the store must be assumed to hold up to 4x that in bytes.
#
# THE CAP LEAVES A MARK (harness-reviewer Major 5). This used to clip
# VERBATIM with no marker, so a 10240-char requirement, a 4001-char one, and a
# genuine 4000-char one were byte-identical in the store — silent loss on a
# field whose entire contract is losslessness, and long multi-clause pastes are
# precisely the highest-invariant-density inputs. A reader (human or agent) now
# always knows it is looking at a fragment, and knows exactly how much is gone.
# The sentinel is appended AFTER the clipped content rather than inside the cap
# so that "the first <max> characters are preserved exactly" stays a clean,
# testable contract; the stored value's real ceiling is max + ~34 chars.
_ar_truncate_hard() {
  local max="$1" s="$2"
  if [[ "${#s}" -le "$max" ]]; then
    printf '%s' "$s"
  else
    printf '%s [TRUNCATED: %s chars omitted]' "${s:0:$max}" "$(( ${#s} - max ))"
  fi
}

# _ar_repeat_char <n> — emit exactly <n> 'A' characters. Self-test helper for
# the truncation-boundary scenarios (RL22). `printf '%*s'` + tr is used rather
# than brace expansion ({1..4001} is unavailable with a variable bound in bash
# 3.2) or `seq` (not guaranteed present) — identical output on 3.2 and 5.x.
_ar_repeat_char() {
  printf '%*s' "$1" '' | tr ' ' 'A'
}

_ar_gen_requirement_id() {
  local date_part; date_part="$(date -u '+%Y%m%d' 2>/dev/null || echo 'unknown')"
  local rand
  if [[ -r /dev/urandom ]]; then
    rand="$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  else
    rand="$(printf '%06x' "$RANDOM")"
  fi
  printf 'req-%s-%s' "$date_part" "$rand"
}

# _ar_next_invariant_id <requirement_id> — sequential inv-N within a
# requirement. grep-based so it works with no jq present (declaring an
# invariant must never depend on the reader toolchain).
_ar_next_invariant_id() {
  local rid="$1" f n
  f="$(ar_registry_file)"
  n=0
  if [[ -f "$f" ]]; then
    n="$(grep -ac "\"record_type\":\"invariant_declared\".*\"requirement_id\":\"${rid}\"" "$f" 2>/dev/null || echo 0)"
    n="$(printf '%s' "$n" | tr -d ' \n')"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
  fi
  printf 'inv-%s' "$((n + 1))"
}

# ----------------------------------------------------------------------
# _ar_requirement_ask_id <requirement_id> — REFERENTIAL INTEGRITY + ask_id
# resolution in ONE lookup (harness-reviewer Critical 3 + Critical 1,
# 2026-07-29).
#
# Prints the ask_id of the newest `requirement_recorded` record bearing this
# requirement_id and returns 0. Returns 1 (printing nothing) when no such
# requirement exists — which is the caller's cue to no-op.
#
# WHY THIS IS THE LEDGER'S OWN GOLDEN CASE. `declare-invariant` used to accept
# ANY --requirement-id. A typo'd id was written happily, printed `inv-1` — a
# SUCCESS CONFIRMATION — and was then invisible to BOTH selectors task-verifier
# actually uses (`--plan-slug` and `--ask-id`, which reach invariants only by
# resolving requirement_recorded -> ask). `invariant-check` therefore reported
# exit 3 "nothing registered", which task-verifier Step 1.6 routes to "the
# common case and NOT a failure signal ... proceed". A clause was silently
# dropped and the checker faithfully reported green: EXACTLY the failure class
# this ledger was built to prevent, reproduced inside the ledger itself.
#
# WHY RESOLVE ask_id HERE RATHER THAN REQUIRE --ask-id (Critical 1, the
# writer-side half). The requirement_id already DETERMINES the ask, so making
# callers repeat it is connascence of value between two arguments: two ways to
# say one thing, and nothing forces them to agree. Requiring `--ask-id` would
# have stopped the EMPTY id but still admitted a WRONG one — filing an
# invariant under an unrelated ask, which is harder to see than a blank row.
# Resolving from the requirement record makes both states unrepresentable, and
# is free: the Critical-3 existence check must perform this exact lookup
# anyway. It is also the strictly kinder calling convention for the agents that
# use these verbs, which is the operator's stated preference.
#
# grep-based, deliberately: declaring an invariant must never depend on the
# READER toolchain (same rule as _ar_next_invariant_id above — jq is required
# to READ the ledger, never to WRITE it). `grep -a` because a stored verbatim
# is arbitrary operator text and a lone control byte must not make grep treat
# the store as binary and silently report nothing.
#
# The field-order assumption (`record_type` precedes `requirement_id`, and
# `ask_id` is the FIRST key) is the same one _ar_next_invariant_id already
# relies on, and it is guaranteed by the single printf in _ar_append_record.
# ----------------------------------------------------------------------
_ar_requirement_ask_id() {
  local rid="$1" f line aid
  [[ -n "$rid" ]] || return 1
  f="$(ar_registry_file)"
  [[ -f "$f" ]] || return 1
  line="$(grep -a "\"record_type\":\"requirement_recorded\".*\"requirement_id\":\"${rid}\"" "$f" 2>/dev/null | tail -1)"
  [[ -n "$line" ]] || return 1
  # `{"ask_id":"<escaped>","record_type":...` — strip to the first value.
  # %% (longest suffix) yields the SHORTEST prefix, so an ask_id that somehow
  # contained the delimiter text cannot over-consume.
  aid="${line#*\"ask_id\":\"}"
  aid="${aid%%\",\"record_type\":\"*}"
  [[ -n "$aid" ]] || return 1
  printf '%s' "$aid"
  return 0
}

# ----------------------------------------------------------------------
# _ar_invariant_rows <sel_kind> <sel> — THE shared reader. Emits one TSV row
# per declared invariant:
#   requirement_id \t invariant_id \t verdict \t evidence_ref \t
#   invariant_text \t verbatim
# `verdict` is the VERDICT FOLD result, or the literal `unverified` when no
# verdict record exists (absence is never a pass).
# Exit 0 = evaluated (row set may be empty). Exit 4 = CANNOT EVALUATE.
# Both text columns are scrubbed of tab/newline so the TSV stays line-oriented
# even when the operator's sentence contains them.
# ----------------------------------------------------------------------
_ar_invariant_rows() {
  local sel_kind="$1" sel="$2"
  local f; f="$(ar_registry_file)"
  if [[ ! -f "$f" ]]; then
    echo "ask-registry.sh: no registry file at $f — cannot evaluate invariants" >&2
    return 4
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ask-registry.sh: jq is not available — cannot evaluate invariants" >&2
    return 4
  fi
  # A FAILED READ IS NOT AN EMPTY READ (harness-reviewer Critical 2,
  # 2026-07-29). jq's exit status used to be discarded by an unconditional
  # `return 0` after this pipeline. One torn or truncated JSONL line — the
  # normal outcome of an interrupted append to an append-only store — makes jq
  # exit non-zero having emitted nothing, so the row set came back EMPTY and
  # cmd_invariant_check read that as "no invariants registered" => exit 3.
  # task-verifier Step 1.6 routes exit 3 to "the common case and NOT a failure
  # signal ... proceed". Net effect, reproduced by the reviewer with a single
  # appended `{"ask_id":"truncated-partial-write` line: a `violated` invariant
  # became a silent PASS. That is the degrade-reads-as-green shape this whole
  # ledger exists to answer, so the status is captured and mapped to 4
  # (CANNOT EVALUATE), which no caller may treat as a pass. jq's own parse
  # error is left on stderr, unswallowed, because it names the bad line.
  local _rows _rc
  _rows="$(jq -s -r --arg selkind "$sel_kind" --arg sel "$sel" '
    # EVERY emitted cell is scrubbed of tab/newline AND guaranteed non-blank
    # (blank -> "-"). The non-blank guarantee is load-bearing, not cosmetic:
    # TAB is an IFS-WHITESPACE character, so bash `read -r a b c` COLLAPSES a
    # run of tabs into one delimiter and silently shifts every later column.
    # An empty evidence_ref on an unverified invariant would therefore print
    # the invariant text in the evidence slot. Emitting "-" keeps the row
    # parseable by bash read, awk and cut alike.
    def cell: (. // "") | gsub("[\t\r\n]"; " ")
              | if test("^ *$") then "-" else . end;
    (to_entries | map(.value + {_i: .key})) as $all |

    # --- selector resolution -------------------------------------------
    (if $selkind == "requirement" then [$sel]
     elif $selkind == "ask" then
       [ $all[] | select(.record_type == "requirement_recorded" and .ask_id == $sel)
               | .requirement_id ]
     elif $selkind == "plan" then
       ([ $all[] | select(.record_type == "plan_linked" and (.plan_slug // "") == $sel)
                 | .ask_id ] | unique) as $askids |
       [ $all[] | select(.record_type == "requirement_recorded"
                         and ((.ask_id // "") | IN($askids[])))
               | .requirement_id ]
     else
       [ $all[] | select(.record_type == "requirement_recorded") | .requirement_id ]
     end | map(select(. != null and . != "")) | unique) as $reqids |

    # --- verbatim per requirement (last requirement_recorded wins) ------
    ( reduce ($all[] | select(.record_type == "requirement_recorded")) as $r
        ({}; .[$r.requirement_id] = ($r.verbatim // "")) ) as $verbatim |

    # --- declared invariants (last declaration of an id wins its text) --
    ( reduce ($all[] | select(.record_type == "invariant_declared")
                     | select((.requirement_id // "") | IN($reqids[]))) as $d
        ({}; .[$d.requirement_id + " " + $d.invariant_id] = $d) ) as $decl |

    # --- VERDICT FOLD: sort by [ts, append-index], last wins ------------
    ( reduce ( [ $all[] | select(.record_type == "invariant_verdict") ]
               | sort_by([.ts, ._i]) | .[] ) as $v
        ({}; .[$v.requirement_id + " " + $v.invariant_id] = $v) ) as $verd |

    ( $decl | keys_unsorted | sort ) as $ks |
    $ks[] as $k |
    $decl[$k] as $d |
    ($verd[$k] // null) as $v |
    [ ($d.requirement_id | cell),
      ($d.invariant_id | cell),
      (if $v == null or (($v.invariant_verdict // "") == "")
       then "unverified" else $v.invariant_verdict end),
      (if $v == null then "-" else ($v.evidence_ref | cell) end),
      ($d.invariant_text | cell),
      ($verbatim[$d.requirement_id] | cell)
    ] | @tsv
  ' "$f")"; _rc=$?
  if [[ "$_rc" != "0" ]]; then
    echo "ask-registry.sh: jq exited $_rc reading $f — the ledger CANNOT be evaluated (a torn/truncated JSONL line does this; see jq's parse error above). This is NOT 'no invariants registered' and NOT a pass." >&2
    return 4
  fi
  [[ -n "$_rows" ]] && printf '%s\n' "$_rows"
  return 0
}

# ----------------------------------------------------------------------
# cmd_record_requirement — store the operator's sentence VERBATIM.
# ----------------------------------------------------------------------
cmd_record_requirement() {
  local ask_id="" verbatim="" requirement_id="" session_id="" \
        emitter="model" repo="" project=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --verbatim) verbatim="${2:-}"; shift 2 ;;
      --requirement-id) requirement_id="${2:-}"; shift 2 ;;
      # --verbatim-ref REMOVED (harness-reviewer Major 6, 2026-07-29).
      # `verbatim_ref` is a FOLD-LIST field (derive-lib.js:110,
      # auditor.js:302, requests-routes.js:148 fold it last-non-empty-wins),
      # so accepting it here let `record-requirement` silently REPLACE the
      # ask's pointer to the original operator prompt — the one artifact this
      # ledger exists to keep reachable. It is kept as an EXPLICIT rejected
      # case rather than deleted so that (a) the `shift 2` stays correct and
      # later flags still parse, and (b) a caller carrying the old flag is
      # TOLD, instead of having it silently eaten by the `*)` arm.
      --verbatim-ref)
        echo "ask-registry.sh record-requirement: --verbatim-ref is not accepted here (it is a fold-list field; writing it would overwrite the ask's pointer to the ORIGINAL operator prompt — see FOLD-FIELD ABSTENTION in the schema header). Flag ignored; the requirement itself is still recorded. Use \`register --verbatim-ref\` to set an ask's pointer." >&2
        shift 2 ;;
      --session-id) session_id="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$ask_id" || -z "$verbatim" ]]; then
    echo "ask-registry.sh record-requirement: --ask-id and --verbatim are required (no-op; never blocks caller)" >&2
    return 0
  fi

  verbatim="$(_ar_truncate_hard "$_AR_VERBATIM_MAX" "$verbatim")"
  [[ -n "$requirement_id" ]] || requirement_id="$(_ar_gen_requirement_id)"

  # EVERY fold-list field is deliberately EMPTY here: status, repo, project,
  # verbatim_ref, summary, title_source (FOLD-FIELD ABSTENTION, schema header).
  _ar_append_record "requirement_recorded" "$ask_id" "" "$repo" "$project" \
    "" "" "$session_id" "" "$session_id" "" "" "$emitter" \
    "" "" "" "" "" "$requirement_id" "$verbatim" "" "" "" "" >/dev/null

  if command -v pl_emit >/dev/null 2>&1; then
    pl_emit --type requirement_recorded --ask "$ask_id" --session-id "$session_id" \
      --emitter ask-registry >/dev/null 2>&1 || true
  fi

  printf '%s' "$requirement_id"
  return 0
}

# ----------------------------------------------------------------------
# cmd_declare_invariant — one separately-checkable statement.
# ----------------------------------------------------------------------
cmd_declare_invariant() {
  local requirement_id="" text="" invariant_id="" ask_id="" emitter="model"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --requirement-id) requirement_id="${2:-}"; shift 2 ;;
      --text) text="${2:-}"; shift 2 ;;
      --invariant-id) invariant_id="${2:-}"; shift 2 ;;
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$requirement_id" || -z "$text" ]]; then
    echo "ask-registry.sh declare-invariant: --requirement-id and --text are required (no-op; never blocks caller)" >&2
    return 0
  fi

  # REFERENTIAL INTEGRITY + ask_id RESOLUTION (Critical 3 + Critical 1).
  # A requirement_id that names no requirement_recorded is refused OUTRIGHT:
  # it would print `inv-1` — a success confirmation — while being unreachable
  # from both selectors task-verifier uses, so the clause silently vanishes
  # and invariant-check reports exit 3 "nothing registered" => proceed.
  # The same lookup yields the authoritative ask_id, which is why --ask-id is
  # no longer read from the caller (see _ar_requirement_ask_id's header).
  local resolved_ask
  if ! resolved_ask="$(_ar_requirement_ask_id "$requirement_id")"; then
    echo "ask-registry.sh declare-invariant: no requirement_recorded exists with --requirement-id '$requirement_id' — refusing to declare an invariant against a requirement that was never recorded (it would be unreachable from --ask-id/--plan-slug and would make invariant-check report 'nothing registered'). Record the requirement first: record-requirement --ask-id <id> --verbatim '<exact words>'. No record written; caller not blocked." >&2
    return 0
  fi
  if [[ -n "$ask_id" && "$ask_id" != "$resolved_ask" ]]; then
    echo "ask-registry.sh declare-invariant: --ask-id '$ask_id' disagrees with the requirement's own ask '$resolved_ask'; using the requirement's ask (the requirement record is authoritative)." >&2
  fi
  ask_id="$resolved_ask"

  text="$(_ar_truncate_hard "$_AR_INVARIANT_MAX" "$text")"
  [[ -n "$invariant_id" ]] || invariant_id="$(_ar_next_invariant_id "$requirement_id")"

  _ar_append_record "invariant_declared" "$ask_id" "" "" "" \
    "" "" "" "" "" "" "" "$emitter" \
    "" "" "" "" "" "$requirement_id" "" "$invariant_id" "$text" "" "" >/dev/null

  printf '%s' "$invariant_id"
  return 0
}

# ----------------------------------------------------------------------
# cmd_invariant_verdict — a verifier's per-invariant judgement.
# ----------------------------------------------------------------------
_AR_VALID_INVARIANT_VERDICTS="holds violated unverifiable"

cmd_invariant_verdict() {
  local requirement_id="" invariant_id="" verdict="" evidence_ref="" \
        ask_id="" emitter="task-verifier"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --requirement-id) requirement_id="${2:-}"; shift 2 ;;
      --invariant-id) invariant_id="${2:-}"; shift 2 ;;
      --verdict) verdict="${2:-}"; shift 2 ;;
      --evidence) evidence_ref="${2:-}"; shift 2 ;;
      --ask-id) ask_id="${2:-}"; shift 2 ;;
      --emitter) emitter="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$requirement_id" || -z "$invariant_id" || -z "$verdict" ]]; then
    echo "ask-registry.sh invariant-verdict: --requirement-id, --invariant-id and --verdict are required (no-op; never blocks caller)" >&2
    return 0
  fi

  local ok=0 v
  for v in $_AR_VALID_INVARIANT_VERDICTS; do
    [[ "$verdict" == "$v" ]] && ok=1
  done
  if [[ "$ok" != "1" ]]; then
    echo "ask-registry.sh invariant-verdict: invalid --verdict '$verdict' (expected one of: $_AR_VALID_INVARIANT_VERDICTS); no record written" >&2
    return 0
  fi

  # A `holds` verdict with no citation is exactly the unevidenced self-report
  # the ledger exists to catch — refuse it rather than persist a hollow pass.
  #
  # BLANK-AFTER-TRIM, NOT MERELY EMPTY (harness-reviewer Major 4, 2026-07-29).
  # The guard used to be `-z`, but the READER's `cell` normalises `^ *$` to
  # `-`, so `--evidence '   '` was accepted AND then rendered BYTE-IDENTICAL to
  # a row that carries no verdict at all. An operator auditing the TSV could
  # not distinguish "nobody has checked this" from "someone passed it with
  # whitespace". Trim first, then require non-empty.
  #
  # Plus a MINIMAL NON-SEMANTIC SHAPE CHECK. `x`, `.`, `0`, `-` and `trust me`
  # all satisfied "non-empty" while citing nothing. A citation in this harness
  # is a file:line, a command, a path, or a commit SHA, so the shape test is:
  #   a ':' followed by a digit  (file:line, cmd:exit)  OR
  #   a run of 7+ hex characters (a commit SHA)         OR
  #   a '/'                      (a path or a URL)
  # This is deliberately SYNTACTIC. It cannot tell a true citation from a
  # false one and does not try: the reviewer's explicit finding is that
  # semantic quality-checking here would over-fire and erode trust in the
  # gate. It rejects only strings that could not be a citation in any reading.
  if [[ "$verdict" == "holds" ]]; then
    local ev_trimmed="${evidence_ref//[[:space:]]/}"
    if [[ -z "$ev_trimmed" ]]; then
      echo "ask-registry.sh invariant-verdict: --verdict holds requires --evidence <citation> (file:line, command, path, or commit SHA). A blank or whitespace-only value renders identically to an UNVERIFIED row, so it is refused; no record written." >&2
      return 0
    fi
    if ! [[ "$evidence_ref" == */* || "$evidence_ref" =~ :[0-9] || "$evidence_ref" =~ [0-9a-fA-F]{7,} ]]; then
      echo "ask-registry.sh invariant-verdict: --evidence '$evidence_ref' does not look like a citation — expected a file:line (path:120), a path (dir/file.sh), a command, or a 7+ char commit SHA. This is a SHAPE check only, not a judgement of the evidence's quality; no record written." >&2
      return 0
    fi
  fi

  evidence_ref="$(_ar_truncate_hard "$_AR_INVARIANT_MAX" "$evidence_ref")"

  # REFERENTIAL INTEGRITY + ask_id RESOLUTION — identical contract to
  # declare-invariant above. A verdict against a requirement that was never
  # recorded is as unreachable, and as silently green, as a declaration
  # against one.
  local resolved_ask
  if ! resolved_ask="$(_ar_requirement_ask_id "$requirement_id")"; then
    echo "ask-registry.sh invariant-verdict: no requirement_recorded exists with --requirement-id '$requirement_id' — refusing to file a verdict against a requirement that was never recorded (it would be unreachable from --ask-id/--plan-slug). No record written; caller not blocked." >&2
    return 0
  fi
  if [[ -n "$ask_id" && "$ask_id" != "$resolved_ask" ]]; then
    echo "ask-registry.sh invariant-verdict: --ask-id '$ask_id' disagrees with the requirement's own ask '$resolved_ask'; using the requirement's ask (the requirement record is authoritative)." >&2
  fi
  ask_id="$resolved_ask"

  _ar_append_record "invariant_verdict" "$ask_id" "" "" "" \
    "" "" "" "" "" "" "" "$emitter" \
    "" "" "" "" "" "$requirement_id" "" "$invariant_id" "" "$verdict" "$evidence_ref" >/dev/null

  return 0
}

# _ar_parse_selector — shared flag parsing for the two read verbs.
# Sets _AR_SEL_KIND / _AR_SEL.
_ar_parse_selector() {
  _AR_SEL_KIND="all"; _AR_SEL=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --requirement-id) _AR_SEL_KIND="requirement"; _AR_SEL="${2:-}"; shift 2 ;;
      --ask-id)         _AR_SEL_KIND="ask";         _AR_SEL="${2:-}"; shift 2 ;;
      --plan-slug)      _AR_SEL_KIND="plan";        _AR_SEL="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
}

# ----------------------------------------------------------------------
# cmd_invariants — read-only listing.
# ----------------------------------------------------------------------
cmd_invariants() {
  _ar_parse_selector "$@"
  printf 'requirement_id\tinvariant_id\tverdict\tevidence_ref\tinvariant_text\tverbatim\n'
  _ar_invariant_rows "$_AR_SEL_KIND" "$_AR_SEL"
  return $?
}

# ----------------------------------------------------------------------
# cmd_invariant_check — the checking step.
#   exit 0 = every declared invariant in scope folds to `holds`
#   exit 1 = at least one is `violated`, `unverifiable`, or `unverified`
#   exit 3 = NOTHING REGISTERED in scope (not a pass — nothing to check)
#   exit 4 = CANNOT EVALUATE (no registry / no jq) — not a pass either
# The distinct 3/4 codes exist so a degraded environment can never be read as
# a green check; that silent-pass-on-degrade shape is the failure this whole
# ledger is a response to.
# ----------------------------------------------------------------------
cmd_invariant_check() {
  _ar_parse_selector "$@"

  local rows rc
  rows="$(_ar_invariant_rows "$_AR_SEL_KIND" "$_AR_SEL")"; rc=$?
  if [[ "$rc" == "4" ]]; then
    echo "invariant-check: CANNOT EVALUATE (see stderr above) — this is NOT a pass"
    return 4
  fi

  if [[ -z "$rows" ]]; then
    echo "invariant-check: no invariants registered for ${_AR_SEL_KIND}=${_AR_SEL:-<all>} — nothing to check (NOT a pass)"
    return 3
  fi

  local total=0 held=0 bad=0 line rid iid verdict ev text
  local IFS_SAVE="$IFS"
  while IFS=$'\t' read -r rid iid verdict ev text _rest; do
    [[ -z "$rid" ]] && continue
    total=$((total + 1))
    if [[ "$verdict" == "holds" ]]; then
      held=$((held + 1))
      echo "  HOLDS       $rid/$iid  $text  [$ev]"
    else
      bad=$((bad + 1))
      echo "  $verdict  $rid/$iid  $text  [$ev]"
    fi
  done <<EOF
$rows
EOF
  IFS="$IFS_SAVE"

  echo "invariant-check: $held/$total invariants hold; $bad unmet"
  if [[ "$bad" -gt 0 ]]; then
    return 1
  fi
  return 0
}

cmd_list() {
  local f
  f="$(ar_registry_file)"
  [[ -f "$f" ]] && cat "$f"
  return 0
}

# ----------------------------------------------------------------------
# cmd_heuristic_summarize --text <raw> — read-only, pure-function verb
# (2026-07-30, backfill-classify-candidates.sh): prints the SAME
# markdown-stripped/first-sentence/140-char-capped label `register` and the
# deterministic classifier already use, so a one-shot backfill process
# (which cannot call this file's internal bash functions directly — it's a
# separate script/process) produces IDENTICAL labels to the live capture
# path instead of a second, subtly-different summarization. No registry
# read, no write, no side effect.
# ----------------------------------------------------------------------
cmd_heuristic_summarize() {
  local text=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text) text="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  _ar_heuristic_summarize "$text"
  return 0
}

# ----------------------------------------------------------------------
# cmd_gen_ask_id --summary <text> — read-only, pure-function verb
# (2026-07-30, harness-reviewer Minor: backfill-classify-amendment-
# candidates.sh's promote path used to `register` first and then re-derive
# the new ask_id by grepping the registry for a matching verbatim_ref —
# workable (proven unique on live data) but a needless lookup-failure/race
# surface). Exposes the SAME `_ar_gen_ask_id` the live deterministic
# classifier already calls directly (in-process), so the backfill script
# can mint the id UP FRONT and pass `--ask-id` explicitly to `register`,
# exactly like the live lane — no post-write lookup, no failure mode. No
# registry read, no write, no side effect.
# ----------------------------------------------------------------------
cmd_gen_ask_id() {
  local summary=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --summary) summary="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  _ar_gen_ask_id "$summary"
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

  echo "Scenario J2 (2026-07-30): heuristic-summarize is a pure, read-only verb (no registry write) producing the SAME label register/the deterministic classifier use"
  local hs_before hs_after hs_out
  hs_before=$(wc -l < "$REG" 2>/dev/null | tr -d ' ')
  hs_out="$(cmd_heuristic_summarize --text 'Please fix the login page so the submit button actually submits the form. Also do X.')"
  hs_after=$(wc -l < "$REG" 2>/dev/null | tr -d ' ')
  if [[ "$hs_out" == "Please fix the login page so the submit button actually submits the form." ]]; then
    pass "heuristic-summarize takes the first sentence (140-char cap), matching register's own summarizer"
  else
    fail "heuristic-summarize returned unexpected output: '$hs_out'"
  fi
  if [[ "$hs_before" == "$hs_after" ]]; then
    pass "heuristic-summarize never touches the registry file (pure function)"
  else
    fail "heuristic-summarize unexpectedly changed the registry line count ($hs_before -> $hs_after)"
  fi

  echo "Scenario J3 (2026-07-30): gen-ask-id is a pure, read-only verb producing the SAME id shape register mints when --ask-id is omitted"
  local gid_before gid_after gid_out
  gid_before=$(wc -l < "$REG" 2>/dev/null | tr -d ' ')
  gid_out="$(cmd_gen_ask_id --summary 'Fix the login page')"
  gid_after=$(wc -l < "$REG" 2>/dev/null | tr -d ' ')
  if [[ "$gid_out" == ask-*-fix-the-login-page-* ]]; then
    pass "gen-ask-id prints an ask-<date>-<slug>-<4hex> id matching register's own auto-generation shape"
  else
    fail "gen-ask-id returned unexpected output: '$gid_out'"
  fi
  if [[ "$gid_before" == "$gid_after" ]]; then
    pass "gen-ask-id never touches the registry file (pure function)"
  else
    fail "gen-ask-id unexpectedly changed the registry line count ($gid_before -> $gid_after)"
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
    #
    # COORD_DIRTY_MARKER_FILE is part of that isolation and was MISSING (CLASS3,
    # 2026-07-29). Because this subprocess sets HARNESS_SELFTEST=0 on purpose,
    # progress-log-lib's guard arm is deliberately off, so its coord-sync marker
    # fell through to arm 3 — the operator's REAL ~/.claude/state/coord-sync/dirty,
    # the flag scripts/coord-sync.sh consumes. Arm 1 (this explicit override) is
    # the right isolation here: it does not re-enable the short-circuit the
    # scenario exists to bypass. PROVEN: with the guard vars unset and HOME
    # pointed at an empty dir, this suite created .claude/state/coord-sync/dirty
    # before this line and creates nothing under .claude/ after it.
    local wt_ar_state="$TMP/l-ar-state" wt_pl_state="$TMP/l-pl-state"
    mkdir -p "$wt_ar_state" "$wt_pl_state"

    ( cd "$wt_dir" \
        && HARNESS_SELFTEST=0 \
           ASK_REGISTRY_STATE_DIR="$wt_ar_state" \
           PROGRESS_LOG_STATE_DIR="$wt_pl_state" \
           COORD_DIRTY_MARKER_FILE="$TMP/l-coord/dirty" \
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

  echo "Scenario Q (cockpit-roadmap-redesign Task 7, A5 iii): EVERY registry append touches the coordination dirty marker at the writer-lib seam — incl. a verb that emits NO progress event (override-project), the exact class a hook-layer-only marker would miss"
  local q_marker="$TMP/coord-dirty-q"
  rm -f "$q_marker" 2>/dev/null
  COORD_DIRTY_MARKER_FILE="$q_marker" cmd_override_project \
    --ask-id "ask-selftest-1" --project "regrouped-demo" >/dev/null 2>&1
  if [[ -f "$q_marker" ]]; then
    pass "override-project (no progress-log event of its own) still dirtied the coordination marker via _ar_append_record"
  else
    fail "expected dirty marker $q_marker after an override-project registry append"
  fi
  if [[ -f "$q_marker" ]] && grep -q "project_override" "$q_marker" 2>/dev/null; then
    pass "marker content names the appended record_type (debug provenance)"
  else
    fail "expected marker content to name record_type project_override, got: '$(cat "$q_marker" 2>/dev/null)'"
  fi
  # ==========================================================================
  # WORK-ITEM LAYER scenarios (cockpit-roadmap-redesign Task 2 — A2/A3/I6):
  # titles with title_source precedence, amendment-candidate capture +
  # async classification + operator correction, explicit amend verb.
  # ==========================================================================

  echo "Scenario Q: set-title appends a summary_updated record with title_source=operator (default emitter operator-ui)"
  cmd_register --ask-id "ask-selftest-title" --summary "auto captured title" >/dev/null
  cmd_set_title --ask-id "ask-selftest-title" --title "Operator renamed this item" >/dev/null
  if grep -q '"ask_id":"ask-selftest-title".*"record_type":"summary_updated".*"summary":"Operator renamed this item".*"emitter":"operator-ui".*"title_source":"operator"' "$REG"; then
    pass "set-title appended an operator-sourced summary_updated record"
  else
    fail "expected an operator-sourced summary_updated record for ask-selftest-title"
  fi

  echo "Scenario Q1: set-title with an EMPTY --title is a no-op (never a blank clobber record)"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_set_title --ask-id "ask-selftest-title" --title "" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "set-title rejected an empty title (no new record)"
  else
    fail "expected no new record for an empty title, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario Q2: created records stamp title_source=auto (registration is machine capture)"
  if grep -q '"ask_id":"ask-selftest-title".*"record_type":"created".*"title_source":"auto"' "$REG"; then
    pass "created record carries title_source=auto"
  else
    fail "expected the created record for ask-selftest-title to carry title_source=auto"
  fi

  echo "Scenario Q3: the async distiller's summary_updated records stamp title_source=auto"
  if grep -q '"ask_id":"ask-selftest-haiku".*"record_type":"summary_updated".*"title_source":"auto"' "$REG"; then
    pass "distiller upgrade record carries title_source=auto"
  else
    fail "expected ask-selftest-haiku's summary_updated record to carry title_source=auto"
  fi

  echo "Scenario Q4: a distiller re-run AFTER an operator title edit never appends (writer-side defense; fold precedence remains the binding rule)"
  # Control leg first: the SAME async lane against an ask with NO operator
  # title MUST append — proving the lane fires in this run, so the no-append
  # assertion below discriminates the skip logic, not a dead lane.
  _AR_HAIKU_CMD='cat'
  cmd_register --ask-id "ask-selftest-title-ctl" --summary "control ask" >/dev/null
  _ar_async_haiku_upgrade "ask-selftest-title-ctl" "control raw text for the distiller lane"
  local q4_waited=0 q4_ctl=0
  while [[ "$q4_waited" -lt 30 ]]; do
    if grep -q '"ask_id":"ask-selftest-title-ctl".*"record_type":"summary_updated"' "$REG" 2>/dev/null; then
      q4_ctl=1
      break
    fi
    sleep 0.2
    q4_waited=$((q4_waited + 1))
  done
  if [[ "$q4_ctl" == "1" ]]; then
    pass "Q4 control: distiller lane appends for an ask WITHOUT an operator title"
  else
    fail "Q4 control: distiller lane never appended for the control ask — the no-append leg below cannot discriminate"
  fi
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  _ar_async_haiku_upgrade "ask-selftest-title" "some raw text the distiller would re-summarize"
  sleep 3
  unset _AR_HAIKU_CMD
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "distiller re-run skipped the append because an operator title exists"
  else
    fail "distiller re-run appended over an operator title (lines $before_lines -> $after_lines)"
  fi

  echo "Scenario R: capture-candidate appends an amendment_candidate (classification=pending, minted cand- id, ref only — raw text NEVER stored)"
  cmd_register --ask-id "ask-selftest-cand" --summary "candidate host ask" >/dev/null
  cmd_capture_candidate --ask-id "ask-selftest-cand" --session-id "sess-cand-1" \
    --verbatim-ref "/transcripts/t1.jsonl#1" \
    --text "the raw follow-up prompt text that must never be persisted verbatim-marker-xyzzy" >/dev/null
  if grep -q '"ask_id":"ask-selftest-cand".*"record_type":"amendment_candidate".*"verbatim_ref":"/transcripts/t1.jsonl#1".*"candidate_id":"cand-.*"classification":"pending"' "$REG"; then
    pass "capture-candidate appended a pending amendment_candidate with a minted cand- id"
  else
    fail "expected a pending amendment_candidate record for ask-selftest-cand"
  fi
  if ! grep -q "verbatim-marker-xyzzy" "$REG"; then
    pass "the candidate's raw prompt text was NOT persisted to the registry (refs only)"
  else
    fail "raw prompt text leaked into the registry file"
  fi

  echo "Scenario R2: ASK_SUMMARIZER=haiku classification lane marks a candidate amendment (async, with a distilled label)"
  _AR_CLASSIFY_CMD='printf "amendment: scope grew to include the sidebar"'
  ASK_SUMMARIZER=haiku cmd_capture_candidate --ask-id "ask-selftest-cand" \
    --session-id "sess-cand-1" --verbatim-ref "/transcripts/t1.jsonl#2" \
    --text "also please add the sidebar to the rebuild" >/dev/null
  local r2_cid
  r2_cid="$(grep '"verbatim_ref":"/transcripts/t1.jsonl#2"' "$REG" | sed -E 's/.*"candidate_id":"([^"]*)".*/\1/' | head -n1)"
  local waited2=0 classified=0
  while [[ "$waited2" -lt 30 ]]; do
    if grep -q '"record_type":"candidate_classified".*"candidate_id":"'"$r2_cid"'".*"classification":"amendment"' "$REG" 2>/dev/null; then
      classified=1
      break
    fi
    sleep 0.2
    waited2=$((waited2 + 1))
  done
  unset _AR_CLASSIFY_CMD
  if [[ "$classified" == "1" ]] \
     && grep -q '"record_type":"candidate_classified".*"summary":"scope grew to include the sidebar".*"candidate_id":"'"$r2_cid"'"' "$REG"; then
    pass "async classifier appended candidate_classified (amendment + distilled label, emitter=ask-registry-classifier)"
  else
    fail "expected an async candidate_classified amendment record for candidate '$r2_cid'"
  fi

  echo "Scenario R3: classification lane marks conversational text noise"
  _AR_CLASSIFY_CMD='printf "noise"'
  ASK_SUMMARIZER=haiku cmd_capture_candidate --ask-id "ask-selftest-cand" \
    --session-id "sess-cand-1" --verbatim-ref "/transcripts/t1.jsonl#3" \
    --text "thanks, looks good so far" >/dev/null
  local r3_cid
  r3_cid="$(grep '"verbatim_ref":"/transcripts/t1.jsonl#3"' "$REG" | sed -E 's/.*"candidate_id":"([^"]*)".*/\1/' | head -n1)"
  local waited3=0 noise=0
  while [[ "$waited3" -lt 30 ]]; do
    if grep -q '"record_type":"candidate_classified".*"candidate_id":"'"$r3_cid"'".*"classification":"noise"' "$REG" 2>/dev/null; then
      noise=1
      break
    fi
    sleep 0.2
    waited3=$((waited3 + 1))
  done
  unset _AR_CLASSIFY_CMD
  if [[ "$noise" == "1" ]]; then
    pass "async classifier marked the conversational candidate noise"
  else
    fail "expected an async candidate_classified noise record for candidate '$r3_cid'"
  fi

  echo "Scenario R4: a FAILING classifier degrades silently — candidate stays honestly pending, no crash, no bad record"
  _AR_CLASSIFY_CMD='false'
  ASK_SUMMARIZER=haiku cmd_capture_candidate --ask-id "ask-selftest-cand" \
    --session-id "sess-cand-1" --verbatim-ref "/transcripts/t1.jsonl#4" \
    --text "this classification call will fail on purpose" >/dev/null
  sleep 0.8
  unset _AR_CLASSIFY_CMD
  local r4_cid
  r4_cid="$(grep '"verbatim_ref":"/transcripts/t1.jsonl#4"' "$REG" | sed -E 's/.*"candidate_id":"([^"]*)".*/\1/' | head -n1)"
  if [[ -n "$r4_cid" ]] && ! grep -q '"record_type":"candidate_classified".*"candidate_id":"'"$r4_cid"'"' "$REG"; then
    pass "failing classifier left the candidate pending (named honest state), no crash"
  else
    fail "expected candidate '$r4_cid' to remain pending after a failing classifier"
  fi

  echo "Scenario R5-R8 (2026-07-30 fix): the DETERMINISTIC classifier — no ASK_SUMMARIZER gate, no model call, resolves REAL text from a REAL transcript, and PROMOTES a genuinely new topic into its own ask"
  local DET_TRANSCRIPT="$TMP/det-transcript.jsonl"
  : > "$DET_TRANSCRIPT"
  _det_append_line() {
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null)"
    printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"%s"}}\n' "$ts" "$1" >> "$DET_TRANSCRIPT"
    printf '%s' "$ts"
  }

  local det_ts0; det_ts0="$(_det_append_line "Please fix the login page so the submit button actually submits the form.")"
  cmd_register --ask-id "ask-selftest-detclass" --summary "Please fix the login page so the submit button actually submits the form." \
    --verbatim-ref "${DET_TRANSCRIPT}#0" --session-id "sess-detclass" >/dev/null
  sleep 2

  echo "  R5: a candidate sharing real vocabulary with the parent is classified 'amendment' via resolved text — NO ASK_SUMMARIZER, NO --text needed"
  local det_ts1; det_ts1="$(_det_append_line "also please disable the submit button while the form is submitting")"
  cmd_capture_candidate --ask-id "ask-selftest-detclass" --candidate-id "cand-det-amend" \
    --session-id "sess-detclass" --verbatim-ref "${DET_TRANSCRIPT}#1" >/dev/null
  local det_waited=0 det_ok=0
  while [[ "$det_waited" -lt 30 ]]; do
    if grep -q '"record_type":"candidate_classified".*"candidate_id":"cand-det-amend".*"classification":"amendment"' "$REG" 2>/dev/null; then
      det_ok=1; break
    fi
    sleep 0.2; det_waited=$((det_waited + 1))
  done
  if [[ "$det_ok" == "1" ]] \
     && grep '"candidate_id":"cand-det-amend"' "$REG" 2>/dev/null | grep -q '"classification":"amendment"' \
     && grep '"candidate_id":"cand-det-amend"' "$REG" 2>/dev/null | grep -q '"summary":"[^"]*submit'; then
    pass "R5 deterministic classifier marked a real-vocabulary-overlap candidate 'amendment' with a real distilled label (no model call, no ASK_SUMMARIZER)"
  else
    fail "R5 expected a deterministic 'amendment' candidate_classified record for cand-det-amend with a real label"
  fi

  echo "  R6: a candidate SUBSTANTIVELY UNRELATED to the parent is PROMOTED into its own new top-level ask, carrying its real resolved text as the new ask's summary"
  sleep 2
  local det_ts2; det_ts2="$(_det_append_line "Completely unrelated: can you also set up weekly backups for the database?")"
  cmd_capture_candidate --ask-id "ask-selftest-detclass" --candidate-id "cand-det-promote" \
    --session-id "sess-detclass" --verbatim-ref "${DET_TRANSCRIPT}#2" >/dev/null
  local det_waited2=0 det_ok2=0
  while [[ "$det_waited2" -lt 30 ]]; do
    if grep -q '"record_type":"candidate_classified".*"candidate_id":"cand-det-promote".*"classification":"promoted"' "$REG" 2>/dev/null; then
      det_ok2=1; break
    fi
    sleep 0.2; det_waited2=$((det_waited2 + 1))
  done
  local new_ask_id=""
  if [[ "$det_ok2" == "1" ]]; then
    new_ask_id="$(grep '"candidate_id":"cand-det-promote"' "$REG" | grep '"classification":"promoted"' | sed -E 's/.*"summary":"([^"]*)".*/\1/' | head -n1)"
  fi
  if [[ -n "$new_ask_id" ]] && grep -q '"ask_id":"'"$new_ask_id"'".*"record_type":"created".*"summary":"Completely unrelated' "$REG" 2>/dev/null; then
    pass "R6 a genuinely new topic mid-session was spun off into its OWN ask ($new_ask_id) with its real resolved text as the title — the operator's core complaint (buried forever as a pending amendment) is fixed"
  else
    fail "R6 expected cand-det-promote to be promoted into a new top-level ask carrying its real resolved text"
  fi

  echo "  R7: a short conversational ack (real, resolvable text) is classified 'noise' by the deterministic path"
  sleep 2
  local det_ts3; det_ts3="$(_det_append_line "thanks, looks good so far")"
  cmd_capture_candidate --ask-id "ask-selftest-detclass" --candidate-id "cand-det-noise" \
    --session-id "sess-detclass" --verbatim-ref "${DET_TRANSCRIPT}#3" >/dev/null
  local det_waited3=0 det_ok3=0
  while [[ "$det_waited3" -lt 30 ]]; do
    if grep -q '"record_type":"candidate_classified".*"candidate_id":"cand-det-noise".*"classification":"noise"' "$REG" 2>/dev/null; then
      det_ok3=1; break
    fi
    sleep 0.2; det_waited3=$((det_waited3 + 1))
  done
  if [[ "$det_ok3" == "1" ]]; then
    pass "R7 deterministic classifier marked a real short acknowledgement 'noise'"
  else
    fail "R7 expected a deterministic 'noise' candidate_classified record for cand-det-noise"
  fi

  echo "  R8: regression safety — an UNRESOLVABLE (fake-path) verbatim_ref never produces a deterministic candidate_classified record (falls through, honest degrade, matches Scenario R/R2/R3/R4's pre-existing fake-ref behavior)"
  cmd_capture_candidate --ask-id "ask-selftest-detclass" --candidate-id "cand-det-unresolvable" \
    --session-id "sess-detclass" --verbatim-ref "/transcripts/does-not-exist.jsonl#0" >/dev/null
  sleep 1.5
  if ! grep -q '"record_type":"candidate_classified".*"candidate_id":"cand-det-unresolvable"' "$REG" 2>/dev/null; then
    pass "R8 an unresolvable verbatim_ref leaves the candidate pending — no fabricated classification"
  else
    fail "R8 expected NO candidate_classified record for an unresolvable ref"
  fi
  unset -f _det_append_line

  echo "Scenario S: classify-candidate rejects an invalid classification vocabulary value (no-op)"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_classify_candidate --ask-id "ask-selftest-cand" --candidate-id "$r4_cid" \
    --classification "bogus-class" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "classify-candidate rejected invalid vocabulary (no new record)"
  else
    fail "expected no new record for an invalid classification, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario S2: detach-candidate appends candidate_classified classification=detached emitter=operator-ui (I6 correction affordance)"
  cmd_detach_candidate --ask-id "ask-selftest-cand" --candidate-id "$r2_cid" >/dev/null
  if grep -q '"record_type":"candidate_classified".*"emitter":"operator-ui".*"candidate_id":"'"$r2_cid"'".*"classification":"detached"' "$REG"; then
    pass "detach-candidate appended an operator detached correction record"
  else
    fail "expected a detached candidate_classified record for candidate '$r2_cid'"
  fi

  echo "Scenario T: amend verb appends a first-class amended record (classification=amendment, heuristic label from --text, minted cand- id)"
  cmd_amend --ask-id "ask-selftest-cand" \
    --text "**Also** migrate the settings pane. And keep the old URL working." \
    --session-id "sess-cand-1" >/dev/null
  if grep -q '"ask_id":"ask-selftest-cand".*"record_type":"amended".*"summary":"Also migrate the settings pane.".*"emitter":"model".*"candidate_id":"cand-.*"classification":"amendment"' "$REG"; then
    pass "amend appended an amended record with the heuristic-distilled label (default emitter=model, labeled memory-dependent)"
  else
    fail "expected an amended record for ask-selftest-cand"
  fi

  echo "Scenario T2: amend with neither --text nor --summary is a no-op"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_amend --ask-id "ask-selftest-cand" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "amend rejected an empty amendment (no new record)"
  else
    fail "expected no new record for an empty amend, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario U: merge accepts --emitter (operator-ui label reaches the record; default stays ask-registry)"
  cmd_register --ask-id "ask-selftest-mergesrc" --summary "merge emitter test" >/dev/null
  cmd_merge --ask-id "ask-selftest-mergesrc" --into "ask-selftest-cand" --emitter "operator-ui" >/dev/null
  if grep -q '"ask_id":"ask-selftest-mergesrc".*"record_type":"merged".*"emitter":"operator-ui"' "$REG"; then
    pass "merge --emitter operator-ui stamped the record"
  else
    fail "expected a merged record with emitter=operator-ui for ask-selftest-mergesrc"
  fi
  if grep -q '"ask_id":"ask-selftest-dup".*"record_type":"merged".*"emitter":"ask-registry"' "$REG"; then
    pass "merge without --emitter still defaults to ask-registry (Scenario H record unchanged)"
  else
    fail "expected the earlier flagless merge record to carry emitter=ask-registry"
  fi

  # ==========================================================================
  # ASK SLA scenarios (accountable-estate-program-2026-07 Task 2 —
  # deadline/clear-deadline/default-action/sla). All in-process (calling
  # cmd_* directly, not forking a subprocess) to stay fast on this
  # fork-taxed machine — synchronous/deterministic, no async model-fork
  # lane involved (that caution applies to Scenarios M/N/R2/R3/R4/Q3/Q4
  # above, none of which these touch).
  # ==========================================================================

  echo "Scenario W: set-deadline normalizes a parseable timestamp and appends deadline_set; sla reports it"
  cmd_register --ask-id "ask-selftest-sla" --summary "sla host ask" >/dev/null
  cmd_set_deadline --ask-id "ask-selftest-sla" --deadline "2026-08-01 00:00:00" >/dev/null
  if grep -q '"ask_id":"ask-selftest-sla".*"record_type":"deadline_set".*"deadline":"2026-08-01T00:00:00Z"' "$REG"; then
    pass "set-deadline normalized a space-separated timestamp to canonical %Y-%m-%dT%H:%M:%SZ"
  else
    fail "expected a deadline_set record with deadline=2026-08-01T00:00:00Z for ask-selftest-sla"
  fi

  echo "Scenario W2: set-deadline with an UNPARSEABLE value is REJECTED (no-op, file unchanged)"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_set_deadline --ask-id "ask-selftest-sla" --deadline "not-a-real-date" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "set-deadline rejected an unparseable timestamp (no new record)"
  else
    fail "expected no new record for an unparseable deadline, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario W3: set-deadline/clear-deadline/set-default-action with missing --ask-id are documented no-ops"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_set_deadline --deadline "2026-08-01T00:00:00Z" >/dev/null 2>&1
  cmd_clear_deadline >/dev/null 2>&1
  cmd_set_default_action --default-action "DEMOTE" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "all three SLA verbs no-op cleanly on a missing --ask-id"
  else
    fail "expected no new records for missing --ask-id calls, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario X: DEADLINE FOLD — clear-deadline after set-deadline wins regardless of the earlier non-empty value (record-type-ordered, not last-non-empty-wins)"
  cmd_register --ask-id "ask-selftest-clear" --summary "clear test ask" >/dev/null
  cmd_set_deadline --ask-id "ask-selftest-clear" --deadline "2026-09-01T00:00:00Z" >/dev/null
  cmd_clear_deadline --ask-id "ask-selftest-clear" >/dev/null
  local clear_sla; clear_sla="$(cmd_sla | grep '^ask-selftest-clear' || true)"
  if [[ "$clear_sla" == *$'\t'"no-deadline"$'\t'* ]]; then
    pass "clear-deadline after set-deadline resolves to no-deadline in the fold (X: $clear_sla)"
  else
    fail "expected ask-selftest-clear to fold to no-deadline after clear, got: '$clear_sla'"
  fi

  echo "Scenario Y: set-default-action appends default_action_set (truncated to 140 chars); a second call is last-non-empty-wins"
  cmd_register --ask-id "ask-selftest-daction" --summary "default action test ask" >/dev/null
  cmd_set_default_action --ask-id "ask-selftest-daction" --default-action "DEMOTE" >/dev/null
  cmd_set_default_action --ask-id "ask-selftest-daction" --default-action "proceed with recommendation X" >/dev/null
  local daction_sla; daction_sla="$(cmd_sla | grep '^ask-selftest-daction' || true)"
  if [[ "$daction_sla" == *"proceed with recommendation X"* ]]; then
    pass "the SECOND set-default-action call wins (last-non-empty-wins fold, no special precedence): $daction_sla"
  else
    fail "expected the latest default_action to win for ask-selftest-daction, got: '$daction_sla'"
  fi

  echo "Scenario Y2: set-default-action with a missing --default-action is a no-op"
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  cmd_set_default_action --ask-id "ask-selftest-daction" >/dev/null 2>&1
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "set-default-action rejected a missing --default-action (no new record)"
  else
    fail "expected no new record for a missing --default-action, lines went $before_lines -> $after_lines"
  fi

  echo "Scenario Z: sla classifies overdue/due-soon/ok/no-deadline correctly and sorts soonest-deadline-first (undated last)"
  local z_overdue z_duesoon z_ok
  z_overdue="$(date -u -d '-3 days' '+%Y-%m-%dT%H:%M:%SZ')"
  z_duesoon="$(date -u -d '+1 day' '+%Y-%m-%dT%H:%M:%SZ')"
  z_ok="$(date -u -d '+5 days' '+%Y-%m-%dT%H:%M:%SZ')"
  cmd_register --ask-id "ask-z-overdue" --summary "z overdue" >/dev/null
  cmd_set_deadline --ask-id "ask-z-overdue" --deadline "$z_overdue" >/dev/null
  cmd_register --ask-id "ask-z-duesoon" --summary "z due soon" >/dev/null
  cmd_set_deadline --ask-id "ask-z-duesoon" --deadline "$z_duesoon" >/dev/null
  cmd_register --ask-id "ask-z-ok" --summary "z ok" >/dev/null
  cmd_set_deadline --ask-id "ask-z-ok" --deadline "$z_ok" >/dev/null
  cmd_register --ask-id "ask-z-undated" --summary "z undated" >/dev/null
  local z_out; z_out="$(cmd_sla)"
  local z_state_overdue z_state_duesoon z_state_ok z_state_undated
  z_state_overdue="$(printf '%s\n' "$z_out" | grep '^ask-z-overdue' | cut -f2)"
  z_state_duesoon="$(printf '%s\n' "$z_out" | grep '^ask-z-duesoon' | cut -f2)"
  z_state_ok="$(printf '%s\n' "$z_out" | grep '^ask-z-ok' | cut -f2)"
  z_state_undated="$(printf '%s\n' "$z_out" | grep '^ask-z-undated' | cut -f2)"
  if [[ "$z_state_overdue" == "overdue" && "$z_state_duesoon" == "due-soon" && "$z_state_ok" == "ok" && "$z_state_undated" == "no-deadline" ]]; then
    pass "sla_state correct for all four buckets (overdue/due-soon/ok/no-deadline)"
  else
    fail "expected overdue/due-soon/ok/no-deadline, got '$z_state_overdue'/'$z_state_duesoon'/'$z_state_ok'/'$z_state_undated'"
  fi
  local z_pos_overdue z_pos_duesoon z_pos_ok z_pos_undated
  z_pos_overdue=$(printf '%s\n' "$z_out" | grep -n '^ask-z-overdue' | cut -d: -f1)
  z_pos_duesoon=$(printf '%s\n' "$z_out" | grep -n '^ask-z-duesoon' | cut -d: -f1)
  z_pos_ok=$(printf '%s\n' "$z_out" | grep -n '^ask-z-ok' | cut -d: -f1)
  z_pos_undated=$(printf '%s\n' "$z_out" | grep -n '^ask-z-undated' | cut -d: -f1)
  if [[ -n "$z_pos_overdue" && -n "$z_pos_duesoon" && -n "$z_pos_ok" && -n "$z_pos_undated" \
        && "$z_pos_overdue" -lt "$z_pos_duesoon" && "$z_pos_duesoon" -lt "$z_pos_ok" && "$z_pos_ok" -lt "$z_pos_undated" ]]; then
    pass "sla sorts soonest-deadline-first, undated last"
  else
    fail "expected sort order overdue < due-soon < ok < undated, got positions $z_pos_overdue/$z_pos_duesoon/$z_pos_ok/$z_pos_undated"
  fi

  echo "Scenario Z2: sla degrades honestly (stderr note, exit 0, never a crash) when no registry file exists yet"
  local z2_out z2_rc
  z2_out="$(ASK_REGISTRY_STATE_DIR="$TMP/no-such-dir-$$" cmd_sla 2>&1)"; z2_rc=$?
  if [[ "$z2_rc" == "0" && "$z2_out" == *"no asks registered yet"* ]]; then
    pass "sla degrades honestly when the registry file does not exist (exit 0, honest note)"
  else
    fail "expected exit 0 + an honest 'no asks registered yet' note, got rc=$z2_rc out='$z2_out'"
  fi

  echo "Scenario V: PRODUCTION SHAPE — real flagless subprocess invocations (bash ask-registry.sh <verb>), full title+timeline pipeline"
  local V_DIR="$TMP/prod-shape"
  mkdir -p "$V_DIR/ar" "$V_DIR/pl"
  local V_REG="$V_DIR/ar/ask-registry.jsonl"
  # COORD_DIRTY_MARKER_FILE belongs in this isolation set for the same reason as
  # Scenario L1: HARNESS_SELFTEST=0 is deliberate here (the point is the real
  # flagless production shape), so progress-log-lib's guard arm is off and its
  # coord-sync marker otherwise falls through to the operator's REAL
  # ~/.claude/state/coord-sync/dirty. Arm 1 (explicit path) isolates it without
  # re-enabling the short-circuit this scenario exists to avoid.
  local V_ENV=(ASK_REGISTRY_STATE_DIR="$V_DIR/ar" PROGRESS_LOG_STATE_DIR="$V_DIR/pl" \
               COORD_DIRTY_MARKER_FILE="$V_DIR/coord/dirty" \
               ASK_REGISTRY_MIRROR_PATH="$V_DIR/mirror.jsonl" HARNESS_SELFTEST=0)
  env "${V_ENV[@]}" bash "$SCRIPT_DIR/ask-registry.sh" register --ask-id "ask-prod-1" \
    --text "Please rebuild the roadmap view. It must show statuses." --session-id "sess-prod" >/dev/null 2>&1
  env "${V_ENV[@]}" bash "$SCRIPT_DIR/ask-registry.sh" set-title --ask-id "ask-prod-1" \
    --title "Roadmap rebuild" >/dev/null 2>&1
  env "${V_ENV[@]}" bash "$SCRIPT_DIR/ask-registry.sh" capture-candidate --ask-id "ask-prod-1" \
    --session-id "sess-prod" --verbatim-ref "/t/prod.jsonl#1" --text "also add kanban" >/dev/null 2>&1
  local v_cid
  v_cid="$(grep '"record_type":"amendment_candidate"' "$V_REG" 2>/dev/null | sed -E 's/.*"candidate_id":"([^"]*)".*/\1/' | head -n1)"
  env "${V_ENV[@]}" bash "$SCRIPT_DIR/ask-registry.sh" detach-candidate --ask-id "ask-prod-1" \
    --candidate-id "$v_cid" >/dev/null 2>&1
  env "${V_ENV[@]}" bash "$SCRIPT_DIR/ask-registry.sh" amend --ask-id "ask-prod-1" \
    --summary "Scope: kanban toggle added" --session-id "sess-prod" >/dev/null 2>&1
  local v_ok=1
  grep -q '"record_type":"created".*"title_source":"auto"' "$V_REG" 2>/dev/null || v_ok=0
  grep -q '"record_type":"summary_updated".*"summary":"Roadmap rebuild".*"title_source":"operator"' "$V_REG" 2>/dev/null || v_ok=0
  grep -q '"record_type":"amendment_candidate".*"classification":"pending"' "$V_REG" 2>/dev/null || v_ok=0
  grep -q '"record_type":"candidate_classified".*"classification":"detached"' "$V_REG" 2>/dev/null || v_ok=0
  grep -q '"record_type":"amended".*"summary":"Scope: kanban toggle added"' "$V_REG" 2>/dev/null || v_ok=0
  if [[ "$v_ok" == "1" ]]; then
    pass "production-shape pipeline wrote the full expected record sequence (created/auto -> set-title/operator -> candidate/pending -> detached -> amended)"
  else
    fail "production-shape pipeline record sequence incomplete in $V_REG"
  fi
  if command -v jq >/dev/null 2>&1 && jq -e . "$V_REG" >/dev/null 2>&1; then
    pass "production-shape registry file is valid JSONL end-to-end (jq)"
  else
    fail "production-shape registry file failed jq validation"
  fi

  # --- model-fork argv shape (2026-07-22 re-review of be037a7, Critical class:
  # refactor-drops-flags-in-untested-live-branch). The _AR_HAIKU_CMD/_AR_CLASSIFY_CMD
  # seams replace the ENTIRE invocation, so no other scenario can see the real
  # argv; AR_DRYRUN_ARGV prints it without ever forking a model.
  local v_argv
  v_argv="$(AR_DRYRUN_ARGV=1 _ar_timeout_claude 20 "shape probe prompt")"
  # The bound is now nl_run_bounded, not bare `timeout`: `timeout` is GNU
  # coreutils and absent on stock macOS, where the old fallback dropped the
  # bound entirely and forked a live model unbounded. The assertion is
  # unchanged in strictness — it still pins the bound AND every flag.
  if [[ "$v_argv" == "nl_run_bounded 20s env -u CLAUDECODE claude --model haiku -p shape probe prompt " ]]; then
    pass "model-fork argv carries the full bounded cheap-model shape (nl_run_bounded Ns env -u CLAUDECODE claude --model haiku -p <prompt>)"
  else
    fail "model-fork argv shape regressed: got '$v_argv'"
  fi
  # And the bound must be a REAL one on this platform, not a documented
  # degradation to unbounded — the whole point of M3.
  if declare -F nl_run_bounded >/dev/null 2>&1; then
    pass "nl_run_bounded is resolvable here (the model fork is genuinely bounded, not silently unbounded)"
  else
    fail "nl_run_bounded unresolved — the cheap-model fork would run unbounded"
  fi

  # ====================================================================
  # OPERATOR-REQUIREMENT LEDGER scenarios (RL1..RL15)
  # Every fixture below is produced by the REAL verbs — no hand-written
  # JSONL is ever fed to the reader.
  # ====================================================================
  local RLREG="$REG"

  echo "Scenario RL1: record-requirement stores the operator's sentence BYTE-EXACT (quotes/backslashes survive)"
  local rl_verbatim='I do not want the agents to pin Opus. Opus is a "fallback", not the primary option (see \\model-pin).'
  cmd_register --ask-id "ask-rl" --summary "original title" --project "demo" >/dev/null
  local rl_rid; rl_rid="$(cmd_record_requirement --ask-id "ask-rl" --verbatim "$rl_verbatim")"
  if [[ "$rl_rid" == req-* ]]; then
    pass "record-requirement returned a req- id ($rl_rid)"
  else
    fail "expected a req-prefixed requirement id, got '$rl_rid'"
  fi
  if command -v jq >/dev/null 2>&1; then
    local rl_stored
    rl_stored="$(jq -rs --arg r "$rl_rid" '[.[] | select(.record_type=="requirement_recorded" and .requirement_id==$r)][-1].verbatim' "$RLREG")"
    if [[ "$rl_stored" == "$rl_verbatim" ]]; then
      pass "verbatim round-trips byte-exact through JSON escaping"
    else
      fail "verbatim was altered in storage: got '$rl_stored'"
    fi
  fi

  echo "Scenario RL2: a >140-char requirement is stored WHOLE (never sentence-split or ellipsised like a summary)"
  local rl_long="" rl_i
  for rl_i in 1 2 3 4 5 6 7 8; do
    rl_long="${rl_long}Fable stays primary and Opus is only borrowed while Fable is unavailable. "
  done
  rl_long="${rl_long}TAILMARKER-RL2"
  local rl_rid2; rl_rid2="$(cmd_record_requirement --ask-id "ask-rl" --verbatim "$rl_long")"
  if command -v jq >/dev/null 2>&1; then
    local rl_stored2
    rl_stored2="$(jq -rs --arg r "$rl_rid2" '[.[] | select(.requirement_id==$r and .record_type=="requirement_recorded")][-1].verbatim' "$RLREG")"
    if [[ "$rl_stored2" == "$rl_long" && "${#rl_long}" -gt 140 ]]; then
      pass "a ${#rl_long}-char requirement survived intact (tail marker present, no ellipsis)"
    else
      fail "long requirement was truncated/paraphrased: stored ${#rl_stored2} of ${#rl_long} chars"
    fi
  fi

  echo "Scenario RL3: one sentence -> two SEPARATELY ADDRESSABLE invariants, both listed against the shared verbatim"
  local rl_a rl_b
  rl_a="$(cmd_declare_invariant --requirement-id "$rl_rid" --text 'Fable remains the declared primary model')"
  rl_b="$(cmd_declare_invariant --requirement-id "$rl_rid" --text 'Opus is used only while Fable is unavailable')"
  if [[ "$rl_a" == "inv-1" && "$rl_b" == "inv-2" ]]; then
    pass "invariant ids are sequential within the requirement (inv-1, inv-2)"
  else
    fail "expected inv-1/inv-2, got '$rl_a'/'$rl_b'"
  fi
  local rl_rows; rl_rows="$(_ar_invariant_rows requirement "$rl_rid")"
  if [[ "$(printf '%s\n' "$rl_rows" | grep -c .)" == "2" ]]; then
    pass "invariants reader emits exactly one row per declared invariant"
  else
    fail "expected 2 invariant rows, got: $rl_rows"
  fi

  echo "Scenario RL4: ABSENCE of a verdict is NOT a pass — invariant-check exits 1 on an unverified invariant"
  local rl_out rl_rc
  rl_out="$(cmd_invariant_check --requirement-id "$rl_rid")"; rl_rc=$?
  if [[ "$rl_rc" == "1" ]] && printf '%s' "$rl_out" | grep -q '0/2 invariants hold'; then
    pass "unverified invariants fail the check (exit 1, 0/2 hold)"
  else
    fail "expected exit 1 with 0/2 holding, got rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL14: column integrity — an unverified row shows the INVARIANT TEXT in the text column, not the verbatim"
  # Regression for the tab-collapse defect: TAB is IFS-whitespace, so an empty
  # evidence cell would silently shift every later column one slot left.
  # POSITIONAL, not substring: under a column shift the invariant text is still
  # present in the line — it just moves into the evidence brackets. A bare
  # `grep -q '<the text>'` is green against the broken code and proves nothing.
  if printf '%s' "$rl_out" | grep -q "unverified  $rl_rid/$rl_a  Fable remains the declared primary model  \[-\]"; then
    pass "invariant text is rendered in its own column, with '-' in the evidence slot"
  else
    fail "column shift: invariant text missing from its own column: $rl_out"
  fi

  echo "Scenario RL16: column integrity when a verdict record EXISTS but its evidence cell is blank"
  # Distinct code path from RL14: RL14 covers the no-verdict-record branch,
  # this covers the blank-cell guard. Only `holds` requires a citation, so a
  # `violated`/`unverifiable` verdict can legitimately carry none.
  local rl_rid_b rl_e rl_rows_b
  rl_rid_b="$(cmd_record_requirement --ask-id "ask-rl" --verbatim 'the borrow is visible in the dispatch log')"
  rl_e="$(cmd_declare_invariant --requirement-id "$rl_rid_b" --text 'DISTINCTIVE-RL16-INVARIANT-TEXT')"
  cmd_invariant_verdict --requirement-id "$rl_rid_b" --invariant-id "$rl_e" --verdict unverifiable
  rl_rows_b="$(_ar_invariant_rows requirement "$rl_rid_b")"
  if [[ "$(printf '%s' "$rl_rows_b" | awk -F'\t' '{print NF}')" == "6" ]]; then
    pass "row keeps all 6 TSV columns with a blank evidence value"
  else
    fail "expected 6 TSV columns, got $(printf '%s' "$rl_rows_b" | awk -F'\t' '{print NF}')"
  fi
  # The assertion MUST go through cmd_invariant_check's bash `read` consumer.
  # awk -F'\t' honours empty fields, so an awk-only assertion cannot see the
  # tab-collapse defect at all — it would be green against the broken code.
  local rl_rendered
  rl_rendered="$(cmd_invariant_check --requirement-id "$rl_rid_b")"
  if printf '%s' "$rl_rendered" | grep -q "unverifiable  $rl_rid_b/$rl_e  DISTINCTIVE-RL16-INVARIANT-TEXT  \[-\]"; then
    pass "rendered row keeps text in the text slot and '-' in the evidence slot"
  else
    fail "column shift on blank evidence: rendered '$rl_rendered'"
  fi

  echo "Scenario RL5: GOLDEN CASE — sibling invariants from ONE sentence: one holds, one violated => check FAILS"
  # This is the 2026-07-28/29 failure verbatim: repinning 21 agents to Opus
  # satisfied "Opus is a fallback" and destroyed "Fable is primary".
  cmd_invariant_verdict --requirement-id "$rl_rid" --invariant-id "$rl_b" \
    --verdict holds --evidence 'agents/*.md:model field unset -> Fable default'
  cmd_invariant_verdict --requirement-id "$rl_rid" --invariant-id "$rl_a" \
    --verdict violated --evidence '21 agents carry an explicit `model: opus` pin'
  rl_out="$(cmd_invariant_check --requirement-id "$rl_rid")"; rl_rc=$?
  if [[ "$rl_rc" == "1" ]] && printf '%s' "$rl_out" | grep -q '1/2 invariants hold'; then
    pass "one satisfied invariant does NOT discharge its violated sibling (exit 1, 1/2 hold)"
  else
    fail "GOLDEN CASE REGRESSION: expected exit 1 with 1/2 holding, got rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL6: check passes ONLY when every invariant holds"
  cmd_invariant_verdict --requirement-id "$rl_rid" --invariant-id "$rl_a" \
    --verdict holds --evidence 'model-pin-gate.sh:120 rejects an explicit opus pin'
  rl_out="$(cmd_invariant_check --requirement-id "$rl_rid")"; rl_rc=$?
  if [[ "$rl_rc" == "0" ]] && printf '%s' "$rl_out" | grep -q '2/2 invariants hold'; then
    pass "all-hold yields exit 0 (2/2)"
  else
    fail "expected exit 0 with 2/2 holding, got rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL7: VERDICT FOLD — the LAST verdict wins, including within the same one-second ts"
  local rl_rid3 rl_c rl_n rl_collision=0
  rl_rid3="$(cmd_record_requirement --ask-id "ask-rl" --verbatim 'the borrow ends without operator action')"
  rl_c="$(cmd_declare_invariant --requirement-id "$rl_rid3" --text 'the borrow ends without operator action')"
  for rl_n in 1 2 3 4 5; do
    cmd_invariant_verdict --requirement-id "$rl_rid3" --invariant-id "$rl_c" --verdict violated --evidence 'still pinned'
    # NOTE: a `holds` evidence value must satisfy the Major-4 shape check
    # (file:line / path / 7+ hex SHA) — 'auto-restore verified' no longer does.
    cmd_invariant_verdict --requirement-id "$rl_rid3" --invariant-id "$rl_c" --verdict holds --evidence 'model-restore.sh:44 auto-restore verified'
  done
  if command -v jq >/dev/null 2>&1; then
    rl_collision="$(jq -rs --arg r "$rl_rid3" '
      [.[] | select(.record_type=="invariant_verdict" and .requirement_id==$r)]
      | group_by(.ts) | map(select(length > 1)) | length' "$RLREG")"
  fi
  rl_out="$(cmd_invariant_check --requirement-id "$rl_rid3")"; rl_rc=$?
  if [[ "$rl_collision" == "0" ]]; then
    fail "RL7 could not be exercised: no two verdicts shared a ts, so the append-index tiebreak was never on the hot path"
  elif [[ "$rl_rc" == "0" ]] && printf '%s' "$rl_out" | grep -q '1/1 invariants hold'; then
    pass "last-written verdict wins across $rl_collision same-second ts group(s)"
  else
    fail "expected the final 'holds' to win (exit 0, 1/1), got rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL8: FOLD-FIELD ABSTENTION — no ledger record writes ANY field a reader folds last-non-empty-wins"
  # Stated over the WHOLE fold list, not per-field (harness-reviewer Major 6).
  # The original assertion checked summary/title_source by hand and therefore
  # could not see that `verbatim_ref` — a sibling in the SAME reader fold array
  # — was writable via `record-requirement --verbatim-ref`, silently replacing
  # the ask's pointer to the original operator prompt. The list below is the
  # union of every reader's last-non-empty-wins fields:
  #   repo, project, verbatim_ref, status  -> derive-lib.js:110, auditor.js:302
  #   summary, title_source                -> the title-precedence fold
  #   verbatim_ref                         -> requests-routes.js:148
  # When a reader gains a folded field, ADD IT HERE — one line, not a new
  # assertion block. That is the whole point of stating the rule this way.
  local RL_FOLD_FIELDS="repo project verbatim_ref status summary title_source"
  if command -v jq >/dev/null 2>&1; then
    # ORDER MATTERS: the adversarial write happens FIRST, so the generic sweep
    # below is evaluated against a store that a defeated guard would have
    # polluted. Sweeping before the attack would leave the generic assertion
    # green under the very mutation it is supposed to catch.
    local rl_vr_rid rl_vr_stored
    rl_vr_rid="$(cmd_record_requirement --ask-id "ask-rl" --verbatim 'pointer must not move' --verbatim-ref '/tmp/HIJACKED-TRANSCRIPT.jsonl#999' 2>/dev/null)"
    rl_vr_stored="$(jq -rs --arg r "$rl_vr_rid" '[.[] | select(.requirement_id==$r and .record_type=="requirement_recorded")][-1].verbatim_ref' "$RLREG")"
    if [[ "$rl_vr_stored" == "" ]]; then
      pass "record-requirement --verbatim-ref is refused at the writer (stored verbatim_ref empty; the ask's prompt pointer survives)"
    else
      fail "--verbatim-ref reached the store as '$rl_vr_stored' — it would replace the ask's pointer to the original operator prompt"
    fi

    local rl_leak rl_fld rl_leakfields=""
    for rl_fld in $RL_FOLD_FIELDS; do
      rl_leak="$(jq -rs --arg f "$rl_fld" '[.[] | select(.record_type=="requirement_recorded" or .record_type=="invariant_declared" or .record_type=="invariant_verdict") | select(((.[$f] // "") != ""))] | length' "$RLREG")"
      [[ "$rl_leak" == "0" ]] || rl_leakfields="$rl_leakfields $rl_fld($rl_leak)"
    done
    if [[ -z "$rl_leakfields" ]]; then
      pass "no ledger record populates ANY fold-list field ($RL_FOLD_FIELDS)"
    else
      fail "ledger records leak into reader folds:$rl_leakfields"
    fi
    local rl_title
    rl_title="$(cmd_sla 2>/dev/null | awk -F'\t' '$1=="ask-rl"{print $5}')"
    if [[ "$rl_title" == "original title" ]]; then
      pass "the ask's folded title is still 'original title' after 3 requirements + 3 invariants + 12 verdicts"
    else
      fail "title fold corrupted: got '$rl_title'"
    fi
  fi

  echo "Scenario RL9: a 'holds' verdict with NO citation is refused (an unevidenced pass is the thing we are preventing)"
  local rl_rid4 rl_d
  rl_rid4="$(cmd_record_requirement --ask-id "ask-rl" --verbatim 'every claim carries a citation')"
  rl_d="$(cmd_declare_invariant --requirement-id "$rl_rid4" --text 'every claim carries a citation')"
  cmd_invariant_verdict --requirement-id "$rl_rid4" --invariant-id "$rl_d" --verdict holds 2>/dev/null
  rl_out="$(cmd_invariant_check --requirement-id "$rl_rid4")"; rl_rc=$?
  if [[ "$rl_rc" == "1" ]] && printf '%s' "$rl_out" | grep -q 'unverified'; then
    pass "evidence-free 'holds' was not persisted; the invariant stays unverified (exit 1)"
  else
    fail "an unevidenced 'holds' was accepted: rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL10: invalid verdict vocabulary is rejected"
  cmd_invariant_verdict --requirement-id "$rl_rid4" --invariant-id "$rl_d" --verdict "probably-fine" --evidence "x" 2>/dev/null
  if command -v jq >/dev/null 2>&1; then
    local rl_bad
    rl_bad="$(jq -rs '[.[] | select(.invariant_verdict=="probably-fine")] | length' "$RLREG")"
    if [[ "$rl_bad" == "0" ]]; then
      pass "out-of-vocabulary verdict was not persisted"
    else
      fail "invalid verdict 'probably-fine' reached the registry"
    fi
  fi

  echo "Scenario RL11: --plan-slug resolves plan -> ask -> requirements through the existing link-plan back-link"
  cmd_link_plan --ask-id "ask-rl" --plan-slug "operator-requirement-ledger" >/dev/null
  rl_out="$(cmd_invariant_check --plan-slug "operator-requirement-ledger")"; rl_rc=$?
  if printf '%s' "$rl_out" | grep -q 'invariants hold' && [[ "$rl_rc" == "1" ]]; then
    pass "plan-slug selector reaches this ask's invariants (and fails on the unverified one)"
  else
    fail "plan-slug selector did not resolve: rc=$rl_rc out=$rl_out"
  fi
  rl_out="$(cmd_invariant_check --plan-slug "a-plan-that-was-never-linked")"; rl_rc=$?
  if [[ "$rl_rc" == "3" ]]; then
    pass "an unlinked plan yields exit 3 (nothing registered), never a silent 0"
  else
    fail "expected exit 3 for an unlinked plan, got rc=$rl_rc"
  fi

  echo "Scenario RL12: an ask with no registered invariants is exit 3 (NOT a pass) — the opt-in property"
  cmd_register --ask-id "ask-rl-empty" --summary "no requirements here" --project "demo" >/dev/null
  rl_out="$(cmd_invariant_check --ask-id "ask-rl-empty")"; rl_rc=$?
  if [[ "$rl_rc" == "3" ]] && printf '%s' "$rl_out" | grep -q 'NOT a pass'; then
    pass "no-invariants is reported as nothing-to-check (exit 3), so the ledger never false-fires on an unenrolled ask"
  else
    fail "expected exit 3 for an ask with no invariants, got rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL13: a missing registry is CANNOT-EVALUATE (exit 4), never a green check"
  local rl_savedir="$ASK_REGISTRY_STATE_DIR"
  export ASK_REGISTRY_STATE_DIR="$TMP/ar-empty"
  mkdir -p "$ASK_REGISTRY_STATE_DIR"
  rl_out="$(cmd_invariant_check --ask-id "ask-rl" 2>/dev/null)"; rl_rc=$?
  export ASK_REGISTRY_STATE_DIR="$rl_savedir"
  if [[ "$rl_rc" == "4" ]] && printf '%s' "$rl_out" | grep -q 'NOT a pass'; then
    pass "degraded environment yields exit 4, distinct from both pass (0) and fail (1)"
  else
    fail "expected exit 4 on a missing registry, got rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL15: the ROUTER propagates the check's exit code (exit \$?, not the write verbs' exit 0)"
  # Every scenario above calls cmd_* in-process, so all of them would still
  # pass if the router swallowed the code. Only a real subprocess proves it.
  local rl_sub_rc rl_sub_rc0
  bash "$0" invariant-check --requirement-id "$rl_rid" >/dev/null 2>&1; rl_sub_rc0=$?
  bash "$0" invariant-check --requirement-id "$rl_rid4" >/dev/null 2>&1; rl_sub_rc=$?
  if [[ "$rl_sub_rc0" == "0" && "$rl_sub_rc" == "1" ]]; then
    pass "subprocess exit codes differ by outcome (all-hold=0, unverified=1) — the router does not swallow them"
  else
    fail "router exit-code propagation broken: all-hold gave $rl_sub_rc0 (want 0), unverified gave $rl_sub_rc (want 1)"
  fi

  # ====================================================================
  # harness-reviewer REJECT round (2026-07-29): one scenario per defect.
  # Each is written to go RED against the pre-fix code — see the fix's own
  # comment block for the mechanism it regresses.
  # ====================================================================

  echo "Scenario RL17 (Critical 1): the ONE writer refuses an empty ask_id, so no verb can create the uncloseable phantom ask"
  # Called at the WRITER, not through a verb: the point of the fix is that a
  # FUTURE verb which forgets the -z guard still cannot poison the store.
  local rl_before rl_after rl_wrc rl_wout
  rl_before="$(grep -ac . "$RLREG" 2>/dev/null || echo 0)"
  rl_wout="$(_ar_append_record "invariant_declared" "" "" "" "" "" "" "" "" "" "" "" "future-verb" \
    "" "" "" "" "" "req-does-not-matter" "" "inv-9" "phantom" "" "" 2>/dev/null)"; rl_wrc=$?
  rl_after="$(grep -ac . "$RLREG" 2>/dev/null || echo 0)"
  if [[ "$rl_before" == "$rl_after" ]]; then
    pass "empty-ask_id append was refused at the writer (line count unchanged at $rl_after)"
  else
    fail "an empty-ask_id record reached the store ($rl_before -> $rl_after lines)"
  fi
  if [[ "$rl_wrc" == "0" && -z "$rl_wout" ]]; then
    pass "writer honoured never-blocks-caller (exit 0) while signalling refusal in-band (empty path on stdout)"
  else
    fail "expected exit 0 + empty stdout on refusal, got rc=$rl_wrc out='$rl_wout'"
  fi
  # The blast radius, asserted directly: readers group by ask_id.
  if command -v jq >/dev/null 2>&1; then
    local rl_phantom
    rl_phantom="$(jq -rs '[.[] | select((.ask_id // "") == "")] | length' "$RLREG")"
    if [[ "$rl_phantom" == "0" ]]; then
      pass "zero empty-ask_id records exist in the whole store — group_by(.ask_id) cannot synthesise a phantom ask"
    else
      fail "$rl_phantom empty-ask_id record(s) present; estate-janitor would render an uncloseable blank ask"
    fi
  fi

  echo "Scenario RL18 (Critical 1): declare-invariant/invariant-verdict file under the requirement's OWN ask without being told it"
  local rl_r18 rl_i18 rl_ask18 rl_vask18
  rl_r18="$(cmd_record_requirement --ask-id "ask-rl-resolve" --verbatim 'the ask id must be derivable')"
  rl_i18="$(cmd_declare_invariant --requirement-id "$rl_r18" --text 'RL18-RESOLVED-INVARIANT')"
  cmd_invariant_verdict --requirement-id "$rl_r18" --invariant-id "$rl_i18" \
    --verdict holds --evidence 'ask-registry.sh:1 resolver returns the requirement ask'
  if command -v jq >/dev/null 2>&1; then
    rl_ask18="$(jq -rs --arg r "$rl_r18" '[.[] | select(.record_type=="invariant_declared" and .requirement_id==$r)][-1].ask_id' "$RLREG")"
    rl_vask18="$(jq -rs --arg r "$rl_r18" '[.[] | select(.record_type=="invariant_verdict" and .requirement_id==$r)][-1].ask_id' "$RLREG")"
    if [[ "$rl_ask18" == "ask-rl-resolve" && "$rl_vask18" == "ask-rl-resolve" ]]; then
      pass "both records carry the resolved ask_id 'ask-rl-resolve' (no --ask-id was passed)"
    else
      fail "ask_id not resolved: declared='$rl_ask18' verdict='$rl_vask18' (want ask-rl-resolve)"
    fi
  fi
  # And the user-visible consequence: the --ask-id selector now reaches them.
  rl_out="$(cmd_invariant_check --ask-id "ask-rl-resolve")"; rl_rc=$?
  if [[ "$rl_rc" == "0" ]] && printf '%s' "$rl_out" | grep -q '1/1 invariants hold'; then
    pass "--ask-id selector reaches the invariant purely via the resolved id (exit 0, 1/1)"
  else
    fail "resolved invariant unreachable by --ask-id: rc=$rl_rc out=$rl_out"
  fi

  echo "Scenario RL19 (Critical 2): a torn JSONL line is CANNOT-EVALUATE (4), never 'nothing registered' (3)"
  # The exact silent-pass the reviewer reproduced: with a `violated` invariant
  # present, one truncated line made the row set empty -> exit 3 -> task-verifier
  # Step 1.6 treats 3 as "not a failure signal ... proceed".
  local rl_r19 rl_i19 rl_torn_rc rl_torn_out
  rl_r19="$(cmd_record_requirement --ask-id "ask-rl-torn" --verbatim 'a torn line must not read as a pass')"
  rl_i19="$(cmd_declare_invariant --requirement-id "$rl_r19" --text 'RL19-VIOLATED-INVARIANT')"
  cmd_invariant_verdict --requirement-id "$rl_r19" --invariant-id "$rl_i19" \
    --verdict violated --evidence 'docs/plans/x.md:7 still broken'
  # Pre-condition: the violation IS visible while the store is intact.
  rl_out="$(cmd_invariant_check --ask-id "ask-rl-torn")"; rl_rc=$?
  if [[ "$rl_rc" == "1" ]]; then
    pass "pre-condition: the violated invariant is detected (exit 1) on an intact store"
  else
    fail "pre-condition failed: expected exit 1 on the intact store, got $rl_rc"
  fi
  printf '%s' '{"ask_id":"truncated-partial-write' >> "$RLREG"
  rl_torn_out="$(cmd_invariant_check --ask-id "ask-rl-torn" 2>/dev/null)"; rl_torn_rc=$?
  if [[ "$rl_torn_rc" == "4" ]]; then
    pass "torn line yields exit 4 CANNOT-EVALUATE (pre-fix this was 3 = 'nothing registered' = proceed)"
  else
    fail "SILENT-PASS REGRESSION: a torn line gave exit $rl_torn_rc (want 4); at 3 a verifier proceeds past a violated invariant"
  fi
  if printf '%s' "$rl_torn_out" | grep -q 'NOT a pass'; then
    pass "the degraded read says so in-band"
  else
    fail "degraded read did not announce itself: '$rl_torn_out'"
  fi
  # `invariants` (the other reader over this store) must degrade identically.
  cmd_invariants --ask-id "ask-rl-torn" >/dev/null 2>&1; rl_rc=$?
  if [[ "$rl_rc" == "4" ]]; then
    pass "cmd_invariants propagates the same CANNOT-EVALUATE 4"
  else
    fail "cmd_invariants returned $rl_rc on a torn store (want 4)"
  fi
  # `sla` is the third jq reader over this store — an empty table there reads
  # as "nothing is overdue".
  cmd_sla >/dev/null 2>&1; rl_rc=$?
  if [[ "$rl_rc" == "4" ]]; then
    pass "cmd_sla also refuses to render an empty (= 'nothing overdue') table on a torn store"
  else
    fail "cmd_sla returned $rl_rc on a torn store (want 4)"
  fi
  # THROUGH THE ROUTER, in a real subprocess. The in-process assertion above
  # cannot see a router that swallows the code — and it did: `sla` was routed
  # `exit 0` like a write verb, so the guard above was green while the CLI
  # (the only way anything actually calls this) still reported success on an
  # unparseable store. Assert the surface the caller observes, not the
  # intermediate return value.
  bash "$0" sla >/dev/null 2>&1; rl_rc=$?
  if [[ "$rl_rc" == "4" ]]; then
    pass "the ROUTER propagates sla's CANNOT-EVALUATE 4 to the CLI exit code"
  else
    fail "router swallowed sla's degrade signal: CLI exit $rl_rc on a torn store (want 4)"
  fi
  bash "$0" invariants --ask-id "ask-rl-torn" >/dev/null 2>&1; rl_rc=$?
  if [[ "$rl_rc" == "4" ]]; then
    pass "the ROUTER propagates invariants' CANNOT-EVALUATE 4 too"
  else
    fail "router swallowed invariants' degrade signal: CLI exit $rl_rc (want 4)"
  fi
  # Repair the fixture store for the scenarios that follow.
  local rl_repair="$TMP/repaired.jsonl"
  grep -a '"record_type"' "$RLREG" | grep -a '}$' > "$rl_repair" 2>/dev/null
  mv "$rl_repair" "$RLREG"
  cmd_invariant_check --ask-id "ask-rl-torn" >/dev/null 2>&1; rl_rc=$?
  if [[ "$rl_rc" == "1" ]]; then
    pass "store repaired; the violated invariant is visible again (exit 1)"
  else
    fail "fixture repair failed: rc=$rl_rc"
  fi

  echo "Scenario RL20 (Critical 3): THE LEDGER'S OWN GOLDEN CASE — a typo'd requirement-id is refused, not silently dropped"
  # Pre-fix: this printed 'inv-1' (a success confirmation), wrote a record
  # invisible to BOTH task-verifier selectors, and invariant-check then said
  # exit 3 'nothing registered' => proceed. A clause vanishes; the checker
  # reports green. That is the exact failure class the ledger exists to stop.
  local rl_r20 rl_typo_out rl_typo_id
  rl_r20="$(cmd_record_requirement --ask-id "ask-rl-typo" --verbatim 'Fable stays primary; Opus only while it is unavailable')"
  rl_typo_id="$(cmd_declare_invariant --requirement-id "${rl_r20}X" --text 'FABLE IS PRIMARY -- THE LOST INVARIANT' 2>/dev/null)"
  if [[ -z "$rl_typo_id" ]]; then
    pass "a typo'd --requirement-id returns NOTHING (pre-fix it returned 'inv-1', a success confirmation)"
  else
    fail "typo'd requirement-id was accepted and confirmed as '$rl_typo_id'"
  fi
  if command -v jq >/dev/null 2>&1; then
    local rl_orphans
    rl_orphans="$(jq -rs '
      ([.[] | select(.record_type=="requirement_recorded") | .requirement_id] | unique) as $known |
      [.[] | select(.record_type=="invariant_declared" or .record_type=="invariant_verdict")
           | select((.requirement_id // "") | IN($known[]) | not)] | length' "$RLREG")"
    if [[ "$rl_orphans" == "0" ]]; then
      pass "the store holds ZERO invariant/verdict records orphaned from a requirement_recorded"
    else
      fail "$rl_orphans orphaned ledger record(s) — each is a clause that invariant-check will report as 'nothing registered'"
    fi
  fi
  # A verdict against a phantom requirement is refused on the same contract.
  cmd_invariant_verdict --requirement-id "${rl_r20}X" --invariant-id "inv-1" \
    --verdict holds --evidence 'some/path.sh:12' 2>/dev/null
  if command -v jq >/dev/null 2>&1; then
    local rl_ghostv
    rl_ghostv="$(jq -rs --arg r "${rl_r20}X" '[.[] | select(.requirement_id==$r)] | length' "$RLREG")"
    if [[ "$rl_ghostv" == "0" ]]; then
      pass "a verdict against a non-existent requirement is refused too (0 records under the typo'd id)"
    else
      fail "$rl_ghostv record(s) written under the typo'd requirement id"
    fi
  fi

  echo "Scenario RL21 (Major 4): a 'holds' citation must survive trimming AND look like a citation"
  local rl_r21 rl_i21 rl_ev rl_acc
  rl_r21="$(cmd_record_requirement --ask-id "ask-rl-ev" --verbatim 'every claim carries a real citation')"
  rl_i21="$(cmd_declare_invariant --requirement-id "$rl_r21" --text 'RL21-EVIDENCE-INVARIANT')"
  # The reviewer's full defeat set. '   ' is the load-bearing one: the reader's
  # `cell` maps ^ *$ to '-', so it rendered IDENTICALLY to an unverified row.
  for rl_ev in '   ' '	' 'x' '.' '0' '-' 'trust me' 'verified'; do
    cmd_invariant_verdict --requirement-id "$rl_r21" --invariant-id "$rl_i21" \
      --verdict holds --evidence "$rl_ev" 2>/dev/null
  done
  rl_out="$(cmd_invariant_check --requirement-id "$rl_r21")"; rl_rc=$?
  if [[ "$rl_rc" == "1" ]] && printf '%s' "$rl_out" | grep -q 'unverified'; then
    pass "all 8 non-citations were refused; the invariant stays unverified (exit 1)"
  else
    fail "a non-citation was accepted as a pass: rc=$rl_rc out=$rl_out"
  fi
  # Positive control — the guard must not eat real citations (over-fire check).
  rl_acc=0
  for rl_ev in 'ask-registry.sh:1683' 'docs/plans/p.md' '417c4344d3c7aa8' 'agents/*.md:12 unset'; do
    cmd_invariant_verdict --requirement-id "$rl_r21" --invariant-id "$rl_i21" \
      --verdict holds --evidence "$rl_ev" 2>/dev/null
    cmd_invariant_check --requirement-id "$rl_r21" >/dev/null 2>&1 && rl_acc=$((rl_acc + 1))
  done
  if [[ "$rl_acc" == "4" ]]; then
    pass "all 4 genuine citation shapes (file:line, path, SHA, glob:line) are accepted — the guard does not over-fire"
  else
    fail "the shape check rejected a real citation ($rl_acc/4 accepted)"
  fi

  echo "Scenario RL22 (Major 5): the verbatim cap LEAVES A MARK — 4001 chars is distinguishable from a genuine 4000"
  local rl_4001 rl_4000 rl_r22a rl_r22b rl_s22a rl_s22b
  rl_4001="$(_ar_repeat_char 4001)"
  rl_4000="$(_ar_repeat_char 4000)"
  if [[ "${#rl_4001}" == "4001" && "${#rl_4000}" == "4000" ]]; then
    pass "fixture lengths are exact (4001 / 4000 chars)"
  else
    fail "fixture generation wrong: ${#rl_4001} / ${#rl_4000}"
  fi
  rl_r22a="$(cmd_record_requirement --ask-id "ask-rl-cap" --verbatim "$rl_4001")"
  rl_r22b="$(cmd_record_requirement --ask-id "ask-rl-cap" --verbatim "$rl_4000")"
  if command -v jq >/dev/null 2>&1; then
    rl_s22a="$(jq -rs --arg r "$rl_r22a" '[.[] | select(.requirement_id==$r and .record_type=="requirement_recorded")][-1].verbatim' "$RLREG")"
    rl_s22b="$(jq -rs --arg r "$rl_r22b" '[.[] | select(.requirement_id==$r and .record_type=="requirement_recorded")][-1].verbatim' "$RLREG")"
    # POSITIVE: the cap fired and said so, with the exact loss quantified.
    if printf '%s' "$rl_s22a" | grep -q '\[TRUNCATED: 1 chars omitted\]$'; then
      pass "4001-char requirement is stored with an explicit '[TRUNCATED: 1 chars omitted]' marker"
    else
      fail "SILENT LOSS: 4001-char requirement carries no truncation marker (tail: '$(printf '%s' "$rl_s22a" | tail -c 40)')"
    fi
    # NEGATIVE: the boundary case must NOT be marked (no false 'lossy' claim).
    if printf '%s' "$rl_s22b" | grep -q 'TRUNCATED'; then
      fail "FALSE MARKER: a genuine 4000-char requirement was labelled truncated"
    else
      pass "a genuine 4000-char requirement carries NO marker (boundary, cap did not fire)"
    fi
    # The two are now distinguishable — the whole point of the finding.
    if [[ "$rl_s22a" != "$rl_s22b" ]]; then
      pass "an over-cap paste and a genuine at-cap requirement are no longer byte-identical in the store"
    else
      fail "4001-char and 4000-char requirements are indistinguishable once stored"
    fi
    # And the preserved prefix is still EXACT (content-preserving contract).
    if [[ "${rl_s22a:0:4000}" == "$rl_4000" ]]; then
      pass "the first 4000 characters are preserved byte-exact ahead of the marker"
    else
      fail "the preserved prefix was altered by the truncation path"
    fi
  fi

  echo "Scenario RL23 (Major 5): \${#s} counts CHARACTERS, not bytes — the header comment claim is testable"
  # The old header called this a 'byte-count cap'. Under a UTF-8 locale a
  # 3-byte character counts as ONE, so the real byte ceiling is up to 4x the
  # stated number. Assert the semantics the comment now claims.
  local rl_multi; rl_multi='日本語'
  if [[ "${#rl_multi}" == "3" ]]; then
    pass "\${#s} is character-counting under this locale (3 chars for a 9-byte string) — 'byte-count cap' was wrong by 3x here"
  elif [[ "${#rl_multi}" == "9" ]]; then
    pass "\${#s} is byte-counting under this C locale (9) — cap is a byte cap here; the header documents both readings"
  else
    fail "unexpected length semantics: ${#rl_multi}"
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
  set-deadline)
    shift
    cmd_set_deadline "$@"
    exit 0
    ;;
  clear-deadline)
    shift
    cmd_clear_deadline "$@"
    exit 0
    ;;
  set-default-action)
    shift
    cmd_set_default_action "$@"
    exit 0
    ;;
  # `exit $?`, NOT the write verbs' `exit 0`: since the Critical-2 sweep, sla
  # returns 4 when jq cannot parse the store, and an empty SLA table reads as
  # "nothing is overdue". Routed through `exit 0` that signal died at the CLI
  # — which is the ONLY way anything calls this verb — so the guard would have
  # been documented-but-inert. Its two other degrade paths (no registry, no jq)
  # still return 0, so this changes nothing for a healthy store.
  sla)
    shift
    cmd_sla "$@"
    exit $?
    ;;
  set-title)
    shift
    cmd_set_title "$@"
    exit 0
    ;;
  capture-candidate)
    shift
    cmd_capture_candidate "$@"
    exit 0
    ;;
  classify-candidate)
    shift
    cmd_classify_candidate "$@"
    exit 0
    ;;
  detach-candidate)
    shift
    cmd_detach_candidate "$@"
    exit 0
    ;;
  amend)
    shift
    cmd_amend "$@"
    exit 0
    ;;
  record-requirement)
    shift
    cmd_record_requirement "$@"
    exit 0
    ;;
  declare-invariant)
    shift
    cmd_declare_invariant "$@"
    exit 0
    ;;
  invariant-verdict)
    shift
    cmd_invariant_verdict "$@"
    exit 0
    ;;
  invariants)
    shift
    cmd_invariants "$@"
    exit $?
    ;;
  # NOTE: `exit $?`, NOT the `exit 0` every write verb uses. invariant-check is
  # the one verb whose exit code IS its output; routing it through `exit 0`
  # would make the check structurally incapable of failing.
  invariant-check)
    shift
    cmd_invariant_check "$@"
    exit $?
    ;;
  list)
    shift
    cmd_list "$@"
    exit 0
    ;;
  heuristic-summarize)
    shift
    cmd_heuristic_summarize "$@"
    exit 0
    ;;
  gen-ask-id)
    shift
    cmd_gen_ask_id "$@"
    exit 0
    ;;
  --self-test|--selftest|selftest|self-test)
    # NOTE: this host does NOT need `export HARNESS_SELFTEST=1` here — cmd_selftest
    # already exports it as its first act (see the export beside the tempdir
    # setup). Adding a second one here would be inert decoration. Its clean-HOME
    # leak had a different cause; see the COORD_DIRTY_MARKER_FILE note in
    # Scenario L1 / Scenario V.
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
  merge --ask-id <source-id> --into <target-id> [--emitter <name>]
                          Mark source as a duplicate of target.
  override-project --ask-id <id> --project <name>
                          Operator override of an ask's project grouping.
  set-deadline --ask-id <id> --deadline <iso8601> [--emitter <name>]
                          Set/update the ask's deadline (rejects an
                          unparseable timestamp; normalizes to canonical
                          UTC form before storing).
  clear-deadline --ask-id <id> [--emitter <name>]
                          Remove a previously-set deadline.
  set-default-action --ask-id <id> --default-action <text> [--emitter <name>]
                          Record what should happen if the deadline
                          passes unanswered (data only this slice).
  sla [--now <iso8601>] [--due-soon-hours <n>]
                          Read-only: list active asks with SLA state
                          (overdue|due-soon|ok|no-deadline), sorted
                          soonest-deadline-first.
  set-title --ask-id <id> --title <text> [--emitter <name>]
                          Operator title edit (title_source=operator — ALWAYS
                          outranks auto at fold time, regardless of
                          timestamps; A3). UI edits delegate here.
  capture-candidate --ask-id <id> --verbatim-ref <ref> [--candidate-id <id>]
                    [--session-id <id>] [--text <raw>]
                          Append one operator prompt as a timeline candidate
                          (ref only, raw text never stored; classification=
                          pending; async classify under ASK_SUMMARIZER=haiku).
  classify-candidate --ask-id <id> --candidate-id <id>
                     --classification <amendment|noise|detached>
                     [--summary <label>] [--emitter <name>]
                          Write a classification verdict (async lane or
                          operator correction; rejects invalid vocabulary).
  detach-candidate --ask-id <id> --candidate-id <id> [--emitter <name>]
                          Operator "not an amendment" correction (I6).
  amend --ask-id <id> (--summary <label> | --text <raw>) [--session-id <id>]
        [--verbatim-ref <ref>] [--emitter <name>]
                          Explicit first-class amendment (model-invoked
                          supplement; labeled memory-dependent).

OPERATOR-REQUIREMENT LEDGER (the operator's words as a checkable artifact):
  record-requirement --ask-id <id> --verbatim <text> [--requirement-id <id>]
                     [--verbatim-ref <ref>] [--session-id <id>] [--emitter <n>]
                          Store the operator's sentence VERBATIM (never
                          paraphrased, never sentence-split, NOT passed through
                          the 140-char summariser). Prints the requirement_id.
  declare-invariant --requirement-id <id> --text <statement>
                    [--invariant-id <id>] [--ask-id <id>] [--emitter <n>]
                          Declare ONE separately-checkable statement extracted
                          from that sentence. One sentence routinely carries
                          two invariants; declare each. Prints the invariant_id.
  invariant-verdict --requirement-id <id> --invariant-id <id>
                    --verdict <holds|violated|unverifiable> [--evidence <ref>]
                    [--ask-id <id>] [--emitter <n>]
                          Record a verifier's per-invariant judgement.
                          `holds` REQUIRES --evidence (a citation).
  invariants [--requirement-id <id> | --ask-id <id> | --plan-slug <slug>]
                          Read-only TSV: requirement_id, invariant_id, verdict,
                          evidence_ref, invariant_text, verbatim.
  invariant-check [--requirement-id <id> | --ask-id <id> | --plan-slug <slug>]
                          THE CHECKING STEP. Exit 0 = every invariant in scope
                          holds; 1 = at least one violated/unverifiable/
                          unverified; 3 = nothing registered in scope; 4 =
                          cannot evaluate. 3 and 4 are NOT passes.
  list                    Print the raw registry JSONL (read-only).
  heuristic-summarize --text <raw>
                          Read-only: prints the markdown-stripped/first-
                          sentence/140-char-capped label (no registry
                          access, no side effect) — the SAME summarizer
                          `register` and the deterministic classifier use,
                          exposed for backfill-classify-amendment-candidates.sh.
  gen-ask-id --summary <text>
                          Read-only: prints a deterministic-shaped
                          ask-<date>-<slug>-<4hex> id (no registry access,
                          no side effect) — the SAME id generator `register`
                          uses when --ask-id is omitted, exposed so a
                          caller can mint the id UP FRONT and pass it back
                          to `register --ask-id` explicitly (backfill-
                          classify-amendment-candidates.sh's promote path).
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
