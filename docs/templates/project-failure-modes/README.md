# Per-Project Failure-Mode Catalog — Adoption Skeleton

Copy-able skeleton for bootstrapping a Failure-Mode (FM) catalog in any project. The full standard is `docs/conventions/failure-mode-catalogs.md` in the harness repo (ratified by Decision 033). This directory is the *starter kit*.

## What's here

| File | Copy to | Purpose |
|---|---|---|
| `failure-modes.md` | `<project>/docs/failure-modes.md` | The catalog itself: schema preamble + one worked `FM-000` example. The project's single, canonical FM catalog. |
| `FM-template.md` | keep alongside, or inline into the team's contributing guide | The copy-paste single-entry template (eight fields). |

## Bootstrap procedure

1. **Copy the catalog file.** `cp docs/templates/project-failure-modes/failure-modes.md <project>/docs/failure-modes.md` (create `<project>/docs/` if absent). One file. Do NOT create a `docs/failure-modes/` directory — one catalog per project, single file.
2. **Keep `FM-template.md`** handy as the copy-paste template for new entries (alongside the catalog, or pasted into `CONTRIBUTING.md`).
3. **Add a one-line pointer** to the project's `CLAUDE.md` / `AGENTS.md`:
   > Investigation-class sessions: `grep -in '<symptom keywords>' docs/failure-modes.md` *before* forming a hypothesis. See `~/.claude/rules/diagnosis.md`.

   New projects inherit this reflex automatically via the harness's global `diagnosis.md` rule; the per-project line is a belt-and-suspenders reminder for human readers and non-harness tooling.
4. **Decide the `FM-000` example's fate.** Either delete it once the project logs its first real failure, or keep it as a permanent format reference. Its ID is the reserved example slot — never reuse `FM-000` for a real failure; real entries start at `FM-001`.
5. **Commit** the new `docs/failure-modes.md` (and the `CLAUDE.md` pointer) in one commit.

## For an existing project with scattered post-mortems

Seed `docs/failure-modes.md` with one entry per *recurring class* found in `docs/reviews/`, `docs/discoveries/`, or closed plans. Do NOT back-fill one-off incidents — the catalog is a record of failure **classes**, not an incident log. A class earns an entry when it has recurred or is judged likely to recur.

## After bootstrap

Every diagnosed root cause thereafter either extends an existing entry (same phenotype → add to its `Example` list) or appends a new `FM-NNN` (new class), per `~/.claude/rules/diagnosis.md` "After Every Failure: Encode the Fix". Populate the optional `Discriminator` and `Recovery` fields whenever they add signal — they are the fields a future investigator will most want.

## The eight-field schema (summary)

Required: `ID`, `Symptom` (primary grep target), `Root cause`, `Detection`, `Prevention`, `Example`. Optional (high-leverage for investigation-first): `Discriminator` (tell this FM apart from look-alikes), `Recovery` (immediate unstuck steps). Full definitions: `docs/conventions/failure-mode-catalogs.md`.
