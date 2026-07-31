# Review-before-deploy — compact

> Enforcement: `install.sh` hard-blocks an uncovered changed in-surface file
> before any file is touched; `session-start-auto-install.sh` fail-open
> skips + loudly warns on an uncovered file (never blocks). AS OF 2026-07-30
> (Amendment H, deterministic-process.md): `hooks/review-record-push-gate.sh`
> is the AUTHORITATIVE runtime carrier — wired into `git-hooks/pre-push`
> (core.hooksPath dispatcher), it BLOCKS `git push` to master/main when the
> pushed range introduces an uncovered in-surface file, reading coverage at
> the COMMITTED blob (not the working tree). `review-record-commit-gate.sh`
> (PreToolUse, commit time) is ADVISORY ONLY as of the same amendment — it
> warns but never blocks, because a builder subagent typically has no
> Task/Agent-dispatch tool and cannot itself satisfy the remedy (docs/
> backlog.md REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01); the orchestrator,
> which DOES have dispatch capability, is the actor at push time. Shared
> surface + coverage logic: `hooks/lib/review-record-gate-lib.sh`. Writer:
> `scripts/write-review-record.sh`. Design: `docs/design-notes/review-record-
> primitive.md` (architecture-reviewer verdict SOUND-WITH-AMENDMENTS,
> 2026-07-16). Full: review-before-deploy-full.md.
> Applies: every harness deploy (install.sh run, or auto-install sync) AND
> every `git push` to master/main from a machine with this harness installed.

**The gap this closes.** No mechanism required a `harness-reviewer` PASS
before a change reached live `~/.claude/`.

**Trigger surface (Amendments A+G):** in-surface iff path relative to
`adapters/claude-code/` matches `hooks/**/*.sh | scripts/**/*.sh |
agents/*.md | config/** | manifest.json | settings.json.template |
rules/**` (config/** residual: never deployed by either carrier), OR
repo-root path matches `neural-lace/workstreams-ui/{server,web}/**/*.js`
(Amendment G, cockpit surface incl. `*.selftest.js`; no INSTALL-time deploy
step exists for the cockpit, so `review-record-push-gate.sh` — not
`review-record-commit-gate.sh`, demoted to advisory by Amendment H — is the
enforcement for this surface too, since it reads the SAME `rrg_in_surface`;
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

**Amendment H (2026-07-30, deterministic-process.md):** the commit-time
carrier's block was UNSATISFIABLE from the layer it fired at — 78 override
events (docs/backlog.md REVIEW-GATE-UNSATISFIABLE-FROM-BUILDER-01), every
2026-07-30 one citing the same builder-has-no-dispatch-tool deadlock.
`review-record-push-gate.sh` moves the authoritative check to `git push`
(the funnel every commit reaches the remote through, AND the layer where the
actor — the orchestrator — can actually satisfy the remedy). Its own
override is NOT `REVIEW_RECORD_GATE_OVERRIDE` (removed from the commit gate
entirely) but an operator-authorized, sha-scoped, 900s-TTL marker written by
`scripts/authorize-review-record-push-override.sh` (Rule 2: an override the
acting agent authors unilaterally is not an override). Manifest proof
obligation (Rule to self): every `blocking:true` entry declares `chokepoint`
+ `bypass_paths`, mechanized by doctor `check_deterministic_process_proof`.

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
