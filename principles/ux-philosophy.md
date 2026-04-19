# UX Philosophy

## What this principle covers
How every user-facing state should guide the user to a resolution. Principles for error messages, empty states, loading indicators, destructive actions, success feedback, and warning severity. These apply to all UI work regardless of framework or platform.

---

## Every State Must Guide the User

A user interface has exactly one job: help the user accomplish what they came to do. Every state the interface can be in -- loading, empty, error, success -- is an opportunity to guide or an opportunity to abandon. There is no neutral state.

---

## Errors Suggest a Solution

An error message that only describes the problem is half-finished. The user already knows something went wrong. What they need is a path forward.

- **Bad:** "Failed to save."
- **Good:** "Failed to save -- check your connection and try again."
- **Best:** "Failed to save -- check your connection and try again. [Retry]"

If you cannot suggest a specific fix, explain what the user can investigate. "Something went wrong" is never acceptable as a final message.

---

## Suggestions Link Directly to Action

When the interface suggests the user do something, that suggestion must be a direct link to the action. Do not make the user hunt for it.

- "Click to categorize" must open the category picker, not navigate to a settings page.
- "Add a payment method" must open the payment form, not link to an FAQ.
- "Try importing your data" must start the import flow, not describe it.

A suggestion that requires the user to figure out how to follow it is not a suggestion. It is a riddle.

---

## Empty States Explain and Offer a First Action

An empty state is the user's first impression of a feature. It must answer two questions: "Why is this empty?" and "What do I do first?"

- **Explain:** "No transactions yet" tells the user the state is expected, not broken.
- **Offer action:** "Import from your bank or add one manually" with a visible button.
- **Never leave it bare.** A blank screen with no guidance reads as a bug.

---

## Destructive Actions Require Confirmation with Reversibility Info

Before any destructive action, tell the user exactly what will happen and whether it can be undone.

- **Confirm:** "Archive this account?"
- **Explain reversibility:** "All data will be preserved. You can restore it anytime from Settings."
- **Or explain irreversibility:** "This will permanently delete 47 transactions. This cannot be undone."

The confirmation dialog must use specific language. "Are you sure?" is not a confirmation. "Delete 47 transactions permanently?" is.

---

## Success States Confirm the Change and Reveal What Is Next

After a successful action, the user needs two things: confirmation that it worked, and a pointer to what they might do next.

- **Confirm:** "Account archived."
- **Reveal next step:** "View archived accounts" or "Create another."

A success message that dead-ends leaves the user wondering where to go. Always offer a forward path.

---

## Loading States Describe What Is Loading

A spinner with no context creates anxiety. The user does not know if the system is frozen, slow, or working.

- **Bad:** A bare spinner.
- **Good:** "Loading payment history..."
- **Better:** "Loading payment history..." with a skeleton placeholder matching the expected layout shape.

Descriptive loading states set expectations and reduce perceived wait time.

---

## Warning Severity by Color

Color communicates urgency. Use it consistently:

- **Yellow/Amber:** Informational or fixable. The user should be aware but is not blocked. Example: "Your subscription renews in 3 days."
- **Red:** Blocking or data-risk. Something is wrong and requires action. Example: "Payment failed. Update your card to continue."

Never use red for informational warnings. It trains users to ignore red, which means they will ignore real emergencies. Reserve red for situations where inaction has consequences.

---

## The Glance Test

Before shipping any UI change, apply the glance test: **Can someone understand this page in 3 seconds?**

If the answer is no, the hierarchy is wrong. The most important information should be the most visually prominent. Secondary details should recede. Actions should be obvious.

Three seconds is not a metaphor. It is the actual attention budget for a first impression.
