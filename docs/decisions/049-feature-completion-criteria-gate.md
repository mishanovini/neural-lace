# ADR 049 — Feature-Completion Criteria Gate (eight criteria, mechanical, with a periodic audit backstop)

**Date:** 2026-06-01
**Status:** Active
**Stakeholders:** Misha (decision authority — declared the failure pattern and the eight criteria); every code session (downstream — the gate fires at their Stop when they declare a feature shipped); the maintainer of the per-project completion audit (downstream — `feature-completion-audit.sh` consumes the same eight-criteria definition post-fact).

## Context

Today the harness enforces exactly ONE bar for "a feature is shipped": **code merged to master.** Every other completion criterion lives in human attention and is therefore systematically missed. The evidence is concrete and recent: F4 Platform Console, C-47 transfer flow, ODS Twilio (both phases), Smart Import, and the What's-New redesign were all merged AND deployed — and none shipped with user-facing support docs (`docs/support/*.mdx`). This is not gradual drift; it is a binary failure of a declared completion bar. The completion criteria were stated; nothing enforced them.

The root cause is an incentive shape. "Code merged" is the easiest exit signal an LLM session has — the commit landed, the PR is green, so the session declares the feature shipped and stops. The remaining seven criteria (tests, dev docs, user docs, migration-applied-to-prod, deploy-verified, acceptance-verified, stakeholder-notified) are invisible to that signal. A memory rule ("remember to add docs") drifts under exactly the context pressure where it matters most — the end of a long build, when the session is most tired and most eager to call it done. Across many parallel sessions, social enforcement of a completion definition does not hold. It must become mechanical.

Misha's framing (2026-06-01): "intended but not finished" is a failure mode he treats as **binary, not gradual**. A feature is complete or it is not. The eight criteria are the definition of complete:

1. Code merged to master
2. Tests added (unit / integration / E2E as appropriate to the feature class)
3. Dev docs updated (ADR / architecture / runbook)
4. User docs updated (`docs/support/*.mdx` for any contractor-facing feature)
5. Migration applied (schema live on prod, not just in repo)
6. Vercel master deploy succeeded for the merged commit
7. Acceptance criteria explicitly verified (demonstrated by a test / smoke run / screenshot)
8. Stakeholder / team notified if relevant

## Decision

Ship a **two-layer mechanism**:

### Layer 1 — `completion-criteria-gate.sh` (Stop hook, block-mode default)

