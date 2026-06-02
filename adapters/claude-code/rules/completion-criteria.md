# Feature-Completion Criteria — "Shipped" Means All Eight, Not Just Merged

**Classification:** Hybrid. The eight-criteria definition of "complete" and the discipline of emitting a `## Completion Criteria` section when declaring a feature shipped are Patterns the session self-applies. The mechanical layer is two artifacts: `completion-criteria-gate.sh` (Stop hook — blocks session wrap when a feature-shipment-declaring final message does not account for all eight criteria) and `page-doc-accuracy-audit.sh` (project-generic, forward-facing post-fact backstop checking each live contractor-facing page against its support doc). The gate's block-mode default, retry-guard loop-break, and per-criterion skip audit-log are Mechanism; the audit's report is Mechanism.

**Ships with:** ADR 049 (`docs/decisions/049-feature-completion-criteria-gate.md`).

## Why this rule exists

The harness enforced exactly one bar for "a feature is shipped": **code merged to master.** Every other completion criterion lived in human attention and was therefore systematically missed. F4 Platform Console, C-47 transfer flow, ODS Twilio (both phases), Smart Import, the What's-New redesign — all merged AND deployed, none with user-facing support docs. That is not drift; it is a binary failure of a declared completion bar that nothing enforced.

The root cause is incentive shape. "Code merged" is the easiest exit signal an LLM session has — the commit landed, the PR is green, so the session declares the feature shipped and stops. The remaining seven criteria are invisible to that signal, and a memory rule ("remember to add docs") drifts under exactly the context pressure where it matters most. Across many parallel sessions, a *social* completion definition does not hold. This rule makes it *mechanical*.

Misha's framing (2026-06-01): "intended but not finished" is a failure mode he treats as **binary, not gradual**.

## The eight criteria

A feature is complete when ALL of these are true (or explicitly N/A with a reason):

1. **`code`** — Code merged to master.
2. **`tests`** — Tests added (unit / integration / E2E as appropriate to the feature class).
3. **`dev_docs`** — Dev docs updated (ADR / architecture / runbook).
4. **`user_docs`** — User docs updated (`docs/support/*.mdx` for any contractor-facing feature).
5. **`migration`** — Migration applied (schema live on prod, not just in repo).
6. **`deploy`** — Vercel master deploy succeeded for the merged commit.
7. **`acceptance`** — Acceptance criteria explicitly verified (demonstrated by a test / smoke run / screenshot).
8. **`stakeholder`** — Stakeholder / team notified if relevant (support team for user-facing changes, platform team for observability changes, etc.).

The bracketed keys are the canonical identifiers used by `COMPLETION_GATE_SKIP` and by the audit.

## When the gate fires

`completion-criteria-gate.sh` is a Stop hook, wired immediately **after** `pr-health-snapshot-gate.sh` and **before** `session-wrap.sh refresh`. On every Stop it reads the last assistant message from `$TRANSCRIPT_PATH` (agent-uneditable JSONL) and:

1. **Trigger.** Does the message DECLARE a feature shipped? Trigger phrases: `feature (shipped|complete|live)`, `(shipped|deployed) to (master|production|prod)`, `live in production`, `Status: COMPLETED`, plus operator-extensible `COMPLETION_GATE_EXTRA_TRIGGER`. **No trigger → the gate is a silent no-op.**

   The bare session-end `DONE:` marker is **deliberately NOT a trigger.** That marker ends *every* successful turn (session-end-protocol); firing on it would demand a completion-criteria section on every harness-dev / investigation / docs / refactor session — ceremony on work with no feature to ship. The gate is scoped to the actual failure pattern: *features declared shipped*.

