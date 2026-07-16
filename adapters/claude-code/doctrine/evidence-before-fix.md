# Evidence-before-fix — compact

> Enforcement: `evidence-before-fix-gate.sh` (PreToolUse on `Bash`, independently
> wired — NOT nested in the `pre-commit-gate.sh` freshness chain, because that
> chain's own stdin/argv is already exhausted by the wrapper that dispatches it,
> so a nested gate cannot see the commit message; see the gate's header comment
> for the reproduced proof). Blocks a `fix(...)`/`fix:` commit unless it carries
> an evidenced root cause. Rule doc: `docs/lessons/2026-07-14-root-cause-must-be-
> evidenced-before-fix.md`. Full: `docs/design-notes/review-record-primitive.md`
> (Consumer contract 2) for the `fix-root-cause` record shape.
> Applies: every commit whose subject line starts with `fix(` or `fix:`.

**The gap this closes.** Three successive investigations reasoned from a
*plausible code path* to a shipped fix (#972) without ever observing the
SPECIFIC incident's evidence (the actual duplicate rows' timestamps, source,
property). `doctrine/diagnosis.md`'s pull-logs-first protocol existed but (a)
read as prod-crash-scoped, so its applicability to a data/behavior bug was
non-obvious, and (b) was a Pattern — nothing *gated* the fix from shipping on
an inferred-not-observed cause. This gate is the Mechanism.

**Trigger:** commit subject line starts with `fix(` or `fix:` (exact
conventional-commit prefixes only — `fixes`/`fixed`/`bug` etc. do NOT trigger;
narrow trigger surface is deliberate, see fp_expectation in the manifest
entry). `fix-trivial:` is a DIFFERENT prefix and never matches — the
decided lighter path for one-line/typo/no-runtime-symptom fixes (see FP-path
decision below).

**Satisfied by EITHER:**
1. **Inline evidence.** The commit message body contains a `## Root cause
   (evidenced)` section with at least one line tagged `PROVEN` (word-boundary
   match) that also carries a citation-shaped token: a `file:line` reference,
   a backtick-quoted command/output, or an explicit `command:`/`output:`/
   `log:` label with content. A section containing ONLY `INFERRED`-tagged
   lines (no `PROVEN` line at all) is mechanically REJECTED — this is the
   exact shape of the postmortem's failure (a plausible mechanism dressed as
   a finding).
2. **Record reference.** The message cites a `frc-YYYYMMDD-xxxxxxxx` record
   id (a `kind: fix-root-cause` review-record, `write-review-record.sh`'s
   naming convention). The gate resolves the record, requires `verdict:
   PASS`, `covered_files` intersecting the staged file set, and
   `payload.root_cause.tag == "PROVEN"` OR (`"INFERRED"` AND
   `payload.blast_radius_bounded == true`) — carrying forward the lesson's
   stated residual that evidence is sometimes genuinely unreachable, in
   which case the fix must be fail-safe and say so, not silently ship at
   full blast radius on a guess.

**Escape hatch (structured waiver, NOT an env var):** a fresh (<1h)
`.claude/state/evidence-before-fix-waiver-*.txt` naming both purpose clauses
(`hooks/lib/waiver-purpose-clause.sh` — "this gate exists to prevent X" /
"that does not apply here because Y") AND a `Files:` line matching at least
one staged file. Matches the `harness-hygiene-scan.sh` structured-waiver
precedent exactly (chosen over an env-var override deliberately — an
audit-logged env var is no harder to invoke than a two-line waiver file, and
the file leaves a durable, reviewable artifact the env-var log line does
not). `scope-enforcement-gate.sh`'s no-waiver posture (three structural
options only) was considered and rejected for THIS gate because the lesson's
own stated residual ("evidence is sometimes genuinely unreachable") is a
legitimate case this gate must accommodate, unlike scope drift.

**FP-path decision (task 3 of `docs/plans/harness-governance-batch-
2026-07-15.md`, decide-and-go per constitution §8):** trivial fixes (typo,
formatting, no runtime symptom) use the `fix-trivial:` prefix instead of
`fix:`/`fix(...)` — structurally exempt because the trigger regex never
matches it, no waiver ceremony needed. Expected FP rate: near-zero on
genuine `fix(...)` commits (the trigger is a literal, narrow prefix match,
not a keyword heuristic); the one deliberate over-inclusion is that a
`fix(...)` commit touching ONLY `*.md` files still triggers (no docs-only
exemption was added, to avoid stacking a second FP-path on top of
`fix-trivial:` — a docs-only fix that isn't trivial can `fix-trivial:` or
waive).

**Skip conditions (mechanically-replayed commits, scope-enforcement-gate's
precedent):** `$GIT_DIR/MERGE_HEAD`, `$GIT_DIR/CHERRY_PICK_HEAD`,
`$GIT_DIR/rebase-apply`, `$GIT_DIR/rebase-merge` present, OR the message's
first line starts with `Merge branch` — any of these skips the check
entirely (exit 0, stderr note). A replayed commit's root cause was
evidenced (or not) at its ORIGINAL authoring time; re-litigating it at
replay time produces false blocks on routine merge/rebase/cherry-pick
operations, not new safety.

**Retirement condition:** retire when `harness-reviewer`/`code-reviewer`
natively enforce this at PR-review time with transcript-verifiable evidence
(closing the same anti-fabrication residual review-before-deploy names), or
when commit messages are structurally replaced by a form that cannot express
free-text sections at all.