A Stop hook, wired immediately after `pr-health-snapshot-gate.sh` and before `session-wrap.sh refresh` in the Stop chain. It reads the last assistant message from `$TRANSCRIPT_PATH` (the agent-uneditable JSONL — the Gen-6 narrative-integrity property that makes Stop-hook scans non-bypassable by the agent's own edits) and:

1. **Trigger check.** Does the message DECLARE a feature shipped? The trigger is a curated phrase set (`feature (shipped|complete|live)`, `(shipped|deployed) to (master|production|prod)`, `live in production`, `Status: COMPLETED`, plus an operator-extensible `COMPLETION_GATE_EXTRA_TRIGGER`). No trigger → exit 0. The bare session-end `DONE:` marker is **deliberately NOT** a trigger — that is session-end-protocol's job, and firing on every session would make the gate noise rather than signal.
2. **Validation.** If triggered, require a `## Completion Criteria` section accounting for all eight criteria. Each criterion is satisfied EITHER by a check-off (`[x]` / ✓) carrying an evidence token (commit SHA, `#PR`, URL, `.mdx`/file path, `/route`, or an artifact keyword like `screenshot`/`smoke test`/`playwright`/`migration NNN`/`deploy green`) OR by an explicit `N/A` with a justification clause.
3. **Verdict.** All eight satisfied → allow. Section missing entirely, or ≥1 criterion unmet (missing / checked-without-evidence / no-verdict) → block in block-mode (the default), naming the unmet criteria and showing the required section template. Block routes through the shared `stop-hook-retry-guard.sh` (3-retry downgrade-to-warn loop-break); the failure signature is the sorted set of unmet keys, so fixing *some* criteria resets the retry counter (progress is recognized).

**Escape hatches** (modeled on `pr-health-snapshot-gate.sh`):
- `COMPLETION_GATE_DISABLE=1` — full suppression (harness-dev sessions, non-feature work).
- `COMPLETION_GATE_SKIP=user_docs,migration` — per-criterion skip; each skip is appended to `.claude/state/completion-gate-skips.log` with the session id + timestamp (an audit trail, mirroring F7's `[skip-docs:]` reason-logging — a skip is a recorded decision, not a silent bypass).
- Mode resolution: `COMPLETION_GATE_MODE` env > `~/.claude/local/completion-gate-mode` file > `block`.

### Layer 2 — `page-doc-accuracy-audit.sh` (forward-facing drift audit)

> **Amendment (2026-06-01, same day):** Part B was redesigned before it became load-bearing. The originally-merged Layer 2 (`feature-completion-audit.sh`) walked `docs/plans/**` for `Status: COMPLETED` items — a *backwards-facing* retrospective. Misha rejected that design: historical plans are messy and mostly don't reflect current useful state. Layer 2 is now a *forward-facing* page-vs-doc accuracy audit. The plan-walker is removed; both layers are now forward-facing (the gate at session-close, the audit on already-shipped pages).

A project-generic script (no project identifiers — it ships under `adapters/`, scanned by the hygiene gate) that, for every LIVE contractor-facing page (PageRegistry `owner: 'org'`), checks whether the page's support doc still accurately describes what the page actually does **now**. It is STATIC and best-effort (Misha: "start static; runtime is a future enhancement"):

- **STALE** (🔴, exit-blocking): a UI term the doc names (bold / short-quoted / "click X" prose) that appears **nowhere** in the project's `src/` tree — the doc references a removed/renamed button or section and is actively misleading contractors. High-precision *by design*: the broad `src/` search makes route→component mapping errors unable to cause a false STALE (the cost of a false STALE — telling the operator to "fix" a correct doc — is high).
- **UNDOCUMENTED** (🟡): a prominent page label (from the route's source closure: `page.tsx` + one-level imports + the `src/components/<feature>/` dir) the doc never mentions. Best-effort; conservative filters (multi-word / non-common-button).
- **MISSING_DOC** (⚪): a contractor-facing page with no doc at all.
- (**BEHAVIOR_MISMATCH** 🟠 — "click X to Y" where the code shows X does Z — deferred; too low-precision for a static v1.)

Platform/admin routes (audit log, platform console, impersonation logs) are skipped — they don't need contractor-facing docs. Output: `<project>/docs/audit/page-doc-accuracy-<date>.md` with an executive summary + per-page findings + cross-cutting notes. Run weekly (scheduled task) or on-demand. Exit 1 iff any STALE is found.

**The two layers are intentionally complementary, not redundant — and both forward-facing.** Part A catches incompleteness *at session-close, going forward*. Part B catches *drift on what is already shipped* — button renames that broke a doc, removed sections still described, features added without doc updates, pages shipped with no doc. Neither is retrospective. The gate favors false-negatives (a real shipment with unusual phrasing slips the phrase-trigger) precisely *because* the audit independently re-checks shipped pages against their docs.

## Alternatives Considered

- **Trigger on the bare `DONE:` marker (the literal reading of the brief).** Rejected. Per session-end-protocol, *every* successful turn ends with `DONE:`. Firing on it would demand a `## Completion Criteria` block on every harness-dev / investigation / docs / pure-refactor session — ceremony on work with no feature to ship. The curated feature-shipment trigger keeps the gate aimed at the actual failure pattern (features declared shipped), and the periodic audit absorbs any feature-shipment that phrases itself unusually.
- **PreToolUse gate on `gh pr merge` (block the merge until criteria met).** Rejected as the primary surface. Many of the eight criteria (deploy-verified, migration-applied-to-prod, stakeholder-notified) only become *true* AFTER the merge — gating the merge would force the session to fake them or to never satisfy them. The Stop surface is correct: it checks the criteria at the moment the session CLAIMS done, after the post-merge steps have had their chance to happen.
- **Warn-mode default (like F7's doc-gate).** Rejected. Misha's directive is explicit: "intended but not finished" is binary and the bar must be enforced, not advised. Block-mode is the default; the retry-guard prevents any deadlock, and the per-criterion `SKIP` + full `DISABLE` hatches handle legitimate exceptions with an audit trail.
- **A single mechanism (gate only, no audit).** Rejected. The brief itself names the residual risk: "sessions can theoretically skip-flag everything and slip through." The audit is the structural answer — it grounds verification in production state rather than the session's self-report, catching both honest misses and the skip-everything evasion.
- **Hardcode the audit to the downstream project.** Rejected on harness-hygiene grounds. The script ships in the kit (`adapters/`) and must carry no downstream-project identifiers. It is parameterized by `--project <path>` and keys off generic conventions (Next.js app-router `src/app/**/page.tsx`, a `src/lib/page-registry.ts` with `owner`/`doc_path` entries, `docs/support/*.mdx`); the per-machine default project path lives outside the kit.
- **Part B as a backwards-facing completed-plan walker (the originally-merged design).** Rejected by Misha on review (see the Layer 2 amendment). Walking `docs/plans/**` for `Status: COMPLETED` is retrospective, messy, and most historical plans don't reflect current useful state. The forward-facing page-vs-doc audit answers the question that actually matters — "does each live page's doc still describe what the page does now?" — and catches the drift class (renamed buttons, removed sections, undocumented new features) the plan-walker structurally could not.

## Consequences

**Enables.** The completion definition moves from social to mechanical. A session that declares a feature shipped cannot wrap without accounting for all eight criteria — done-with-evidence or justified-N/A. The audit catches what the gate misses, including already-shipped features (the baseline run surfaces the F4 / C-47 / Smart Import / What's-New user-doc gaps). The skip log and unresolved-stop-hooks log give a durable trail of every exception.

**Costs.** (a) The gate fires on every Stop, but the pre-trigger phrase check is cheap (`grep`) and most sessions don't match — only feature-shipment-declaring sessions pay the full validation. (b) Sessions that genuinely ship a feature now carry the one-time cost of writing an eight-line `## Completion Criteria` section; this is the intended cost — it is the artifact that makes completion auditable. (c) Harness-dev sessions that touch the gate itself must set `COMPLETION_GATE_DISABLE=1` (this very PR's session does), exactly as `PR_HEALTH_GATE_DISABLE=1` exists for the sibling gate. (d) The trigger's false-negative bias means a feature shipped with unusual phrasing is caught only by the audit, not the gate — accepted, because the audit is the backstop and a false-positive-on-every-session gate would be worse (operators disable noisy gates).

**Blocks.** Nothing structurally. The gate is wired in the template's Stop chain; it activates per-machine when `install.sh` syncs it into the live `~/.claude/settings.json`. The self-test is gh-free and node-free (presence check on the agent's own output), so it passes cold in CI and needs **no** `KNOWN_FAILING_HOOKS` entry.

**Refutation criterion (HYPOTHESIZED → to be confirmed by the baseline audit).** The hypothesis is "the named features shipped without user docs because no mechanism enforced criterion #4." It would be REFUTED if the baseline `feature-completion-audit.sh` run found that F4 / C-47 / Smart Import / What's-New each *do* have a `docs/support/*.mdx` — i.e., the gap was already closed and the failure pattern was misremembered. The baseline audit run is the evidence pass; its report records which criteria each feature actually missed.
