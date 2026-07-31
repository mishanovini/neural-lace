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

**Trigger surface (Amendments A+G+H):** in-surface iff path relative to
`adapters/claude-code/` matches `hooks/** | scripts/** | git-hooks/** |
schemas/** | install.sh | sync.sh | agents/*.md | config/** |
manifest.json | settings.json.template | rules/**` (config/** residual:
never deployed by either carrier), OR
repo-root path matches `neural-lace/workstreams-ui/{server,web}/**/*.js`
(Amendment G, cockpit surface incl. `*.selftest.js`; no INSTALL-time deploy
step exists for the cockpit, so `review-record-push-gate.sh` — not
`review-record-commit-gate.sh`, demoted to advisory by Amendment H — is the
enforcement for this surface too, since it reads the SAME `rrg_in_surface`;
residual `scripts/|state/|config/|web/*.{html,css}`, -full.md). Manifest
is a CROSS-CHECK only — every `hooks[]` entry must resolve in-surface
(doctor `review-surface-cross-check`), else RED.

**Amendment H surface shape (2026-07-30):** the four CARRIER-CHAIN trees
(`hooks/`, `scripts/`, `git-hooks/`, `schemas/`) are matched WHOLESALE —
not by extension — minus an exact-path exemption list of three non-code
members. Extension allowlists were retired because they are hand-written
lists that drift silently: a new `.mjs`/`.rb`/`.yaml` fell OUT of surface
with no edit and no reviewer. Exemptions are exact paths, never patterns,
so a new sibling defaults IN. Re-derive the exemption list with
`git ls-files 'adapters/claude-code/hooks/*' 'adapters/claude-code/scripts/*'
| grep -vE '\.(sh|js|ts|py|ps1)$'`.

**Subject-set enumeration (Amendment H, extended round 4):**
`review-record-push-gate.sh` enumerates the pushed range on THREE arms —
`--diff-filter=ACMRT`, a separate `--diff-filter=D --no-renames` pass, and a
`--raw` pass for FILE MODE. "The enforcing file no longer enforces at its
path" is ONE outcome with FIVE verbs: edit `M`, `git rm` `D`, `git mv`
`R100 <old> <new>` (ACMR emits only the DESTINATION, D emits nothing),
typechange `T` (excluded by BOTH), and **mode-only `chmod` `M` with an
unchanged blob — enumerated, but it PASSED coverage, because the authorized
key is `{path, blob_sha}` and the blob never moved.** `review-record-commit-
gate.sh` and `lib/review-queue-auto-enqueue-lib.sh` carry ACMRT + the `D`
pass too (round 4): advisory-only is a reason for a softer CONSEQUENCE, never
for a smaller SUBJECT SET.

Three rules, each earned by a proven bypass:

1. **Enumerate by the codes through which the subject can change *or leave*
   the surface.** Every self-test carries a `git mv`, a typechange, and a
   mode-only case beside its `git rm` case.
2. **A control that authorizes content BY HASH must state what metadata the
   hash does NOT cover** — mode, symlink-ness, path encoding, filename case —
   and either cover it or enumerate it as a named bypass. See
   `manifest.json` `review-record-push-gate.bypass_paths[16]` for this
   control's exhaustive statement.
3. **Git path OUTPUT is a rendering, not the path.** Every harness consumer
   of `git diff --name-only` / `ls-files` that feeds a path PREDICATE must use
   `-c core.quotePath=false` **and** `-z`, consumed with
   `while IFS= read -r -d ''`. Measured: `core.quotePath=false` alone still
   quotes a backslash; a space is never quoted, which is why the obvious probe
   misses this. A C-quoted `hooks/pré-push-gate.sh` was classified
   out-of-surface and landed on a real remote at rc=0.

**Degraded scans re-derive EVERY arm or fail closed (round 4).** When the
pushed range cannot be diffed (an unfetched remote tip — reachable on a plain
push and on `--force`), the change arm degrades UPWARD to
`EMPTY_TREE..local_sha`, a strict superset. The removal and mode arms cannot:
both are differential and re-derive from the remote-tracking refs (an anchor
the push does not write), unioned across every ref that resolves. If none
resolves, the push is REFUSED. A fallback that recomputes a SUBSET of the
subject set is a bypass that fires exactly when the gate is least sure of
itself — the previous revision recomputed only the change arm and silently
dropped the whole deletion arm, and `EMPTY_TREE..local` structurally cannot
emit a `D`.

**A remedy must be SATISFIABLE, not merely runnable.** For a mode-only change
the review pathway can never clear the block (the record would attest to the
blob it already attests to), so that block routes to the operator override and
says why. Scenario 22 pins that the emitted remedy PARSES; Scenario 17g pins
that it can actually be FOLLOWED.

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
