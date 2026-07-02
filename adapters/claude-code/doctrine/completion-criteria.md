# Feature-Completion Criteria — compact
> Enforcement: completion-criteria-gate.sh (Stop, block-mode — RELOCATING per D.4), page-doc-accuracy-audit.sh (forward-facing doc-drift audit). Full: none (compact only)
> Applies: any final message that DECLARES a feature shipped/deployed/live — never the bare session-end DONE: marker.

- "Shipped" means all EIGHT criteria, not just code-merged: `code` (merged, cite SHA), `tests` (added, cite path), `dev_docs` (ADR/architecture updated), `user_docs` (contractor-facing `.mdx` updated), `migration` (applied to prod, not just in repo), `deploy` (Vercel master deploy green), `acceptance` (verified — smoke test/screenshot/curl), `stakeholder` (support/platform team notified if relevant).
- When triggered, the final message needs a `## Completion Criteria` section: each of the 8 as `[x] <criterion> — <evidence: SHA/#PR/@handle/.mdx path/route/artifact keyword>` OR `N/A — <reason>`. A bare checkbox with no evidence FAILs; a bare N/A with no reason FAILs.
- Escape hatches: `COMPLETION_GATE_SKIP=<keys>` (per-criterion, audit-logged) and `COMPLETION_GATE_DISABLE=1` (harness-dev sessions editing the gate itself).
- **D.4 relocates this gate**: completion-criteria moves from a Stop-hook to `close-plan.sh` + the PR-merge path (also closes GAP-53's preview-deploy false-pass — a preview deploy is not a production deploy). Until D.4 lands, the Stop-hook form above is live.
- The companion forward-facing audit (`page-doc-accuracy-audit.sh`) checks every LIVE contractor-facing page against its support doc for drift (STALE/UNDOCUMENTED/MISSING_DOC) — catches the class this gate misses on already-shipped pages.
