# UX Guidelines

> **Status:** Active  
> **Audience:** Developers, Claude Code, designers building user interfaces  
> **Enforcement:** Loaded as a Claude Code rule (`.claude/rules/ux-standards.md`) when editing components or pages.

---

## Context

These guidelines were originally developed for a business SaaS product aimed at non-technical office workers and small-business owners. The principles apply broadly to any consumer-focused or SMB-focused product where users are busy, non-technical, and judging software by "can I find what I need in 3 seconds?"

Individual projects should tailor the "who we're designing for" section to their specific audience.

## Who We're Designing For (example)

### Primary: Non-technical end user
- Learned previous software through repetition, not documentation.
- Busy — multiple tabs open, constant interruptions.
- Glances at the product between tasks. Rarely sits and studies a page.
- Judges software by "can I find what I need in 3 seconds?"
- Distrusts things they don't understand — "AI" can feel like a black box.

### Secondary: Business owner / decision maker
- Cares about business impact, not features.
- Checks the dashboard once a day, maybe less.
- Wants trends going up and red flags going down.
- Makes decisions based on gut + data. Needs both.

**The glance test:** Every screen must be understandable — what it's telling you and what to do next — within 3-5 seconds.

---

## Principles

### 1. Every number tells a story

Raw numbers are meaningless without context.

| Wrong | Right |
|-------|-------|
| "147 messages sent" | "147 messages sent (▲ 12% from last month)" |
| "41% response rate" | "41% response rate — industry average is 22%" |
| "38 appointments" | "38 appointments booked by AI this month" |

**Requirements:**
- Every KPI card shows: value, trend indicator (▲/▼ with %), comparison period
- Trend color: green for improving, red for declining, gray for stable
- Tooltips on metrics explaining what they mean and what "good" looks like
- Numbers that represent lists are clickable → drill into the data behind them

### 2. Color is information, not decoration

Never use color purely for aesthetics. Every color communicates meaning.

#### Semantic Color System

| Color | Meaning | Use For |
|-------|---------|---------|
| **Blue** | Information, acquisition, neutral action | New leads, informational badges, links, secondary buttons |
| **Green** | Success, improvement, active/healthy | Positive trends, active states, confirmations, "good" metrics |
| **Amber/Yellow** | Warning, attention needed, in-progress | Declining metrics, contacts going cold, pending actions |
| **Red** | Critical, error, blocking | Failed messages, opt-outs, system errors, urgent alerts |
| **Purple** | AI, intelligence, premium | AI-generated content, AI Insights, smart features, retention |
| **Gray** | Inactive, disabled, secondary | Terminal states, disabled controls, secondary text |

**Rules:**
- **Red is never informational.** Red = "something is wrong." Low-but-not-broken metrics use amber.
- **Purple = AI everywhere.** Every AI feature, badge, and indicator uses purple. Users learn: purple means "the AI did something smart here."
- **Color is never the only signal.** Always pair with text, icon, or pattern (accessibility).
- **Domain-specific colors** (e.g., funnel state colors, status colors) should live in a central color file and be referenced consistently across the app.

#### Trend Colors
- **Improving:** `text-green-600 dark:text-green-400`
- **Declining:** `text-red-600 dark:text-red-400`
- **Stable:** `text-gray-500 dark:text-gray-400`

### 3. Progressive disclosure — show less, reveal more

Don't dump everything on screen. Show the summary, let users drill in.

**The three-level hierarchy:**
```
Level 1 (Card):    "38 appointments booked (▲ 7%)"
                   [Click card or "View details →"]
                   
Level 2 (Detail):  Table showing all 38 — who, when, how booked
                   [Click any row]
                   
Level 3 (Action):  Individual contact with full history
                   [Take action: reschedule, message, reassign]
```

**Requirements:**
- Every summary card is clickable to a detail view
- Numbers that represent lists link to those lists
- Detail views use slide-out panels or modals (not full page navigation) to preserve context
- Expandable sections for dense information (collapse by default)
- Breadcrumbs or back arrows — user never feels lost

### 4. Attention hierarchy — guide the eye

On any page, the eye follows this path:
1. **What's the headline?** (largest, boldest)
2. **What needs my attention?** (color-highlighted alerts or changes)
3. **What can I do?** (clear primary action button)
4. **What are the details?** (tables, lists, secondary info)

**Tools for attention:**
- **Size**: Most important = `text-3xl font-bold`. Secondary = `text-xl`. Detail = `text-sm`
- **Weight**: Bold for values, medium for labels, regular for descriptions
- **Color**: Purple for primary CTAs, semantic colors for status, gray for secondary
- **Position**: Top-left reads first. Most important thing goes there.
- **White space**: Important things have breathing room. Crowded = unimportant.
- **Motion**: Elements that just updated animate briefly to draw the eye