2. **Validate.** A triggered message must contain a `## Completion Criteria` section accounting for all eight criteria. Per criterion:
   - **Done:** a check-off (`[x]` / ✓) carrying an **evidence token** — a commit SHA, `#PR`, `@handle`/`#channel`, URL, `.mdx`/file path, `/route`, or an artifact keyword (`screenshot`, `smoke test`, `playwright`, `curl`, `migration NNN`, `deploy green`). A bare `[x]` with no evidence FAILS.
   - **Not applicable:** an explicit `N/A` followed by a justification clause (`N/A — <reason>`). A bare `N/A` with no reason FAILS.
3. **Verdict.** All eight satisfied → allow. Section missing, or ≥1 criterion unmet (missing / checked-without-evidence / no-verdict) → **block** (block-mode default), naming the unmet criteria and showing the template. Blocks route through `stop-hook-retry-guard.sh` (3-retry downgrade-to-warn). The failure signature is the *sorted set of unmet keys*, so satisfying some-but-not-all is a NEW signature and resets the retry counter — progress is recognized.

### What a passing section looks like

```markdown
## Completion Criteria

- [x] Code merged to master — PR #412, commit ab12cd3
- [x] Tests added — e2e/transfer.spec.ts, src/lib/transfer.test.ts
- [x] Dev docs updated — docs/decisions/047-transfer.md
- [x] User docs updated — docs/support/transfer.mdx
- [x] Migration applied to production — migration 152 pushed, verified applied
- [x] Vercel master deploy succeeded — deploy green for ab12cd3
- [x] Acceptance criteria verified — smoke test against /contacts, screenshot
- [x] Stakeholder notified — support team alerted in #support
```

Each line may be `N/A — <reason>` instead when the criterion genuinely does not apply (e.g. `- Migration: N/A — no schema change in this feature`).

## Escape hatches

