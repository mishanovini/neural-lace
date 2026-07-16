# Review-before-deploy — compact

> Enforcement: `install.sh` hard-blocks an uncovered changed in-surface file
> before any file is touched; `session-start-auto-install.sh` fail-open
> skips + loudly warns on an uncovered file (never blocks). Shared surface +
> coverage logic: `hooks/lib/review-record-gate-lib.sh`. Writer:
> `scripts/write-review-record.sh`. Design: `docs/design-notes/review-record-
> primitive.md` (architecture-reviewer verdict SOUND-WITH-AMENDMENTS,
> 2026-07-16). Full: the design doc.
> Applies: every harness deploy (install.sh run, or auto-install SessionStart sync).

**The gap this closes.** Nothing deterministically required a harness change
(hook/gate/agent/rule) to carry a `harness-reviewer` PASS before it reached a
live `~/.claude/`. This failed twice in the model-enforcement workstream: a
buggy gate live-synced with zero review, and a fix was `install.sh`-deployed
before its re-review returned. Golden scenario: those two proven misses.

**Trigger surface (Amendment A) — path-glob, not manifest-derived:** a file is
in-surface iff its path relative to `adapters/claude-code/` matches
`hooks/**/*.sh | scripts/**/*.sh | agents/*.md | config/** | manifest.json |
settings.json.template | rules/**`. The manifest is a CROSS-CHECK, not the
source: every filename in any manifest entry's `hooks[]` must resolve to an
in-surface path (doctor check `review-surface-cross-check`), else RED.

**Coverage (Amendments D+E):** a changed in-surface file is covered iff its
`{path, blob_sha}` appears in the cutover `grandfather-manifest.json`
(pre-cutover content, never needs review) OR in the content-keyed
`index.json` with a `kind: harness-change-review`, `verdict: PASS` row. The
records directory itself is audit-only and is NEVER scanned on the deploy
gate's hot path — only the index is read (doctor check `review-index-consistency`
verifies the index stays a faithful rebuild of the records directory).

**Posture differs by carrier (Amendment F):** `install.sh` (operator present)
is a loud HARD BLOCK — the whole install aborts before touching any file,
naming every uncovered file + its blob_sha + the remedy. `session-start-
auto-install.sh` (fail-open by platform contract, always exits 0) SKIPS the
uncovered file + warns loudly (stale-not-blocked, stated explicitly) while
every other file still syncs — this composes with the hook's existing
fail-open posture instead of making it the one hard-blocking exception.
Rollout-lag consequence: a machine relying solely on auto-install can run a
stale copy of a covered file for at least one more session after an
unreviewed change lands — `install.sh` remains the authoritative immediate
enforcement point.

**HONEST RESIDUAL — anti-fabrication (Amendment C, NOT gate-able today).** The
deploy gate checks record EXISTENCE + content-match only; it cannot verify the
reviewer's quoted verdict is genuine (zero `SubagentStop`/`TaskCompleted`
capture hooks exist to retrieve the real transcript). The record is an audit
+ honesty anchor, NOT a deploy-path anti-fabrication control. Follow-up
(`REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`, `docs/backlog.md`): a capture
hook feeding `write-review-record.sh` a verifiable transcript reference.

**What this gate does NOT catch (Amendment B):** it is content-presence only
— blind to (i) absence of expected forward content (a silent merge/rebase
drop, the `937e8cb` class) and (ii) reverts to a previously-PASS'd blob
(accepted by design, no TTL). Merge-integrity is a SEPARATE mechanism (the
merge-time dropped-side sweep, `docs/runbooks/master-reconcile-and-estate-
cleanup.md` step 6) — this record does not substitute for it.

**Retirement condition:** retire the hard-block half when `install.sh` is
retired in favor of a single continuously-reconciling sync path, or when a
real anti-fabrication anchor + a native platform review-gate make this
record-based check redundant.
