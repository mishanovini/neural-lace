# Plan: Contact transfer between reps (FIXTURE)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)
Mode: code
acceptance-exempt: false

## Goal
An org admin can move a contact (and its open conversations, scheduled messages,
and history) from one rep to another, see a confirmation of everything that moved,
be warned when the receiving rep is at capacity, undo the transfer within 5
minutes, and have the contact notified of their new rep — all from the contact
detail page.

## User-facing Outcome
Admin transfers a contact in under a minute and can verify nothing was lost.

## Scope
- IN: transfer action on contact detail page; confirmation summary; capacity
  warning; 5-minute undo; contact notification; transfer audit entry.
- OUT: bulk transfer; cross-org transfer.

## Edge Cases
- Receiving rep at exactly its capacity cap.
- Transfer while a message to the contact is mid-send.
- Undo after the receiving rep has already replied to the contact.

## Acceptance Scenarios
- [populate me]

## Out-of-scope scenarios
- [populate me]

## Testing Strategy
- E2E against the running dev app.
