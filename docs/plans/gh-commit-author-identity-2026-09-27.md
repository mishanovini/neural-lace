# Plan: gate git commit author identity against the gh account logged in for the repo

Status: ACTIVE
Execution Mode: single-session
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism work (a PreToolUse gate, a shared
resolution library, an additive library function, manifest + settings-template wiring,
doctrine) with no user-facing UI surface; the self-test suites of each touched file ARE
the acceptance oracle, per work-shapes/build-harness-infrastructure.md's harness-internal
carve-out — same shape as `docs/plans/hygiene-gate-escape-fix-2026-08-04.md`.
tier: 2
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
design-ref: n/a — direct operator dispatch (golden scenario + FP-rate + retirement
condition given inline in the dispatch, matching constitution section 10's bar for a new
blocking gate); no separate design-doc cycle was run, matching the direct-dispatch
harness-safety-fix shape (fix + self-test evidence + harness-reviewer, not a designed
program).

## Intended Functionality

**Outcome (operator's terms, 2026-09-27):** "set things to always use the email that's
logged into GH instead of the email used to log into Claude." A git commit an agent makes
must carry the identity of the GitHub account logged in FOR THE REPO BEING COMMITTED TO —
never whatever "user email" value Claude Code's own session context hands the agent for
authorship.

**Golden scenario (why now):** 2026-09-21, on a downstream project's PR — fixer subagents
committed with author set to the session's context email; the repo's own git config was already
correct, so the override must have been passed explicitly. Vercel maps commit emails to
Vercel users and blocked the deploy over the mismatch (~1hr cost). The session's context
email has since changed to yet another address, so the risk is structural, not a one-off.

**Observation:** `bash adapters/claude-code/hooks/gh-commit-author-identity-gate.sh
--self-test` blocks a `git commit`/`commit-tree` whose command overrides identity
(`--author=`, `-c user.email=`/`-c user.name=`, `GIT_AUTHOR_*`/`GIT_COMMITTER_*`) away
from the identity expected for the repo it targets, allows a matching override or no
override, allows the `GIT_COMMIT_IDENTITY_GATE_ACK=1` escape (logging it), and fails open
when no expected identity is resolvable at all — never fabricating a
`users.noreply.github.com` guess. `bash adapters/claude-code/hooks/lib/gh-commit-identity-
lib.sh --self-test` demonstrates the resolution chain (gh API via the target account's own
stored token, cached 24h; fallback to the repo's own git config; the noreply-never-used
guarantee) in isolation. `bash adapters/claude-code/hooks/lib/gh-account-lib.sh --self-test`
demonstrates the two additive owner-parsing helpers this reuses rather than duplicates.

**Deterministic pass/fail:** all three touched self-test suites exit 0 with zero failures
(gate 15/15, identity lib 9/9, account lib 9/9 — including the specific pinned scenarios
named in `## Testing Strategy` below).

## Goal

Land a PreToolUse gate (`kind: gate`, `blocking: true` in manifest.json) that structurally
prevents the GH-COMMIT-IDENTITY-01 golden-scenario class from recurring, without breaking
any legitimate commit shape (no override, or an override that already matches the expected
identity), and without ever silently blocking a repo whose identity this gate genuinely
cannot resolve.

## Scope

In scope: the new gate + its resolution library; two additive helpers on the pre-existing
`gh-account-lib.sh` shared library (reuse, not duplication, of the owner->account mapping
`gh-account-autoswitch.sh`/`gh-account-blindness-hint.sh` already use); manifest.json +
settings.json.template wiring; `doctrine/git.md` (compact pointer) + `doctrine/git-full.md`
(detail section).

Out of scope (named, not silently dropped): rewriting `gh-account-autoswitch.sh`'s own
private URL-parsing copy to delegate to the new shared helper (it is already
self-tested and working; touching it is not needed to ship this gate and would be
uncontained scope creep on a file with a large pre-existing self-test suite); an "expected
name" oracle independent of the repo's own `git config user.name` (no such GH-side oracle
exists; see the identity lib's header for the documented design choice); tracking an env
var exported in an EARLIER, SEPARATE Bash tool call (out of this hook's visibility by
construction — named as an accepted residual, not silently absent).

## Tasks
- [x] `hooks/lib/gh-account-lib.sh`: add `gh_owner_from_url` / `gh_owner_from_cwd_remote`
      (additive; existing self-test suite untouched and still green).
- [x] `hooks/lib/gh-commit-identity-lib.sh` (new): resolve the expected commit email for a
      repo — gh API via the target account's OWN stored token (never switching the active
      account), cached 24h under `~/.claude/state/gh-emails/`; fall back to the repo's own
      effective `git config user.email` on any failure; never a synthesized noreply guess.
      Also resolves the expected NAME as the repo's own current `git config user.name`.
