# UX Standards for UI Development (src/components/** and src/app/**/page.tsx)

When building or modifying any UI component, follow:
- `~/.claude/docs/ux-guidelines.md` — detailed design guidelines
- `~/.claude/docs/ux-checklist.md` — 20-domain UX checklist (contrast, affordance, consistency, error prevention, accessibility, etc.)

Key rules enforced here:

## Color Rules
- **Red = error/critical ONLY.** Never use red for informational or "low but not broken" metrics. Use amber.
- **Purple = AI.** Every AI feature, badge, indicator, and sparkle icon uses purple. Consistently.
- **Semantic colors:** Blue=information, Green=success, Amber=warning, Red=critical, Purple=AI, Gray=inactive.
- **Color is never the only signal.** Always pair with text label, icon, or pattern.
- **Domain-specific colors** (e.g., state colors, category colors) should live in a central color module and be referenced consistently — never hardcode them inline.

## Visual Contrast (MANDATORY — All Modes)
Every UI element must be visually distinct against its background in ALL color modes. These are non-negotiable:

**Buttons:**
- Action buttons MUST have a filled background — not just a border and text color. Outline-only buttons lack contrast in both light and dark mode.
- Primary: filled with the action color (`bg-blue-600 text-white`). Secondary: `bg-gray-200 dark:bg-gray-700`. Destructive: `bg-red-600 text-white`. AI-specific actions (Preview, Generate, Suggest): `bg-purple-600 text-white`.
- **Purple is reserved for AI features only.** Do not use `bg-purple-600` for generic primary actions like Save, Create, Launch, Submit — use blue instead. Purple marks actions that involve AI generation or AI-driven behavior.
- Dashed "add more" buttons: `border-2` minimum weight with sufficient color contrast against the container.

**Borders:**
- Every border MUST have explicit light AND dark variants. Never write `border-gray-200` without also specifying `dark:border-gray-600`.
- Minimum visible border: `border-gray-300` (light) / `dark:border-gray-600` (dark). Anything fainter blends in.
- Left accent borders: use `-500` for light mode, `-400` for dark mode (`border-l-blue-500 dark:border-l-blue-400`).
- Section dividers: `border-gray-300 dark:border-gray-600` minimum — `border-gray-200` is invisible on light backgrounds too.

**Backgrounds:**
- Never use opacity for primary container backgrounds (`/20`, `/30`, `/50` become transparent or washed out). Use solid colors.
- Tinted backgrounds: light mode uses the `-50` shade; dark mode uses `-950` or custom hex barely off the base background.
- Accordion/list item headers: MUST have a filled background (`bg-gray-100 dark:bg-gray-800`), never transparent. Transparent headers blend into their container.

**Text:**
- Every text class MUST have an explicit `dark:` variant. Do not assume defaults are sufficient.
- `text-gray-500` is the minimum for secondary text on white. `dark:text-gray-400` is the minimum for secondary text on dark.
- `text-gray-600` without a dark variant is unreadable in dark mode. Always pair with `dark:text-gray-400` or brighter.

**Test mentally:** For EVERY element, ask: "Would I see this on a white background? Would I see this on a #111827 background?" If either answer is "barely" — fix the contrast.

## Every Number Needs Context
- KPI values must show a trend indicator (▲/▼ with %)
- Trend colored: green (improving), red (declining), gray (stable)
- Numbers representing lists must be clickable (link to the data behind them)
- Add tooltips explaining what the metric means and what "good" looks like

## Every Card Is Clickable
- Summary cards use `cursor-pointer hover:shadow-md` transition
- Clicking a card navigates to detail view (panel, modal, or page)
- No dead-end numbers — every metric links to its data

## State Handling (ALL states required)
For every async data display, implement ALL of:
- **Loading:** Skeleton placeholders matching layout shape + descriptive text ("Loading campaigns...")
- **Empty:** Icon + explanation + first action button ("No contacts yet." + [Import] [Add Contact])
- **Error:** Specific error + cause + recovery action ("Connection issue" + [Refresh])
- **Success:** Confirm what happened + next step ("Campaign scheduled — 847 contacts" + [View] [Create Another])

## AI Features
- AI-generated content: purple `✦` marker + "AI-generated" text (text-xs)
- AI content block: `border-l-2 border-purple-400 pl-3`
- AI decisions: show one-sentence human-readable reasoning (expandable for detail)
- AI suggestions: popup with editable preview — NEVER overwrite original text until user clicks Accept
- AI writing assist: sparkle icon (✦) in purple, positioned near the textarea

## Attention Hierarchy
- Most important element: `text-3xl font-bold` (one per page section)
- Dashboard: 1-2 hero cards (larger) + supporting grid (smaller, consistent)
- Primary action: purple primary button, one clear CTA per section
- White space around important elements — don't crowd

## Micro-Interactions
- Button press: `active:scale-[0.98]` (100ms)
- Card hover: `hover:shadow-md transition-shadow duration-150`
- Animations: 150-250ms (shorter = jarring, longer = laggy)
- AI thinking state: pulsing purple dot or shimmer, not a bare spinner

## Accessibility
- `button` for actions, `a` for navigation — never `div onClick`
- ARIA labels on icon-only buttons
- Keyboard navigation: tab, enter, escape for all interactive elements
- Focus rings visible
- Heading hierarchy: h1 → h2 → h3, no skipping

## Before Committing UI Changes
- Run the glance test: "Can someone understand this page in 3 seconds?"
- Verify every number has context (trend, comparison, explanation)
- Check all four states (loading, empty, error, success)
- Confirm AI features use purple consistently
- Check mobile responsiveness on key pages
