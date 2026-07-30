# Workstreams UI — full overview + walkthrough brief (2026-07-30)

Written at the operator's request: "I don't know where these rows are... I need you to
provide me full context I can review, perhaps a full overview + a walkthrough we can
discuss together." This file IS that context — self-contained, no references to ledger
row numbers or session shorthand. The underlying evidence lives in
docs/reviews/cockpit-ui-requirements-ledger.md (73 requirements, each live-verified),
but this brief stands alone.

---

## 1. What the UI is, in one paragraph

One registry, three views. **Roadmap** (the landing tab): every plan as a row —
`<Key><Task>` tokens matching chat exactly (`EST T6`, `SE1`), a task-span column
("T6 next" / "M6 running"), progress bar + fraction, exception chips only when something
needs attention, completed plans folded into a Shipped group, plans banded In-progress →
Upcoming → Shipped. **Requests**: every ask you've made, auto-captured, with its
evolution timeline. **Inbox (N)**: everything waiting on YOU, rendered with full context
(decision, options, outcomes), honest about errors — a broken source renders (!) never a
reassuring zero. Plus **Harness Health** (diagnostics + the new Machines section) and a
**Docs** browser.

## 2. What is DONE and verified live (the short version of 68 requirements)

- Chat↔UI correlation: plan keys + task ids on every row; the filter finds them
  (typing `T3` or `M4` reveals the matching task under its plan).
- Honest statuses: six-value enum (not-started / in-progress / running / complete /
  stalled+reason / unknown+reason); corrupt or unreadable inputs render `unknown(...)`,
  never a confident guess, never vanish; count badges distinguish number / zero / error.
- Recession over noise: completed = the only dim thing; no per-row project chips; no
  duplicate status text; exception column empty unless something needs you.
- Running visibility: live sessions attributed to tasks show "running" on the task AND
  roll up to a badge on the collapsed plan row.
- Multi-round regression protection: every requirement you have ever stated is a row in
  the requirements ledger with a live-verified status; every future acceptance pass
  re-checks ALL of it, not just the latest complaints.

## 3. IN FLIGHT right now (Round 16 — your six newest, verbatim-driven)

1. Tighten the awkward spacing between plans / nesting rails.
2. The plan-doc popup renders FORMATTED markdown (currently raw text).
3. Remove the buttons below plan-doc links (layout jump + unnecessary).
4. No plan-title editing anywhere.
5. Drag-and-drop reordering replaces the buttons (a non-visual keyboard path is kept so
   reordering stays accessible — the visible buttons are gone).
6. GREEN for running/in-progress; blue reserved exclusively for links.

## 4. OPEN — the decisions that are genuinely yours

### A. Multi-project roadmap (my #1 recommendation)
TODAY the Roadmap shows ONLY neural-lace. Your other project, Circuit
(/Users/misha/Claude/Circuit — the Docs browser already lists 836 of its files), never
appears, because the roadmap reads a machine-local config file
(`neural-lace/workstreams-ui/config/projects.json`) that was never created on this Mac.
The scanning mechanism exists and is tested — it is ONE config file away.
**Decision: list which project folders belong on your roadmap, and it happens.**

### B. The Machines panel (cross-machine view)
This Mac publishes its state every 60s. The panel stays honestly empty until the Windows
desktop publishes too. **SECOND CORRECTION (2026-07-30, supersedes the first — which was
itself wrong): the installer script HAS been on origin/master since 14568b2 (2026-07-17);
proven by `git cat-file -e origin/master:adapters/claude-code/scripts/install-coord-sync-task.ps1`
→ exit 0 after a fresh fetch. The first "correction" claimed the script was unmerged —
asserted without running that one-line check. The REAL failure, per the operator's own
screenshot: PowerShell was at `C:\Users\misha`, outside the repo, so the relative `-File`
path had nothing to resolve against.** The corrected ask (cd into the repo → git pull →
run, each step its own fenced block) is re-issued in the Inbox and is actionable NOW —
no merge required.

### C. The propose/accept flow — the ONE thing you asked for that was never built
From your Round 4 sit-down (2026-07-17/18): work items sourced from meetings/suggestions
should arrive as PROPOSALS — you accept / modify / partially accept / reject them BEFORE
they become real roadmap work. It was deliberately deferred to a separate plan
("Circuit P1") and has sat unbuilt since. The Inbox + Requests views absorbed some of
this need. **Decision: still wanted (it becomes a real plan), or retire it (recorded as
your call, not silently dropped)?**

### D. Your walkthrough
After Round 16 lands (hours), one cold walkthrough by you closes the redesign plan's
final task. Everything else in that plan is done and machine-verified.

## 5. Retired at YOUR OWN direction (listed so nothing dies silently)

- The "phases" framing (Round 11: "labeling each item as phases is misleading").
- Per-item project chips (Round 12: "redundant considering they're all underneath the
  NL node").
- The old master-plan aggregate rendering (superseded by the parent-plan mechanism).

## 6. The honest caveats

- "Zero regressions" is true as of the FIRST full-ledger audit (this week). Earlier
  rounds regressed things precisely because no such audit existed; the ledger is now the
  standing checklist that keeps the number meaningful.
- Task-level "running" depends on dispatches carrying the attribution header; adoption
  is growing but historical sessions show as "unattributed" in the banner.
- The Requests tab has an untriaged 401-OAuth item visible — identified as some
  session's failed-auth request record; on the triage list, not yet diagnosed.

## 7. The walkthrough — REFRAMED per the operator (2026-07-30)

The operator's words: "The purpose of the walkthrough is not for you to show me what's
there; it's to review everything I've requested over the last couple months and see how
much of it is still not there, and allow me to decide how much I truly want every item
I've asked for in the past. There's a lot I've asked for that has regressed."

So the walkthrough is an AUDIT SITTING, not a demo tour. Format:
1. The instrument is the requirements ledger (docs/reviews/cockpit-ui-requirements-ledger.md,
   all 77 rows) presented row by row IN CHAT with full content — never row numbers alone.
2. Order: REGRESSED and rebuild-losses first, then PARTIAL/UNBUILT, then SUPERSEDED
   (confirm each really was the operator's own direction), then spot-check the METs live.
3. Per row the operator gives one of: KEEP (stays binding, gets rebuilt if not live) /
   DROP (retired at operator direction, recorded like the phases row) / CHANGE (new
   verbatim recorded as a new row).
4. The rebuild history gets its own honest section: the 3-4 unrequested full rebuilds,
   what each one silently lost, and which losses are now restored vs still missing.
5. Output: an updated ledger where every row carries an operator disposition — THAT
   closes the redesign plan's final task, not a tour.
