# Failure Mode Catalog

> **Purpose.** Canonical, sanitized catalog of known failure classes for THIS project. Every new failure that surfaces during a session either extends an existing entry (same class) or is added as a new entry (new class). Investigation-class sessions consult this file FIRST, before forming a hypothesis. Every failure not encoded here is a failure that will repeat — at full cost — in a later session.

> **Scope.** Failure CLASSES, not individual incidents. Each entry generalizes from one or more concrete observations. Sanitized — no credentials, no personal identifiers, no real incident dates tied to a customer, no absolute paths containing usernames.

> **Standard.** This file follows the cross-project FM-catalog convention (`docs/conventions/failure-mode-catalogs.md` in the harness repo; Decision 033). One catalog per project, this single file, this schema.

## Schema

Six required fields, plus two optional fields. The optional fields are additive — entries may omit them where they add nothing; consumers read by `Symptom` phenotype or by `FM-NNN` ID, never positionally.

Required:

- **ID.** `FM-NNN` ascending. Never recycled. Renaming an entry preserves the old ID. `FM-000` is the reserved example slot — never a real failure.
- **Symptom.** What an operator or user observes when this manifests, in 1-2 sentences. **Primary grep target** — write it as a searchable phenotype with concrete keywords.
- **Root cause.** What in the system actually produced the symptom. Names mechanism, not blame.
- **Detection.** Which hook / agent / test / review step is positioned to surface this class. If detection is purely behavioral today, say so — the gap is the point.
- **Prevention.** What stops the class at the source. If partial or aspirational, say so honestly.
- **Example.** One sanitized concrete instance, in generic terms.

Optional (populate whenever they add signal — highest-leverage for investigation-first):

- **Discriminator.** How to tell *this* FM apart from look-alike FMs that share surface symptoms — the single observation or command that distinguishes it.
- **Recovery.** The immediate human steps to get *unstuck right now* (distinct from Prevention, which is mechanism-facing).

## How to extend

1. Read this catalog top-to-bottom. If the phenotype matches an existing `Symptom`, extend that entry's `Example` list rather than create a duplicate.
2. If the root cause is a new class, append a new entry with the next `FM-NNN` ID. Sanitize.
3. Populate `Discriminator` and `Recovery` for any new entry where they add signal.
4. Reference the catalog entry from any related code / config / doc change in the same commit.

The harness's `~/.claude/rules/diagnosis.md` ("After Every Failure: Encode the Fix" + "Check the Failure-Mode Catalog Before Forming a Hypothesis") makes this an explicit step in both the investigation and the post-failure workflow.

---

## FM-000 — Example entry (format reference — delete or keep as reference; never reuse this ID)

- **Symptom.** A scheduled background job silently stops producing output after a deploy; no error is logged, the job's last-run timestamp simply stops advancing, and downstream data goes stale without any alert firing.
- **Root cause.** The deploy changed an environment variable name the job reads at startup; the job's config loader treats a missing variable as "feature disabled" and exits cleanly instead of failing loudly, so the scheduler records a successful (no-op) run.
- **Detection.** Behavioral today — noticed only when a human spots stale downstream data. No health-check asserts the job produced output; the "successful run" signal is a false positive because clean-exit-on-missing-config is indistinguishable from clean-exit-on-no-work.
- **Prevention.** Make the config loader fail loudly on a *required* variable being absent (distinct from an *optional* feature flag being unset); add a freshness assertion on the job's output (last-output-age alarm), not just a run-completed signal.
- **Example.** After a deploy, a nightly aggregation job ran "successfully" for four nights while producing nothing because `AGG_SOURCE_URL` was renamed to `AGGREGATION_SOURCE_URL` in the deploy and the loader defaulted the missing old name to "disabled."
- **Discriminator.** Distinguish from a genuine no-work run: check whether *required* inputs exist for the period (is there data the job should have processed?). If inputs exist but output is empty and the run is marked successful, this is the silent-clean-exit class, not a legitimate no-op.
- **Recovery.** Diff the deploy's env-var changes against the job's config loader; restore/alias the renamed variable; backfill the missed periods; add the freshness alarm before closing.
