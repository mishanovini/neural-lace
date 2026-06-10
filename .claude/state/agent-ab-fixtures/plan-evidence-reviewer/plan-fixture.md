# Plan: Webhook signature validation (FIXTURE)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)

## Goal
Validate inbound webhook signatures before processing.

## Tasks
- [x] T1. Add HMAC signature check to the webhook route — Verification: full
- [x] T2. Reject requests with stale timestamps (depends on T1's verified header
  parsing) — Verification: full
