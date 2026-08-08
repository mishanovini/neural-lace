# Plan: secret-scan documented-placeholder allowlist (scrub-then-retest)

Status: ACTIVE
Owner: session dbe36e21 (cross-account takeover, 2026-08-08)
Rung: 1

## Problem

The repo deliberately carries AWS's published example key
(`AKIAIOSFODNN7EXAMPLE`) as secret-scan fixtures
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
