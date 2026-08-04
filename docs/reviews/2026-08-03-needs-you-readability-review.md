# NEEDS-YOU.md Readability Review — audit + target format + generator spec

**Reader persona:** Misha (the operator), opening the file cold to answer ONE question: "what do you need from me, most important first?" Busy; ~10 seconds before deciding whether to keep reading.
**Audit mode:** static + live-artifact verification (the live machine-local `NEEDS-YOU.md` at the main-checkout root read in full, Generated 2026-08-03T16:14:38Z, 167 lines; generator read at `adapters/claude-code/scripts/needs-you.sh`; 11 referenced product-repo PRs verified via `gh`; referenced worktrees verified on disk). Naming note: per harness-hygiene, this committed review says "the product repo" for the business repo the ledger entries reference; the machine-local ledger carries the real links.
**Rubric:** constitution §2 (communication hygiene, "every ask is a complete instruction") and §3 (compact ≤20-line decision format, cold-reader bar) — the ledger's OWN governing format, which its renderer ignores — plus Carroll minimalism (action-first), inverted-pyramid readability, and ROT staleness analysis.
**Date:** 2026-08-03 | Operator-directed (verbatim complaint 2026-08-03: "incredibly messy… not clear what you actually need from me").

## Executive summary

The file fails its single job — "what do you need from me, most important first?" — for four compounding reasons, all in the RENDER + LIFECYCLE layer, not in authorship. (1) A rendering bug duplicates every entry's first line as both heading and body — 15 of 15 open decision blocks affected, one rendering as `### ###`. (2) Entries render oldest-first with no priority, so the only born-today, genuinely-live decision (DEC-4) sits 14th of 15, below 26-day-old asks. (3) There is no staleness lifecycle for OPEN items: at least 4 of the 15 open decisions are PROVEN superseded (PR #985 merged 07-17, #974 closed, #973 merged + its migrations applied by 07-28) yet render at full length forever. (4) The "Open questions" dedup groups by exact text, so 5 recurring worktree alerts render as 25 near-identical bullets. Notably, the three NEWEST entries already have good §3 bodies — the add-time cold-reader lint works; the file is unreadable because the renderer has no summary, no ordering, no demotion, and a title bug. All four fixes are contained in `needs-you.sh` and preserve its machine-maintained contract.

The honest headline number: of 15 "Awaiting your decision" entries, only **5 genuinely need Misha** (2 of them today), **4 are answer-when-you-can with defaults already applied**, and **6 are stale or superseded**. The current format makes those 5 indistinguishable from the 10.

## Findings ledger (ranked; line numbers cite the live NEEDS-YOU.md of 2026-08-03T16:14:38Z and this repo's needs-you.sh)

```
- Location: needs-you.sh:1114-1118 (_ny_render_decision_block) → NEEDS-YOU.md L8-9, L13-14, L18-19, L30-31, L35-36, L40-41, L45-46, L50-51, L55-56, L60-61, L65-66, L70-71, L81-82, L101-102, L112-113
  Defect: The renderer prints `### $(head -1 "$text")` and then the FULL text verbatim — including that same first line. Every one of the 15 open decision blocks opens with its title printed twice. Where the stored text itself starts with "### " (entry NY-1783716259-0a77), the output is a double-hash heading: L18 reads "### ### Segments layer…".
  Framework: rubric: readability fail (broken visual grammar); Diátaxis reference-purity (a generated ledger must mirror its data, not stutter it)
  Reader impact: The reader's first two lines of every block are identical walls; skimming is punished immediately; the file reads machine-broken, which erodes trust in everything below it (the operator's exact complaint).
  Confidence: PROVEN (code path read; every live block exhibits it; the self-test comment at needs-you.sh:1643-1653 even codifies "renders title-then-full-body" as expected behavior)
  Class: render-title-duplication
  Sweep query: grep -n "head -1" adapters/claude-code/scripts/needs-you.sh (title extraction sites: 832, 1115)
  Effort: S  Impact: H
  Required fix: Body = `tail -n +2` of text when multi-line; empty body when single-line (title carries it). Normalize title: strip leading `#{1,6} ` before printing `### `.
  Required generalization: Update the self-test scenario that asserts title-then-full-body (comment block needs-you.sh:1643-1653) to assert single occurrence; add a regression scenario "first line of text appears exactly once in the rendered block".

