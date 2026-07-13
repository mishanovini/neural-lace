# Plan: Master-Drift Auto-Correction (FF-only, dedicated-clone)

OPERATOR GREENLIGHT REQUIRED before Task 1 — see NEEDS-YOU.md

Status: ACTIVE
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal git plumbing; the user is the maintainer — the --self-test suites plus one live run against the real remote pair are the demonstration.
tier: 2
rung: 4
architecture: coding-harness
frozen: false
lifecycle-schema: v2
owner: misha
target-completion-date: 2026-07-31
prd-ref: n/a — harness-development

<!--
Greenlight gate: this plan implements handoff Task 2 of
docs/handoffs/masters-reconciled-remaining-2026-07-11.md, which the handoff
explicitly marks "needs operator greenlight" before building. Status stays
DRAFT and frozen stays false until the operator answers the NEEDS-YOU.md
entry; Task 1 below is the recorded greenlight itself. Nothing in Tasks 2-7
may be built before Task 1 is checked.
-->

## Goal

The repo has two masters — `origin/master` (personal remote) and the mirror
remote's master (work-org remote, locally named `pt`). Local pushes dual-push
both, but GitHub SERVER-SIDE PR merges land on exactly one of them, so the
two masters drift apart until someone notices. Detection already exists (the
SessionStart hook `adapters/claude-code/hooks/session-start-git-freshness.sh`
compares LOCAL master against each remote master); what is missing is
AUTO-CORRECTION of the benign case and loud, single-line surfacing of the
dangerous case.

