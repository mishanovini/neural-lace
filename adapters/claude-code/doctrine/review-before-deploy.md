# Review-before-deploy — compact

> Enforcement: `install.sh` hard-blocks an uncovered changed in-surface file
> before any file is touched; `session-start-auto-install.sh` fail-open
> skips + loudly warns on an uncovered file (never blocks). Shared surface +
> coverage logic: `hooks/lib/review-record-gate-lib.sh`. Writer:
> `scripts/write-review-record.sh`. Design: `docs/design-notes/review-record-
> primitive.md` (architecture-reviewer verdict SOUND-WITH-AMENDMENTS,
> 2026-07-16). Full: review-before-deploy-full.md.
> Applies: every harness deploy (install.sh run, or auto-install sync).

**The gap this closes.** No mechanism required a `harness-reviewer` PASS
before a change reached live `~/.claude/`.

**Trigger surface (Amendments A+G):** in-surface iff path relative to
`adapters/claude-code/` matches `hooks/**/*.sh | scripts/**/*.sh |
agents/*.md | config/** | manifest.json | settings.json.template |
rules/**` (config/** residual: never deployed by either carrier), OR
repo-root path matches `neural-lace/workstreams-ui/{server,web}/**/*.js`
(Amendment G, cockpit surface incl. `*.selftest.js`; enforced ONLY at
commit-time — no deploy step exists for the cockpit, so
`review-record-commit-gate.sh` IS the enforcement, not a backstop;
residual `scripts/|state/|config/|web/*.{html,css}`, -full.md). Manifest
is a CROSS-CHECK only — every `hooks[]` entry must resolve in-surface
(doctor `review-surface-cross-check`), else RED.

**Coverage (Amendments D+E):** covered iff `{path, blob_sha}` is in
`grandfather-manifest.json` (pre-cutover, exempt) OR in `index.json` with
`kind: harness-change-review`, `verdict: PASS`. Records dir is audit-only,
never scanned on the hot path (doctor `review-index-consistency`).
Amendment G re-bootstraps at a new cutover in the commit right after it
lands (cutover_ref = the Amendment-G commit's SHA); `review-grandfather-
integrity` REDs for that one commit BY DESIGN, not a regression.

**Carrier posture (F):** header line has the hard-block-vs-skip+warn split.

**HONEST RESIDUAL (Amendment C).** Existence + content-match only — cannot
verify the quoted verdict is genuine (quote-forgery, open:
`REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`). WHO reviews, closed:
`docs/plans/review-independence.md` — `review-queue.sh enqueue` is the
author's only legal move; doctor `review-reviewer-independence` REDs on
matching git-commit authorship.

**Grandfather + records dir are TRUST ANCHORS, not self-verifying** — doctor
REDs on divergence from a fresh re-derivation; git history is a second
audit trail. Neither prevents a bad edit, both make it detectable after.

**Does NOT catch (B):** content-presence only — blind to silent drops and
reverts of a previously-PASS'd blob (no TTL); merge-integrity is separate
(`.../master-reconcile-and-estate-cleanup.md` step 6).

**Retirement:** hard-block half retires when `install.sh` retires for a
reconciling sync path, or an anti-fabrication anchor + native review-gate
make it redundant.
