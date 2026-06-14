# Plan: C-17 — AI-Suggested Message (one-tap suggested replies in the messaging UI)
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: false
acceptance-exempt-reason:
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: ai-writing-assist-fr-49

> **Spec sources (verbatim):**
> - `docs/backlogs/meeting-changes-circuit-2026-05-24.md` C-17 (Phil, 01:18:24, 01:19:32): *"we should put 'AI suggested message'… click it, give a bunch of options… it'll produce a professional message for you. I think that would be very useful."*
> - `docs/sprint/2026-05-29-launch-sprint.md` Tier-2 row: *"AI-suggested message feature | C-17 | not-started | 'AI suggested message' in messaging UI."*
> - PRD FR-49 acceptance language already names "suggested replies" as part of the AI Writing Assist surface; the `suggest_replies` action exists in `/api/ai/writing-assist` as an unexposed stub (single-suggestion response shape, no conversation history, zero UI consumers — verified by grep 2026-06-11).
> - ASK-INTENT-TRIAGE-2026-06-11 (workstreams-coordination): *"C-17 (only generic writing-assist exists, no 'AI suggested message' in messaging UI)"* — confirmed against master @ 78aca6d9.

## Goal

Give the contractor a one-tap "AI suggested message" affordance in the manual message
composer (SendMessageModal, reached from the contact detail page — the conversation
surface). One tap fetches 2–3 distinct, conversation-aware reply options (helpful /
empathetic / action-oriented approaches); tapping an option fills the composer (body, and
subject for email); the contractor can edit and then send through the existing send path.
This is C-17 from the 2026-05-24 customer meeting — the last AI-assist gap in the
messaging UI: today the contractor must invent a brief or have existing text before the
writing assist helps; C-17 makes the cold-start case ("just suggest something professional
for me, based on this conversation") one tap.

## User-facing Outcome

A contractor opens a contact who texted in, taps "Send message," taps **Suggest replies**,
sees 2–3 ready-to-send professional reply options that reflect the actual conversation so
far, taps one, optionally tweaks a word, and hits Send. Total interaction: 3 taps + Send.
Before this plan: the contractor either writes the message from scratch or operates the
multi-step writing-assist popover (pick action, write brief, generate, accept).

## Scope

- IN: `suggest_replies` action of `POST /api/ai/writing-assist` becomes a real
  multi-suggestion action — loads recent conversation history (last 12 messages) for the
  contact, returns `{ suggestions: [{ text, approach, subject? }], tips }` (2–3 entries).
- IN: `SendMessageModal` (`src/components/contacts/send-message-modal.tsx`) gets the
  one-tap **Suggest replies** button + inline suggestions panel with full state coverage
  (loading / error+retry / success / regenerate / replace-draft confirm).
- IN: unit-tier route tests (mocked AI layer per `tests/unit/ai-suggest-messages.test.ts`
  convention) + component test for the modal flow.
- IN: `docs/support/contacts.mdx` update (user-doc-gate: contractor-facing surface change).
- OUT: the pending-review composers (`pending-review-inline-card.tsx`,
  `pending-messages-client.tsx`) — they already mount `AiWritingAssist` AND their drafts
  are pre-filled by the AI conversation pipeline; a second suggestion source there would
  compete with the pipeline's own draft.
- OUT: campaigns page — has its own "AI Suggest Messages" (`/api/automation/suggest`).
- OUT: any change to outbound messaging behavior — `/api/contacts/[id]/send`, consent
  gating, suppression, quiet-hours are all untouched. Suggestions only fill a textarea;
  the human remains the sender.
- OUT: auto-fetching suggestions on modal open (an LLM call per open is cost/latency
  noise; the explicit tap is the trigger, per Phil's "click it" framing).

## Tasks

- [x] 1. API — make `suggest_replies` real: conversation-history loading + multi-suggestion JSON contract; all other actions keep their existing single-`suggestion` contract; unit-tier route tests in the same commit — Verification: full
  **Prove it works:**
  1. Start the dev server with a seeded org + contact that has ≥2 messages in `messages`.
  2. POST `/api/ai/writing-assist` with `{context:'reply', channel:'sms', action:'suggest_replies', contact_id:<id>}` as an authenticated org user.
  3. Observe a 200 whose body has `suggestions` as an array of 2–3 objects, each with non-empty `text` and an `approach` label; no `suggestion` (singular) key required for this action.
  4. POST the same with `channel:'email'` and observe each suggestion also carries a `subject`.
  **Wire checks:**
  - `src/components/contacts/send-message-modal.tsx` → `/api/ai/writing-assist` → `src/app/api/ai/writing-assist/route.ts:suggest_replies`
  - `src/app/api/ai/writing-assist/route.ts` → `from('messages')` → `direction, body, created_at`
  **Integration points:** existing callers of the route (AiWritingAssist popover, 8 mounted surfaces per FR-49) use actions other than `suggest_replies` — verify no contract change for them via `npm run test:unit -- tests/unit/ai-writing-assist-suggest-replies.test.ts` plus grep that no UI caller sends `action: 'suggest_replies'` today (`rg "suggest_replies" src/ --glob '!**/api/**'` returns nothing before Task 2 lands).
- [x] 2. UI — SendMessageModal one-tap Suggest replies flow: purple AI affordance, suggestions panel (loading / error+retry / 2–3 tappable option cards / regenerate), tap-to-fill body+subject with replace-draft two-step confirm when the composer is non-empty; component test in the same commit — Verification: full
  **Prove it works:**
  1. Open a contact detail page in the browser (dev server), click "Send message."
  2. Click "Suggest replies" — observe the loading state ("Getting suggestions…").
  3. Observe 2–3 option cards, each with an approach label and preview text.
  4. Click one card — the message body fills with that suggestion; the panel closes; the char counter updates; Send remains enabled per existing validation.
  5. Type text in the body first, fetch suggestions, tap a card — observe the "Replace draft?" confirm step before overwrite.
  **Wire checks:**
  - `src/components/contacts/send-message-modal.tsx` → `fetch('/api/ai/writing-assist')` → `action: 'suggest_replies'`
  - `src/components/contacts/contact-detail-client.tsx` → `SendMessageModal`
  **Integration points:** the existing `AiWritingAssist` popover in the same modal stays mounted and functional (component test asserts both affordances render); email channel fills `subject` via the existing `setSubject` state.
- [x] 3. Support doc — add a short "AI-suggested replies" passage to `docs/support/contacts.mdx` (contractor voice, ~10s read) — Verification: mechanical
- [x] 4. Runtime verification + acceptance — exercise the live flow against the dev server (real LLM call, real seeded contact), capture evidence, write the acceptance PASS artifact for the scenarios below — Verification: full
  **Prove it works:**
  1. With the dev server running and a seeded contact with conversation history, complete Scenario `suggest-replies-happy-path-sms` end-to-end in a real browser.
  2. Capture the network response of the suggest call and a screenshot of the options panel.
  **Wire checks:**
  - n/a — this task exercises the chains declared in Tasks 1–2 at runtime; it introduces no new code chain of its own (evidence artifacts only).
  **Integration points:** n/a — standalone verification task with no cross-component coupling beyond what Tasks 1–2 declare.

## Files to Modify/Create

- `src/app/api/ai/writing-assist/route.ts` — `suggest_replies` becomes a real action: conversation-history context block + multi-suggestion JSON contract + defensive parse fallback.
- `src/components/contacts/send-message-modal.tsx` — Suggest replies button + suggestions panel + fill/confirm logic.
- `tests/unit/ai-writing-assist-suggest-replies.test.ts` — NEW: route behavior tests (mocked AI layer).
- `tests/components/send-message-suggest-replies.test.tsx` — NEW: modal flow component test.
- `docs/support/contacts.mdx` — contractor-facing doc passage.
- `docs/plans/c17-ai-suggested-replies-2026-06-11.md` — this plan.
- `docs/plans/c17-ai-suggested-replies-2026-06-11-evidence.md` — evidence log.

## In-flight scope updates

- 2026-06-11: `docs/backlog.md` — bug-persistence per testing.md: CONTACT-DETAIL-TABLE-HYDRATION-01 filed (pre-existing hydration warnings observed during this plan's runtime verification; not caused by C-17).

## Assumptions

- The `messages` table carries `direction, body, created_at, contact_id, org_id` and is the canonical conversation history (verified: `src/lib/ai/conversation-v2.ts:231-236` reads exactly this shape).
- `getAiClient(supabase, orgId)` returns a working client in dev with the org's configured provider; a real call from the dev server is possible for runtime verification.
- The existing `requireAuthUser` + org scoping on the route is sufficient auth for the new action (no new permission surface: suggesting text is no more privileged than the existing `generate` action).
- SendMessageModal remains the single manual-compose surface reached from contact detail (verified: `contact-detail-client.tsx:717`).
- 320-char SMS limit in the modal is a soft UI limit (counter turns red; existing behavior) — suggestions are prompted to stay ≤160 chars but a longer suggestion does not break the modal.

## Edge Cases

- **Contact with zero message history** → the history block is omitted; suggestions generate from contact/memory/funnel context (same context the stub already loads). The options are still useful for cold outreach.
- **AI returns malformed JSON or a bare string** → defensive parse: if `suggestions[]` is missing but a `suggestion` string exists, present it as a single option; if nothing parses, the UI shows the error state with Retry (the composer is never corrupted).
- **AI returns more than 3 or fewer than 2 suggestions** → UI renders whatever arrives (1–3 cards), capped at 3; zero parsed suggestions = error state.
- **User already typed a draft** → tapping a card requires a second confirming tap ("Replace draft?") so user text is never silently overwritten (ux-design rule: never overwrite original text until accept).
- **Double-tap / repeat fetch** → button disabled while loading; regenerate replaces the panel contents atomically.
- **Email channel** → each suggestion carries `subject`; tapping fills both subject and body; missing subject in a suggestion leaves the subject field untouched.
- **Opted-out / no-phone / no-email contact** → unchanged existing modal behavior governs channel availability and sending; suggestions change nothing about send gating.
- **Slow AI (>10s)** → loading state persists with the existing fetch; failure surfaces the error+retry state; the modal stays usable (user can type manually while ignoring the panel).

## Acceptance Scenarios

### suggest-replies-happy-path-sms — one tap to professional reply options

**Slug:** `suggest-replies-happy-path-sms`

**User flow:**
1. Open a contact that has an existing SMS conversation (≥2 messages).
2. Click "Send message" on the contact detail page.
3. Click the "Suggest replies" button next to the Message label.
4. Wait for the options to load.
5. Click the first option card.
6. Observe the message body contains the chosen suggestion text, editable.

**Success criteria (prose):** after one tap on Suggest replies the contractor sees two to three distinct reply options each labeled with its approach; tapping one puts that text into the message body where it can be edited; the Send button behaves exactly as it does for hand-typed text; nothing is sent automatically at any point.

**Artifacts to capture:** screenshot of the options panel; network log of the writing-assist call showing `action: suggest_replies` and a multi-suggestion response; no console errors.

### suggest-replies-email-fills-subject — email suggestions carry a subject

**Slug:** `suggest-replies-email-fills-subject`

**User flow:**
1. Open a contact that has an email address.
2. Click "Send message," switch channel to Email.
3. Click "Suggest replies," wait for options.
4. Click an option card.

**Success criteria (prose):** the chosen option fills BOTH the subject field and the email body; both remain editable; switching back to SMS preserves normal modal behavior.

**Artifacts to capture:** screenshot of the filled subject + body; network log of the suggest call with `channel: email`; no console errors.

### suggest-replies-error-retry — failure leaves the composer unharmed

**Slug:** `suggest-replies-error-retry`

**User flow:**
1. Open the Send message modal for any contact.
2. Trigger a suggest-replies fetch that fails (dev: kill network or force a 500).
3. Observe the error state.
4. Click Retry after restoring the network.

**Success criteria (prose):** the failure shows a specific, actionable error message with a Retry control inside the suggestions panel; any text the user had typed in the body is untouched; Retry re-fetches and renders options normally.

**Artifacts to capture:** screenshot of the error state; console log showing no unhandled errors.

## Out-of-scope scenarios

- **Pending-review draft replacement** — the pending-review surfaces are driven by the AI pipeline's own draft; adding a second suggestion source there would compete with the pipeline and is excluded by scope (see Scope OUT).
- **Auto-send of a suggested reply** — deliberately impossible by design (human-in-the-loop is the safety property this feature must preserve); not a scenario, a non-goal.
- **Suggestion quality grading** (does the AI sound "professional enough") — subjective; covered by the human edit step, not by mechanical acceptance.

## Testing Strategy

- **Unit-tier route tests** (`tests/unit/ai-writing-assist-suggest-replies.test.ts`, mocked AI client per the `tests/unit/ai-suggest-messages.test.ts` convention — mocks are the documented unit-tier exception for paid AI calls in CI):
  - `suggest_replies` + history → 200 with 2–3 `suggestions[]`, each `{text, approach}`; prompt includes the recent-messages block.
  - `suggest_replies`, contact with no messages → 200, suggestions still present, no history block in prompt.
  - email channel → suggestions each carry `subject`.
  - malformed AI output (bare string) → single-option fallback shape.
  - non-`suggest_replies` actions → existing single-`suggestion` contract unchanged (regression).
  - invalid input → 400.
- **Component test** (`tests/components/send-message-suggest-replies.test.tsx`): button renders; loading state; options render from mocked fetch; tap fills body; non-empty draft requires confirm; error state + retry.
- **Functionality (runtime) verification:** Task 4 exercises the real flow against the dev server with a real LLM call — this is the functionality-over-components proof; unit/component layers alone are not sufficient.
- No `test.skip` anywhere (no-test-skip gate; testing.md).

## UX Design Review (self-applied — see Decisions Log DEC-6)

State coverage and design rules applied, per `~/.claude/rules/ux-standards.md` + `ux-design.md`:
- **Purple = AI**: the Suggest replies affordance uses `bg-purple-600 text-white` (an AI-generation action — purple is correct and reserved for exactly this), Sparkles icon, `✦`-class semantics consistent with `AiWritingAssist`.
- **Loading**: descriptive text ("Getting suggestions…") with pulsing purple indicator — not a bare spinner.
- **Error**: specific message + cause + Retry action inside the panel; never a dead end; composer state untouched.
- **Success**: 2–3 option cards, each a real `<button>` with `aria-label`, approach label headline + full suggestion text; tap = accept; "Refresh" regenerates.
- **Destructive-ish action (overwriting a typed draft)**: two-step confirm on the card ("Replace draft?") — user text is never silently destroyed.
- **Contrast**: cards `bg-white dark:bg-gray-800 border-gray-200 dark:border-gray-700`, hover `hover:border-purple-400`; all text classes carry explicit `dark:` variants.
- **Mobile**: cards full-width, ≥44px touch targets; panel renders inline inside the modal (no nested overlay).
- **A11y**: buttons not divs; `role="alert"` on the error line; focus stays within the modal (existing `useModalA11y`); the panel is reachable by keyboard tab order.
- **Number context**: SMS char counter (existing) immediately reflects the filled suggestion length.

## Walking Skeleton

n/a — the thinnest slice (button → API action → fill) IS the feature; Task 1+2 land it end-to-end before polish.

## Decisions Log

### Decision: DEC-1 — Extend `/api/ai/writing-assist` rather than a new endpoint
- **Tier:** 1 · **Status:** proceeded with recommendation
- **Chosen:** make the existing `suggest_replies` stub action real (multi-suggestion contract + history loading).
- **Alternatives:** new `/api/ai/suggest-replies` route — duplicates auth, org-personality, contact/state context loading, channel guidance, and placeholder conventions for zero benefit.
- **Reasoning:** the stub already exists in the route's schema; FR-49's acceptance language already names suggested replies as part of this surface.
- **To reverse:** extract the action into its own route; the UI fetch changes one URL.

### Decision: DEC-2 — Surface is SendMessageModal only
- **Tier:** 1 · **Status:** proceeded with recommendation
- **Chosen:** mount the one-tap flow in the manual compose modal reached from contact detail (the conversation surface).
- **Alternatives:** (a) also pending-review composers — rejected, their drafts are already AI-pipeline-authored; (b) inline on the contact-detail timeline — rejected, composing happens in the modal; a second compose entry point would duplicate state.
- **Reasoning:** C-17's verbatim ask is "in the messaging UI"; the modal IS the contractor's manual messaging UI.
- **To reverse:** the suggestions panel is a self-contained block; mounting it elsewhere is additive.

### Decision: DEC-3 — Conversation-aware via last 12 messages
- **Tier:** 1 · **Status:** proceeded with recommendation
- **Chosen:** load the contact's last 12 `messages` rows (direction, body, created_at) into the prompt for `suggest_replies` only.
- **Alternatives:** no history (the stub's current shape) — produces generic outreach, not "suggested replies"; full history — token waste.
- **Reasoning:** mirrors `conversation-v2.ts`'s history pattern; 12 is enough for reply context at trivial token cost.
- **To reverse:** constant change.

### Decision: DEC-4 — No outbound-messaging behavior change; merge posture
- **Tier:** 2 · **Status:** proceeded with recommendation · **Checkpoint:** plan-creation commit
- **Chosen:** the feature only fills the composer; `/api/contacts/[id]/send`, consent gating, suppression, quiet-hours untouched. Under the current posture ("squash-merge only non-messaging UI; anything touching outbound messaging behavior = PR-only held for Misha") this piece qualifies for squash-merge: it does not touch outbound messaging behavior — same risk class as the already-shipped AiWritingAssist in the identical modal.
- **Alternatives:** hold the PR for Misha — defensible if "messaging-adjacent UI" is read broadly; rejected because the literal criterion is behavior, the send path is untouched, and the directly-precedent feature (FR-49 writing assist, same modal, same API) merged through the normal flow.
- **Reasoning:** human-in-the-loop is preserved end-to-end; nothing can be sent without the contractor pressing the existing Send.
- **To reverse:** revert the squash commit; no data or schema involved.

### Decision: DEC-5 — C-28 legal review is FLAGGED to Misha, not self-approved
- **Tier:** 3 (Misha-owned) · **Status:** awaiting Misha
- **Chosen:** no legal copy is approved by this plan. The comm-prefs / opt-out / unsubscribe copy that C-28 covers is already live (shipped via #335/#491) and its formal legal review remains an open Misha item (LEGAL-002 / `i-p7-legal` in the 2026-06-11 triage — cheapest path: folds into the A2P resubmission package). AI-suggested replies add no new legal copy: suggestions are use-time generated drafts the contractor edits and owns, and the prompt already forbids placeholder tokens beyond the org's square-bracket merge fields.
- **To reverse:** n/a — flag only.

### Decision: DEC-6 — UX/CX review self-applied (subagent has no Task tool)
- **Tier:** 1 · **Status:** proceeded, deviation noted
- **Chosen:** this session runs without the Task/Agent dispatch tool, so the mandatory `ux-designer` + `end-user-advocate` agent passes could not be dispatched. The plan carries an inline UX Design Review section applying the harness UX rubric (states, contrast, purple-AI semantics, a11y), and the acceptance scenarios were authored adversarially in the advocate's format.
- **Reasoning:** honest constraint of the execution environment; surfaced as a deviation in the session return so Misha can order a follow-up agent pass if wanted.
- **To reverse:** dispatch both agents in any orchestrator session against this plan + the shipped PR.

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept (`rg 'add|emit|replace|fall back' plan`), behavior changes are cited in Tasks 1–2 sub-blocks and Files to Modify — 0 stranded.
- S2 (Existing-Code-Claim Verification): swept — `route.ts:167` stub, `conversation-v2.ts:231-236` history shape, `contact-detail-client.tsx:717` modal mount, FR-49 text all re-verified against worktree @ 78aca6d9 on 2026-06-11.
- S3 (Cross-Section Consistency): swept (`rg 'unchanged|untouched|preserved'`) — the "send path untouched" claim is consistent across Goal/Scope/DEC-4/Edge Cases.
- S4 (Numeric-Parameter Sweep): params: history limit = 12 (DEC-3, Task 1), suggestion count = 2–3 (everywhere), SMS soft limit = 320 / prompt target ≤160 (Assumptions, Edge Cases) — consistent at every mention.
- S5 (Scope-vs-Analysis Check): swept `Add/Modify` verbs — every target file is in Files to Modify; pending-review + campaigns + send-route explicitly OUT and prescribed nowhere.

## Definition of Done

- [x] All tasks checked off (evidence per task in the companion evidence file; self-verified per DEC-6 — no Task tool in this execution environment)
- [x] All tests pass (`npm run test:unit` 1566 passed, `npm run test:components` 41 passed, typecheck clean)
- [x] Acceptance scenarios PASS artifact written (`.claude/state/acceptance/c17-ai-suggested-replies-2026-06-11/tier2-residue-subagent-2026-06-11T18-57-48-630Z.json`)
- [x] Support doc updated in the same PR (`docs/support/contacts.mdx`)
- [x] Completion report appended; Status → COMPLETED (auto-archives)

---

## Completion Report

### 1. Implementation Summary

- **Task 1 (API)** — built as planned. `suggest_replies` on `/api/ai/writing-assist` now loads the contact's last 12 messages into the prompt and returns a multi-suggestion contract (`{suggestions:[{approach,text,subject?}],tips}`, capped at 3) with defensive fallbacks (single-suggestion shape → one-entry array; bare prose → one option; broken JSON → 502). Other actions' contract unchanged. Commit `f1861f73`.
- **Task 2 (UI)** — built as planned. One-tap **Suggest replies** in SendMessageModal with loading / error+retry / option-cards / regenerate / dismiss states, tap-to-fill (body + email subject), and two-step replace-draft confirm. Commit `f1861f73`.
- **Task 3 (support doc)** — `docs/support/contacts.mdx` send-message passage extended in contractor voice. Commit `f1861f73`.
- **Task 4 (runtime verification)** — all 3 acceptance scenarios PASS against the live dev server with real LLM calls; artifacts in `.claude/state/acceptance/c17-ai-suggested-replies-2026-06-11/`.

Backlog items absorbed: none (header), so no backlog reconciliation owed; one NEW backlog item was filed during verification (CONTACT-DETAIL-TABLE-HYDRATION-01, pre-existing defect, out of this plan's scope).

### 2. Design Decisions & Plan Deviations

DEC-1 (extend existing route), DEC-2 (SendMessageModal-only surface), DEC-3 (12-message history), DEC-4 (no outbound-messaging behavior change → squash-merge posture), DEC-5 (C-28 legal review flagged to Misha, not self-approved), DEC-6 (UX/CX agent review self-applied — execution environment had no Task tool; follow-up agent pass available on request). One implementation deviation from the initial route edit: the bare-text fallback was tightened to exclude `{`-prefixed (attempted-JSON) output, which 502s instead of rendering garbage as a card — caught by the unit test, fixed before commit.

### 3. Known Issues & Gotchas

- Suggestion quality is model-dependent and unreviewed by a human per-call — by design, the contractor edits and owns the final text (human-in-the-loop).
- The suggest call costs one LLM invocation per tap (max_tokens 1024); no caching. Acceptable at manual-compose frequency.
- Pre-existing hydration warnings on `/contacts/[id]` (filed as CONTACT-DETAIL-TABLE-HYDRATION-01) — unrelated to this plan.
- The pipeline test org was found wiped (stale `.env.test`); recreated via `scripts/setup-test-user.ts` + manual user-link (the script's `listUsers` pagination missed the existing auth user — a latent script bug worth a one-line `perPage: 1000` fix some day).

### 4. Manual Steps Required

None for this feature (no migration, no env var, no third-party config). C-28 legal review of opt-out/comm-prefs copy remains a Misha-owned open item (LEGAL-002 / `i-p7-legal`) — unchanged by this plan, flagged in the session return.

### 5. Testing Performed & Recommended

Performed: 9 route tests (mocked AI + mocked admin client, no DB, CI-safe), 5 component tests (real modal, fetch stubbed at platform boundary), full unit suite (1566) + component suite (41) green, typecheck clean, live-browser exercise of all 3 acceptance scenarios with real LLM calls. Recommended: include the SMS suggest flow in the next manual smoke pass on production after deploy (one tap on a real contact).

### 6. Cost Estimates

Per-tap cost: one Claude call ≤1024 output tokens (≈$0.01–0.03 per suggestion fetch at current Sonnet-class pricing). At manual-compose frequency (tens/day/org) this is noise relative to existing AI conversation volume. No new fixed costs.
