# Evidence-before-fix — full

Detail companion to the compact `evidence-before-fix.md` (which was trimmed to
fit the 3000-byte doctrine-compact CI cap). Everything below was moved out of
the compact verbatim or near-verbatim; the compact carries the imperative
rules and points here for rationale, narrative, and measurement method.

## Enforcement wiring detail

`evidence-before-fix-gate.sh` is independently wired on PreToolUse for `Bash`
— NOT nested in the `pre-commit-gate.sh` freshness chain, because that
chain's own stdin/argv is already exhausted by the wrapper that dispatches
it, so a nested gate cannot see the commit message; see the gate's header
comment for the reproduced proof.

## Record shape pointer

For the `fix-root-cause` record shape referenced by path 2 (Record
reference), see `docs/design-notes/review-record-primitive.md` (Consumer
contract 2).

## The gap this closes (full narrative)

Three successive investigations reasoned from a *plausible code path* to a
shipped fix (#972) without ever observing the SPECIFIC incident's evidence
(the actual duplicate rows' timestamps, source, property). `doctrine/
diagnosis.md`'s pull-logs-first protocol existed but (a) read as
prod-crash-scoped, so its applicability to a data/behavior bug was
non-obvious, and (b) was a Pattern — nothing *gated* the fix from shipping on
an inferred-not-observed cause. This gate is the Mechanism -- currently in
warn-mode rather than blocking, because the RULE and the gate's TRIGGER
turned out not to be the same shape (see next section).

## The doctrine/mechanism scope mismatch (harness-review finding, not yet resolved — warn-mode IS the calibration for this, not a claim it's closed)

The RULE is scoped to *observed defects* — a live incident with rows, logs,
or a repro to cite. The gate's TRIGGER is broader than that by construction:
it fires on ANY commit whose subject starts `fix(`/`fix:`, regardless of
whether that commit is actually about an observed defect. Measured against
this repo's own history (`git log -400 --format=%s | grep -cE '^fix(\(|:)'`
= 61/400, ~15%; a -300 sample independently measured ~13%), the DOMINANT
class triggering the gate is harness-maintenance / review-remediation fixes
("fix(review): address harness-review findings", "fix(wave-o): ...") — not
incident-forensics-shaped bugs. For that dominant class, "PROVEN root cause"
in the observed-incident sense often doesn't even apply (the real evidence
IS a reviewer's verdict, closer in shape to path 2's record reference than
path 1's citation). Blocking on a trigger this much broader than the rule it
enforces would have bricked ordinary maintenance work — that is exactly why
this gate is warn-mode, not blocking, and why the PROMOTION CONDITION
requires either narrowing the trigger or re-measuring the over-fire rate
before blocking is reconsidered.

## PROMOTION CONDITION — measurement method

Tracked `docs/backlog.md EVIDENCE-BEFORE-FIX-PROMOTION-01`. Method: repeat
the reviewer's own sweep — `git log -N --format=%s`, bucket matches into
{incident-shaped, review/audit-remediation, refactor/typo, other}, report
the share and the bucket breakdown.

## Trigger — full rationale

Exact conventional-commit prefixes only — `fixes`/`fixed`/`bug` etc. do NOT
trigger; narrow trigger surface is deliberate, see `fp_expectation` in the
manifest entry — narrow does NOT mean rare, see the scope-mismatch section
above. `fix-trivial:` is a DIFFERENT prefix and never matches — the decided
lighter path for changes touching NO runtime/product code (see FP-path
decision below).

## Banner-silencing — full rationale

Path 1 (inline evidence): a `PROVEN` line WITHOUT a citation shape does not
silence the banner — plain prose asserting "I confirmed this" is not itself
a citation (surfaced explicitly in the banner text so authors aren't
surprised by this). A section containing ONLY `INFERRED`-tagged lines (no
`PROVEN` line at all) does NOT silence it either — this is the exact shape
of the postmortem's failure (a plausible mechanism dressed as a finding).

Path 2 (record reference): the gate's requirement of `PROVEN` OR
(`INFERRED` AND `blast_radius_bounded == true`) carries forward the lesson's
stated residual that evidence is sometimes genuinely unreachable, in which
case the fix should be fail-safe and say so.

## Escape hatch — full rationale

Matches the `harness-hygiene-scan.sh` structured-waiver precedent exactly
(chosen over an env-var override deliberately — an audit-logged env var is
no harder to invoke than a two-line waiver file, and the file leaves a
durable, reviewable artifact the env-var log line does not).
`scope-enforcement-gate.sh`'s no-waiver posture (three structural options
only) was considered and rejected for THIS gate because the lesson's own
stated residual ("evidence is sometimes genuinely unreachable") is a
legitimate case this gate must accommodate, unlike scope drift.

## FP-path decision — full context

Decided in task 3 of `docs/plans/harness-governance-batch-2026-07-15.md`
(decide-and-go per constitution §8; tightened 2026-07-16 harness-review
remediation). `fix-trivial:` is reserved for changes that touch NO
runtime/product code — docs, comments, formatting only, zero behavior
change. That constraint is the point: a change meeting it is trivially
SPOT-CHECKABLE — a reviewer can confirm correctness by eye from the diff
alone, with no need for root-cause forensics at all. This is structurally
exempt (the trigger regex never matches `fix-trivial:`), no waiver ceremony
needed.

Measured FP context (2026-07-16): the trigger's over-fire is real (~13-15%
of this repo's own commits, see the scope-mismatch section above) but is NOT
concentrated in trivial docs/comment fixes — it's concentrated in
harness-maintenance/review-remediation fixes that DO touch runtime/product
code, which is exactly why `fix-trivial:` alone doesn't close the gap and
warn-mode is the calibration period instead of a second structural
exemption.

## Parser reach — full detail

Message extraction (2026-07-16 harness-review PROVEN fixes) handles heredoc
(the dominant convention), glued/spaced `-m`/`--message` with or without
`=`, MULTIPLE `-m`/`--message` segments (concatenated as separate
paragraphs, matching git's own behavior), `-F <file>`, and a best-effort
`--amend`-with-no-explicit-message proxy (reads HEAD's current message —
correct, not stale, unlike the `.git/COMMIT_EDITMSG` case in the gate's
header comment). Disclosed, unsolved residual: a message built via shell
interpolation the static command string doesn't literally contain, or an
interactive `--amend` editor session, still produces no evidence check —
lower-stakes under warn-mode (nothing blocks either way) but still means a
triggering commit in such a shape gets no teaching banner either.

## Skip conditions — full rationale

Mechanically-replayed commits, following `scope-enforcement-gate`'s
precedent: `$GIT_DIR/MERGE_HEAD`, `$GIT_DIR/CHERRY_PICK_HEAD`,
`$GIT_DIR/rebase-apply`, `$GIT_DIR/rebase-merge` present, OR the message's
first line starts with `Merge branch` — any of these skips the check
entirely (exit 0, stderr note). A replayed commit's root cause was
evidenced (or not) at its ORIGINAL authoring time; re-litigating it at
replay time produces false blocks on routine merge/rebase/cherry-pick
operations, not new safety.

## Retirement — full note

Retire when `harness-reviewer`/`code-reviewer` natively enforce this at
PR-review time with transcript-verifiable evidence (closing the same
anti-fabrication residual review-before-deploy names), or when commit
messages are structurally replaced by a form that cannot express free-text
sections at all.

## Restored detail (adversarial content-preservation verify, 2026-07-17)

The trim initially dropped three load-bearing specifics; restored here verbatim from the
pre-trim compact:

1. **PROMOTION CONDITION — the concrete trigger-refinement options.** The over-fire class
   (non-incident maintenance/review-remediation fixes) counts as separable by a trigger
   refinement e.g. by **excluding a `fix(review)`/`fix(wave-*)`-shaped scope**, or by
   **requiring an incident/finding-ID reference for the gate to even apply**. These two are
   the doc's central warn-mode -> blocking design path.
2. **PROMOTION CONDITION — sequencing qualifier:** ...OR the over-fire class is acceptably
   rare **once the parser-reach fixes are reflected in a fresh measurement** — i.e. re-measure
   the over-fire rate only AFTER the parser-reach fixes land, not before.
3. **Path 1 matching nuance:** the `PROVEN` tag is matched on a **word boundary** — this
   governs whether an author's evidence line is actually recognized as silencing the banner.
