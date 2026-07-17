# Review-before-deploy — compact

> Enforcement: `install.sh` hard-blocks an uncovered changed in-surface file
> before any file is touched; `session-start-auto-install.sh` fail-open
> skips + loudly warns on an uncovered file (never blocks). Shared surface +
> coverage logic: `hooks/lib/review-record-gate-lib.sh`. Writer:
> `scripts/write-review-record.sh`. Design: `docs/design-notes/review-record-
> primitive.md` (architecture-reviewer verdict SOUND-WITH-AMENDMENTS,
> 2026-07-16). Full: review-before-deploy-full.md.
> Applies: every harness deploy (install.sh run, or auto-install SessionStart sync).

**The gap this closes.** No mechanism required a `harness-reviewer` PASS
before a harness change reached live `~/.claude/`.

**Trigger surface (Amendment A):** a file is in-surface iff its path
relative to `adapters/claude-code/` matches `hooks/**/*.sh |
scripts/**/*.sh | agents/*.md | config/** | manifest.json |
settings.json.template | rules/**` (globs walked recursively). The
manifest is a CROSS-CHECK only — every `hooks[]` entry must resolve to an
in-surface path (doctor check `review-surface-cross-check`), else RED.

**Coverage (Amendments D+E):** a changed in-surface file is covered iff its
`{path, blob_sha}` is in `grandfather-manifest.json` (pre-cutover, exempt)
OR in `index.json` with `kind: harness-change-review`, `verdict: PASS`. The
records dir is audit-only, never scanned on the gate's hot path (doctor
check `review-index-consistency`).

**Named residual:** `config/**` is in-surface (Amendment A) but never
deployed by either carrier — a pre-existing deployment gap, not a gate
hole.

**Posture differs by carrier (Amendment F):** see header Enforcement line
for the hard-block-vs-skip+warn split.

**HONEST RESIDUAL (Amendment C, NOT gate-able today).** The gate checks
record EXISTENCE + content-match only — it cannot verify the quoted verdict
is genuine. Audit/honesty anchor only, NOT anti-fabrication. Follow-up:
`REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`, `docs/backlog.md`.

**Grandfather manifest + records dir are TRUST ANCHORS, not self-verifying.**
Doctor check `review-grandfather-integrity` re-derives the manifest and
REDs on divergence; git history is a second audit trail. Neither prevents
a bad edit at write time — both make it detectable after.

**What this gate does NOT catch (Amendment B):** content-presence only —
blind to silent content drops and to reverts of a previously-PASS'd blob
(no TTL). Merge-integrity is separate
(`docs/runbooks/master-reconcile-and-estate-cleanup.md` step 6).

**Retirement condition:** retire the hard-block half when `install.sh`
retires for a single continuously-reconciling sync path, or when a real
anti-fabrication anchor + native review-gate make this check redundant.
