---
title: Workstreams tree — design misread (kind-grouping) + repo top-tier added
date: 2026-06-03
type: architectural-learning
status: decided
auto_applied: true
originating_context: GUI fix session for the flat-list Workstreams tree; Misha corrected the design intent twice
decision_needed: n/a — decided with Misha in-session
predicted_downstream:
  - neural-lace/workstreams-ui/web/app.js
  - neural-lace/workstreams-ui/web/app.css
  - neural-lace/workstreams-ui/scripts/regression.e2e.js
  - workstreams-design-v2-2026-05-30.md
---

## What was discovered

1. **Design misread.** The tree rendered as a flat list. My first fix grouped items
   by `kind` (Decisions/Questions/Actions). That is WRONG: design-v2 §1 says the
   hierarchy is **Project → Workstream → WorkItem → Sub-task**, and Decision/
   Question/Action are *cross-cutting kinds that attach at any tier* — a per-item
   badge, never a nesting axis. Shipped the wrong version to both masters before
   Misha corrected it.

2. **Repo top-tier (new requirement).** Misha added a tier above projects: group
   projects by their owning GitHub repo. The state data has **no `repo` field and
   no `tier:workstream` nodes** (node keys: bound_sessions, cross_links, draft, id,
   items, node_id, opened_at, parent_id, state, title, tree_id). So the hierarchy
   had to be derived, not read.

3. **Project→repo mapping must be derived, not guessed.** My hand-typed guess put
   cortex-one/foresight under Pocket Technician — WRONG. Ground truth (`gh repo list`
   per account + local `<home>\dev\<account>\` folders): cortex-one + foresight
   are mishanovini-only (Personal); Circuit is Pocket-Technician-only; neural-lace is
   in BOTH. The empty "Personal"/"Pocket Technician" 0-item nodes are account names,
   not projects.

4. **GUI-served-from-volatile-working-tree fragility (process failure).** The GUI
   server serves `web/app.js` from whatever branch the shared working tree is on. A
   concurrent session switched the tree to `feat/component-c-cross-machine-sync`
   (which lacked my fix), so "shipped to master + verified in a fresh headless
   browser" did NOT equal "what Misha's live GUI serves." Verified against a
   transient working-tree state instead of the live server's served bytes — twice.

## Why it matters

Two wrong ships to master + a design built on a misread = lost trust and rework.
The root causes are durable lessons: (a) re-read the design doc before building a
structure; (b) derive identity/ownership mappings from real sources (git remotes,
folders), never hand-type; (c) verify against the actual running server's served
bytes, not the working tree the editor sees.

## Decision (with Misha, 2026-06-03)

- Hierarchy: **Repo → Project → Workstream → WorkItem** (kinds are per-item badges).
- Repo tier: **Pocket Technician** (Circuit), **Personal** (cortex-one, foresight),
  **Shared** (neural-lace — dual-remoted, its own group per Misha).
- Workstream tier: **derived by logical theme** from item text (best-guess backfill
  Misha approved) until real `tier:workstream` nodes exist. Override hooks:
  node-level `repo` field and a served `S.repoMap`.
- Revert the wrong kind-grouping from both masters; ship the corrected renderer;
  rewrite the regression test to assert the 4-tier geometry against the live server.

## Implementation log

- neural-lace/workstreams-ui/web/app.js — repo tier + reposOf + derived workstreams (renderDerivedWorkstreams)
- neural-lace/workstreams-ui/web/app.css — .repo-group / .tree-kids guide-rail nesting
- neural-lace/workstreams-ui/scripts/regression.e2e.js — repo→project→workstream geometry test (replaces the kind-grouping bug#9)
- (verified live: repo x=10 → project=38 → workstream=66 → item=95; screenshot diag-workstreams.png)
