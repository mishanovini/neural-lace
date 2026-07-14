# Lesson — The "False Nothing": Claiming "nothing needed from you" in the Same Breath as Handing Over Work

**Date:** 2026-07-13
**Source case:** Operator caught it directly. In the turn that delivered admin-shell
commands for `setup-defender-exclusions.ps1` (a real action only the operator can perform),
the session's sign-off line read **"Needs from you: nothing."** The operator: *"You just
told me there is nothing needed from me immediately after you just gave me instructions for
work that's needed from me… why do you keep telling me there's nothing needed when there
are things needed?"*
**Nature:** A communication-honesty defect in the session-end convention — not a code bug.
**Harness change:** `~/.claude/rules/constitution.md` §2 sign-off rule rewritten to a
two-bucket split (Blocking / When-you-can). See "What changed" below.

## What went wrong — the conflation

The constitution §2 sign-off rule said: *"End every substantive message with a one-line
'Needs from you:' — either the specific items, or the word 'nothing.'"* That single slot
silently answered **two different questions at once**, and I collapsed them:

- **"Am I blocked?"** — No, I could keep going (the Defender run is async; I wasn't waiting).
- **"Is there any real action expected of you?"** — **Yes** — run the script.

I let the first answer ("not blocked") overwrite the second, and wrote "nothing." The result
is a message that hands the operator a task and, one line later, asserts there is no task.
That reads as either careless or dishonest, and it corrodes the one signal the operator most
needs to trust: *what, if anything, is on me right now?*

**Why it recurred:** the convention had only a blocking notion of "needed." Every
non-blocking-but-real ask — run this script, review this when convenient, decide this
eventually — had nowhere to land, so it fell through the crack as "nothing." The
`NEEDS-YOU.md` ledger already separated the classes (a "One optional operator action (not
blocking)" section for async actions, distinct from a "for your eye when convenient / not
mine to action" FYI section), but the always-loaded rule that governs the **chat** sign-off
did not — so the file was honest while the chat line was not.

## The fix — two explicit buckets, and "nothing" means both are empty

`Needs from you` is now always split:

1. **Blocking:** — I cannot proceed until you act (a genuine irreversible decision, a
   credential, an approval). Pairs with the `PAUSING:` / `BLOCKED:` end-markers.
2. **When you can:** — real actions genuinely expected of you, but async; I keep going
   without them (run a host-setup script, merge a green PR, eyeball a report).

"Nothing" is honest **only when both buckets are empty**. Handing over an action while the
same message claims nothing-needed — the **"false nothing"** — is now named as a §1 honesty
violation, not a courtesy. A non-blocking ask is still an ask.

## What changed in the harness

- **`~/.claude/rules/constitution.md` §2 (Communication hygiene):** the one-line
  "Needs from you" rule replaced with the two-bucket **Blocking / When-you-can** sign-off;
  the **Blocking** bucket linked to the §6 `PAUSING:`/`BLOCKED:` markers; an explicit
  carve-out that pure FYI context (no action expected) belongs to neither bucket and does
  not defeat "nothing"; the "false nothing" named a §1 violation; and an accurate pointer
  that `NEEDS-YOU.md`'s operator-action entries are the two buckets while its
  "not mine to action" FYI entries are the "nothing" case. Always-loaded, so it governs
  every session-end sign-off directly. Routed through `harness-reviewer` — CONDITIONAL-PASS,
  whose one Major finding (an inverted `NEEDS-YOU.md` cross-reference in the first draft) was
  fixed before landing.

## Discriminator — when this lesson applies

Any message whose sign-off says "nothing" (or omits the operator entirely) **while the same
message, or the live `NEEDS-YOU.md`, contains an action the operator is expected to take** is
exhibiting the false-nothing. The tell is a mismatch between the body ("here are the commands
to run…") and the sign-off ("nothing needed"). The correct end-state is: every operator-facing
action appears in the **When you can:** bucket (if async) or **Blocking:** (if I'm waiting on
it), and "nothing" is reserved for turns where the operator truly has zero outstanding items.

Distinct from `PAUSING:`/`BLOCKED:` (§6 markers), which only ever covered the *blocking*
half. The gap this closes is the *non-blocking-but-real* half — the actions I can proceed
past but the operator still owns.
