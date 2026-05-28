# Plan: Neural Lace cross-repo mirror automation
Status: COMPLETED
Execution Mode: orchestrator
Mode: design
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal CI/sync automation; the workflow is staged-not-enabled and gates on the unification cutover, so there is no running product surface to exercise. Self-tests + structural checks are the acceptance artifact.
Backlog items absorbed: none

## Goal
Keep the two Neural Lace repositories — `<pt-org>/neural-lace` (private) and
`<personal-user>/neural-lace` (public) — at identical master SHAs forever after a
one-time unification cutover, with neither repo canonical, both kept live, and strict
governance (PR + linear history + required status check) preserved on both. Today there
is NO automated mirror: the only "sync" was a manual, remote-name-dependent `sync.sh`
wrapper that drifted the moment two clones used different remote names. This plan
DESIGNS and STAGES (does not enable) the durable mechanism: a cross-repo GitHub Action
that mirrors each repo's master to the sister on push, plus a URL-based rewrite of
`sync.sh` for local/Dispatch integration.

## Scope
- IN: a single parameterized GitHub Actions workflow (`.github/workflows/mirror-to-sister.yml`)
  deployed to both repos; a URL-based, remote-name-independent rewrite of
  `adapters/claude-code/sync.sh`; ADR `docs/decisions/044-neural-lace-mirror-automation.md`
  + its `docs/DECISIONS.md` index row; a schema fix to `adapters/claude-code/examples/accounts.config.example.json`
  (the stale-schema example that caused the gh auto-switch failure).
- OUT: enabling the Action on either repo (gates on the cutover — staged on a feature
  branch, not pushed); the one-time SHA reconciliation/force-push itself (Q1, separate
  cutover step); the conv-tree-UI conflict resolution (Q4, deferred); creating/rotating
  the PATs and setting repo variables/secrets (a cutover runbook step, documented here
  but performed by Misha at cutover); branch-protection bypass-allowance configuration
  (cutover runbook step).

## Tasks

- [x] 1. Write ADR `docs/decisions/044-neural-lace-mirror-automation.md` (decision, token model, conflict handling, failure alerting, sync.sh interface) + add the index row to `docs/DECISIONS.md`. — Verification: mechanical
- [x] 2. Write `.github/workflows/mirror-to-sister.yml`: push-to-master trigger, concurrency-serialized, SHA-equality loop-break, fast-forward-only push (never force) to `${{ vars.SISTER_REPO }}` via `${{ secrets.MIRROR_PAT }}`, fail-loud + optional ntfy alert on non-FF. No hardcoded repo identity (read from repo variable). — Verification: mechanical
- [x] 3. Rewrite `adapters/claude-code/sync.sh` to push the branch to each distinct remote URL resolved at runtime (name-independent), never force, fail loudly if any push fails (no silent half-sync). Preserve `--self-test`-able structure; add a self-test. — Verification: mechanical
- [x] 4. Fix `adapters/claude-code/examples/accounts.config.example.json` to the schema `read-local-config.sh` actually consumes (`gh_user` + `work`/`personal` both arrays), so a fresh install's auto-switch works (D1 committable mechanism fix). — Verification: mechanical

## Files to Modify/Create
- `docs/decisions/044-neural-lace-mirror-automation.md` — NEW. The decision record.
- `docs/DECISIONS.md` — MODIFY. Add the ADR-044 index row.
- `.github/workflows/mirror-to-sister.yml` — NEW. The cross-repo mirror Action.
- `adapters/claude-code/sync.sh` — MODIFY. URL-based dual-push rewrite.
- `adapters/claude-code/examples/accounts.config.example.json` — MODIFY. Stale-schema fix.

## In-flight scope updates
(none yet)

## Assumptions
- `read-local-config.sh` consumes `gh_user` + array-shaped `work`/`personal` (verified by
  reading the live script and its self-test on 2026-05-27); the committed example file
  drifted to an older `user`/object shape and never matched.
- GitHub's built-in loop guard (pushes by the default `GITHUB_TOKEN` do not trigger further
  workflow runs) does NOT apply to PAT pushes — a PAT push to the sister WILL trigger the
  sister's workflow. The SHA-equality early-exit is therefore load-bearing for loop
  prevention, not optional.
