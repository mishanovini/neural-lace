# Convention — Failure-Mode (FM) Catalogs (cross-project standard)

> **Status:** the single source of truth for HOW every project does failure-mode catalogs. Ratified by Decision 033 (`docs/decisions/033-failure-mode-catalog-cross-project-convention.md`). Applies uniformly to the harness repo itself and every downstream project that consumes the harness.

> **Classification:** Hybrid. The schema, the single-file location, and the adoption procedure are a Pattern every project self-applies. The mechanical consumers that already enforce parts of it (the `harness-lesson` / `why-slipped` skills' "Step 0", the PR-template "What mechanism would have caught this?" CI gate, `plan-reviewer.sh`'s FM-NNN references) keep working unchanged because the schema is extended *additively*.

## Why this convention exists

A failure that is not written down is a failure that will be rediscovered — at full cost — by the next session. The originating evidence: an investigation that consumed roughly twelve hours and several wrong leads to identify a single root cause. With a catalog consulted *first*, recognition could plausibly have happened in the first hour. The catalog turns "diagnose from scratch" into "match a phenotype, read the recovery."

This was already true for the harness's own catalog (`docs/failure-modes.md`, 23+ entries, deeply wired into ~40 files). This convention makes the *same* pattern a uniform standard across **every** project, so a future investigation in any repo starts at the catalog instead of from zero.

## The one rule

**Every project has exactly one FM catalog, at `docs/failure-modes.md`, using the schema below.** One file. One schema. One catalog per project. Do NOT create a `docs/failure-modes/` directory, a second catalog file, or a per-feature catalog — fragmentation is the exact failure the catalog exists to prevent (one catalog per project, one mechanism per class).

## The schema (eight fields — six required, two optional)

Every entry is a `## FM-NNN — <short title>` section with these fields, in this order:

| # | Field | Required | Purpose |
|---|---|---|---|
| 1 | **ID** | yes | `FM-NNN` ascending, never recycled. Renaming an entry preserves the old ID. |
| 2 | **Symptom** | yes | What an operator/user *observes* when this manifests, in 1-2 sentences. **This is the primary grep target** — write it as a searchable phenotype so a future session diagnosing a similar event finds it by keyword. |
| 3 | **Root cause** | yes | What in the system actually produced the symptom. Names mechanism, not blame. |
| 4 | **Detection** | yes | Which hook / agent / skill / review step is positioned to surface this class. If detection is purely behavioral today, say so — the gap is the point. |
| 5 | **Prevention** | yes | What stops the class at the source. If partial or aspirational, say so honestly. |
| 6 | **Example** | yes | One sanitized concrete instance, in generic terms. No codenames, no personal identifiers, no real incident dates tied to a specific product. |
| 7 | **Discriminator** | optional | How to tell *this* FM apart from look-alike FMs that share surface symptoms. The single observation/command that distinguishes it. *This is the field that shortcuts a multi-hour investigation's dead ends.* Omit only when the Symptom is already unambiguous. |
| 8 | **Recovery** | optional | The immediate human steps to get *unstuck right now* (distinct from Prevention, which is mechanism-facing). What an investigator mid-incident does in the next five minutes. Omit only when there is no distinct recovery beyond "apply Prevention." |

Fields 7-8 are **additive and optional** (Decision 033). Existing entries that predate them need no migration; every consumer reads by `Symptom` phenotype or by `FM-NNN` ID, never positionally. New entries SHOULD populate Discriminator and Recovery whenever they add signal — they are the highest-leverage fields for the investigation-first use case.

### Why Discriminator and Recovery are separate from Detection/Prevention

`Detection` and `Prevention` answer *"what mechanism catches/stops this class?"* — they serve the harness's self-improvement loop. They do **not** serve an investigator mid-incident, who needs *"is this the bug I'm looking at (Discriminator), and what do I do in the next five minutes (Recovery)?"* The twelve-hour incident is precisely the case where multiple FMs share a Symptom and the Discriminator is what collapses the search.

## Grep-ability: the catalog IS its own index

A single file with searchable `Symptom` and `Discriminator` fields is its own index — no separate `INDEX.md` is required or wanted (a second file is a second thing to keep in sync). The convention for keeping it grep-able:

- Write `Symptom` in the **operator's words**, with concrete keywords (the exact error string class, the observable state, the tool that misbehaves). Not "the build is wrong" but "`npm run build` hangs with no output after the `Collecting page data` line; no error, no exit".
- The investigation-first lookup is literally: `grep -in '<keyword>' docs/failure-modes.md` then read the matching entries' Discriminator + Recovery.
- An optional `<!-- keywords: ... -->` HTML comment line under a `Symptom` is permitted for hard-to-phrase phenotypes (e.g., a numeric error code, a stack-frame name) — it is invisible in rendered Markdown but grep-visible.