- [x] `hooks/gh-commit-author-identity-gate.sh` (new, PreToolUse matcher `Bash`): parses
      the command (reusing `hooks/lib/git-command-parse.sh`'s segment splitter/tokenizer/
      cd-tracking primitives, extended with a purpose-built subcommand walk that — unlike
      that library's own `gcp_resolve_commit_target` — recognizes `commit-tree` as
      identity-bearing too, and captures `-c` VALUES and `--author` rather than skipping
      them); blocks a mismatched override; allows a match, no override, or the
      `GIT_COMMIT_IDENTITY_GATE_ACK=1` escape (logged as a signal-ledger `waiver` event);
      optionally auto-sets a wholly-unconfigured repo's `user.email` once, non-blocking.
- [x] `manifest.json`: `gh-commit-author-identity` entry (`kind: gate`, `blocking: true`,
      golden_scenario/fp_expectation/retirement_condition/honest_status/waiver_path per
      constitution section 10's bar for a new blocking gate).
- [x] `settings.json.template`: standalone `PreToolUse` / matcher `Bash` wiring.
- [x] `doctrine/git.md` (compact pointer) + `doctrine/git-full.md` (detail section).
- [x] Self-test all three touched/new files; fix the bugs the FIRST self-test run
      surfaced (a self-test `HOME` leak that let the real machine's global git config
      answer an assertion meant to test the fully-unresolvable case; two self-test
      commands that placed `-c` in an invalid post-subcommand position, which is not
      something real git accepts either — both are test-harness bugs, not gate bugs;
      documented in the C-Round Record below).
- [x] Independent review of head `f9b9b3cb` (a genuinely separate session, per
      `docs/plans/review-independence.md`) returned **REFORMULATE** (PR #67's review
      comment, 2026-09-28 — see the PR's own comment thread for the exact text and
      permalink; not reproduced here so this file does not have to embed a full GitHub
      URL naming the personal account this PR happens to be opened against). Findings
      M1-M4 (major, all PROVEN against real repos/transcripts) + m1-m7 (minor). Fixed in
      this same PR, same session that fixed the CI reds above (see the Review-Fix Round
      below for what changed per finding, with self-test evidence for each).
- [ ] A FRESH `harness-reviewer` PASS on the new head — NOT run by this (authoring)
      session per `docs/plans/review-independence.md`: the authoring session's only
      legal interaction with the review queue is the MECHANICAL auto-enqueue that fires
      as a side effect of committing. A separately-invoked session/process is the one
      that may claim + review + record a verdict.
- [ ] Merge to master (explicitly NOT done by this task — "Open a PR; do NOT merge").

## Review-Fix Round (independent review REFORMULATE, 2026-09-28)

Fixed in this PR, same session, in response to the independent review comment linked
above. Every fix ships with a pinned self-test regression case; combined self-test after
all fixes: 27/27 (gate) + 12/12 (identity lib) + 9/9 (account lib) = 48/48.

- [x] **M1 (major, PROVEN)** — identity overrides on `merge`/`cherry-pick`/`revert`/
      `pull`/`rebase`/`am` passed the gate (only `commit`/`commit-tree` were checked).
      Widened `_gcia_analyze_segment`'s target-verb set; `--author` stays scoped to
      `commit` only (no other verb accepts that flag). Also had to widen BOTH raw-payload
      prefilters (the top-of-file one added for m4, and the pre-existing one inside
      `_gcia_run`) past the literal substring `"commit"` — a real bug this fix's own
      first self-test run caught (all six new verb-coverage cases initially failed at
      rc=0 because the prefilter silently skipped them before the parser ever ran).
- [x] **M2 (major, PROVEN)** — this gate counted as a new standalone blocking-budget
      unit (16/14 on base `4ff107f4`, 17/14 on head). Added
      `'gh-commit-author-identity': 'commit-boundary'` to `UNIT_MAP` in
      `blocking-budget-check.js`; re-measured at 16/14, net-zero contribution.
- [x] **M3 (major, PROVEN)** — on a machine whose `~/.claude/local/accounts.config.json`
      still holds only the shipped placeholder entries, owner->account resolution always
      fails and the gh-API rung never fires, with nothing saying so; the doctrine also
      named the wrong reason for the fallback. Fixed: `gia_resolve_expected_email` now
      emits a signal-ledger `warn` naming the unmapped owner when a real github.com
      remote owner has no accounts.config.json entry; manifest `honest_status` and
      `doctrine/git-full.md` now state the dependency explicitly and no longer claim
      the affected account by name (the affected account varies by machine/token
      lifecycle — verify with `gia_gh_primary_email <account>` directly rather than
      trusting a name in a doc). Populating the config file is an explicit machine-config
      action left to the operator, not done by this code.
- [x] **M4 (major, PROVEN false positive)** — a repo with NO github.com remote (a
      scratch/throwaway `git init` fixture) got its commit checked against whatever this
      MACHINE's global `~/.gitconfig` happened to hold. Fixed: `_gcia_evaluate` now
      fails open completely (no check, no auto-set) when the target has no resolvable
      github.com remote owner. Self-test reproduces the exact false-positive shape,
      including a sandboxed "global" config the ORIGINAL self-test suite never
      populated (which is why this escaped it originally).
- [x] **m1 (minor, PROVEN)** — named + partially closed bypasses: `env NAME=VALUE git
      commit` (closed: strips the leading `env` token so the existing assignment-scan
      handles it) and `git config user.email X && git commit` (closed: tracks a plain
      `git config user.email|user.name` SET across segments in the same command, folded
      into a later commit-creating segment unless that segment carries its own explicit
      override, which still wins). `bash -c '...'`, `--config-env=`, and
      `GIT_CONFIG_COUNT`/`KEY_N`/`VALUE_N` are named as accepted residuals (not closed —
      cost vs. realistic likelihood) in the hook header and doctrine, not silently absent.
- [x] **m2 (minor, PROVEN)** — a NAME-only override (`-c user.name=`, no email mismatch)
      blocked, adding false-positive surface with no attribution benefit (Vercel/GitHub
      attribute by email). Changed to WARN (signal ledger), never block.
- [x] **m3 (minor, measured)** — no negative cache on a failed `gh api user/emails`
      lookup meant every commit in an unmapped/unauthorized-scope repo re-spawned both
      `gh auth token` and `gh api`. Added a 5-minute negative cache, independent of the
      24h positive-cache TTL.
- [x] **m4 (minor, measured)** — the per-Bash-call cost of sourcing 5 libraries landed on
      every call, including non-commit ones. Moved the raw-payload verb-substring
      prefilter to run BEFORE any `source` line.
- [x] **m5 (minor, HYPOTHESIZED)** — the block message's FIX text claimed dropping the
      override always yields "git's own default identity resolution", which is false
      when the expected value came from the gh API and differs from the repo's own
      config. Reworded to name the actual resolved value + its source and point at
      fixing the repo's config specifically when it differs.
- [x] **m6 (minor, HYPOTHESIZED)** — the auto-set side effect's "never a silent side
      effect" claim rested on a stderr note that PreToolUse does not guarantee surfaces
      to the agent on a non-blocking exit. Reworded to name the signal ledger as the
      reliable record and the stderr note as a best-effort courtesy.
- [x] **m7 (minor)** — `fp_expectation` cited only self-test pass counts, not a measured
      false-positive rate. Ran an independent grep-based replay of local session
      transcripts (methodology + exact command recorded in the manifest field): 22
      co-occurring Bash-tool-use lines across 3 distinct files, the same order of
      magnitude as the review's own independently-run replay (25 matches across 6
      files) and directly overlapping on one cited session (`dbe36e21`). Recorded in
      `fp_expectation`, replacing the self-test-only framing.

