# Evidence — lessons-learned-fixes-2026-07-13

All tasks `Verification: mechanical` (harness-internal; acceptance-exempt). Each is
proven by its artifact's `--self-test` and/or a grep-verifiable on-disk change, cited
to the commit that landed it. Masters converged at `406bd8f` (origin == pt == local);
changes are live-synced to `~/.claude` (2 installed, 3 updated, 1 settings-entry merged).

---

## Task 1 — commit the source efficiency lesson — PASS
- commit: 2e99894
- The lesson `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md`
  was an untracked working-tree deliverable; now tracked in master history. `git log --oneline
  -- docs/lessons/2026-07-13-*.md` shows 2e99894.

## Task 2 — fix "Pending build" bullet in the 2026-07-11 lesson — PASS
- commit: 2e99894
- `docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md` no longer
  contains "(Pending build" (grep count 0); now cites the SHIPPED `concurrent-ownership-gate.sh`
  (19/19 self-test, live) + `broadcast-active-session.sh` extension (10/10). Verified honest per
  the L2-docstale + L2-broadcast audit agents (both ALREADY_DONE, adversarially confirmed).

## Task 3 — fix stale rules/→doctrine/ path pointers (FM-029, ADR-035, DECISIONS.md) — PASS
- commit: 2e99894
- `grep -cE '~/.claude/rules/(diagnosis|claims)\.md' docs/failure-modes.md
  docs/decisions/035-diagnostic-first-protocol.md` → 0 residual; new `~/.claude/doctrine/` refs
  present (3 + 4). Historical "landed at" records preserved. DECISIONS.md 035 row also corrected
  (decisions-index-gate consistency).

## Task 4 — cheap pre-filters on the two giant PreToolUse gates — PASS
- commit: 94b10a6 (pre-filters), 92a6894 (harness-review corrections: honesty comment + pinned self-test)
- `scope-enforcement-gate.sh --self-test` = 35 passed / 0 failed (of 34; scenario 34 pins the
  obfuscation residual). `plan-deletion-protection.sh --self-test` = 19 / 19 (scenario 19 pins it).
  Behavior preserved (baseline was 34/33 and 18/18). Fast-path proven: `ls -la` → exit 0;
  full-path proven: `rm docs/plans/…` → exit 1 (still blocks). Common non-matching path
  ~612→205 ms measured on scope-enforcement. Live copies carry the pre-filter (`_SCOPE_PF` present).

## Task 5 — non-blocking find-scan-warn.sh hook — PASS
- commit: 94b10a6 (hook + wiring), 92a6894 (F3 regex widening)
- `find-scan-warn.sh --self-test` = 18 passed / 0 failed (warns on `/`,`~`,`$HOME`,`${HOME}`,
  `"$HOME"`,`/c`,`/d`,`/mnt/d`,`/c/Users`; silent on `find .`,`find adapters/`,`/etc`,`/home/x`;
  always exit 0). Wired in `settings.json.template`, registered in `manifest.json`,
  `harness-architecture.md` regenerated. Live: present at `~/.claude/hooks/find-scan-warn.sh`,
  wired in `~/.claude/settings.json` (1).

## Task 6 — single-flight debounce on session-start-auto-install — PASS
- commit: c0ba4ca (lib + gate), 92a6894 (G1 fail-open find-guard)
- `lib/sessionstart-singleflight.sh --self-test` = 9 passed / 0 failed (acquire / skip-when-fresh /
  reclaim-when-stale / re-acquire / SSF_DISABLE bypass / fail-open-on-uncreatable-dir / N-racer
  mutual-exclusion). `session-start-auto-install.sh --self-test` = 15 / 15 with the gate present
  (bypassed via SSF_DISABLE). Integration proven end-to-end: run 1 syncs (0 skips), run 2 on the
  same LIVE_DIR SKIPS ("another session synced within ~2 min"). Live: `ss_singleflight` present in
  `~/.claude/hooks/session-start-auto-install.sh`.

## Task 7 — route Task 4 + Task 6 through harness-reviewer — PASS
- commit: 92a6894
- harness-reviewer verdict: **Change 2 (single-flight) = PASS**; **Change 1 (pre-filters) =
  REFORMULATE** for one honesty defect (the "strict SUPERSET / NEVER a false skip" overclaim,
  falsified for quote-obfuscated verbs). All findings addressed in 92a6894: F1 (comments corrected),
  F2 (residual pinned by plan-deletion S19 + scope-enforcement S34), F3 (find regex widened),
  G1 (fail-open find-guard), G2 (stamp-before-sync residual recorded in Decisions Log). All
  post-fix self-tests green (scope 35/35, plan-deletion 19/19, find-scan 18/18, single-flight 9/9).

## Task 8 — file deferred backlog rows + reconcile §8 bookkeeping — PASS
- commit: b228718
- `docs/backlog.md` gains `HOOK-SHIM-RETIRE-01` (rec 3) + `PRETOOLUSE-DISPATCHER-01` (rec 4) with
  deferral rationale, and `SESSIONSTART-SINGLEFLIGHT-01` annotated PARTIALLY LANDED. The efficiency
  lesson gains a §8b Disposition (recs 5/6 IMPLEMENTED, rec 2 partial, rec 1 operator-only, recs 3/4
  deferred, rec 7 obsolete). grep confirms all three IDs present.

---

## Whole-plan verification
- Closure-contract self-tests (all green): scope-enforcement 35/35, plan-deletion 19/19,
  find-scan-warn 18/18, sessionstart-singleflight 9/9, session-start-auto-install 15/15.
- Doctor regression: the specific checks this plan could affect are GREEN — template↔live
  wired-hook drift is empty (find-scan-warn now in both), and the new hook is consistent across
  manifest + disk + live wiring. The full `harness-doctor --quick` is the known-slow spawn-tax
  (the very subject of the efficiency lesson); its pre-existing ~28 reds (stale branches, ledger
  warns, untriaged nl-issues, monitor alerts — all present at SessionStart) are unrelated to this plan.
