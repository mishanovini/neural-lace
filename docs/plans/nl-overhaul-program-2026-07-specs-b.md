# Wave B specs — exact per-task build specs (appendix to nl-overhaul-program-2026-07.md)
Status: REFERENCE (spec appendix, not an independent plan — task B.0 deliverable)
prd-ref: n/a — harness-development

Builder contract (applies to every task): you work on a worker branch cut from `claude/modest-satoshi-150d97` (first action: `git checkout -b worker-<task-id> claude/modest-satoshi-150d97`). Read the master plan section for your task + this appendix section. Edit ONLY the files your section names (plus new files it names). Run your Done-when assertions before committing. Commit on your worker branch with message `overhaul(B.<n>): <summary>`. Do NOT invoke task-verifier, do NOT edit the plan file, do NOT edit `settings.json.template` (B.6 owns wiring), do NOT touch `~/.claude/` (live mirror is install-only). Return: verdict, commit SHAs, ≤5-sentence summary, blockers.

## §B.1 harness-doctor.sh

New file `adapters/claude-code/hooks/harness-doctor.sh` (bash, no hard jq dependency — degrade with a warning; node allowed only with graceful absence handling). Modes:
- `--quick` (default): run checks 1–6 below against the LIVE mirror (`$HOME/.claude`) and the repo (resolve repo root via `git -C "$(dirname "$0")" rev-parse --show-toplevel` falling back to `$NL_REPO_ROOT`). Never runs self-tests. Exit 0 iff zero RED lines.
- `--full`: quick + check 7 (self-test sweep). Exit 0 iff zero RED.
- `--self-test`: fixture suite in `mktemp -d` sandboxes (set `HARNESS_SELFTEST=1`); one RED-producing fixture AND one GREEN fixture per check class; exit 0 iff all scenarios behave.
Output format: `[doctor] RED <check-id>: <one-line detail>` / final `[doctor] GREEN — <n> checks passed` ; `[doctor] WARN <check-id>: ...` for non-blocking.