**Anti-pattern: The wall of equal cards.** If everything looks the same, nothing stands out. Dashboards have 1-2 "hero" cards (larger, prominent) and supporting cards (grid).

### 5. Make the AI feel like a team member, not a machine

**Visual markers:**
- AI-generated content gets a small purple `✦ AI` badge — visible but not screaming
- AI decisions show one-sentence reasoning. Expandable for detail.
- AI changes show before/after (e.g., old strategy → new strategy with improvement %)

**Transparency:**
- "AI booked this for Tuesday morning because their history shows they respond best before noon"
- Use first person: "I noticed this contact responds better to mornings" (not "Analysis indicates...")

**Human control:**
- Every AI action has a visible Edit or Override option
- Every AI suggestion shows [Accept] / [Edit] / [Dismiss]
- The user is never locked out of AI decisions

**Purple = AI vocabulary:**
- AI Insights sidebar icon: purple
- AI status badge on contacts: purple
- AI writing assist sparkle icon: purple
- AI-generated message indicator: purple left border
- Self-learning insight cards: purple accent

### 6. Every dead end is a failure

No page should leave the user wondering "now what?"

| State | What to show |
|-------|-------------|
| **Empty list** | Icon + explanation + first action. "No contacts yet. Import your first contacts or add one manually." + [Import] [Add Contact] |
| **Error** | Specific error + likely cause + action. "Couldn't load campaigns — connection issue. Try refreshing." + [Refresh] |
| **Success** | Confirm what happened + what's next. "Campaign scheduled for May 15 — 847 contacts will receive it." + [View Campaign] [Create Another] |
| **Loading** | Describe what's loading + skeleton matching layout shape. "Loading AI insights for this month..." |
| **Zero results** | Explain why + offer to broaden. "No contacts match these filters." + [Clear all filters] |
| **Permission denied** | Explain what's needed. "This feature requires an admin role. Contact your account owner." |

### 7. Micro-interactions build trust

Small animations confirm actions and show responsiveness.

| Interaction | Animation |
|-------------|-----------|
| Button click | Subtle press (scale 98%, 100ms) |
| Card hover | Shadow increase + subtle lift (150ms) |
| Toggle | Smooth slide with color change (200ms) |
| Toast notification | Slide up from bottom-right, auto-dismiss 4s |
| Data loading | Skeleton placeholders matching layout shape |
| Number change | Count up/down animation (300ms) |
| Success action | Brief green checkmark, fades after 1.5s |
| AI thinking | Pulsing purple dot or shimmer (not a spinner) |

**Timing rule:** Animations are 150-250ms. Shorter = jarring. Longer = laggy.

### 8. Mobile-responsive is not optional

Contractors check phones between jobs.

**Must work on mobile:**
- Dashboard KPI cards (stack to single column)
- Contact list (scrollable, tap to detail)
- AI Insights headline card
- Conversation/messaging view (portrait-friendly)
- Toast notifications

**Can defer to desktop:**
- Campaign wizard (complex creation)
- Funnel automation editor
- Analytics charts (show simplified view on mobile)

### 9. Consistency eliminates cognitive load

| Rule | Example |
|------|---------|
| Same action = same button style | Primary actions (Book, Send, Create) always use purple primary button |
| Same data = same card pattern | Contact counts use the same visual pattern everywhere |
| Same status = same color | "Booked" is always green, whether in pipeline, contacts, or campaigns |
| Same icon = same meaning | Sparkle (✦) always means AI. Calendar always means scheduling. |

### 10. Accessibility is a baseline

- Contrast ratio minimum 4.5:1 for text (WCAG AA)
- All interactive elements keyboard-reachable (tab, enter, escape)
- ARIA labels on every icon-only button
- Color is never the ONLY signal
- Focus rings visible on all interactive elements
- Semantic HTML: `button` not `div onClick`, `a` not `span onClick`
- Heading hierarchy (h1 → h2 → h3, no skipping)

---

## Component Patterns

### KPI Card
```
┌─ border-l-4 border-{semantic-color} ──────────┐
│  Label (text-xs uppercase text-muted)          │
│  Value (text-2xl font-bold)  Trend (▲ 7%)     │
│  Subtitle (text-sm text-muted)                 │
│  [Optional: sparkline]                         │
└─ cursor-pointer hover:shadow-md ───────────────┘
```
- Left border color indicates category/sentiment
- Clickable — navigates to detail view
- Trend arrow colored green/red/gray

### AI Content Block
```
┌─ border-l-2 border-purple-400 pl-3 ───────────┐
│  ✦ AI-generated  (text-xs text-purple-600)     │
│  Message content here...                        │
│  [Edit] [Regenerate] (ghost buttons, text-xs)  │
└────────────────────────────────────────────────┘
```