- A fine-grained PAT cannot natively restrict pushes to a single branch ref; "push only to
  master" is enforced by the workflow (it only ever writes `refs/heads/master`) plus
  branch-protection bypass configuration — not by the token. Stated honestly so the setup
  runbook is correct.
- PT master branch protection has `enforce_admins: false` (per the deep-dive), so an
  admin/owner actor's PAT in the bypass-allowance list can push a fast-forward update to the
  protected master.
- Post-cutover both masters are linear and dev is squash-only, so every steady-state mirror
  push is a fast-forward; a non-FF push only arises from true concurrent divergence, which
  the Action surfaces as a loud failure rather than resolving.
- Real repo identities (`<pt-org>`, `<personal-user>`) live in per-repo GitHub
  variables/secrets and local git remote URLs, NEVER in committed harness files
  (harness-hygiene), so the workflow file and `sync.sh` stay identity-free and generic.
- **Both repos' `validate` workflows are kept identical** (a governance precondition). The
  mirror push to the sister's master is a bypass-actor FF ref update, so it does NOT re-run
  the sister's `validate`; the SHA only passed `validate` on its originating repo's PR. If
  the two `validate` definitions ever diverge, the mirror could land a SHA the sister's
  validate would reject. Because `validate` IS itself mirrored content, keeping it in sync
  self-maintains post-cutover — but it is a stated precondition, not a free property.

## Edge Cases
- **Mirror loop** (A→B push triggers B→A push): broken by the SHA-equality early-exit —
  the second run sees sister==local and no-ops.
- **No-op push** (re-run with no new commit): both sides equal → no-op, no loop.
- **Rapid-succession ancestor push** (a SECOND commit X→Y lands on the originating repo
  before the sister's return-leg run executes): the sister is already at Y (which descends
  from the older SHA X); the older run's pushed SHA X is an ANCESTOR of the sister tip. The
  workflow classifies this with `git merge-base --is-ancestor` and treats it as a benign
  no-op (the sister is already ahead) — NOT a failure. This avoids a false-alarm red run on
  ordinary back-to-back merges; the newer SHA's run re-converges.
- **Concurrent divergent pushes** to both masters (neither tip an ancestor of the other):
  the FF-only push is rejected → that run fails loudly + alerts; a human reconciles. Never
  auto-discards a commit. The `merge-base --is-ancestor` discriminator is what distinguishes
  this (true divergence → fail) from the benign ancestor case above (sister ahead → no-op).
- **Merge commit reaches one master**: the FF push carries it to the sister; PT's
  linear-history protection rejects it → loud failure. Consistent with strict governance.
- **PAT expired/revoked**: push auth fails → loud workflow failure + alert.
- **Sister repo unreachable / API outage**: `git ls-remote` or push fails → loud failure;
  next push retries the mirror.
- **Shallow-checkout missing ancestor objects**: avoided by `fetch-depth: 0`.
- **Secret leakage in logs**: only the raw secret is referenced (auto-masked by Actions);
  no transform of the secret is printed.
- **Clone with only one remote** (personal-only clone running `sync.sh`): pushes to the one
  URL it knows — correct, not a half-sync error.

## Acceptance Scenarios
n/a — `acceptance-exempt: true` (harness-internal, staged-not-enabled automation; no running
product surface). Structural/self-test verification stands in for runtime acceptance.

## Testing Strategy
- Task 1 (ADR): file exists; `docs/DECISIONS.md` has the 044 row; no hardcoded real identity
  (`grep` confirms placeholders only).
- Task 2 (workflow): YAML parses (`python -c yaml.safe_load` or `yq`); contains the
  SHA-equality early-exit; contains NO `--force`/`-f`/`force` push; references
  `vars.SISTER_REPO` + `secrets.MIRROR_PAT` (not hardcoded identity); `if: failure()` alert
  step present.
- Task 3 (sync.sh): `bash -n` syntax check; `sync.sh --self-test` passes (dedup-by-URL,
  fail-loud, no-force assertions); `grep` confirms no `--force`.
