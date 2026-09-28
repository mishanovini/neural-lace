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

**Golden scenario (why now):** 2026-09-21, Circuit PR #1871 — fixer subagents committed
with author set to the session's context email; the repo's own git config was already
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
- [ ] `harness-reviewer` PASS review-record — NOT run by this (authoring) session per
      `docs/plans/review-independence.md`: the authoring session's only legal interaction
      with the review queue is the MECHANICAL auto-enqueue that fires as a side effect of
      committing (`review-record-commit-gate.sh`'s `rq_auto_enqueue_uncovered` splice,
      advisory-only since the 2026-07-30 demotion — it never blocks the commit, it only
      enqueues + prints a non-blocking notice). A separately-invoked session/process is
      the one that may claim + review + record a verdict. This task's own dispatch says
      exactly this: "if not, say so — the orchestrator will run it."
- [ ] Merge to master (explicitly NOT done by this task — "Open a PR; do NOT merge").

## Files to Modify/Create
- `adapters/claude-code/hooks/gh-commit-author-identity-gate.sh` — new PreToolUse gate.
- `adapters/claude-code/hooks/lib/gh-commit-identity-lib.sh` — new resolution library.
- `adapters/claude-code/hooks/lib/gh-account-lib.sh` — additive `gh_owner_from_url` /
  `gh_owner_from_cwd_remote` + their self-test cases.
- `adapters/claude-code/manifest.json` — new `gh-commit-author-identity` gate entry.
- `adapters/claude-code/settings.json.template` — new standalone `PreToolUse`/`Bash` wiring.
- `adapters/claude-code/doctrine/git.md` — compact pointer line.
- `adapters/claude-code/doctrine/git-full.md` — detail section.
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
- `harness-doctor.sh --quick` — run against the live mirror pre-merge; the only
  attributable findings are the EXPECTED "template-live-drift"/"manifest-freshness"
  RED pair naming this exact change (self-resolving once reviewed + installed — the
  `review-before-deploy` gate correctly refused to install an unreviewed change locally,
  which is the mechanism working as designed, not a defect); every other RED/WARN in that
  run predates this change (`workstreams-state-gate.sh` live/template drift,
  `docs/harness-architecture.md` drift, a stale `NEEDS-YOU.md`) and is unrelated to it.

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
