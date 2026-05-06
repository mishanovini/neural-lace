# Floor 11 — UX standards (UI projects only) — Standard

## Default
Color rules: red = error/critical only; purple = AI; semantic colors elsewhere (blue=info, green=success, amber=warning, gray=inactive). Filled buttons with explicit `dark:` variants. Every async data fetch handles loading + error + empty + success states. WCAG 2.1 AA for customer-facing views. Every number has context (trend, comparison, explanation). Every card is clickable to its detail.

## Seven baseline UX principles
1. Errors suggest a solution.
2. Suggestions link directly to action.
3. Empty states explain why and offer a first action.
4. Destructive actions require confirmation with reversibility info.
5. Success states confirm what happened and reveal what is next.
6. Loading states describe what is loading (not bare spinners).
7. Warnings by color: yellow = informational/fixable, red = blocking/data-risk; never red for informational.

## Alternatives
- **Custom design language** (Material, Apple HIG, Fluent) — adopt the framework's rules wholesale; the seven baseline principles still apply on top.
- **No dark mode** — acceptable for early-stage internal tools; ship dark mode before public launch.
- **Custom color palette** — fine; map the semantic roles (primary, success, warning, error, AI) to your palette and audit consistency.

## When to deviate
- Embedded / kiosk UIs with no general-public users may relax accessibility; never accessibility-zero.
- Brand-driven visual systems (consumer-facing) often override the AI=purple rule; pick one consistent AI marker (sparkle icon, label, etc.).

## Cross-references
- Harness implementation: `~/.claude/rules/ux-design.md` (seven principles), `~/.claude/rules/ux-standards.md` (color/contrast/affordance/interaction depth).
- `~/.claude/agents/ux-designer.md` — mandatory plan-time review for new UI surfaces.
- `~/.claude/agents/ux-end-user-tester.md`, `~/.claude/agents/domain-expert-tester.md`, `~/.claude/agents/audience-content-reviewer.md` — post-build review trio.