Checks (v1 — manifest arrives in C.1; v1 embeds its data inline):
1. `wiring-resolves`: every `*.sh` basename referenced in live `settings.json` hooks AND in `adapters/claude-code/settings.json.template` exists under `~/.claude/hooks/` (or `~/.claude/scripts/`) and is readable. RED per missing.
2. `lib-deps`: for every live hook, each `source`/`.`-included path under `lib/` resolves. RED per missing target (the audit's `workstreams-state-resolver.sh` case).
3. `legacy-paths`: `grep -rl "claude-projects/neural-lace" ~/.claude/hooks ~/.claude/scripts` must be empty. RED per file.
4. `template-live-drift`: the sorted basename set of hooks wired in live settings vs template must be equal; RED listing each side's extras.
5. `claim-honesty`: embedded checklist (v1): each of `customer-facing-review-gate.sh`, `worktree-teardown-gate.sh`, `session-start-worktree-advisor.sh`, `stalled-work-surfacer.sh`, `workstreams-turn-emit.sh` must be EITHER wired in live settings OR its rule file must contain the string `pending Wave` (the honest-status marker B.5 adds). RED per violation.
6. `byte-budget`: `cat ~/.claude/rules/*.md | wc -c` vs threshold from `~/.claude/local/doctor-budget` (default if absent: 1000000 = warn-only era; C.5 lowers to 30000). Over → RED (or WARN in the default era).
7. `selftest-sweep` (--full only): for every live hook containing `--self-test`, run `HARNESS_SELFTEST=1 timeout 120 bash <hook> --self-test </dev/null`; RED per non-zero exit, listing hook + exit code + last line.

Done-when: `bash adapters/claude-code/hooks/harness-doctor.sh --self-test` exits 0 with ≥7 scenario pairs (one red + one green fixture per check 1–6, plus a --full fixture exercising check 7 against a stub hook).

## §B.2 legacy-path family + nl-paths resolver

New file `adapters/claude-code/hooks/lib/nl-paths.sh` exposing `nl_repo_root()`: echo first hit of (1) `$NL_REPO_ROOT` if dir, (2) content of `~/.claude/local/nl-repo-path` if dir (single line, absolute path), (3) `git -C "${BASH_SOURCE%/*}" rev-parse --show-toplevel` when inside the repo, (4) probe list: `"$HOME/claude-projects/neural-lace"` (machine-specific checkouts come from tiers 1-2, never hardcoded). Also `nl_workstreams_ui()` = `<root>/neural-lace/workstreams-ui`. Node twin: same resolution order inside `adapters/claude-code/hooks/lib/workstreams-task-bridge.js` (env → config file → probe list) replacing its hardcoded `claude-projects` path (the audit's 213-failures-in-a-month defect).
Known offender files (fix these, then grep for stragglers): `hooks/goal-coverage-on-stop.sh`, `hooks/goal-extraction-on-prompt.sh`, `hooks/imperative-evidence-linker.sh` (fixture-dir fallbacks), `hooks/lib/workstreams-task-bridge.js`. Fixture fallbacks become: repo `adapters/claude-code/tests/<suite>` via `nl_repo_root`, THEN `~/.claude/tests/<suite>` (B.3 installs them).
Done-when: `grep -rl "claude-projects/neural-lace" adapters/claude-code/hooks adapters/claude-code/scripts` empty; `bash adapters/claude-code/hooks/workstreams-task-binding.sh --self-test` exits 0; `node -e 'require("./adapters/claude-code/hooks/lib/workstreams-task-bridge.js")'` does not throw module-not-found (or equivalent smoke per the bridge's export shape).

## §B.3 install completeness

Edit `install.sh` only. Add to its copy steps (mirroring existing conventions): `adapters/claude-code/hooks/lib/` → `~/.claude/hooks/lib/` (FULL dir, currently partial); `adapters/claude-code/tests/` → `~/.claude/tests/`; `adapters/claude-code/patterns/` → `~/.claude/patterns/`; `adapters/claude-code/examples/` → `~/.claude/examples/`. Additionally: write the resolved repo root to `~/.claude/local/nl-repo-path` (create `local/` if missing; NEVER overwrite other local files). Add `--verify` flag: after copying, run `~/.claude/hooks/harness-doctor.sh --quick` and propagate its exit code (skip gracefully with a warning if doctor not yet present). Preserve idempotency + the `.example`-suffix rule for user-editable files.
Done-when (temp-HOME test): `HOME=$(mktemp -d) bash install.sh` (adapt to install.sh's actual interface after reading it) then from that HOME: the four self-tests `goal-coverage-on-stop.sh`, `goal-extraction-on-prompt.sh`, `imperative-evidence-linker.sh`, `decision-context-gate.sh` all exit 0, and `~/.claude/patterns/harness-denylist.txt` exists.

## §B.4 junk + dead-ref sweep (hook files only)

1. `git mv` these six to `adapters/claude-code/attic/` (create dir with a README.md line: "retired hooks, kept one release; see ADR 058"): `hooks/conversation-tree-emit.sh`, `hooks/conversation-tree-read.sh`, `hooks/conversation-tree-state-gate.sh`, `hooks/conversation-tree-stop-gate.sh`, `hooks/conversation-tree-extract-pending.sh`, `hooks/conv-tree-emit-reconciler.sh` (all are 3–7-line rename shims past their 2026-06-30 delete-by date; wired nowhere).
2. Delete stray state files under `adapters/claude-code/hooks/.claude/` (self-test cwd pollution).
3. `hooks/completion-criteria-gate.sh` header (~line 29): `feature-completion-audit.sh` → `page-doc-accuracy-audit.sh`.
4. `hooks/workstreams-emit-reconciler.sh` (~line 68): remove the dead fallback to `conversation-tree-emit.sh` (target now in attic; the primary `workstreams-emit.sh` always exists).
Done-when: `ls adapters/claude-code/hooks/conversation-tree-*.sh adapters/claude-code/hooks/conv-tree-*.sh 2>/dev/null | wc -l` = 0; `grep -rn "feature-completion-audit" adapters/claude-code/hooks | grep -v attic` empty; `grep -n "conversation-tree-emit.sh" adapters/claude-code/hooks/workstreams-emit-reconciler.sh` empty; `bash adapters/claude-code/hooks/workstreams-emit-reconciler.sh --self-test` still exits 0 if it has a self-test.

## §B.5 doc truth sweep (rules/docs only — no hook edits)

Each item: file → change → assertion. All under `adapters/claude-code/rules/` unless noted.
1. `git-discipline.md` — force-push "Enforcement gap (honest)" paragraph + enforcement-table "gap" rows: rewrite to state the LIVE inline PreToolUse blocker exists (settings.json inline matcher blocks `push --force|-f|--force-with-lease` and `--no-verify`); keep the PostMerge-sync gap honest. Assertion: `grep -c "not yet implemented" git-discipline.md` = 0.
2. `INDEX.md` — git-discipline row "(Pattern, no current hook)" → "(inline PreToolUse blocker live)"; completion-criteria row `feature-completion-audit.sh` → `page-doc-accuracy-audit.sh`. Assertions: `grep -c "no current hook" INDEX.md` = 0; `grep -c "feature-completion-audit" INDEX.md` = 0.
3. `harness-hygiene.md` — "/harness-review … (planned — not yet implemented)" → exists (skills/harness-review.md). Assertion: `grep -c "not yet implemented" harness-hygiene.md` = 0.
4. `automation-modes.md` — replace hardcoded inventory counts ("26 hooks", "17 rules", "16 agents", "5 skills") with a pointer to `docs/harness-architecture.md` (no numbers). Assertion: `grep -c "26 hooks" automation-modes.md` = 0.
5. Stale "landing in Phase 1d-*" (all landed 2026-05): `prd-validity.md`, `spec-freeze.md`, `vaporware-prevention.md`, `findings-ledger.md`, `definition-on-first-use.md`, `design-mode-planning.md` → change to "landed". Assertion: `grep -rlc "landing in Phase 1d" adapters/claude-code/rules/` empty.
6. `decision-context.md` — all `neural-lace/conversation-tree-ui/…` paths → `neural-lace/workstreams-ui/…`. Merge the still-relevant content of `conv-tree-orchestrator-emit.md` into `workstreams-state.md` (a short "auto-emit layers" subsection; drop the 12 stale pre-rename script names), delete `conv-tree-orchestrator-emit.md`, remove its INDEX row. Assertions: `grep -rl "conversation-tree-ui/" adapters/claude-code/rules` empty; file absent; `grep -c "conv-tree-orchestrator-emit" adapters/claude-code/rules/INDEX.md` = 0.
7. `adapters/claude-code/CLAUDE.md` — trim to ≤200 lines by converting the longest inline blocks to one-line pointers (the real ≤100 rewrite is C.3; keep content-lossless via pointers). Assertion: `wc -l < adapters/claude-code/CLAUDE.md` ≤ 200.
8. Honesty markers for not-yet-live Mechanisms (doctor check 5 depends on the exact string `pending Wave`): `session-end-protocol.md` + `CLAUDE.md` (continuation-enforcer → "pending Wave D session-honesty-gate"); `worktree-isolation.md` (both hooks → "wired in template; live wiring pending Wave B.6 install"); `background-work-tracking.md` (stalled-work-surfacer → same); `customer-facing-review.md` (→ "pending Wave B.6 install; slated for Wave D relocation per ADR 058"); `workstreams-state.md` (turn-emit → "pending Wave D disposition"). Assertions: `grep -c "enforced by .continuation-enforcer" session-end-protocol.md` = 0; `grep -l "pending Wave" <each of the five files>` non-empty.
Done-when: every assertion above passes; `bash evals/golden/rules-index-coverage.sh` still exits 0.

## §B.6 wiring reconciliation (SERIAL — orchestrator-supervised, after B.1–B.5 cherry-picked)

1. `git tag pre-wave-b-cutover`.
2. Back up live settings: `cp ~/.claude/settings.json ~/.claude/settings.json.bak-waveb`.
3. Reconcile live `settings.json`'s `hooks` object to the template's (preserve every non-hooks key: permissions, env, model, etc.). Method: node JSON merge, not hand edit.
4. Run `install.sh` (now B.3-complete) to sync all files; verify `~/.claude/hooks/lib/workstreams-state-resolver.sh` now present.
5. `bash ~/.claude/hooks/harness-doctor.sh --quick` → must exit 0. If RED: fix the named defect (this is the point of the task), re-run.
Done-when: doctor --quick exit 0; backup file exists; tag exists.

## §B.7 main-checkout surgery (SERIAL — orchestrator-supervised; exact script, review diff before step 5)

At the MAIN checkout (path per ~/.claude/local/nl-repo-path): (1) record `git log --oneline origin/master..master` and `git diff --cached --stat > /tmp-audit`; (2) `git checkout -b backup/gap-51-staged-batch-20260702 && git commit -m "backup: GAP-51 staged batch (unaudited, preserved)"`; (3) `git cherry origin/master backup/gap-51-staged-batch-20260702` — for any `+` commit whose content is NOT on origin, note it in the B.7 report (content rescue decided by orchestrator); (4) `git checkout master`; (5) AFTER orchestrator diff review: `git reset --hard origin/master`; (6) assert: status clean, `git rev-list --count master..origin/master` = 0, backup branch exists, `grep -c "FM-03" docs/failure-modes.md` ≥ 3.

## §B.8 remotes/account fix (batch 2)

Diagnose: `git remote -v` (both checkouts); `gh auth status`; `gh repo view <origin-owner>/<repo>` under each account (`gh auth switch -u <user>`). Fix = whichever of: remote URL update, account mapping in `~/.claude/local/accounts.config.json` (requires /grant-local-edit), or documented manual step. Done-when: `git fetch origin && git fetch personal` exit 0 from the main checkout.

## §B.9 backlog markers (batch 2, haiku)

In `docs/backlog.md`: append ` **(absorbed by docs/plans/nl-overhaul-program-2026-07.md — <task>)**` to the entries for: GAP-20, GAP-21, GAP-22 (→ program governance F.1), the P0 synthetic-session-runner (→ E.4), waiver-density alarm (→ E.3), continuation-enforcer wiring (→ D.3), GAP-52 (→ B.3), GAP-53 (→ D.4), tool-call-budget --ack/HMAC (→ D.6 retirement), GAP-42 (→ E.4 CI substrate). Mark GAP-19 and HARNESS-HYGIENE-STALE-PLANS-01 closed with one-line evidence. Refresh the `Last updated` line. Done-when: `grep -c "absorbed by docs/plans/nl-overhaul-program-2026-07.md" docs/backlog.md` ≥ 10; per-ID greps pass.

## §B.10 baseline snapshot (batch 2, haiku)

Write `docs/reviews/nl-overhaul-baseline-2026-07.md` with current values + exact reproduction commands for: (1) retry-guard downgrade entries (`wc -l` of unresolved-stop-hooks.log at main checkout), (2) acceptance waiver files count (project state), (3) external-monitor alert count + acked count, (4) `cat ~/.claude/rules/*.md | wc -c`, (5) live Stop-chain entry count (node one-liner on settings.json), (6) live blocking-gate count (doctor output once B.6 lands — else note pending). Done-when: file exists; all six sections have a number + command.

## §B.11 estate freeze — verification record

Performed inline 2026-07-02 by the orchestrator (see master plan Decisions Log). Done-when: `grep -c "^frozen: true" docs/plans/orchestrator-prime.md` = 1; same for `docs/plans/workstreams-completed-filter-fix-2026-06-17.md`.

## Dispatch map

Batch 1 (parallel, ≤5): B.1 sonnet · B.2 sonnet · B.3 sonnet · B.4 haiku · B.5 haiku — file-disjoint by construction.
Batch 2 (after batch-1 cherry-pick + verify): B.6 serial supervised · B.7 serial supervised · B.8 sonnet · B.9 haiku · B.10 haiku.
