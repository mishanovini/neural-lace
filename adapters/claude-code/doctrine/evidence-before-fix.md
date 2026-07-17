# Evidence-before-fix — compact

> Enforcement: `evidence-before-fix-gate.sh` (PreToolUse on `Bash`, independent
> of `pre-commit-gate.sh` — see gate header for why). **WARN-MODE (2026-07-16
> harness-review remediation) — never blocks.** On a `fix(...)`/`fix:` commit
> lacking evidence it prints a teaching banner and exits 0. Rule doc:
> `docs/lessons/2026-07-14-root-cause-must-be-evidenced-before-fix.md`.
> Full: `evidence-before-fix-full.md`.
> Applies: every commit whose subject starts `fix(` or `fix:`.

**The gap.** Fixes shipped from a plausible-but-unobserved cause, not the
incident's own evidence. Warn-mode, not blocking, because the RULE
(observed-defect scope) is narrower than the gate's TRIGGER (any `fix(`/
`fix:` subject, ~13-15% of commits) -- mismatch + measurement method: full.

**PROMOTION CONDITION** (`docs/backlog.md EVIDENCE-BEFORE-FIX-PROMOTION-01`):
promote to blocking only once the over-fire class (non-incident maintenance
fixes) is separated by trigger refinement or measured acceptably rare.
Method: full.

**Trigger:** subject starts `fix(` or `fix:` exactly (`fixes`/`fixed`/`bug`
do NOT trigger). `fix-trivial:` never matches -- see FP-path below.

**Banner silenced by EITHER:**
1. **Inline evidence.** Body has `## Root cause (evidenced)` with a
   `PROVEN`-tagged line carrying a citation (`file:line`, backtick
   command/output, or `command:`/`output:`/`log:` label). Plain prose or
   `INFERRED`-only does NOT silence it.
2. **Record reference.** Cites a `frc-YYYYMMDD-xxxxxxxx` `fix-root-cause`
   review-record id. Gate requires `verdict: PASS`, `covered_files`
   intersecting staged files, and `root_cause.tag == "PROVEN"` OR
   (`"INFERRED"` AND `blast_radius_bounded == true`).

**Escape hatch (structured waiver, not env var):** fresh (<1h)
`.claude/state/evidence-before-fix-waiver-*.txt` naming both purpose clauses
(`hooks/lib/waiver-purpose-clause.sh`) AND a `Files:` line matching a staged
file. Rationale: full.

**FP-path:** `fix-trivial:` = NO runtime/product code touched (docs/comments/
formatting only) -- structurally exempt, no waiver. Any runtime file touched
-> use `fix(...)` + path 1, 2, or waiver. Measured FP context: full.

**Parser reach:** handles heredoc, `-m`/`--message` (glued/spaced/multi),
`-F <file>`, best-effort `--amend`. Residual gaps: full.

**Skip conditions:** `$GIT_DIR/MERGE_HEAD`, `CHERRY_PICK_HEAD`,
`rebase-apply`, `rebase-merge`, or message starting `Merge branch` -> skip
entirely (exit 0); replayed commits were evidenced at original authoring time.

**Retirement:** when `harness-reviewer`/`code-reviewer` natively enforce this
at PR-review time, or commit messages can't carry free-text sections.