This plan designs (and, after operator greenlight, builds) a
fast-forward-only drift corrector that runs from the existing session-start
detection path, performs every mutating git operation inside the F.6
dedicated sync clone (`~/.claude/sync-clone/<repo-basename>` — never a live
checkout), pushes the strictly-behind master forward when and only when
`git merge-base --is-ancestor` proves fast-forwardability, and emits exactly
one digest line when the masters have truly diverged (auto-merge is
categorically refused; divergence always demands a reviewed merge per the
handoff's reconcile procedure).

Operator-set constraints this design honors:
- NO GitHub Action mirror. The mirror Action was deliberately reverted
  2026-05-28 (commit `5bf55c7`: "PAT cross-account operational burden
  disproportionate; drift coverage moves to a harness-internal mechanism").
  This plan does not resurrect it in any form.
- NO tokens. No PAT is created, stored, or read. The corrector reuses the
  machine's existing git credential surface — the same credentials the
  established local dual-push already uses.
- FF-only. Only a master that is STRICTLY BEHIND its sibling is auto-synced.
  True divergence (neither SHA is an ancestor of the other) is surfaced,
  never auto-merged.
- Never touch live checkouts. All fetch/push runs inside the dedicated sync
  clone (F.6 / specs-e §SYNC-CLONE-C architecture, already shipped in
  `adapters/claude-code/scripts/sync-pt-to-personal.sh`); the interactive
  checkout is used read-only for remote-URL discovery.

## Existing mechanisms this plan builds ON TOP OF (verified on disk 2026-07-12)

1. **Interactive-session lock (B.12)** —
   `adapters/claude-code/hooks/lib/interactive-session-lock.sh` exists
   in-tree AND in the live mirror (`~/.claude/hooks/lib/`). Its header
   contract binds every unattended tree-mutator. The corrector sources it
   and inherits the F.6 verdict-branching: caller checkout distinct from the
   sync clone → LOG-AND-PROCEED (caller tree is never touched); degenerate
   invocation from inside the clone → REFUSE.
2. **F.6 dedicated sync clone (specs-e §SYNC-CLONE-C)** — shipped in
   `adapters/claude-code/scripts/sync-pt-to-personal.sh`: all mutating git
   ops run in `$SYNC_CLONE_DIR` (default `~/.claude/sync-clone/<repo-basename>`),
   bootstrapped on demand from the caller's remote URLs via read-only
   `git remote get-url`; never force-pushes; `--self-test` green is its
   demonstration. The corrector REUSES this exact architecture (and its
   `_discover_mirror_remote` pattern) rather than inventing a second one.
   Note: `~/.claude/sync-clone/` is not yet materialized on this machine —
   the clone is bootstrapped on first real run; that is the designed
   behavior, not a gap.
3. **Detection** — `session-start-git-freshness.sh` fetches all remotes
   (timeout-bounded) and reports local-vs-remote master state into the
   consolidated session-start digest (`session-start-digest.sh`, "git
   freshness" feed). Gap this plan closes: it never compares the two REMOTE
   masters against each other, so remote-vs-remote drift is only surfaced
   indirectly (via whichever remote the local master trails).

## Disposition: `~/.claude/local/workstreams-sync.config.PAUSED-2026-06-02-thrash-investigation`

The handoff asks whether this pause can be lifted now that F.6 landed.
Verified 2026-07-12: **the question is moot — there is no pause left to
lift.**

- The PAUSED file is ABSENT from `~/.claude/local/` (checked with a forced
  directory listing; neither the PAUSED name nor an active
  `workstreams-sync.config` exists).
- The config's only-ever consumer — the `sync-events` subcommand of
  `broadcast-active-session.sh` — exists NOWHERE in the current tree
  (`grep -rn sync-events adapters/` → 0 matches) nor in the live
  `~/.claude/scripts/` / `~/.claude/hooks/` (backups excluded). It lived
  only on the never-merged `feat/component-c-cross-machine-sync` branch,
  which no longer exists on any remote.

Disposition (recorded into the originating discovery by Task 6): the
2026-06-02 stopgap ended when the file left disk; nothing reads that config
today, so neither restoring nor deleting it changes any runtime behavior.
If Component-C cross-machine sync is ever rebuilt, it must inherit the ISL
contract + the F.6 dedicated-clone architecture by design (the
interactive-session-lock.sh header already binds it verbatim) — it must NOT
re-arm via the old config name.

## User-facing Outcome

n/a — harness-internal: the user is the maintainer. After this plan ships,
a server-side PR merge that advances one master no longer silently strands
the other: within one session start on this machine, the behind master is
fast-forwarded to match (observable: `git rev-parse origin/master
<mirror>/master` prints EQUAL SHAs), and a genuine divergence produces
exactly one `[master-drift] DIVERGED …` digest line pointing at the runbook
instead of being discovered mid-push days later.

## Scope

- IN: a new standalone corrector script
  `adapters/claude-code/scripts/master-drift-autocorrect.sh` (dedicated-clone,
  FF-only, self-tested); a remote-vs-remote comparison + backgrounded
  corrector dispatch added to
  `adapters/claude-code/hooks/session-start-git-freshness.sh`; one digest
  line for the divergence case; a runbook
  `docs/runbooks/master-drift-autocorrect.md`; `adapters/claude-code/manifest.json`
  + doctor wiring; the PAUSED-config disposition note appended to
  `docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md`.
- OUT: any GitHub Action or server-side mirror (operator-reverted `5bf55c7`);
  any PAT/token creation or storage; auto-merging diverged masters (always a
  reviewed merge per the handoff procedure); a scheduled/daemon runner (see
  Decisions Log D1 — rejected in favor of the session-start path);
  cross-machine workstreams-state sync (Component C) in any form; changes to
  `sync-pt-to-personal.sh` (it serves the different-SHA cherry-pick era and
  stays as-is); drift handling for any branch other than `master`.

## Mechanism sketch

**Where it runs — session-start hook extension (chosen), not a scheduled
task.** `session-start-git-freshness.sh` already fetches all remotes at
every session start; it gains a remote-vs-remote comparison
(`origin/master` vs `<mirror>/master` SHAs, discovered per the
`_discover_mirror_remote` pattern) and, on inequality, dispatches
`master-drift-autocorrect.sh` BACKGROUNDED (`&` + disown, output to the
corrector's own log) so session start gains zero blocking seconds. A
scheduled task was rejected: drift only matters when someone is about to
work — which is exactly when sessions start — and an unattended daemon
mutator is the failure class the 2026-06-02 discovery documents; the
session-start path keeps a human present for every correction. The
corrector is also directly invocable by hand (same script, no arguments)
for on-demand runs.

**How FF-only is asserted.** Inside the dedicated clone, after
`git fetch origin && git fetch <mirror>`:

- SHAs equal → exit 0 silently (one line to its own log only).
- `git merge-base --is-ancestor <mirrorSHA> <originSHA>` → mirror strictly
  behind: `git push <mirror> <originSHA>:master` (plain push — never
  `--force`; the server rejecting non-FF is the independent backstop if a
  concurrent push races the check).
- The reverse ancestor test → origin strictly behind: symmetric plain push.
- NEITHER is an ancestor → DIVERGED: touch nothing, write the divergence
  state file, exit 0 (surfacing is the next session start's digest line).

Because the two masters are SHA-converged since the 2026-07-11
reconciliation (handoff: they "must be EQUAL"), FF pushes preserve
SHA-identity — no cherry-picking, no new commit objects, ever.

**Failure/divergence surfacing — one digest line.** The corrector writes
`~/.claude/state/master-drift/<repo-basename>.status` (single line:
`CONVERGED <sha7>` | `CORRECTED <remote> <sha7>` | `DIVERGED <sha7-origin> <sha7-mirror>` |
`PUSH-REJECTED <remote> <reason-word>`). The git-freshness hook reads that
file on the NEXT session start and, for the non-quiet states, emits exactly
one line into the existing digest feed, e.g.:
`[master-drift] DIVERGED origin/master=<sha7> <mirror>/master=<sha7> — auto-sync refused; reviewed merge required (docs/runbooks/master-drift-autocorrect.md)`.
The line is deduplicated by the digest's existing per-feed dedup once
acknowledged/resolved (state file returns to CONVERGED).

## Tasks

- [x] Task 1: operator greenlight recorded — operator replied "greenlight" in-session 2026-07-12 ~15:0x (see checkpoint OPERATOR DIRECTIVES block) — Verification: mechanical — Docs impact: none — the greenlight itself is recorded here (checkbox + date + the operator's exact reply pasted below this line) and the NEEDS-YOU.md entry is closed in the same commit. Flips Status: DRAFT → ACTIVE and frozen: false → true.
- [ ] 2. Build `adapters/claude-code/scripts/master-drift-autocorrect.sh` — dedicated-clone bootstrap (reuse the F.6 pattern from `sync-pt-to-personal.sh`), ISL sourcing with F.6 verdict-branching, FF-only compare/push logic per the mechanism sketch, single-instance lock (`mkdir`-based, inside the clone dir), status-file writer, `--self-test` covering the full scenario matrix (see Testing Strategy) — Verification: mechanical — Docs impact: none — runbook authored in Task 5; script carries the full header contract.
- [ ] 3. Extend `adapters/claude-code/hooks/session-start-git-freshness.sh`: remote-vs-remote master SHA comparison; backgrounded dispatch of the corrector on inequality; status-file → digest-line rendering for CORRECTED / DIVERGED / PUSH-REJECTED; extend its `--self-test` matrix accordingly — Verification: mechanical — Docs impact: hook header comment gains the new feed description.
- [ ] 4. Register the mechanism: `adapters/claude-code/manifest.json` entry + `harness-doctor.sh` predicate (script exists, is executable, `--self-test` exits 0, hook wiring present), so the doctor arbitrates the mechanism claim per constitution §10 — Verification: mechanical — Docs impact: manifest entry is the doc.
- [ ] 5. Author `docs/runbooks/master-drift-autocorrect.md`: what auto-corrects vs what never will; the DIVERGED procedure (verbatim the handoff's reconcile steps: temp worktree off `origin/master`, `git merge --no-ff` the mirror master, DECISIONS.md union rule, dual push, re-verify EQUAL); kill switch (`MASTER_DRIFT_AUTOCORRECT=0` env honored by the hook); PUSH-REJECTED triage (wrong-account 403 → `gh auth switch -u <owner>` guidance) — Verification: mechanical — Docs impact: the runbook itself.
- [ ] 6. Append the PAUSED-config disposition (section above, condensed) to the Implementation log of `docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md` so the discovery stops carrying an open question — Verification: mechanical — Docs impact: discovery implementation-log entry.
- [ ] 7. Live demonstration against the real remote pair — Verification: full — Docs impact: evidence files under the plan's evidence dir.
    **Prove it works:**
    1. Run `bash adapters/claude-code/scripts/master-drift-autocorrect.sh` from the main checkout with both masters converged → output reports CONVERGED, status file says `CONVERGED <sha7>`, `git rev-parse` of both remote masters prints equal SHAs, zero writes to the interactive checkout (its `git status` and HEAD unchanged before/after).
    2. If a real FF-drift window occurs during the build (a PR merge on one remote), run the corrector and capture the CORRECTED output + the post-push EQUAL SHAs. If no real window occurs, the self-test's live-fixture scenario (two local bare "remotes", one advanced) stands in — state which of the two was captured, honestly.
    3. Start a session (or run `bash adapters/claude-code/hooks/session-start-git-freshness.sh` manually) and confirm the digest line renders for a synthetic DIVERGED status file, and does NOT render for CONVERGED.
    **Wire checks:**
    - `adapters/claude-code/hooks/session-start-git-freshness.sh` backgrounded dispatch → `adapters/claude-code/scripts/master-drift-autocorrect.sh`
    - `adapters/claude-code/scripts/master-drift-autocorrect.sh` sources `adapters/claude-code/hooks/lib/interactive-session-lock.sh` (`isl_live_session`, `isl_refuse_log`)
    - `adapters/claude-code/scripts/master-drift-autocorrect.sh` FF assertion `merge-base` / `--is-ancestor` → status file consumed by `adapters/claude-code/hooks/session-start-git-freshness.sh` digest rendering (`master-drift`)
    **Integration points:**
    - `adapters/claude-code/manifest.json` entry (Task 4 prerequisite) — verify `harness-doctor.sh --quick` stays GREEN with the new predicate.
    - Digest budget — the new feed adds at most 1 line to the 15-line digest cap (1 line emitted only in non-quiet states; quiet = 0 lines).

## Files to Modify/Create

Create:
- `docs/plans/master-drift-autocorrection-2026-07.md` — this plan.
- `adapters/claude-code/scripts/master-drift-autocorrect.sh` — the FF-only dedicated-clone corrector + `--self-test`.
- `docs/runbooks/master-drift-autocorrect.md` — divergence procedure, kill switch, triage.

Modify:
- `adapters/claude-code/hooks/session-start-git-freshness.sh` — remote-vs-remote comparison, backgrounded dispatch, digest-line rendering, self-test extension.
- `adapters/claude-code/manifest.json` — mechanism entry + doctor predicate wiring.
- `docs/discoveries/2026-06-02-component-c-sync-daemon-thrashes-live-checkout.md` — implementation-log disposition entry (Task 6).

## In-flight scope updates

- 2026-07-12 (build, Tasks 2+3): mirror discovery keys on FETCH urls, not
  push urls — a deliberate divergence from the reused F.6
  `_discover_mirror_remote` pattern (see Decisions Log D5). Same files, same
  scope; commit `5b00692`.

## Assumptions

- The machine's existing git credential surface (the one local dual-pushes
  already use) can push `master` to BOTH remotes without any new token. If a
  push is rejected (401/403), the corrector surfaces PUSH-REJECTED and never
  attempts credential acquisition (constitution: never ask for credentials;
  operator constraint: no tokens).
- The mirror master's branch protection (required_linear_history + a
  required status check, `enforce_admins: false`) admits a plain FF push
  from the machine's admin credential — proven by the 2026-07-11
  reconciliation landing exactly that way (handoff §FIRST ACTION notes the
  bypass mechanics). An FF push of already-reviewed commits changes nothing
  about history shape versus the established local dual-push.
- The two masters are SHA-converged at plan start (handoff invariant:
  `git rev-parse origin/master pt/master` must be EQUAL). The FF corrector
  PRESERVES SHA-identity; it never creates commit objects.
- `session-start-git-freshness.sh` remains a digest feed (Wave E.1
  consolidation) — its stdout lands in session context via
  `session-start-digest.sh`.
- The F.6 clone-bootstrap pattern in `sync-pt-to-personal.sh` (read-only
  remote discovery from the caller, all mutation in `$SYNC_CLONE_DIR`) works
  as shipped; its `--self-test` is green on master.

## Edge Cases

- **Concurrent session starts** (two sessions boot within the same minute):
  single-instance `mkdir` lock inside the clone dir; the loser exits 0
  silently. Server-side non-FF rejection is the second backstop.
- **Race with a human push mid-check**: the ancestor check passes, then a
  human dual-push advances the target before our push → server rejects
  non-FF → corrector records PUSH-REJECTED; next session start re-evaluates
  from scratch (usually now CONVERGED). No retry loop.
- **Network down / fetch timeout**: fetch is timeout-bounded (reuse the
  hook's `FETCH_TIMEOUT_SECONDS` discipline); on failure the corrector exits
  0 without writing a scary status (stale CONVERGED is acceptable; detection
  re-runs next session).
- **Only one remote configured** (fresh clone, mirror not set up): mirror
  discovery returns empty → corrector exits 0 with a log line, no digest
  noise.
- **Diverged AND one side also behind** (true divergence): neither ancestor
  test passes → DIVERGED path; the corrector must NOT "partially help" by
  pushing anything.
- **Kill switch**: `MASTER_DRIFT_AUTOCORRECT=0` in the environment causes
  the hook to skip dispatch entirely (detection line still renders); the
  runbook documents it. Loud-is-not-rare lesson: the switch is a present-
  moment env check, not a deferred audit entry.
- **Degenerate invocation from inside the sync clone**: ISL F.6 branching
  REFUSES (the only refuse branch), matching `sync-pt-to-personal.sh`.
- **First run on a machine with no sync clone yet**: bootstrap clones from
  the caller's remote URLs (read-only discovery), exactly as F.6 ships.

## Acceptance Scenarios

n/a — `acceptance-exempt: true`: harness-dev plan, no product user; the
self-test matrices + the Task 7 live demonstration are the acceptance
surface (see acceptance-exempt-reason in the header).

## Out-of-scope scenarios

- Auto-resolving true divergence with an automated merge — permanently
  excluded by operator constraint; divergence is a reviewed-merge event.
- Cross-machine drift correction (another machine's checkouts) — each
  machine's own session starts run their own corrector; no daemon reaches
  across machines.
- Non-master branch drift (e.g., the shared feat branch) — different
  ownership semantics; handled by the branch-reconciliation procedures, not
  auto-sync.

## Behavioral Contracts

- **Idempotency:** every path is re-runnable: CONVERGED re-run is a pure
  read; a CORRECTED re-run finds EQUAL SHAs and reports CONVERGED; pushing
  a SHA already present on the target is a server-side no-op. The status
  file is overwritten whole (single line), never appended.
- **Performance budget:** the session-start blocking path gains one local
  SHA comparison over refs the hook ALREADY fetched (0 additional network
  calls in the hook itself); the corrector runs backgrounded — worst case
  2 fetches × 10s timeout + 1 push ≈ 30s wall, all off the blocking path,
  so session-start added blocking time = 0s by construction.
- **Retry semantics:** none in-process. Every session start is the natural
  retry tick. PUSH-REJECTED and DIVERGED persist in the status file until a
  later run observes convergence.
- **Failure modes:** see Systems Engineering Analysis §7 table; every
  failure degrades to "no mutation + at most one digest line", never to a
  mutation of a live checkout and never to a force push.

## Closure Contract

- **Commands that run:**
  `bash adapters/claude-code/scripts/master-drift-autocorrect.sh --self-test`;
  `bash adapters/claude-code/hooks/session-start-git-freshness.sh --self-test`;
  `bash ~/.claude/scripts/harness-doctor.sh --quick` (post-install);
  the Task 7 live run.
- **Expected outputs:** both self-tests exit 0 with all scenarios PASS;
  doctor GREEN including the new predicate; live run prints
  CONVERGED/CORRECTED with post-state EQUAL remote-master SHAs.
- **On-disk artifact location:**
  `docs/plans/master-drift-autocorrection-2026-07-evidence/<task-id>.evidence.json`
  (one per task, `write-evidence.sh capture`).
- **Done when:** all 7 tasks are task-verifier PASS AND the evidence set
  exists with PASS verdicts AND the plan is flipped COMPLETED + archived in
  the same session as the final task (closure IS the work).

## Testing Strategy

- **Corrector `--self-test` (Task 2)** builds a fixture triple under
  `mktemp -d`: two bare repos ("origin", "mirror") + one work clone playing
  the interactive checkout, plus a fixture sync clone. Scenarios: (T1)
  converged → CONVERGED, no push; (T2) mirror strictly behind → pushed,
  SHAs equal after, CORRECTED; (T3) origin strictly behind → symmetric;
  (T4) diverged → DIVERGED, both bares unchanged (rev-parse before ==
  after); (T5) push rejected (pre-advance the target after the fixture's
  ancestor check via a hook or by racing a second commit) → PUSH-REJECTED,
  no force fallback — assert the script contains no `--force`/`-f` push
  (grep, same guarantee style as `sync-pt-to-personal.sh`); (T6) lock held →
  second instance exits 0 silently; (T7) invocation from inside the clone →
  ISL REFUSE; (T8) kill switch honored; (T9) single-remote repo → silent
  no-op; (T10) no clone yet → bootstrap then proceed.
- **Hook `--self-test` extension (Task 3):** remote-vs-remote inequality
  renders detection + dispatches (assert via a stub corrector on PATH);
  status-file states render exactly one line each; CONVERGED renders zero
  lines; `MASTER_DRIFT_AUTOCORRECT=0` skips dispatch but keeps detection.
- **Task 7** exercises the real remote pair as specified in its
  Prove-it-works block — the only test tier that touches the network.
- Per constitution §4, harness scripts' `--self-test` passing IS the
  demonstration; evidence JSONs capture each summary line.

## Walking Skeleton

The skeleton is Task 2's script run end-to-end against the T2 fixture: a
session-shaped caller → clone bootstrap → fetch both → ancestor check → FF
push → status file — every architectural layer (caller discovery, dedicated
clone, FF assertion, push, surfacing state) in one thin slice before any
hook wiring exists. First task: 2 (Task 1 is the greenlight gate, not a
build step).

## Decisions Log

- **D1 (2026-07-12, plan-time): session-start extension over a scheduled
  task.** Options: (a) extend the existing SessionStart detection hook with
  a backgrounded corrector; (b) a Windows scheduled task running the
  corrector on an interval. Chose (a): drift is only consequential when work
  begins (session start), the fetch infrastructure already exists there, and
  (b) creates a new unattended-mutator surface — the exact failure class of
  the 2026-06-02 discovery — plus scheduler registration/teardown burden.
  Reversible: the standalone script is runner-agnostic; a scheduled runner
  can be added later without changing the script. Recorded here per §8
  decide-and-go; greenlight review is the operator's chance to override.
- **D2 (2026-07-12, plan-time): FF assertion is `git merge-base
  --is-ancestor` + plain push.** The ancestor check is the explicit gate;
  the server's non-FF rejection on a plain (never forced) push is the
  independent backstop against check-to-push races. No force flag exists
  anywhere in the script (self-test T5 greps for this).
- **D3 (2026-07-12, plan-time): PAUSED workstreams-sync config is MOOT —
  no lift action.** Verified absent from disk with zero consumers in tree or
  live mirror (details in the Disposition section). Task 6 records this in
  the originating discovery; no restore, no delete, no new config.
- **D4 (2026-07-12, plan-time): plan ships as Status: DRAFT.** The handoff
  makes building explicitly greenlight-gated; DRAFT keeps it out of the
  stale-ACTIVE sweep and defers the ACTIVE-plan header enforcement to the
  moment the operator answers. Precedent: the observability program plan
  (DRAFT, frozen) uses the same greenlight-gated posture.
- **D5 (2026-07-12, build-time, decide-and-go §8): mirror discovery compares
  FETCH urls, not push urls.** Caught preparing Task 7's live run, before
  any real invocation: this machine's checkouts configure `origin` as a
  DUAL-PUSH remote (`remote.origin.pushurl` twice — work-org URL first,
  personal URL second), so origin's first push URL EQUALS the mirror
  remote's and the reused F.6 push-URL `_discover_mirror_remote` pattern
  finds NO mirror — the whole mechanism silently no-ops on the real repo.
  Since what the corrector compares and corrects are the remotes' FETCH
  identities (`origin/master` vs `<mirror>/master` tracking refs), fetch
  URLs are the honest discovery key; the dedicated clone additionally
  enforces a single-push invariant (`--unset-all remote.<name>.pushurl`) so
  a push inside the clone targets exactly one repo. Pinned by corrector
  self-test T11 (reproduces the real dual-pushurl topology; reverting to
  push-URL discovery fails it) and the hardened hook fixture (T9-T14).
  `sync-pt-to-personal.sh` shares the latent pattern but is Scope OUT —
  filed on the machine-wide ledger via nl-issue.sh. Reversible: one-line
  discovery-key change. Commit `5b00692`.

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept — 2 entry points (SessionStart hook dispatch; manual script invocation) both named in Mechanism sketch, Tasks 2-3, and Files to Modify/Create; kill-switch env entry point named in Edge Cases + Task 5.
- S2 (Existing-Code-Claim Verification): swept — 5 existing-code claims (ISL lib path + F.6 verdict branching; sync-clone default path + bootstrap; freshness hook fetch/timeout/feed behavior; digest 15-line cap; `_discover_mirror_remote` pattern) each verified against the file on disk 2026-07-12 before authoring; `sync-events` absence verified by grep (0 matches).
- S3 (Cross-Section Consistency): swept — status-file states (CONVERGED/CORRECTED/DIVERGED/PUSH-REJECTED) identical across Mechanism sketch, Tasks, Behavioral Contracts, and Testing Strategy; FF-only and no-force claims consistent in Goal, Mechanism, D2, T5.
- S4 (Numeric-Parameter Sweep): swept for params [fetch timeout 10s, worst-case background wall ≈ 2 × 10s + push ≈ 30s, digest cap 15 lines, new-feed contribution ≤ 1 line, blocking-path delta 0s] — values consistent everywhere they appear.
- S5 (Scope-vs-Analysis Check): swept — every Add/Modify verb in Tasks and the SEA maps to a Scope IN bullet; the three Scope OUT exclusions (Action mirror, tokens, auto-merge) are contradicted nowhere.

## Definition of Done

- [ ] All tasks checked off (Task 1 = recorded operator greenlight, first)
- [ ] Both self-tests + doctor --quick green (Closure Contract)
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

Within one session start after a server-side PR merge lands on either
remote, `git rev-parse origin/master <mirror>/master` on a fresh fetch
prints EQUAL SHAs without any human action — OR the session's digest
contains exactly one `[master-drift] DIVERGED …` line naming both SHAs and
the runbook. Measured over the weeks after shipping: zero sessions that
discover drift mid-push (the failure mode that cost the 2026-07-11
reconciliation session).

### 2. End-to-end trace with a concrete example

A PR merges server-side on the work-org repo: its master advances
`5043531 → e4f9a12` while origin/master stays `5043531`. Next morning a
session starts in the main checkout. `session-start-git-freshness.sh` runs:
fetches both remotes (each bounded by the 10s timeout), compares
`origin/master`=`5043531` vs `<mirror>/master`=`e4f9a12` → unequal → prints
its detection line and dispatches `master-drift-autocorrect.sh` backgrounded.
The corrector: (1) ISL check — caller checkout is the interactive tree,
distinct from the clone → LOG-AND-PROCEED entry in
`~/.claude/logs/interactive-session-lock.log`; (2) ensures
`~/.claude/sync-clone/neural-lace` exists (first run: `git clone` from the
caller's origin URL + `git remote add` the mirror URL — both discovered
read-only); (3) takes the `mkdir` lock; (4) fetches both remotes IN THE
CLONE; (5) `git merge-base --is-ancestor 5043531 e4f9a12` → true, reverse →
false: origin is strictly behind; (6) `git push origin e4f9a12:master` —
plain push, fast-forward, succeeds; (7) re-fetches, confirms EQUAL, writes
`CORRECTED origin e4f9a12` to `~/.claude/state/master-drift/neural-lace.status`;
(8) releases the lock. The interactive checkout's HEAD, index, and worktree
were never touched — its own `origin/master` ref updates on its next fetch.
The NEXT session start renders one digest line: `[master-drift] CORRECTED
origin/master fast-forwarded to e4f9a12`; the feed's dedup retires it once
the status returns to CONVERGED.

### 3. Interface contracts between components

- **Hook → corrector:** the hook promises to dispatch at most one
  backgrounded corrector per session start, only on SHA inequality, only
  when `MASTER_DRIFT_AUTOCORRECT` ≠ 0; it passes no arguments (the corrector
  self-discovers from its cwd = repo root). The corrector promises exit 0
  in every path (a SessionStart hook chain must never be poisoned).
- **Corrector → status file:** exactly one line, one of four states, token-
  separated, overwritten atomically (write temp + `mv`); consumers must
  tolerate an absent file (= quiet).
- **Corrector → remotes:** plain `git push` only; promises no `--force`, no
  ref deletions, no non-master refs; authenticates via the ambient
  credential store — never prompts (`GIT_TERMINAL_PROMPT=0`).
- **Corrector → ISL lib:** sources `interactive-session-lock.sh`; honors
  its refuse verdict for degenerate invocations; logs proceed verdicts.
- **Status file → digest:** the freshness hook renders ≤ 1 line per session
  from the status file; promises zero lines for CONVERGED/absent.

### 4. Environment & execution context

Runs on Windows under Git Bash (MSYS), dispatched by Claude Code
SessionStart from the repo root of whichever checkout the session opened.
Persistent state: the dedicated clone (`~/.claude/sync-clone/<repo>`), the
status dir (`~/.claude/state/master-drift/`), logs
(`~/.claude/logs/`). Ephemeral: the lock dir (removed on exit via trap;
stale-lock recovery by age check > 30 min). Path normalization must follow
the F.6 `_normalize_path` approach (Windows-native vs MSYS spellings of the
same dir). Survives restarts trivially — no daemon, no in-memory state;
everything re-derives from git refs at next invocation.

### 5. Authentication & authorization map

Git pushes authenticate via the machine's existing credential manager
entries for the two remote hosts' URLs — the identical surface local
dual-pushes use today; NO new credential, token, or PAT is introduced
(operator constraint). `gh` CLI is NOT used by the corrector (no API calls
— pure git). Rate limits: none material (2 fetches + ≤1 push per session
start). Authorization failure (403 wrong-account, revoked credential)
lands in PUSH-REJECTED with the runbook's `gh auth switch` triage pointing
the human at the fix; the corrector never retries and never escalates
privileges.

### 6. Observability plan (built before the feature)

Every run appends one line per phase to
`~/.claude/logs/master-drift-autocorrect.log` (timestamp, repo, phase,
verdict): dispatch, ISL verdict, lock acquire/skip, fetch result, ancestor
verdict, push result, final state. The status file is the machine-readable
summary of the LAST run. The ISL refusal log keeps its own trail. From logs
alone one can reconstruct: when drift appeared, which side was behind, what
was pushed, or why nothing was (lock, kill switch, network, rejection,
divergence). The doctor predicate asserts the mechanism exists and
self-tests green, so "documented but not firing" (constitution §10 theater)
is mechanically caught.

### 7. Failure-mode analysis per step

| Step | Failure | Observable symptom | Recovery | Escalates when |
|---|---|---|---|---|
| Hook comparison | fetch timed out earlier, refs stale | no dispatch this session | next session start retries | drift persists > a few sessions (digest keeps showing detection line) |
| Dispatch | corrector missing/not executable | log line absent; doctor predicate RED | reinstall (`install.sh`) | doctor stays RED |
| ISL check | lib missing | corrector exits 0, logs `isl-lib-missing` | reinstall | recurring log entries |
| Clone bootstrap | clone fails (network/auth) | log `bootstrap-failed`; no status change | next run retries bootstrap | repeated failures → PUSH-REJECTED-style digest line (auth variant) |
| Lock | stale lock (crashed run) | log `lock-held`; skip | age > 30 min → break lock, proceed | never |
| Fetch (clone) | network down | log `fetch-failed`; exit 0, status untouched | next session | never (benign) |
| Ancestor check | diverged | status DIVERGED; one digest line | HUMAN: runbook reviewed-merge procedure | immediately (by design — this IS the escalation) |
| Push | non-FF race / rejected | status PUSH-REJECTED | next session re-evaluates (usually CONVERGED) | rejection repeats with auth reason → operator fixes credential |
| Push | partial (one remote unreachable) | only one push attempted per run anyway | next run handles the other side | never |
| Status write | disk error | log line only | next run rewrites | never |

### 8. Idempotency & restart semantics

Every step is restartable from scratch because all state lives in git refs
+ one overwritten status line: a crash after fetch → next run re-fetches; a
crash after push but before status write → next run finds EQUAL SHAs and
writes CONVERGED (the push's effect is self-evident in the refs); a crash
holding the lock → age-based break at 30 min. Running the corrector twice
concurrently is excluded by the lock; twice sequentially is a no-op the
second time. There is no state that can half-apply: a git push either moved
the ref or did not, and the ancestor check re-derives from reality every
run.

### 9. Load / capacity model

Per session start: ≤ 2 fetches + ≤ 1 push + ~10 local git plumbing calls,
all in the background clone. Even at 20 session starts/day that is ≤ 40
fetches/day — orders of magnitude under any GitHub abuse threshold, and 0
API (REST/GraphQL) calls, so no token-bucket concerns. Bottleneck resource:
none meaningful; the lock serializes the only contended path. Saturation
behavior: a second concurrent invocation exits immediately (graceful,
silent) — no queue, no pile-up.

### 10. Decision records & runbook

Decisions D1-D4 in the Decisions Log above (D1 placement, D2 FF assertion,
D3 PAUSED-config moot, D4 DRAFT posture); Task 1's greenlight is the
operator decision record for building at all. Runbook
(`docs/runbooks/master-drift-autocorrect.md`, Task 5) entries: DIVERGED →
run the handoff's reviewed-merge procedure (temp worktree, `--no-ff` merge,
DECISIONS.md union, dual push, verify EQUAL); PUSH-REJECTED(auth) →
`gh auth switch -u <owner>` then rerun by hand; suspected misbehavior →
`MASTER_DRIFT_AUTOCORRECT=0` kill switch + file an nl-issue against the
gate; clone corruption → delete `~/.claude/sync-clone/<repo>` (it is
disposable; next run re-bootstraps).