## The investigation-first reflex

The catalog is only as good as the habit of checking it. The standing rule lives in `~/.claude/rules/diagnosis.md` ("Check the Failure-Mode Catalog Before Forming a Hypothesis"): **before forming any hypothesis in an investigation / debug / root-cause session, grep the project's `docs/failure-modes.md` `Symptom`/`Discriminator` fields for keywords from the reported problem.** This makes the catalog the *first* lookup in the diagnosis workflow — not only the last step of the encode workflow.

The pre-existing consumers remain unchanged and complementary:

- `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix" — at *encode* time, extend or add an entry.
- The `harness-lesson` and `why-slipped` skills' "Step 0 — check the failure-mode catalog FIRST" — when *proposing a mechanism*, don't add a competing one if the class is already cataloged.
- The PR-template "What mechanism would have caught this?" CI gate — answer form (a) cites an `FM-NNN`; answer form (b) proposes a new one.

## Adoption procedure (any project)

To bootstrap the catalog in a project that does not yet have one:

1. Copy the skeleton from `docs/templates/project-failure-modes/` in the harness repo into the target project's `docs/`:
   - `failure-modes.md` → `docs/failure-modes.md` (the starter file: schema preamble + one worked `FM-000` example).
   - `FM-template.md` → keep alongside as the copy-paste single-entry template (or inline its content into the team's contributing guide).
2. Delete the `FM-000` example once the project has its first real entry (or keep it as a format reference — its ID is reserved as the example slot and never reused for a real failure).
3. Add a one-line pointer in the project's `CLAUDE.md` / `AGENTS.md`: *"Investigation-class sessions: grep `docs/failure-modes.md` before forming a hypothesis (see `~/.claude/rules/diagnosis.md`)."* New projects inherit this automatically through the harness's global `diagnosis.md` rule; the per-project line is a belt-and-suspenders reminder for non-harness readers.
4. Commit. From then on, every diagnosed root cause either extends an existing entry (same phenotype) or appends a new `FM-NNN` (new class), per `diagnosis.md`.

For an existing project with scattered post-mortems: seed `docs/failure-modes.md` with one entry per recurring class found in `docs/reviews/` / `docs/discoveries/` / closed plans; do not back-fill one-offs (the catalog is *classes*, not an incident log).

## How to extend an existing catalog

When a new failure surfaces during a session:

1. Read the catalog top-to-bottom. If the phenotype matches an existing `Symptom`, **extend that entry's Example list** (and refine Detection/Prevention/Discriminator/Recovery if the new instance reveals something) rather than create a duplicate.
2. If the root cause is a new class, append a new entry with the next `FM-NNN` ID. Sanitize: no codenames, no personal identifiers, no real incident dates tied to a specific product, no absolute paths containing usernames.
3. Populate Discriminator and Recovery for any new entry where they add signal — they are optional but they are the fields a future investigator will most want.
4. Reference the catalog entry from any related rule / hook / agent change in the same commit.

## Cross-references

- Decision 033 — `docs/decisions/033-failure-mode-catalog-cross-project-convention.md` (the decision this convention implements).
- Decision 008 — `docs/decisions/008-capture-codify-failure-modes-stub.md` (the original catalog stub this generalizes).
- `docs/failure-modes.md` — the canonical reference instance (the harness's own catalog).
- `docs/templates/project-failure-modes/` — the copy-able adoption skeleton.
- `docs/proposals/fm-catalog-auto-search-harness-integration.md` — the proposed SessionStart auto-search hook (highest-leverage future execution; not yet shipped).
- `~/.claude/rules/diagnosis.md` — the investigation-first reflex + the encode-the-fix loop.
- `~/.claude/skills/harness-lesson/SKILL.md`, `~/.claude/skills/why-slipped/SKILL.md` — the "Step 0" consumers.

## Scope

Applies to every project whose Claude Code installation loads the harness's global `diagnosis.md` rule (i.e. all of them). Adoption of the per-project `docs/failure-modes.md` file is the project's responsibility (bootstrap procedure above); a project without the file simply has no catalog to grep — the reflex degrades to "no matches, proceed to diagnose" rather than erroring. The harness repo's own `docs/failure-modes.md` is the reference implementation and is never optional.