- Location: needs-you.sh:1304 (cmd_render, decisions jq select — no sort) → NEEDS-YOU.md L8 (oldest, 2026-07-08) … L112 (newest, 2026-08-03)
  Defect: Open decisions render in ledger-insertion order = oldest first. The one item both the operator-todo AUTO section and today's sessions agree is live (DEC-4, NY-1785771976-caeb) is the 14th of 15 blocks, at L101 of a 167-line file.
  Framework: inverted pyramid / Carroll #1 (action first); §2 "the operator must never have to hunt"
  Reader impact: The cold reader wades through 26-day-old, partially-dead asks before reaching the decision that actually blocks machine-wide maintenance (doctor goes RED 2026-08-16). Most-important-first is inverted to most-important-last.
  Confidence: PROVEN
  Class: no-priority-ordering
  Sweep query: grep -n 'select(.section == "decision" and .state == "open")' adapters/claude-code/scripts/needs-you.sh
  Effort: S  Impact: H
  Required fix: `sort_by(.created_at) | reverse`, with blocking-flagged items (see --blocking, below) hoisted first.
  Required generalization: Same ordering rule for the Decide-now table (below); questions/inflight keep chronological (they are logs, not queues).

- Location: needs-you.sh:928-… (cmd_expire — RESOLVED items only) → NEEDS-YOU.md L8-68 (11 open decisions aged 16-26 days)
  Defect: Staleness handling exists ONLY for resolved items (7-day §8 window). Open items have no lifecycle at all: NY-1784210057-dd0b (L45, "DO NOT APPLY #973 AS-IS") renders at full length 18 days after PR #973 merged WITH the property-aware amendment; NY-1784189529-18cf (L40) still asks "YOUR MERGE" of PR #985, which merged 2026-07-17T03:39Z (gh-verified); NY-1784014662-db23 (L35) is a 6-item board of which 5 are done/superseded (PRs #975/#977/#985 merged, #974 closed, the duplicate-appointment pair auto-completed per L50).
  Framework: ROT: outdated — the highest-cost class; a confidently-stale ask is worse than no ask (the operator learns to distrust the whole ledger)
  Reader impact: Misha cannot tell live from dead, so he either re-verifies everything himself (the ledger's whole purpose inverted) or ignores the file (the observed outcome).
  Confidence: PROVEN for the three cited examples (gh PR states; entry NY-1785234921-5fd5's own text "prod migration list verified clean with exactly this one pending" proves the #973 migrations were applied by 07-28)
  Class: no-open-item-staleness-lifecycle
  Sweep query: n/a — structural (one lifecycle gap, every aged entry is a symptom)
  Effort: M  Impact: H
  Required fix: Render-time age partition: open decisions older than NY_STALE_OPEN_DAYS (proposed 14) demote to a collapsed "Probably dead — confirm to close" section as one-liners with a reply affordance ('still live <id>' / 'confirm dead <id>' → resolve).
  Required generalization: Same demotion for Open questions and In flight (L155-160 cite three product-repo worktrees by generated name — all PROVEN deleted from disk; L161's fidelity re-audit is PROVEN complete: the product repo's docs/reviews/2026-07-08-fidelity-reaudit-findings.md exists).

- Location: needs-you.sh:1322-1328 and 1344-1350 (cmd_render dedup: group_by(.text)) → NEEDS-YOU.md L126-135, L137-151
  Defect: Dedup groups by IDENTICAL text, but supervisor-tick re-adds each orphaned-worktree obligation with volatile fields ("last commit Nd ago", "alert #N", "N live/throttled session(s)") — so 5 distinct obligations render as 25 near-identical bullets, ~55% of the Open-questions section by volume.
  Framework: Carroll minimalism (minimize interference); signal-to-noise; the exact "duplicate noise" defect class the dedup was built for (its own comment, needs-you.sh:1138-1144) — defeated by its key choice
  Reader impact: The section is unscannable; the 2 genuinely unique questions (L125 estate cleanups, L136 prospect facts) drown.
  Confidence: PROVEN (diffed the repeated bullets; only volatile tokens differ)
  Class: dedup-key-includes-volatile-fields
  Sweep query: grep -n "group_by(.text)" adapters/claude-code/scripts/needs-you.sh
  Effort: M  Impact: M
  Required fix: Normalize the grouping key: gsub volatile spans (\b[0-9]+d ago\b, alert #[0-9]+, [0-9]+ live/throttled session\(s\), dirty=[0-9]+, unintegrated=[0-9]+, "First detected …;") before group_by; render the NEWEST representative + "xN since <first-seen date>".
  Required generalization: Better long-term: recurring emitters (supervisor-tick) should pass an explicit stable `--dedup-key` (e.g. the worktree path); the text-normalization is the fallback for keyless callers.

- Location: needs-you.sh:1296-1302 (cmd_render header) — no summary pass → NEEDS-YOU.md L1-6
  Defect: The file opens with provenance boilerplate then dives into full blocks. There is no top-of-file answer to the reader's only question; no counts, no table, no "decide now".
  Framework: §3 compact-format spirit applied to the whole file; Every-Page-is-Page-One (the file IS the landing page); inverted pyramid
  Reader impact: 10-second skim yields nothing actionable; the operator must read ~4,000 words to discover 2 of 15 items matter today.
  Confidence: PROVEN
  Class: missing-executive-summary
  Sweep query: n/a — instance-only (one render header)
  Effort: M  Impact: H
  Required fix: Render a "## Decide now" table (≤10 rows: id | one-line ask | reply with | age | blocking?) above the four canonical sections, plus a one-line count banner. See target format below.
  Required generalization: n/a — instance-only.

- Location: ledger schema + needs-you.sh:678-875 (cmd_add — no reply/blocking/supersedes fields) → e.g. NEEDS-YOU.md L45-46 ('973-amend-now' buried mid-paragraph), L55 ('a2p-o1/o2/o3: <choice>' mid-sentence)
  Defect: §3 item 5 ("Reply with: the exact one-word answers and what each triggers") has no first-class field; reply tokens are buried in prose. Likewise no `blocking` flag (§2's Blocking / When-you-can split) and no `supersedes` link — which is why three generations of the #973 ask (dd0b → 62ef → referenced by 5fd5) all render as open siblings.
  Framework: constitution §2 two-bucket sign-off + §3 item 5; terminology/scent — the reply token IS the label the reader acts on
  Reader impact: Even for a live item, Misha must excavate the reply token from a wall of prose; superseded chains force him to reconstruct which ask is current.
  Confidence: PROVEN
  Class: schema-missing-action-fields
  Sweep query: grep -n '"reply\|blocking\|supersedes' adapters/claude-code/scripts/needs-you.sh (no hits = confirmed absent)
  Effort: M  Impact: H
  Required fix: Additive flags on add: --reply-with <tokens>, --blocking, --supersedes <id> (auto-resolves the older entry with note "superseded by <new-id>"). Render falls back to heuristic extraction (first line matching /[Rr]eply/) for legacy entries.
  Required generalization: Extend _ny_lint_decision_text with a warn-only `no-reply-line` code so future entries carry the token by construction.

- Location: NEEDS-YOU.md L8, L13, L30-31, L35-36 etc. (single-paragraph bodies) — authorship, pre-lint entries
  Defect: The 11 oldest entries are single-paragraph walls (the worst, L35-36 db23, packs SIX numbered asks into one sentence-stream). The three newest (L70-79, L81-99, L101-110) already have real §3 shape — the 2026-07-28 interactive lint block visibly fixed authorship.
  Framework: §3 compact format; Carroll #4 (survive skimming)
  Reader impact: Pre-lint entries can't be skimmed; but this cohort ages out — no renderer prose-rewriting is warranted (it would violate the machine-maintained contract).
  Confidence: PROVEN
  Class: pre-lint-wall-of-text (self-resolving cohort)
  Sweep query: n/a — bounded to entries added before 2026-07-28
  Effort: n/a (no code fix)  Impact: M
  Required fix: None in the renderer. The stale-demotion fix collapses most of this cohort to one-liners anyway; the digest (companion deliverable) hand-triages them once.
  Required generalization: n/a — the interactive lint already prevents recurrence.

- Location: docs/operator-todo.md AUTO section vs NEEDS-YOU.md — 13 open ledger decisions have NO AUTO pointer (splice postdates them); the AUTO ticks don't feed back to the ledger (by design, Task-12 auditor pending)
  Defect: The two "awaiting operator" surfaces disagree: operator-todo shows 2 open items; the ledger shows 15. A reader trusting either alone gets a wrong picture.
  Framework: findability / single-source-of-truth; §2 "chat is a notification; the file is the record" — but there are two records
  Reader impact: Misha checks the todo, sees 2, and reasonably concludes the other 13 are handled.
  Confidence: PROVEN (compared both files)
  Class: dual-ledger-divergence
  Sweep query: diff <(grep -o 'NY-[0-9]*-[0-9a-f]*' NEEDS-YOU.md) <(grep -o 'NY-[0-9]*-[0-9a-f]*' docs/operator-todo.md)
  Effort: M  Impact: M
  Required fix: Out of this review's scope to build; recommend the planned Task-12 auditor pass reconcile tick-state from the ledger. The digest below is the interim reconciliation.
  Required generalization: n/a — one auditor, one reconciliation rule.

- Location: needs-you.sh:1119 ("Links: (none)"), L10, L62, L67; meta line format L11 etc.
  Defect: Empty-value noise: "Links: (none)" prints for entries with no links; the meta line always spells out session `unknown`.
  Framework: minimalism; readability polish
  Reader impact: Minor — 3 extra noise lines, but every line in this file competes with the signal.
  Confidence: PROVEN
  Class: empty-field-noise
  Sweep query: grep -n "'(none)'" adapters/claude-code/scripts/needs-you.sh
  Effort: S  Impact: L
  Required fix: Suppress the Links line when empty; drop "session `unknown`" from the meta line (keep id + date).
  Required generalization: Apply to bullet renderer too.
```

## Target format — the top of the new NEEDS-YOU.md, fully rendered

Everything above the first canonical header is NEW; the four canonical headers survive below it (required — see contract notes). This example uses today's real content:

```markdown
# NEEDS-YOU
Generated 2026-08-03T16:14:38Z · 3 decide-now · 4 when-you-can · 8 probably-dead · 2 open questions

## Decide now

| # | id | Ask | Reply with | Age | Blocking? |
|---|------|-----------------------------------------------------------|----------------------------------|-----|-----------|
| 1 | caeb | Ratify the NL-Maintenance resident daemon (DEC-4) | `ratify` / `pure-tick` / `hold` | 0d | YES — zero maintenance runs; doctor RED 2026-08-16 |
| 2 | 5fd5 | Apply the parts-queue prod migration (PR #1203) | `apply parts migration` / `hold parts` | 6d | YES — PR #1203 merge waits on it |
| 3 | bfef | Repoint 52 .env.local files off PRODUCTION (PR #1287) | `repoint all 52` / `leave them` | 1d | no — but prod-safety exposure until answered |

## Awaiting your decision

### DEC-4: ratify the resident maintenance daemon (NL-Maintenance) `NY-1785771976-caeb` · added 2026-08-03 · tier 2
**Decision needed:** register ONE Windows scheduled task keeping a supervised bash daemon alive for all machine maintenance.
Context: the 6 legacy NL-* tasks are Disabled since 2026-08-02; until registered this machine runs ZERO recurring maintenance; doctor WARNs now, RED on 2026-08-16. Your Round-3 direction said "no bespoke resident daemon"; the architecture review (docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md, F3) calls this shape defensible but explicitly yours to ratify. Both Criticals re-reviewed PASS (docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md).
| Option | What happens |
|---|---|
| `ratify` | installer runs; maintenance resumes machine-wide in 5 min; HALT flag drains it; -Rollback uninstalls |
| `pure-tick` | same coverage, no resident process; sub-5-min cadences floor at 5 min |
| `hold` | nothing registers; WARN → RED 2026-08-16; cross-machine sync stays dead |
**My pick:** ratify. **Reply with:** `ratify` / `pure-tick` / `hold`
```

(…remaining fresh entries as the same ≤20-line blocks, newest first…)

```markdown
## Probably dead — confirm to close

Open >14 days, or evidence says superseded. One line each; reply `confirm dead <id>` (resolves) or `still live <id>` (re-promotes).

- `dd0b` DO-NOT-APPLY PR #973 as-is — superseded: #973 merged 07-17 WITH the property-aware amendment · 18d
- `62ef` Authorize #973 migration apply — evidence applied by 07-28 (5fd5: "prod list … exactly this one pending") · 17d
- `db23` 2026-07-14 six-item board — 5/6 done or superseded (#975/#977/#985 merged, #974 closed) · 20d
- `18cf` Merge PR #985 — merged 2026-07-17; only the P4-a..d default-gates survive (see when-you-can) · 18d
…
```

Design rules the example encodes: (1) the answer to "what do you need from me" is the first screen; (2) every live entry is a §3 compact block with a bold **Reply with** line; (3) age and blocking are first-class columns; (4) stale items cost one line each and carry their own close affordance; (5) newest first everywhere the reader acts.

## Generator spec — exact changes to needs-you.sh (contract-preserving)

All changes are inside `adapters/claude-code/scripts/needs-you.sh`; all ledger-schema changes are ADDITIVE (schema_version stays 1; every existing jq read tolerates extra fields).

| # | Function / site | Change | Effort |
|---|---|---|---|
| S1 | `_ny_render_decision_block` (L1103-1130) | Title-dup fix: body = `tail -n +2` when text is multi-line, empty otherwise; strip leading `#{1,6} ` from the title; suppress `Links:` when `(none)`; meta line drops session-`unknown` | S |
| S2 | `cmd_render` (L1284-1386) | New "## Decide now" pass BEFORE the canonical sections: one jq over open decision+question items, filter age ≤ NY_STALE_OPEN_DAYS, sort blocking-desc then created_at-desc, cap 10 rows; columns id-suffix, title (≤70 chars), reply_with (field, else heuristic `/[Rr]eply/` line extract), age-days, blocking. Plus a one-line count banner replacing 2 lines of boilerplate | M |
| S3 | `cmd_render` decisions select (L1304) | `sort_by(.created_at) | reverse`, blocking items hoisted first | S |
| S4 | `cmd_render` + new constant `NY_STALE_OPEN_DAYS=14` | Render-time partition of open decisions/questions/inflight by age: fresh → current sections; stale → new "## Probably dead — confirm to close" one-liner section (id, title, age). Pure render-time computation: NO ledger mutation, so `render` stays idempotent (same-day re-renders byte-identical apart from the Generated timestamp, exactly as today) | M |
| S5 | dedup jq (L1322-1328, L1344-1350) | Group by NORMALIZED text: `gsub` volatile spans (`[0-9]+d ago`, `alert #[0-9]+`, `[0-9]+ live/throttled session\\(s\\)`, `dirty=[0-9]+ file\\(s\\)`, `unintegrated=[0-9]+ commit\\(s\\)`, `First detected [^;]*;`) before `group_by`; render NEWEST representative + `xN since <first-seen>` | M |
| S6 | `cmd_add` (L678-875) | Three additive flags: `--reply-with <str>` (stored `reply_with`), `--blocking` (stored `blocking:true`), `--supersedes <id>` (after the successful ledger write, auto-`cmd_resolve <id> --note "superseded by <new-id>"`; a missing target WARNs, never dies — add must stay total) | M |
| S7 | `_ny_lint_decision_text` (L626-673) | Warn-only fourth code `no-reply-line` when neither `--reply-with` nor a `/[Rr]eply/` line is present. Decision-section only (preserves the T25 lint_warnings-decision-only contract the cockpit Inbox consumes) | S |
| S8 | self-tests (`cmd_self_test`) | Update: the scenario codifying title-then-full-body (comment L1643-1653) now asserts the first text line appears EXACTLY once per block; T4 format assertions updated. Add: decide-now table renders and caps at 10; stale item demotes at 15d and NOT at 13d; volatile-token bullets collapse to one; `--supersedes` resolves its target; blocking sorts first; single-line entry renders no duplicate body | M |

**Contract-preservation checklist (each verified against the current code):**
- **Ids:** untouched (`_ny_gen_id` L480-488 unchanged).
- **Append semantics:** `cmd_add` still a single jq append (L770-784); new fields ride the same call. The bash-3.2 `${links[@]+…}` idiom and both write guards (L503-520, L809) untouched.
- **Re-render idempotency:** S4 partitions at render time from `created_at` vs now — no state mutation; `cmd_expire`'s resolved-only semantics unchanged.
- **Cold-reader lint:** interactive-block vs mechanical-quarantine paths (L707-748) unchanged; S7 only appends a warn code.
- **`bootstrap-migrate` / `_ny_md_has_all_headers` (L1189-1197): CRITICAL — the four canonical headers must all remain present or every render would re-ingest the file as legacy content (recursion class already seen 2026-07-29). New sections are ADDITIVE; the canonical four stay. Add a self-test asserting `_ny_md_has_all_headers` passes on the new layout.**
- **Downstream consumers:** the digest feed that counts `^### ` lines under "Awaiting your decision" (per comment L1631-1637) will see stale items leave that section — correct semantically (they are not awaiting), but the consumer (`feed_needs_you`, session-start digest) and the cockpit Inbox (`server/inbox-routes.js`, reads `lint_warnings`) must be smoke-checked in the same PR. `has-entry-for-session` (L1391-1399) reads state only — unaffected.
- **operator-todo splice** (L411-442): unchanged; `--supersedes` does not retro-edit pointers (append-only contract).

## Quick wins vs. structural

**Ship this week (S effort, H impact):** S1 title-dup fix · S3 newest-first sort · S8's regression test for S1. These three alone turn the file from "machine-broken" to "readable but unprioritized".
**Scope as one small PR (M):** S2 Decide-now table + S4 stale demotion + S5 dedup normalization + S6 fields — one coherent render-redesign PR with the self-test suite extension.

## Durable enforcement

- The interactive cold-reader lint already prevents new wall-of-text entries — evidence: the three newest entries are the three best-formatted. Keep it; add S7's `no-reply-line`.
- Add a self-test invariant: "no line in rendered output equals its predecessor" (catches the title-dup class generically).
- The stale-demotion threshold is the durable fix for ROT: no open ask can silently cost full-length attention for a month again.
- Recurring mechanical emitters (supervisor-tick) should adopt `--dedup-key`; until then S5's normalization is the backstop.

## Open questions for the operator

None on format — the operator's complaint IS the requirement and every change above is defensible from constitution §2/§3. One threshold call made decide-and-go: NY_STALE_OPEN_DAYS=14 (long enough that a week away doesn't demote live asks; short enough that the July cohort collapses). Override in the render PR if you want a different window.