### Insight Card (AI Insights page)
```
┌─ bg-{status}-50 border-{status}-200 rounded-lg p-4 ┐
│  [icon] Title           (font-medium)                │
│  Description            (text-sm text-gray-700)      │
│                                                       │
│  Stat | Stat | Stat     (text-xs grid)               │
│  [View examples ▼]      (ghost button)               │
└──────────────────────────────────────────────────────┘
```
- Green bg for "What's Working", blue for "Recent Changes", amber for "Flagged"

### Flagged Review Card
```
┌─ bg-amber-50 border-amber-200 rounded-lg p-4 ──────┐
│  ⚠ Flagged for Review              Date             │
│  Message preview (italic, text-sm)                   │
│  Contact response (text-sm)                          │
│                                                       │
│  AI Assessment: explanation (text-sm text-gray-600)  │
│  [Mark OK] [Flag Tone] [Flag Timing] [Dismiss]      │
└──────────────────────────────────────────────────────┘
```

### AI Writing Assist Popup
```
┌─ rounded-lg shadow-xl border p-4 max-w-md ─────────┐
│  ✦ AI Suggestion                                     │
│  ┌─ editable textarea (border, rounded) ──────────┐ │
│  │  AI's suggested text, editable by user          │ │
│  └────────────────────────────────────────────────┘ │
│  Contextual tips (text-xs text-gray-500):            │
│  • "This message is 210 chars — under 160 fits one  │
│    SMS segment"                                      │
│  • "Consider referencing their original need"        │
│                                                       │
│  [Cancel] (ghost)            [Accept] (primary)      │
└──────────────────────────────────────────────────────┘
```
- Popup positioned near the textarea it assists
- Text is editable in the popup BEFORE injecting
- Original textarea content is NEVER overwritten until Accept

### Hero Dashboard Card (AI summary)
```
┌─ bg-gradient-to-r from-purple-50 to-white
│  border border-purple-200 rounded-xl p-6 ──────────┐
│  ✦ Your AI This Month                    May 2026   │
│                                                       │
│  [38]          [41%]          [$12,400]              │
│  appointments  response rate  revenue                │
│  booked        (▲ 7%)        influenced              │
│                                                       │
│  "Switched to shorter follow-ups — response rate     │
│   jumped 12% in the first week."                     │
│                                                       │
│  [View AI Insights →]                                │
└──────────────────────────────────────────────────────┘
```
- Gradient purple background makes it visually distinct
- Larger than other cards — this is the hero
- Single natural-language sentence about improvement

---

## UX Validation Checklist

Run this against every page/feature before marking it complete:

### The Glance Test
- [ ] Can you understand the page's purpose in 3 seconds?
- [ ] Is the most important information the most visually prominent?
- [ ] Is there a clear primary action?

### Information Quality
- [ ] Every number has context (trend, comparison, or explanation)?
- [ ] Every metric has a tooltip explaining what it means?
- [ ] Numbers that represent lists are clickable to drill in?

### Color & Visual
- [ ] Colors follow the semantic system (no decorative color)?
- [ ] Red is only used for errors/critical (never informational)?
- [ ] Purple is used consistently for AI features?
- [ ] Trends are color-coded (green up, red down, gray stable)?
- [ ] Color is never the only signal (paired with text/icon)?

### Interaction
- [ ] Every card/summary is clickable to detail?
- [ ] Primary actions use the primary button style?
- [ ] Loading states show skeletons (not bare spinners)?
- [ ] Empty states explain why + offer a first action?
- [ ] Error states suggest a solution + offer recovery?
- [ ] Success states confirm what happened + suggest what's next?

### AI Features
- [ ] AI-generated content has a visible purple marker?
- [ ] AI decisions show human-readable reasoning?
- [ ] Human override is one click away?
- [ ] AI writing assist popup preserves original text until Accept?

### Accessibility & Responsiveness
- [ ] All interactive elements keyboard-accessible?
- [ ] ARIA labels on icon-only buttons?
- [ ] Contrast ratio >= 4.5:1?
- [ ] Layout stacks cleanly on mobile (key pages)?

---

## Anti-Patterns to Avoid

| Anti-Pattern | Why It's Bad | Do This Instead |
|--------------|-------------|-----------------|
| Wall of equal cards | Nothing stands out | 1-2 hero cards + supporting grid |
| Bare spinner | User doesn't know what's loading | Skeleton + "Loading your campaigns..." |
| "Something went wrong" | User can't fix it | Specific error + suggested action |
| Generic "just checking in" | Feels automated and lazy | Context-aware messaging referencing their situation |
| Numbers without context | User can't judge good/bad | Always show trend, comparison, or benchmark |
| Color-only status | Inaccessible, ambiguous | Pair with text label and/or icon |
| AI content without attribution | User doesn't know what AI wrote | Purple ✦ marker on all AI content |
| In-place overwrite | User loses their work | Popup with preview, editable before Accept |
| Full page navigation for details | Loses context | Slide-out panel or modal |
| "Are you sure?" with no info | User can't decide | "Archive this contact? All data preserved. Restore anytime." |
