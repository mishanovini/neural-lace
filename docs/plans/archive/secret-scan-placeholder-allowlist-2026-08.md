# Plan: secret-scan documented-placeholder allowlist (scrub-then-retest)

Status: COMPLETED
Owner: session dbe36e21 (cross-account takeover, 2026-08-08)
Rung: 1

## Goal

Backup pushes of stale branches complete without tripping the secret scan
on AWS's documentation placeholder, while real-shaped credentials keep
blocking at both commit time and push time.

## Intended Functionality

- **Outcome (operator's terms):** backing up my branches actually works
  again — a push of the stranded branches reaches the remotes instead of
  dying on a "secret" that is just AWS's documentation example, while
  anything that looks like a REAL credential still gets stopped.
- **Observation:** the previously-blocked backup push completes and the
  branches are visible on the remote (`git ls-remote origin` lists them);
  staging or pushing a real-shaped key is still blocked with a banner.
- **Deterministic pass/fail:** `git push` of the previously-blocked
  branches exits 0 and every pushed ref appears in `git ls-remote origin`;
  `pre-push-scan.sh --self-test` reports 5 passed, 0 failed (its s2
  real-key scenario asserts exit 1); `secret-backstop-fixture-check.sh`
  reports 4 passed, 0 failed.
- **Explicitly NOT included:** scan runtime (the ~2h cost is ledgered, not
  fixed here); the CI backstop workflow itself; the pt/master divergence.
- **Human dependencies:** none required. INTENDED (optional): the operator
  may extend the allowlist per machine via
  `~/.claude/sensitive-patterns-allowlist.local` (16-char minimum enforced).

## Problem

The repo deliberately carries AWS's published example key
(the access-key ID spelled out in both scanners' `ALLOWLIST_VALUES`) as
secret-scan fixtures
(`adapters/claude-code/tests/secret-backstop-fixture-check.sh`,
`adapters/claude-code/hooks/harness-hygiene-scan.sh`, archived plan
`docs/plans/archive/secret-scan-ci-backstop-skip.md` gave CI the same
exemption). Both local scanners flag it, so any stale branch whose
catch-up range re-adds those already-public files blocks its own backup
push. PROVEN 2026-08-08: a 19-branch backup push blocked after a 119m46s
scan naming only the three fixture files; the introducing commit
`f25132ae` is an ancestor of origin/master (`git merge-base
--is-ancestor` exits 0), so the content is already public on the same
remote. Two branches remain unbacked-up solely because of this
(`claude/hopeful-bose-b98694`, `ws-ui-server-stable`).

## Scope

IN: the two local secret scanners — pre-push and pre-commit — gaining a
documented-placeholder allowlist with scrub-then-retest semantics, plus a
self-test for the pre-push scanner.
OUT: scan performance (119-minute cost is filed to nl-issues, not fixed
here); the CI backstop (already exempted per the archived plan); pattern
list changes; review-record gates.

## Assumptions

- Vendor-reserved documentation values (AWS's published example
  credentials) can never be live; AWS reserves them in its docs.
- Scrub-then-retest (replace allowlisted values with a sentinel, re-test
  the pattern) preserves detection of a real credential sharing a line
  with a placeholder. Verified by control s3.
- The commit-time and push-time scanners must stay in sync — same
  allowlist, same semantics (same class, two instances).

## Tasks

- [ ] 1. Add the documented-placeholder allowlist (scrub-then-retest) to
  `pre-push-scan.sh` with `--self-test`, and the same fix to the
  commit-time scanner in `git-hooks/pre-commit` — Verification: mechanical
  — Evidence: pre-push-scan `--self-test` 4/4 (placeholder allowed,
  real-shaped key blocked, key-beside-placeholder blocked, sensitive
  filename blocked); real-repo controls: placeholder-only staging rc 0 /
  no banner, real-shaped key rc 1 with banner; `set -e` regression found
  and fixed (`|| true` on the grep-terminated assignment,
  git-hooks/pre-commit:17 is the `set -e`).

## Files to Modify/Create

Modify:
- `adapters/claude-code/hooks/pre-push-scan.sh` (T1)
- `adapters/claude-code/git-hooks/pre-commit` (T1)
- `adapters/claude-code/tests/secret-backstop-fixture-check.sh` (T1 — the CI
  backstop's red scenario planted the documented placeholder, which the
  allowlist now correctly allows; red scenario re-planted with a
  runtime-composed real-shaped key, and a new allowlist-green scenario
  locks the placeholder-allowed behavior into the same oracle)

Create:
- `docs/plans/secret-scan-placeholder-allowlist-2026-08.md` (this plan) (T1)

## Edge Cases

- Line carries BOTH a placeholder and a real credential → still blocks
  (scrub-then-retest; control s3 proves it).
- Per-machine extension via `~/.claude/sensitive-patterns-allowlist.local`
  (one exact value per line, `#` comments) — absent file is a no-op.
- Sensitive FILENAME patterns are unaffected by the allowlist (control s4).
- Pattern with zero matches under `set -e` → `|| true` keeps the hook
  alive (the silent-abort regression).

## Testing Strategy

`bash adapters/claude-code/hooks/pre-push-scan.sh --self-test` (4
scenarios in a mktemp fixture repo, fixture commits use `--no-verify` so
the commit-time hook cannot decide push-scan scenarios). Commit-time
scanner: staged-probe controls in the real repo (placeholder rc 0, fake
key rc 1). Full-scale proof: re-push of the two blocked branches after
this lands.

## Verification

Functional oracle = the previously-blocked push passes while the
synthetic real-credential control still blocks.

## Completion Report

_Generated by close-plan.sh on 2026-08-09T07:09:03Z._

### 1. Implementation Summary

Plan: `docs/plans/secret-scan-placeholder-allowlist-2026-08.md` (slug: `secret-scan-placeholder-allowlist-2026-08`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/git-hooks/pre-commit`
- `adapters/claude-code/hooks/pre-push-scan.sh`
- `adapters/claude-code/tests/secret-backstop-fixture-check.sh`
- `docs/plans/secret-scan-placeholder-allowlist-2026-08.md`

Commits referencing these files:

```
08624a4c fix(secret-scan): allowlist vendor documentation placeholders, scrub-then-retest
0b767aa2 fix(git-hooks): restore the exec bit — NO git hook has been firing on this Mac
0d40d08a fix(secret-scan): remediate review hcr-20260808-4edc4e8b findings 1-3
303286bf fix(secret-scan): re-point the CI backstop red scenario at a non-allowlisted key
ba22fd91 chore(harness): exec bits set by install.sh deploy across hooks/ and scripts/
deb6bc09 feat(agent-efficiency T7): path-in-block-message sweep across 38 gate hooks
dfc4693d fix-trivial(plan): reference the documented placeholder instead of quoting it
f25132ae feat(ci): SECRET-SCAN-CI-BACKSTOP-01 — CI backstop for --no-verify secret bypass
f283e8e0 fix(secret-scan): kill the MSYS subprocess storm — single-pass scan, pure-bash filename match
fa506615 Initial release v1.0
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)

## Closure Outcome

_Written by close-plan.sh at closure (2026-08-09T07:09:02Z)._

Outcome metric: no outcome metric declared by the plan at close time
Re-check date: 2026-08-23T00:09:02Z (default)

Evidence pointers:
- 08624a4c fix(secret-scan): allowlist vendor documentation placeholders, scrub-then-retest
- 0b767aa2 fix(git-hooks): restore the exec bit — NO git hook has been firing on this Mac
- 0d40d08a fix(secret-scan): remediate review hcr-20260808-4edc4e8b findings 1-3
- 303286bf fix(secret-scan): re-point the CI backstop red scenario at a non-allowlisted key
- ba22fd91 chore(harness): exec bits set by install.sh deploy across hooks/ and scripts/
- deb6bc09 feat(agent-efficiency T7): path-in-block-message sweep across 38 gate hooks
- dfc4693d fix-trivial(plan): reference the documented placeholder instead of quoting it
- f25132ae feat(ci): SECRET-SCAN-CI-BACKSTOP-01 — CI backstop for --no-verify secret bypass
- f283e8e0 fix(secret-scan): kill the MSYS subprocess storm — single-pass scan, pure-bash filename match
- fa506615 Initial release v1.0
