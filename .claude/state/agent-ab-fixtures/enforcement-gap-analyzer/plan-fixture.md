# Plan: Campaign duplicate button (FIXTURE)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)

## Goal
Users can duplicate an existing campaign from the campaigns list; the copy appears
at the top of the list with name suffix "(Copy)" and cleared schedule.

## Tasks
- [x] T1. Add Duplicate button + API endpoint + list refresh — Verification: full

## Acceptance Scenarios
### duplicate-campaign-happy-path — duplicate from the list
**Slug:** `duplicate-campaign-happy-path`
**User flow:**
1. Open the campaigns list.
2. Click Duplicate on the first campaign.
3. See a new row at top with name suffix "(Copy)".
**Success criteria (prose):** the new row matches the original except name suffix
and cleared scheduled time; the original row is unchanged.
**Artifacts to capture:** screenshot of list; network log of the duplicate POST;
no console errors.
