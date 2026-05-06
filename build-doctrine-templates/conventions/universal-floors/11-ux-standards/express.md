# Floor 11 — UX standards (UI projects only) — Express

Default: **color rules** (red = error/critical only, never informational; purple = AI features only). **Filled buttons** with explicit `dark:` variants (no outline-only buttons). **Every async data fetch handles loading + error + empty + success states**. **WCAG 2.1 AA** for customer-facing views.

- Color: never red for informational; never red for "low-but-not-broken" metrics (use amber).
- Buttons: filled, not outlines. Both light AND dark variants explicit on every text/border class.
- All four states for async data: loading skeleton + descriptive text, error with recovery action, empty with first-action, success with next-step.
- Accessibility: `button` for actions, `a` for nav, ARIA labels on icon-only buttons, keyboard-navigable, focus rings visible.

Skip this floor entirely for non-UI projects with rationale recorded in `.bootstrap/state.yaml`.
