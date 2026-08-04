# Review-before-deploy — compact

> Enforcement: `install.sh` hard-blocks an uncovered changed in-surface file before any file
> is touched; `session-start-auto-install.sh` fail-open skips + loudly warns (never blocks).
> AS OF 2026-07-30 (Amendment H): `hooks/review-record-push-gate.sh` is the AUTHORITATIVE
> runtime carrier — wired into `git-hooks/pre-push`, BLOCKS `git push` to master/main on an
> uncovered in-surface file, reading coverage at the COMMITTED blob. `review-record-commit-
> gate.sh` (commit time) is ADVISORY ONLY as of the same amendment — a builder subagent
> typically has no dispatch tool and cannot satisfy the remedy; the orchestrator, which can,
> is the actor at push time. Full: `review-before-deploy-full.md` (incident narrative,
> Amendment G cockpit surface, Amendment H subject-set enumeration + degraded-scan behavior).
> Applies: every harness deploy AND every `git push` to master/main with this harness installed.

**The gap this closes.** No mechanism required a `harness-reviewer` PASS before a change
reached live `~/.claude/`.

**Trigger surface:** in-surface iff path relative to `adapters/claude-code/` matches
`hooks/** | scripts/** | git-hooks/** | schemas/** | install.sh | sync.sh | agents/*.md |
config/** | manifest.json | settings.json.template | rules/**` (config/** never deployed by
either carrier), OR repo-root path matches `neural-lace/workstreams-ui/{server,web}/**/*.js`
(Amendment G). Manifest is a CROSS-CHECK only — every `hooks[]` entry must resolve
in-surface, else RED.

**Three enumeration rules (Amendment H), each earned by a proven bypass:** (1) enumerate by
every code a subject can change *or leave* the surface through — edit, `git rm`, `git mv`,
typechange, mode-only chmod; (2) a control authorizing content BY HASH must state what
metadata the hash does NOT cover (mode, symlink-ness, path encoding, case) and either cover
it or name it as a bypass; (3) git path OUTPUT is a rendering, not the path — every consumer
of `git diff --name-only`/`ls-files` feeding a path predicate needs `-c core.quotePath=false
-z`, `while IFS= read -r -d ''`.

**A remedy must be SATISFIABLE, not merely runnable.** A mode-only change can never clear the
review pathway (the record would attest to the blob it already attests to) — that block routes
to the operator override and says why.

**Coverage:** `{path, blob_sha}` in `grandfather-manifest.json` (pre-cutover, exempt) OR in
`index.json` with `kind: harness-change-review`, `verdict: PASS`.

**HONEST RESIDUAL.** Existence + content-match only — cannot verify the quoted verdict is
genuine (open: `REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`). Blind to silent drops/reverts of
a previously-PASS'd blob (no TTL); merge-integrity is separate (`master-reconcile-and-
estate-cleanup.md` step 6).

**Retirement:** hard-block half retires when `install.sh` retires for a reconciling sync path,
or an anti-fabrication anchor + native review-gate make it redundant.
