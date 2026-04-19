# UX Design Checklist

Referenced by all UX testing agents. Every item applies to every page/component. Flag violations as findings with the category and severity noted.

---

## 1. Visual Contrast (P1 if violated)
- Action buttons: filled background, never outline-only
- Borders: explicit light AND dark variants. Minimum `border-gray-300` / `dark:border-gray-600`
- Accent borders: `-500` light / `-400` dark
- Backgrounds: solid, never opacity-based for primary containers
- Accordion/list headers: filled background, never transparent
- Text: every text class needs explicit `dark:` variant. `text-gray-600` without `dark:text-gray-400` is invisible
- **Test:** Would I see this on white? Would I see this on #111827?

## 2. Affordance — Do interactive things look interactive? (P1)
- Every `onClick` element has visual cues: underline, button styling, hover effect, cursor-pointer, or action icon
- Non-interactive elements never look clickable (no colored text that isn't a link, no hover effects on static content)
- Expandable sections have a visible chevron/expand icon
- Disabled elements show `opacity-50` + `cursor-not-allowed`
- Draggable items have visible drag handles

## 3. Consistency Across Pages (P1)
- Same action = same label everywhere ("Edit" not sometimes "Modify")
- Same button style for same action level across all pages
- Same date/time format everywhere
- Same number format everywhere (1,234 not sometimes 1234)
- Same card/modal structure for similar data
- Same status badge style for same status across pages

## 4. Feedback and Response Time (P1 if >1s with no feedback)
- Every button shows loading state while action is in-flight
- Operations >1s show a spinner; >5s show a progress indicator
- Successful mutations show a confirmation (toast, inline message, visual change)
- Optimistic updates for inline edits (toggle, status change)
- Buttons disable during action to prevent double-submit

## 5. Error Prevention (P1)
- `type="email"` for email, `type="tel"` for phone, `maxLength` for limits
- Date pickers instead of free-text date input
- Dropdowns instead of free-text where options are finite
- Inline validation (real-time as user types), not just on submission
- Smart defaults: fields pre-populated with sensible values
- Unsaved changes warning on navigation away from dirty forms
- Destructive actions have confirmation with specific consequences + reversibility info

## 6. Recognition Over Recall (P2)
- Reference fields (Select a contact, Choose a campaign) show enough context — not just a name
- Dropdown menus with >7 options have search/filter
- Wizard/multi-step flows show summary of previous steps
- Toolbar icons have text labels (not just icons) for infrequent actions
- Breadcrumbs for pages deeper than 2 levels

## 7. Power User Efficiency (P2)
- Tables support sorting by clicking column headers
- Bulk selection (checkbox column + bulk action bar) for list views
- Copy-to-clipboard on shareable data (IDs, links, phone numbers)
- Keyboard shortcut hints on frequently-used actions

## 8. Minimalist Design (P2)
- Each viewport has ≤7 distinct visual groups (sections/cards)
- No redundant information (same data shown multiple times without purpose)
- Secondary/advanced options behind disclosure ("Advanced" toggle)
- ≤2 primary CTA buttons per page section
- Labels don't restate what's already obvious from the placeholder/UI

## 9. In-Context Help (P1 for complex features)
- Settings fields have tooltip or description explaining what they do
- Complex features have first-use guidance or onboarding hint
- Placeholder text shows expected format ("(555) 123-4567" not just "Phone")
- Error messages include next step or "Learn more" link
- Empty states explain both WHAT the feature is and HOW to start

## 10. Touch Targets (P1 for mobile-used apps)
- Interactive elements ≥44px in both dimensions
- Adjacent interactive elements ≥8px apart
- No hover-only interactions without touch equivalent
- Dropdown menus fit within viewport on small screens

## 11. Information Density and Scanning (P2)
- Most important column is leftmost in tables
- Long text truncated with "show more" — never pushes layout
- Key-value pairs use consistent formatting (bold label, regular value)
- Lists use consistent alignment — values aligned, labels aligned

## 12. Progressive Disclosure (P2)
- Advanced options hidden behind disclosure toggle
- Forms with >8 fields grouped into collapsible sections
- Data-heavy pages show summaries first, detail on drill-down
- Modals show only what's needed for the immediate decision

## 13. Undo and Reversibility (P1 for destructive actions)
- Destructive actions (delete, disconnect) specify consequences + whether recoverable
- Successful destructive actions show "Undo" toast (10s timeout) when possible
- Critical data edits have version history or "revert to previous" option
- Bulk destructive actions have undo, not just "Are you sure?"

## 14. System Status Visibility (P2)
- Active filters show visible indicator + clear button
- Current page highlighted in sidebar navigation
- Background processes show status indicator (sync, AI processing)
- Stale data shows "Last updated" timestamp
- Multi-step processes show progress (Step 2 of 5)
- Unsaved changes shown via visual indicator (dot, asterisk, badge)

## 15. Color Blindness / Accessibility (P1)
- Red/green distinctions always have a non-color signal (icon, text, pattern)
- Charts use patterns or labels in addition to color
- Modals trap focus (Tab doesn't cycle to background)
- ARIA labels on icon-only buttons
- Focus rings visible on all interactive elements
- `prefers-reduced-motion` respected for animations

## 16. Typography Hierarchy (P2)
- Exactly one top-level heading per page
- Heading sizes decrease monotonically (h1 > h2 > h3)
- Body text ≥14px; labels/captions ≥12px
- Link text visually distinct from regular text

## 17. Whitespace (P2)
- Inter-section gaps > intra-section gaps (proximity principle)
- Form fields ≥16px vertical spacing
- Modal content ≥24px internal padding
- Interactive elements ≥8px apart

## 18. Cognitive Load (P1 for decision points)
- Decision points have all options explained in context
- Navigation menus ≤7±2 top-level items (or grouped)
- Error messages appear next to the field, not in a summary
- Dropdown options self-explanatory without external reference

## 19. Gestalt Grouping (P2)
- Related controls share a visual container (card, border, background)
- Similar elements look the same; different elements look different
- Form fields aligned to consistent grid
- Destructive and constructive buttons visually separated (different color + position)

## 20. Navigation Context (P2)
- Current page highlighted in sidebar
- Deep pages (>2 levels) have breadcrumbs
- Browser back button preserves state
- Modals close with Escape key
- Deep-linked URLs work when bookmarked/shared

## 21. Cross-Page Interactions (P1)
- **Abandoning a dirty form:** On EVERY page with a form or editable fields, simulate: enter data → click a sidebar link. Does a "Save or discard?" warning appear? If not, flag as P1.
- **Disabled buttons without explanation:** If a submit/action button is disabled, there MUST be visible text explaining what's missing. A disabled button with no explanation is a dead end — the user doesn't know what to do. Flag as P1.
- **Required field indicators:** Every required field must be marked (asterisk, "(required)" label, or similar). The user should know what's required BEFORE they try to submit, not after.

## 22. Reusable Component Coverage (P1)
- **Guards, banners, and modals must be used everywhere they apply.** If the codebase has an `UnsavedChangesGuard`, grep for all form pages and verify it's wired into each one. If a `UnhappyCustomerBanner` exists, verify it appears on every page it should.
- **Check for inconsistent protection:** If one form page has unsaved-changes protection but another doesn't, flag the unprotected page.
- To find reusable components: grep for components in `src/components/` that are only imported in 1-2 files but solve problems that exist on many pages.
