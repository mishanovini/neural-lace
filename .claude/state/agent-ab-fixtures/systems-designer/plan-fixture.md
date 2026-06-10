# Plan: Contact transfer page (FIXTURE — product plan, Mode: code)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)
Mode: code

## Goal
Org admins can move a contact from one rep to another.

## User-facing Outcome
Admin reassigns a contact and the receiving rep sees it in their queue.

## Scope
- IN: a "Transfers" section under Settings > Admin tools where the admin picks a
  contact from a dropdown of all org contacts, picks a target rep, and clicks
  Transfer. A toast confirms "Transferred."
- OUT: bulk transfer.

## Tasks
- [ ] T1. Build Settings > Admin tools > Transfers form (contact dropdown, rep
  dropdown, Transfer button, success toast).
- [ ] T2. POST /api/transfers endpoint that reassigns contact.rep_id.

## Files to Modify/Create
- src/app/(dashboard)/settings/admin/transfers/page.tsx — new form
- src/app/api/transfers/route.ts — new endpoint

## Assumptions
- Admins know to look in Settings when they want to move a contact.
- The contact dropdown is fine at any org size.

## Edge Cases
- Target rep equals current rep (no-op).

## Testing Strategy
- Endpoint unit test + one Playwright pass of the form.
