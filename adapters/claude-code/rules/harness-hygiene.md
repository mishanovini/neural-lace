<!-- Adapter copy of principles/harness-hygiene.md. Keep in sync. -->

# Harness Hygiene — What Never Ships

**Classification:** Hybrid. The conventions below (what counts as sensitive, how configs are layered, what templates look like) are documented as a Pattern the maintainer follows when editing harness code. The "no sensitive data in harness code" ban is backed by a Mechanism: the pre-commit scanner at `adapters/claude-code/hooks/harness-hygiene-scan.sh` refuses any commit that matches `adapters/claude-code/patterns/harness-denylist.txt`. The Pattern parts are self-applied. The denylist match is mechanical.

## Purpose

A harness is a kit — a shareable set of tools someone else can install and use. It is not a project — it is not the accumulated artifacts of one person's past work. A kit does not carry the identity of who used it. When a harness leaks the maintainer's usernames, employers, client codenames, credentials, or personal file paths into its shipped code, it stops being a kit and becomes a personal snapshot that happens to be installable. This rule codifies what must never appear in harness code so the published artifact stays generic and safe.

## No sensitive data in harness code

None of the following may appear in any file committed to a harness repo, anywhere — not in comments, not as fallback defaults, not in example fixtures, not in rule bodies, not in tests:

- **No passwords, tokens, API keys, or secrets** — even as "placeholder" or "fallback" values. Placeholders get copy-pasted into real usage. Real credentials get pasted back into "placeholder" slots. The only safe rule is none of them, ever, anywhere in committed harness code.
- **No real email addresses.** Use `test@example.com`, `user@example.test`, or noreply forms (`noreply@github.com`, `noreply@anthropic.com`). The `.example` and `.test` TLDs are reserved for this purpose and cannot resolve to a real mailbox.
- **No real domain names tied to identity.** Use `example.com`, `example.test`, `example.org`. Never a domain the maintainer owns or uses professionally.
- **No personal names** except as the maintainer's attribution in a clearly-marked `Owner:` or `Maintainer:` field at the top of a document. In code, scripts, rule bodies, template text, and examples, use `$USER`, `<user>`, `maintainer`, or a generic role noun.
- **No absolute paths containing a username.** Always `$HOME`, `~/`, or relative. A path like `/Users/alice/projects/foo` leaks both OS and identity; `~/projects/foo` or `$HOME/projects/foo` says the same thing generically.
- **No company or org names.** Use `<your-org>`, `<work-org>`, `<team>`, `<employer>`. Even a former employer is identity metadata.
- **No product codenames.** Use generic nouns — "the project", "a Next.js app", "a production system". Codenames embedded in lessons ("the Foo incident") couple every future reader to one specific company's memory.
- **No incident-specific details tied to a real product.** Anonymize: "a production incident involving a missing column in a webhook handler", not "the 2026-04-14 Widgets Inc. impersonation bug". The lesson survives anonymization; the identifier does not.
- **No real user data in test fixtures.** Use faker-generated values, `test@example.com`, obvious fake names like `Jane Doe` or `Test User`. Never real-world-looking strings "that happened to be there" when a fixture was first written.

## Two-layer config architecture

Harness code that needs personalization reads from a two-layer config:

- **Harness layer** — shareable, committed, generic. Hooks, rules, agents, templates, scripts. Every value in this layer is a generic default or a placeholder that the harness layer itself can operate on.
- **Local layer** — personal, gitignored, user-specific. By convention at `~/.claude/local/`, containing files like `personal.config.json`, `accounts.config.json`, `projects.config.json`, and a `custom-rules/` subdirectory for the user's personal overrides.

Harness code reads from the local layer at runtime via safe fallbacks. If the local layer is missing or partially populated, the harness still works with generic defaults; it does not crash, and it does not substitute a real identifier from anywhere else. A fresh install with no local config should behave correctly out of the box.

## Harness repos do not ship DOWNSTREAM-PROJECT plan, decision, or review INSTANCES

The harness ships **templates** for plans, decisions, and reviews (`templates/plan-template.md`, `templates/decision-log-entry.md`, `templates/completion-report.md`) and the **rules** describing when and how to produce instances of those templates.

**The distinction that matters:** the harness repo has its own development — improving the harness itself, adding hooks, writing new rules, etc. That work is a real project and produces real plans, decisions, reviews, and session summaries. Those artifacts BELONG in the harness repo and SHOULD be committed.

What does NOT belong in the harness repo: plan/decision/review/session files that were produced while USING the harness to build a DIFFERENT project. Those accumulate downstream-project identifiers and belong in the downstream project's own repo.

### Rules by file type

- **`templates/`** — shipped: these are generic, identifier-free templates.
- **`docs/plans/`, `docs/decisions/`, `docs/reviews/`, `docs/sessions/`** — committed when they describe harness-dev work itself (improving the harness). Enforcement is layered: the harness-hygiene scanner catches identifier leakage in any committed file regardless of directory, AND the `.gitignore` uses naming-convention allowlists (see "Reviews / decisions / sessions naming convention" below) so non-conforming downstream-project artifacts cannot be committed by accident.
- **`SCRATCHPAD.md`** — gitignored (ephemeral session state, not a permanent record).