- **`COMPLETION_GATE_DISABLE=1`** — full suppression. For harness-dev sessions editing the gate itself, and for non-feature work. (This is the sibling of `PR_HEALTH_GATE_DISABLE=1`.)
- **`COMPLETION_GATE_SKIP=user_docs,migration`** — per-criterion skip. Each skip is appended to `.claude/state/completion-gate-skips.log` with the session id + timestamp. **A skip is a recorded decision, not a silent bypass** — chronic skips of the same criterion are themselves a signal surfaced at audit time.
- **Mode:** `COMPLETION_GATE_MODE` env > `~/.claude/local/completion-gate-mode` file > `block`. The default is `block` per the hard-requirement directive (unlike the doc-gate's warn-default). Flip to `warn` per-machine if needed.

Per `~/.claude/rules/gate-respect.md`: when the gate blocks, the first move is to satisfy the criteria (or justify them N/A), not to reach for `DISABLE`. The gate's stderr names exactly which criteria are unmet and why.

## The audit backstop — `page-doc-accuracy-audit.sh` (forward-facing)

> Redesigned 2026-06-01 (per Misha): Part B was originally a backwards-facing completed-plan walker; that is removed. Part B is now a **forward-facing page-vs-doc accuracy audit** — current pages vs current docs, not historical plans vs current state.

`page-doc-accuracy-audit.sh` checks, for every LIVE contractor-facing page (PageRegistry `owner: 'org'`), whether the page's support doc still accurately describes what the page does **now**. It is **project-generic** (ships in the kit, no project identifiers; parameterized by `--project <path>`) and keys off Next.js app-router conventions (`src/app/**/page.tsx` with route groups stripped), a `src/lib/page-registry.ts`, and `docs/support/*.mdx`. STATIC + best-effort (runtime/Playwright is a future enhancement). Per page it flags:

- **🔴 STALE** (exit-blocking) — a UI term the doc names (bold / short-quoted / "click X" prose) that appears **nowhere** in `src/`. The doc points contractors at a removed/renamed button or section — actively misleading. **High-precision by design:** the broad `src/` search (one prebuilt source index) makes route→component mapping errors unable to cause a false STALE, because the cost of a false STALE (telling the operator to "fix" a correct doc) is high.
- **🟡 UNDOCUMENTED** — a prominent page label (from the route's source closure) the doc never mentions. Best-effort; conservative filters (multi-word / non-common-button); a prompt to confirm, not a confirmed gap.
- **⚪ MISSING_DOC** — a contractor-facing page with no doc at all.

Platform/admin routes (audit log, platform console, impersonation) are skipped. Output: `<project>/docs/audit/page-doc-accuracy-<date>.md` (override `--out`). Exit 1 iff any STALE. Run weekly (scheduled task) or on-demand (a project may wire `npm run audit:doc-accuracy` to call it). It catches the drift class the project-tier doc-gate misses on *already-shipped* pages: button renames that broke a doc, removed sections still described, new features added without doc updates.

**The two layers are complementary — and both forward-facing.** Part A (the gate) catches incompleteness *at session-close, going forward*; Part B (this audit) catches *drift on what is already shipped*. Neither walks history. The gate intentionally favors false-negatives (a real shipment with unusual phrasing slips the phrase-trigger) *because* the audit independently re-checks shipped pages against their docs.

## Cross-references

- **ADR:** `docs/decisions/049-feature-completion-criteria-gate.md` — the decision, alternatives, and the refutation criterion the baseline audit tests.
- **Gate:** `adapters/claude-code/hooks/completion-criteria-gate.sh` (`--self-test`: 14/14, gh-free + node-free → no `KNOWN_FAILING_HOOKS` entry).
- **Audit:** `adapters/claude-code/scripts/page-doc-accuracy-audit.sh`.
- **Sibling gate (the pattern this mirrors):** `~/.claude/rules/pr-health-snapshot.md` + `adapters/claude-code/hooks/pr-health-snapshot-gate.sh` — same block-mode-default + retry-guard + escape-hatch shape, also a presence-check on the agent's own final message.
- **Composes with:** `~/.claude/rules/session-end-protocol.md` (the `DONE:` marker the gate deliberately does NOT trigger on); `~/.claude/rules/gate-respect.md` (diagnose-before-bypass when it blocks); `~/.claude/rules/planning.md` "FUNCTIONALITY OVER COMPONENTS" (the higher principle — a feature is done when the user can do the thing, which user docs + acceptance verification operationalize); F7's dev-doc gate (covers criterion #3 when wired); the project-tier user-doc gate (covers criterion #4 at PR time).
- **Enforcement map:** `~/.claude/rules/vaporware-prevention.md` (one row).

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | The eight criteria; when the gate fires; the section format; the escape-hatch policy | `adapters/claude-code/rules/completion-criteria.md` |
| Gate (Stop hook, Mechanism) | Feature-shipment-declaring final message must account for all eight (✓+evidence or N/A+justification) or session wrap blocks | `adapters/claude-code/hooks/completion-criteria-gate.sh` |
| Audit (Mechanism) | Forward-facing page-vs-doc accuracy check on every live contractor-facing page; report + non-zero exit on STALE docs | `adapters/claude-code/scripts/page-doc-accuracy-audit.sh` |
| Retry-guard (Mechanism) | 3-retry downgrade-to-warn; unmet-set signature so partial progress resets the counter | `adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh` |
| Skip audit-log (Mechanism) | Every `COMPLETION_GATE_SKIP` criterion is recorded with session + timestamp | `.claude/state/completion-gate-skips.log` |

## Scope

Applies in any session whose Claude Code installation has `completion-criteria-gate.sh` wired in the Stop chain of `settings.json`. The canonical wiring is in `adapters/claude-code/settings.json.template`; the live `~/.claude/settings.json` is updated per-machine by `install.sh` (the same template-vs-live split the sibling gates have). The gate is defensively inert where it cannot apply (no transcript, no `jq`, no trigger phrase, disable env), so it is safe in every session mode. The audit applies to any project following the `docs/plans/` + `docs/support/` conventions; it no-ops cleanly on projects that don't.