## Review-Fix Round 2 (harness-reviewer REFORMULATE, record hcr-20260930-68fd4a0d)

The record (`docs/reviews/records/2026-09-30-harness-change-review-68fd4a0d.json`) is
cherry-picked onto this branch. Every finding below has a pinned NEGATIVE (must allow)
and POSITIVE (must still block) self-test case, prefixed `R2` in the gate's suite. The
suite run against the round-1 gate body (305d2e3c) fails 16 of the new cases, so they
catch the round-1 defects rather than restating the new code.

- [x] **MAJOR-1 (PROVEN, text-as-data read as identity overrides).** Four shapes were
      rc=2 with no mismatching identity: F1 (a `-m "$(cat <<'EOF' ...)"` message quoting
      `"git commit --author=..."`), F4 (`git commit -F - <<'EOF'` whose body mentions
      `--author=`), R1 (an ANSI-C `$'...'` string holding git text), and P1
      (`E=<matching> && GIT_AUTHOR_EMAIL="$E"`, where the literal `$E` was compared).
      Fixes, in the gate:
      - `$'...'` is decoded and re-emitted as ordinary single quotes.
      - Here-doc BODIES are removed before splitting. Only a body whose terminator line
        is present is removed.
      - Assignment-only and `export` segments are substituted into later segments with
        `gcp_subst_vars_var`.
      - A value still holding `$` or a backtick is UNKNOWN. It gets a ledger warn and is
        never treated as a mismatch.
      - The flag walk stops at a `<<` token, a backtick, or an unbalanced `$(`.
      - The shell-accurate tokenizer honours `\"` escapes.

      One deliberate deviation from the reviewer's suggested fix: a token that holds a
      BALANCED `$(...)`, or a newline, is SKIPPED as an opaque value rather than stopping
      the walk. After the two whole-command normalizations, such a token can only be a
      well-formed quoted value. Stopping at it would lose a real `--author=` placed AFTER
      a multi-line message, and the R2 F1-positive case pins that such an `--author=` is
      still blocked. A command-scoped prefix on a non-commit segment
      (`GIT_AUTHOR_EMAIL=x git add f && git commit`) no longer leaks into the commit.