- Task 4 (example): `jq -e` validates JSON; shape matches what `read-local-config.sh`
  consumes (`.work[0].gh_user`, `.personal[0].gh_user` resolve); placeholders only.
- Harness-hygiene scan over the diff passes (no real identity in committed files).

## Walking Skeleton
The thinnest end-to-end slice that proves the mechanism: a single push to one master,
mirrored to the sister as an identical SHA, with the return path no-oping via SHA-equality.
Concretely the workflow's load-bearing lines — (1) `ls-remote` sister master,
(2) `[ "$SISTER_SHA" = "$GITHUB_SHA" ] && exit 0` (equal ⇒ loop-break no-op), (3) fetch
sister tip + `git merge-base --is-ancestor $GITHUB_SHA <sister-tip> && exit 0`
(sister-ahead ⇒ benign no-op), (4) FF `git push <sister> $GITHUB_SHA:refs/heads/master`
(non-FF ⇒ loud failure) — are the skeleton; everything else (concurrency group, alert step)
is hardening around it.
Because the Action is staged-not-enabled, the skeleton is verified structurally (YAML +
grep assertions) rather than by a live push, per the acceptance-exempt rationale.

## Decisions Log
### Decision: ADR number 044 (avoid the known PT collision set)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** 044. PT master already holds ADRs 036–042; the deep-dive reserves 043 for the
  decision-queue ADR (personal PR #36 renumber). 044 is the next free number on the unified
  tip.
- **Alternatives:** 037 (collides with PT 037); 043 (reserved for decision-queue).
- **Reasoning:** cross-pattern thinking — the ADR-number-collision class is exactly what bit
  the two repos; pick a number free on the unified tip, not just free in this checkout.
- **To reverse:** rename the ADR file + its index row (one commit).

### Decision: fail-loud over auto-resolve on concurrent divergence (interface impact — surfaced to Misha)
- **Tier:** 2
- **Status:** recommended; surfaced to Misha in the session report (Dispatch → plain text)
- **Chosen:** on a non-FF mirror push (true concurrent divergence), the Action FAILS LOUDLY
  and a human reconciles. Neither side "wins" automatically.
- **Alternatives:** (a) later-timestamp-wins; (b) designate one repo primary-writer.
- **Reasoning:** auto-picking a winner silently discards the loser's commit — data loss,
  violating Rule 0 (honesty) and the "alert clearly, don't silently drop" constraint.
  Fail-loud is the only option with no silent data loss. A primary-writer model is a valid
  UX choice if Misha prefers it; recorded as the alternative.
- **To reverse:** add a primary-writer branch + auto-rebase step to the workflow.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept the SE analysis for behavior changes (push trigger, SHA
early-exit, FF-only push, fail-loud alert, sync.sh dedup-by-URL); each is cited in the
corresponding Task + Files-to-Modify entry. 5 behaviors, all surfaced.
S2 (Existing-Code-Claim Verification): swept claims about existing code — `sync.sh` current
shape (read at adapters/claude-code/sync.sh, name-match logic confirmed), `read-local-config.sh`
schema (read + self-test confirmed `gh_user`/array), branch-protection state (from the
deep-dive's `gh` queries). All verified against files at audit time.
S3 (Cross-Section Consistency): swept "preserved/unchanged/never" claims — "never force-push",
"strict governance preserved", "neither canonical" appear consistently in Goal, Scope, Edge
Cases, and SE §3/§5/§7; 0 contradictions.
S4 (Numeric-Parameter Sweep): swept for numeric parameters — the only fixed parameters are
`fetch-depth: 0` and the PAT permission set (`Contents: write`); both stated once and
consistently. No rate/cap/timeout numerics. 0 inconsistencies.
S5 (Scope-vs-Analysis Check): swept "Add/Modify/Replace" verbs against the Scope OUT list —
enabling the Action, the SHA reconciliation, conv-tree conflict, and PAT/secret creation are
all OUT and the analysis treats them as cutover-runbook steps, not in-scope edits. 0
contradictions.

## Definition of Done
- [ ] All 4 tasks checked off (task-verifier)
- [ ] ADR 044 + DECISIONS.md row committed
- [ ] Workflow YAML parses, no force-push, no hardcoded identity, loop-break present
- [ ] sync.sh rewritten, `--self-test` passes, no force-push
- [ ] Example config schema fixed and jq-valid
- [ ] Harness-hygiene scan clean over the diff
- [ ] Committed on `feat/neural-lace-mirror-automation`, NOT pushed, Action NOT enabled
- [ ] SCRATCHPAD / report reflects staged-not-enabled state

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
After the cutover enables this Action, a maintainer who merges a PR to master on EITHER repo
sees the SISTER repo's master advance to the identical SHA within one workflow run, with no
manual `sync.sh` invocation — OR, if a true concurrent divergence occurred, sees a red
workflow run + an alert naming the desync, and never a silent drift. Measured by: sister
master SHA equals origin master SHA after a single push (the steady-state invariant), and a
deliberately-divergent test push produces a failed run rather than a silent overwrite.
Until cutover the measurable outcome is narrower: the workflow file exists, parses, and
asserts the three skeleton behaviors, staged on a feature branch and not enabled.

### 2. End-to-end trace with a concrete example
T=0: maintainer merges PR on the PT repo via squash; PT master moves W→X. T=0:01: GitHub
emits a `push` event on PT `refs/heads/master`. The PT-resident `mirror-to-sister.yml` run
starts; `concurrency: mirror-master` ensures no sibling run races it. It checks out at full
depth, reads `GITHUB_SHA=X`, reads repo variable `SISTER_REPO=<personal>/neural-lace`, runs
`git ls-remote https://…@github.com/<personal>/neural-lace.git refs/heads/master` → returns
`W`. `X != W`, so it runs `git push <personal-url> X:refs/heads/master` authenticating with
`secrets.MIRROR_PAT` (a PAT created by the personal-account owner, scoped to the personal
repo, `Contents: write`). The personal master moves W→X. That PAT push emits a `push` event
on the PERSONAL repo, starting the personal-resident run: `GITHUB_SHA=X`, `ls-remote` of the
PT sister → `X`, `X == X` → the run exits 0 without pushing. The loop terminates after
exactly one round trip; both masters hold X.

### 3. Interface contracts between components
| Producer | Consumer | Contract |
|---|---|---|
| GitHub push event (master) | `mirror-to-sister.yml` | Delivers `github.sha` = the exact pushed commit; the workflow pushes THAT sha, not "current master", so a later commit cannot be skipped silently. |
| Workflow | sister repo master | Promises a FAST-FORWARD ref update of `refs/heads/master` to `github.sha`, authenticated by `MIRROR_PAT`; never a force update. A non-FF update is rejected by the receiving repo. |
| Repo variable `SISTER_REPO` | Workflow | `owner/repo` string of the sister; the ONLY place repo identity lives (keeps the committed YAML identity-free). |
| Repo secret `MIRROR_PAT` | Workflow | Fine-grained PAT, `Contents: write` on the sister repo only, whose owning account holds branch-protection bypass on the sister's master. |
| `sync.sh` | local git remotes | Pushes the branch to every DISTINCT push URL discovered from `git remote -v`; reports per-URL outcome; non-zero exit if any push fails. |

### 4. Environment & execution context
GitHub-hosted `ubuntu-latest` runner, one per workflow run, ephemeral. Pre-installed: git,
gh, bash, python3, jq-equivalent. Working directory: the checked-out repo at `github.sha`
with `fetch-depth: 0` (full history, so the FF push has all ancestor objects). Provided:
`GITHUB_TOKEN` (default, NOT used for the cross-repo push because its pushes wouldn't trigger
the sister's loop-break and it has no rights on the sister), `secrets.MIRROR_PAT`,
`vars.SISTER_REPO`, optional `vars.NTFY_TOPIC`/`secrets.NTFY_URL`. Nothing persists between
runs; the only durable effect is the ref update on the sister.

### 5. Authentication & authorization map
Two distinct fine-grained PATs, one per repo's secret store, both named `MIRROR_PAT`:
- PT repo's `MIRROR_PAT`: created by the PERSONAL-account owner, repository access limited to
  the PERSONAL repo, permission `Contents: Read and write`. Used by PT's workflow to push to
  personal. Personal master has no protection, so no bypass entry is needed there.
- Personal repo's `MIRROR_PAT`: created by the PT-org admin actor, repository access limited
  to the PT repo, permission `Contents: Read and write`, AND that actor is added to PT
  master's branch-protection bypass-allowances (allow specified actors to bypass required
  PRs). Used by personal's workflow to push to PT's protected master.
The "push only to master" guarantee is enforced at the workflow layer (it only writes
`refs/heads/master`) and the branch-protection layer, NOT at the token layer (fine-grained
PATs have no per-branch scope). The required `validate` check gates PR MERGES, not a
bypass-actor's direct FF ref update, so the mirror push does not re-run `validate` on the
sister; the SHA already passed `validate` on its originating repo's PR.

### 6. Observability plan (built before the feature)
Every run prints: the originating SHA, the sister's pre-push SHA, and the decision
(`already-in-sync no-op` vs `pushing X to sister`). A successful mirror prints the new sister
SHA. A failure path prints the rejected-push stderr (e.g., `non-fast-forward` or
`auth failed`). The workflow's pass/fail status is itself the top-level signal (GitHub emails
the actor on failure by default). An `if: failure()` step additionally posts to ntfy when
`vars.NTFY_TOPIC` is configured (ADR-042 ntfy infra), so a desync pages immediately. From
logs alone one can reconstruct: which SHA triggered, what the sister held, whether a push was
attempted, and why it failed. No secret value is printed (only the auto-masked raw secret is
referenced).

### 7. Failure-mode analysis per step
| Step | Failure mode | Observable symptom | Recovery / policy | Escalation |
|---|---|---|---|---|
| push event | event missed (GitHub outage) | sister never updates | next push to master re-triggers; mirror is idempotent | if persistent, run `sync.sh` locally |
| checkout | shallow history | push rejected (shallow update) | prevented by `fetch-depth: 0` | n/a |
| ls-remote sister | auth/network fail | run red, no push | retry on next push; alert fires | check PAT validity |
| SHA compare | equal (loop return leg) | `no-op` log, exit 0 | designed terminal state | n/a |
| ancestor check | pushed-SHA is ancestor of sister tip (benign rapid-succession) | `sister-ahead no-op` log, exit 0 | designed: sister already has this content; newer SHA re-converges | n/a |
| FF push | non-FF, neither tip an ancestor (true concurrent divergence) | run red, `non-fast-forward` | NO auto-resolve; human reconciles. **Discriminator:** `git merge-base --is-ancestor <pushed> <sister-tip>` — false on BOTH directions ⇒ true divergence (vs the benign ancestor row above) | alert + manual reconcile |
| FF push | merge commit present | run red, linear-history rejection (PT) | rebase to linear, re-push via PR | alert + manual |
| FF push | PAT expired/revoked/insufficient | run red, `403`/auth error | rotate PAT secret | alert |
| alert step | ntfy not configured | step skipped | GitHub native failure email is the floor | n/a |

### 8. Idempotency & restart semantics
Each run is idempotent: it pushes `github.sha` only if the sister differs; re-running the
same run (or a no-op push) is a SHA-equal no-op. A partially-completed run can only have
either not-yet-pushed (sister unchanged; safe to re-run) or pushed (sister at X; a re-run
no-ops). There is no intermediate corrupt state because the only mutation is a single atomic
ref update. Restart procedure from any state: push to master again (or run `sync.sh master`)
— the SHA-equality logic converges both masters to the latest SHA. `sync.sh` is likewise
idempotent: pushing an already-present branch tip is a no-op per URL.

### 9. Load / capacity model
Throughput is bounded by GitHub Actions concurrency on the master branch; `concurrency:
group: mirror-master, cancel-in-progress: false` serializes runs so rapid successive merges
queue rather than race. Each run does one `ls-remote` + at most one `push` — negligible load.
The bottleneck is human merge cadence to master, not the Action. At saturation (many merges
in quick succession) runs queue and execute in order; each converges the sister to the latest
SHA, so intermediate queued runs may no-op when a later SHA already mirrored — graceful, no
overflow.

### 10. Decision records & runbook
Decisions: ADR-044 (this mechanism), the fail-loud-over-auto-resolve choice (Decisions Log
above), and the Q1–Q6 cutover decisions Misha already made. Runbook for the cutover (NOT
executed here):
1. Complete the one-time SHA reconciliation (Q1: one-shot force-push of personal to the
   unified tip) so both masters are identical and linear BEFORE enabling the Action.
2. On PT repo: set variable `SISTER_REPO=<personal>/neural-lace`; add secret `MIRROR_PAT`
   (personal-owner PAT, personal repo, Contents:write).
3. On personal repo: set variable `SISTER_REPO=<pt-org>/neural-lace`; add secret `MIRROR_PAT`
   (PT-admin PAT, PT repo, Contents:write); add that actor to PT master's bypass-allowances.
4. (optional) set `vars.NTFY_TOPIC` on both for alerting.
5. Merge this branch's workflow into both masters (this is what ENABLES it).
6. Smoke test: push a trivial commit to one master; confirm the sister advances to the same
   SHA and the return run no-ops.
Runbook for a desync alert: read the failed run's stderr; if `non-fast-forward`, inspect both
masters, decide which commit set is authoritative, reconcile the divergence (rebase/replay
the authoritative set), then
push the reconciled tip — the Action re-converges.

## Completion Report

### 1. Implementation Summary
All four tasks built and task-verified PASS at commit `9928860` on branch
`feat/neural-lace-mirror-automation` (NOT pushed; Action NOT enabled — per scope):
- T1: ADR 044 + DECISIONS.md row (043 reserved for decision-queue). systems-designer PASS.
- T2: `.github/workflows/mirror-to-sister.yml` — parameterized, SHA-equality early-exit +
  `merge-base --is-ancestor` benign-no-op, FF-only/never-force, fail-loud + optional ntfy,
  identity in `vars.SISTER_REPO` (no hardcoded identity). Both `run:` blocks `bash -n` clean.
- T3: `sync.sh` URL-based rewrite, `--self-test` OK (dedup + dual-push + fail-loud).
- T4: example `accounts.config.example.json` schema fix (`gh_user`+arrays) — the committable
  half of the gh-account-switch fix (D1).
Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations
- ADR number 044 chosen to avoid the known PT collision set (036–042 taken, 043 reserved).
- Fail-loud over auto-resolve on concurrent divergence (surfaced to Misha; no silent
  data loss). systems-designer's two non-blocking findings folded in: the benign ancestor
  no-op is implemented in the workflow (not just documented), and the "both repos' `validate`
  must stay identical" governance precondition is now an explicit Assumption.
- No deviation from approved scope. Enabling + PAT/secret setup + SHA reconciliation are
  explicitly OUT (cutover runbook, §10).

### 3. Known Issues & Gotchas
- Workflow YAML was NOT machine-parsed locally (no python/js-yaml/yq in this environment);
  validated structurally + both shell bodies `bash -n` clean. Definitive YAML validation
  occurs at GitHub enable-time (staged-not-enabled, so acceptable).
- A fine-grained PAT cannot restrict to a branch ref; "push only to master" is workflow- +
  branch-protection-enforced (documented honestly in the ADR/plan).

### 4. Manual Steps Required (cutover runbook — NOT done here)
Complete the Q1 SHA reconciliation first; then per repo set `SISTER_REPO` var + `MIRROR_PAT`
secret, add the PT-side actor to master bypass-allowances, optionally set `NTFY_TOPIC`, merge
the workflow into both masters (this ENABLES it), smoke-test. Full steps in §10.

### 5. Testing Performed
Per-task mechanical verification (task-verifier PASS, evidence in
`neural-lace-mirror-automation-evidence.md`): file existence, `jq -e` schema, no forced push
(grep), `vars`/`secrets` references, `bash -n` on shell, `sync.sh --self-test` OK,
harness-hygiene scan clean over the diff. Runtime mirror behavior is not testable until
enabled (acceptance-exempt).

### 6. Cost Estimates
Negligible: one GitHub Actions run per master push (one `ls-remote` + at most one `push`,
seconds of free-tier minutes). Two fine-grained PATs (no cost). ntfy optional/free.
