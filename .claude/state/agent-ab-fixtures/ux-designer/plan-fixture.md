# Plan: Add "Team Activity" dashboard page (FIXTURE)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)
Mode: code

## Goal
New top-level dashboard page showing each rep's recent activity (messages sent,
jobs closed, response times) so an owner can spot who is falling behind.

## UI Section (to review)
- New route `/dashboard/team-activity`, added to the sidebar nav.
- Layout: a data table (one row per rep) with columns: rep name, msgs sent (7d),
  jobs closed (7d), median response time. Above the table, three KPI tiles.
- Each row has a 16x16px icon-only "details" button (no text label) opening a
  side panel with the rep's recent items.
- Data loads from `/api/team-activity` on mount.
- Sorting by any column; default sort = msgs sent desc.
- Color: response-time cell turns red when median > 4h.

## Tasks
- [ ] T1. Build the page per the UI section above.