- [x] **MAJOR-2 (PROVEN, section 10 FP RATE missing).** Re-ran the reviewer's classified
      replay: the same 58 distinct identity-bearing commit-creating commands (from 12
      transcripts, extracted by the reviewer's `extract.js`), fed through the round-2
      gate as real PreToolUse payloads. The replay results:
      - **18 blocked, all on-target, and 0 off-target**, so the FP rate is 0/58 (0.0%).
        In round 1 it was 4/58 (6.9%), with 4 of 9 blocks off-target.
      - The 18 on-target blocks break down as follows. 4 are `-c user.email=<session-context
        email>` commits on a downstream worktree. 14 are `-c user.email=<AI-vendor noreply
        address>` commits and merges in downstream worktrees. 13 of those 14 were FALSE NEGATIVES in
        round 1, because `W=<dir>; cd "$W"` targets were left unresolved and therefore
        failed open. The MAJOR-1 variable substitution closed that gap.
      - 40 were allowed. One of the 40 (a `-c user.email=<session-context email>` commit)
        is golden-class but unjudgeable in replay, because its target worktree no longer
        exists and so the check fails open.
      - HONEST CAVEAT: these fixes were written while looking at this same corpus. The 4
        rows fixed are closed by general mechanisms (normalization, substitution, the
        records exemption), not by special cases, but a fresh corpus is the stronger test.
      - The per-row output is `replay-r2.tsv` in the round-2 author's scratchpad. It is
        not committed, because it holds transcript text.
- [x] **MAJOR-3 (PROVEN, blocked the harness's own review-record commits).** A commit is
      exempt when both of these hold:
      - every RESOLVED identity override has the `reviewer+<...>@<...>` shape that
        `review-runner.sh` finalize stamps (A1);
      - the content is records-only, meaning every path is `docs/reviews/records/<file>`.
        This is judged from the commit's own `-- <pathspec>`, or else from the staged
        index plus any `git add` earlier in the same command. `-a`, a wildcard add, and
        an unresolved path each disqualify.

      Every exemption is logged as a ledger `skip`. A `reviewer+` identity on anything
      else is still blocked, and the FIX line then names `review-runner.sh finalize`. The
      runner bug that forces the manual fallback (the writer's stdout captured with
      `2>&1`, `review-runner.sh:~326`) is out of this PR's scope and remains on
      origin/master.
- [x] **Minors.** Each item below was fixed and pinned by a self-test:
      - m2: a plain commit with no override and a configured `user.email` short-circuits
        on one `git config --get`. Measured best of 5, from the round-1 gate to this one:
        - a plain commit went from 2240 to 892 ms;
        - a non-git call with a verb in its description went from 704 to 177 ms, after a
          `*git*` raw prefilter was added;
        - a plain commit on the unmapped-owner repo went from 2102 to 814 ms.

        The unmapped-owner ledger warn is deduped to once per owner per day (lib S11).
      - m1: a directory that this same command `git init`s fails open, like any throwaway
        repo.
      - m3: SSH host-alias remotes (`git@github-<alias>:owner/repo`) resolve through
        `ssh -G`, and are enforced only when the effective HostName is github.com (lib
        L10-L13, gate R2 m3).
      - m4: the block message carries the NL-FINDING-016 note that the ENTIRE command did
        not run. A tracked config set is labelled `git config user.email` and named as a
        SET earlier in the same command.
      - m5/r2-1: a tracked `git config user.email` applies only to a commit in the same
        repo, compared by normalized path, then by `--show-toplevel`. `git -C <dir>
        config ...` is now parsed.

      Two items are named residuals rather than fixes:
      - m5: a `git config user.email` set in a SEPARATE, earlier Bash call is not seen.
      - m6 (HYPOTHESIZED): the gh-API rung ignores primary-email visibility.

## Files to Modify/Create
- `adapters/claude-code/hooks/gh-commit-author-identity-gate.sh` — new PreToolUse gate.
- `adapters/claude-code/hooks/lib/gh-commit-identity-lib.sh` — new resolution library.
- `adapters/claude-code/hooks/lib/gh-account-lib.sh` — additive `gh_owner_from_url` /
  `gh_owner_from_cwd_remote` + their self-test cases.
- `adapters/claude-code/manifest.json` — new `gh-commit-author-identity` gate entry.
- `adapters/claude-code/settings.json.template` — new standalone `PreToolUse`/`Bash` wiring.
- `adapters/claude-code/doctrine/git.md` — compact pointer line.
- `adapters/claude-code/doctrine/git-full.md` — detail section.
- `adapters/claude-code/scripts/blocking-budget-check.js` — M2 fix (independent review):
  added `gh-commit-author-identity` to `UNIT_MAP`'s `commit-boundary` class so this gate
  consumes no net-new blocking-budget unit.
- `docs/plans/gh-commit-author-identity-2026-09-27.md` — this plan.

## Assumptions
- The operator's dispatch is authoritative on the golden scenario, the resolution chain's
  priority order (gh API via the target account's own token, never the active account;
  fallback to repo git config; never a noreply guess), and the FP-rate/retirement-condition
  bar (constitution section 10) — no assumption was needed on WHETHER to build this, only
  on implementation shape, which is documented inline in each file's own header rather than
  left implicit.
- "Expected name" has no independent GH-side oracle analogous to the email (`gh api
  user/emails` has no name equivalent worth trusting cross-session); this plan's design
  choice — judge a name override against the repo's OWN current `git config user.name` —
  is stated as a design choice in `hooks/lib/gh-commit-identity-lib.sh`'s header, not
  hidden as an implicit limitation.
- `gh auth token -u <account>` (used to fetch a SPECIFIC, possibly-non-active account's
  token without switching) is assumed available on the `gh` CLI versions this harness
  targets; if a machine's `gh` predates that flag, `gia_gh_primary_email` fails closed to
  the git-config fallback rung (same code path as the documented missing-`user`-scope
  case), never a crash or a noreply guess.
- Other `Status: ACTIVE` plans in this repo are unrelated to this fix; this plan exists
  solely to satisfy `scope-enforcement-gate.sh`'s requirement that every commit's staged
  files be declared by at least one active plan (union-of-scopes semantics — see that
  gate's own header).

## Edge Cases
- **`git -C <other-repo> commit --author=...` from an unrelated cwd** — judged against
  `<other-repo>`'s expected identity, not the invoking cwd's (self-test: "-C target dir
  drives expected-identity lookup").
- **`git commit-tree <tree> -c user.email=... -m x`** (with `-c` correctly preceding the
  subcommand, per real git syntax) — commit-tree is explicitly identity-bearing for this
  gate even though `git-command-parse.sh`'s own `gcp_resolve_commit_target` deliberately
  excludes it for its own callers (self-test: "commit-tree recognized as identity-bearing").
- **`export GIT_AUTHOR_EMAIL=... && git commit -m x`** — an env var exported in an EARLIER
  segment of the SAME command is visible to a LATER commit segment, exactly like real
  shell semantics (self-test: "export in an earlier segment blocked").
- **An unparseable `--author` value** (no `<email>` bracket) — fails CLOSED (blocks) rather
  than silently passing an unverifiable identity through (self-test: "unparseable --author
  value fails closed").
- **Nothing resolvable at all** (owner unknown to `accounts.config.json` AND the repo has
  no git config identity at any level) — fails OPEN (allows), and is asserted to NEVER
  contain the substring "noreply" anywhere in its output (self-test + lib self-test's
  static source-lint, both named "noreply-never-used").
- **The gh API is reachable but the account's token lacks the `user` scope** (the live,
  named case on this machine) — falls back to the repo's own git config, not a crash, not
  a guess (self-test: "scope-missing-fallback").
- **A repo with no `user.email` at any level, no override present** — the optional
  auto-set fires exactly once and is logged, never silent (self-test: "no-override-allowed
  (+ auto-set unset user.email)").

## Testing Strategy
Pinned self-test scenarios (all currently GREEN, evidence in the C-Round Record below):
- `hooks/lib/gh-account-lib.sh --self-test` — 9/9, including L5-L9 (the two new helpers:
  https/ssh URL parsing, non-github rejection, cwd-remote resolution, unknown-remote
  rejection).
- `hooks/lib/gh-commit-identity-lib.sh --self-test` — 9/9 (S1 gh-api resolves; S2 cache
  hit avoids a repeat API call; S3 a TTL of 0 forces re-resolution; S4 scope-missing
  fallback; S5/S5b/S5c noreply-never-used, both behaviorally and as a static source-lint;
  S6 no `gh` binary at all; S7 name resolution).
- `hooks/gh-commit-author-identity-gate.sh --self-test` — 15/15 (override-blocked,
  matching-override-allowed, no-override-allowed-plus-auto-set, scope-missing-fallback,
  noreply-never-used, commit-tree, `-c user.name` mismatch, glued `-c<key>=<val>`, env var
  via command-scoped prefix, env var via an earlier `export`, the ACK escape plus its
  ledger write, `-C` target-dir resolution, non-commit no-op, unparseable `--author`, and
  cache reuse across two invocations).
- `bash adapters/claude-code/manifest.json` — validated as well-formed JSON (`node -e
  "JSON.parse(...)"`).
- `harness-doctor.sh --quick` — run against the live mirror pre-merge; the
  attributable findings are the EXPECTED "template-live-drift"/"manifest-freshness"
  RED pair naming this exact change (self-resolving once reviewed + installed — the
  `review-before-deploy` gate correctly refused to install an unreviewed change locally,
  which is the mechanism working as designed, not a defect); every other RED/WARN in that
  run predates this change (`workstreams-state-gate.sh` live/template drift,
  `docs/harness-architecture.md` drift, a stale `NEEDS-YOU.md`) and is unrelated to it.
  **CORRECTED (M2, PR #67 independent review, PROVEN):** this claim was
  incomplete — `node adapters/claude-code/scripts/blocking-budget-check.js` measured
  16/14 on this PR's base commit (`4ff107f4`, already over the ADR 058 D5 budget,
  pre-existing and unrelated to this PR) and 17/14 on this PR's head BEFORE the fix
  below, because `gh-commit-author-identity` counted as a new standalone
  `commit-boundary`-class unit with no `UNIT_MAP` entry. Fixed by adding
  `'gh-commit-author-identity': 'commit-boundary'` to `UNIT_MAP` in
  `blocking-budget-check.js` (this gate fires ONLY on git-commit-shaped Bash
  commands, definitionally the same class every other `commit-boundary` member
  already is) — re-measured at 16/14 on this PR's head after the fix, i.e. net-zero
  budget contribution, matching the base exactly.

## Definition of Done
- [x] All three touched/new self-test suites green (33/33 combined assertions).
- [x] `manifest.json` valid JSON with a complete `kind: gate`, `blocking: true` entry
      naming golden_scenario/fp_expectation/retirement_condition/honest_status/waiver_path.
- [x] `settings.json.template` wires the gate as a standalone `PreToolUse`/`Bash` entry.
- [x] Doctrine updated (compact pointer + detail section).
- [ ] PR opened against `origin/master` (branch `feat/commit-author-from-gh-account`);
      NOT merged, per this task's explicit instruction.
- [ ] A `harness-reviewer` PASS review-record — deferred to a separately-invoked
      session/process per `docs/plans/review-independence.md` (see Tasks above); this
      plan stays `Status: ACTIVE` (not `COMPLETED`) until that review lands and the PR
      merges, since "done" per CLAUDE.md/constitution section 1 means merged with a SHA,
      which has deliberately not happened here.

## C-Round Record — self-test bugs found and fixed while building (2026-09-27)

The FIRST self-test run of `gh-commit-author-identity-gate.sh` was 12/15, not 15/15. All
three failures were bugs in the SELF-TEST, not the gate:
1. **HOME leak.** The "no-override-allowed" case unset the repo's LOCAL `user.email` but
   never sandboxed `HOME`, so `git config --get user.email` fell through to the real
   operator machine's GLOBAL `~/.gitconfig` email — an assertion whose outcome depended on
   whichever machine ran the suite (the same self-invalidating class CLAUDE.md's
   Windows-local-failures note already warns about elsewhere in this estate). Fixed by
   exporting a sandboxed `HOME` for the whole self-test, matching the practice
   `gh-account-autoswitch.sh`'s own self-test already uses.
2. **Two test commands placed `-c user.email=...` AFTER the `commit`/`commit-tree`
   subcommand word** (`git commit -m x -c user.email=...`), which is not valid git syntax
   either — `-c` is a global flag and must precede the subcommand. The gate's parser
   correctly did not treat it as a global config override in that position; the fix was to
   correct the two test commands (`git -c user.email=... commit -m x`), not the parser.

Both are documented here rather than silently fixed, per the constitution's honesty rule:
a report that reads better than reality is a defect. Re-run after both fixes:
`gh-commit-author-identity-gate.sh --self-test` → 15/15.