### Reviews / decisions / sessions naming convention

NL-self-artifacts (audits / decisions / sessions about the harness itself) and downstream-project artifacts share the same `docs/{reviews,decisions,sessions}/` directories but follow different naming conventions so the `.gitignore` can distinguish them mechanically:

- **NL-self-artifacts** follow the established date / number prefix pattern at the top level of the directory:
  - `docs/reviews/YYYY-MM-DD-<topic>.md`
  - `docs/decisions/NNN-<slug>.md`
  - `docs/sessions/YYYY-MM-DD-<slug>.md`
  These ARE tracked by git and committed normally — no `git add -f` needed.
- **Downstream-project artifacts** typically arrive as nested directories (e.g., `docs/reviews/some-codename-research-YYYY-MM-DD/`) or as filenames that don't match the date-prefix convention (e.g., `docs/reviews/some-codename-internal.md`). These remain gitignored.

The `.gitignore` enforces this with a per-directory denylist + allowlist pair (paraphrased):
```
docs/reviews/*
!docs/reviews/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md
docs/decisions/*
!docs/decisions/[0-9][0-9][0-9]-*.md
docs/sessions/*
!docs/sessions/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md
```

Adding a new harness-self review or decision? Use the date-prefix or numbered-slug naming convention and it will be tracked automatically. Working on a downstream project's review and putting it in the harness repo by accident? It won't match the convention, and `.gitignore` will silently exclude it — defense-in-depth alongside the denylist scanner.

This closes HARNESS-GAP-10 sub-gap H.

### For downstream projects using the harness

Normal project repos SHOULD commit their plans, decisions, and reviews as team-shared permanent records. A product team's `docs/plans/*.md`, `docs/decisions/NNN-*.md`, `docs/reviews/YYYY-MM-DD-*.md`, and `docs/sessions/YYYY-MM-DD-*.md` are how future teammates understand rationale and history — they belong in that project's own repo. The project-level rule is unchanged; see `~/.claude/rules/planning.md`.

## Installation is idempotent and lossless

- Re-running `install.sh` never destroys user customization in `~/.claude/local/` or in a user-edited `settings.json`.
- When a template would otherwise overwrite a user-editable file, the installer writes it with a `.example` suffix instead and leaves the user's copy alone.
- The installer is safe to run repeatedly as the user refreshes the harness from upstream; a second run should produce the same state as the first, not mutate user state.

## Every default in templates is a functional placeholder

Template values must be obviously-not-real so nobody accidentally ships them:

- `<your-username>`, not a real username
- `<your-work-org>`, not a real organization
- `<your-personal-email>`, not a real address
- `<your-company>.com`, not a real domain

Generic visibly-placeholder values are safer than realistic-looking defaults. If a user forgets to customize a value, a bracketed placeholder is immediately obvious in output; a realistic-looking default might ship silently.

## Test fixtures use example or faker data

Fixtures used in automated tests, example inputs, demo payloads, and documentation screenshots must use example-domain or faker-generated data:

- `example.com`, `example.test` for domains
- `test@example.com` for emails
- Generated fake values for names, addresses, phone numbers — or obviously-synthetic values (`Jane Doe`, `Test User`)

A fixture that looks like real data because it once was real data is a silent leak waiting to happen. The test passes, the fixture ships, and a real identifier goes public with it.

## Enforcement

- **Hook-enforced:** `adapters/claude-code/hooks/harness-hygiene-scan.sh` runs as a pre-commit hook in the harness repo. It reads `adapters/claude-code/patterns/harness-denylist.txt` and rejects any commit whose staged diff matches a denylisted pattern. This is the mechanical layer and cannot be bypassed by forgetting a rule.
- **Pattern-enforced:** the `harness-reviewer` agent checks for hygiene violations on every rule, agent, or hook change before commit. This catches cases the denylist patterns don't cover, such as stylistic leakage and overly-specific incident citations.
- **Runtime-enforced (planned — not yet implemented):** a `/harness-review` skill will run weekly across the full tree (not just the staged diff), catching any drift that slipped through pre-commit and producing a dated review under `docs/reviews/`. See Phase 7 of `docs/plans/public-release-hardening.md` for the implementation plan. Until it lands, full-tree scans can be run manually via `adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree`.

## Scope

This rule applies to:

- Neural Lace itself (the harness repo and its principles)
- Any Claude Code adapter (`adapters/claude-code/`)
- Any tool-specific adapter added in the future (`adapters/codex/`, `adapters/cursor/`, etc.)
- Any file under `principles/` or `patterns/`

This rule does NOT apply to projects that use the harness for their own work. Projects have their own conventions, commit their own plans and decisions, and reference their own teammates by name. The hygiene rule is specifically about what ships in the harness kit itself, not about how the kit is used downstream.
