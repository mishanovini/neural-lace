# Evaluation Discipline

## What this principle covers
How to verify that work is actually done: testing before declaring completion, evaluating at every stage, validating deployments, and confirming that the built thing achieves its stated purpose.

---

## Test Before Declaring Done

Run existing tests before claiming work is complete. A successful edit is not a successful feature. The test suite is the minimum bar, not an optional step.

- **Write tests for new features.** If you built it, prove it works.
- **Reproduce bugs before fixing them.** A test that fails before the fix and passes after is the only reliable proof the fix is correct. Fixing without reproducing is guessing.
- **Failing tests are blockers.** Never skip or delete tests to make a build pass. If a test fails, either the code is wrong or the test is wrong. Determine which, and fix it.
- **Test edge cases.** Empty states, error states, boundary values, null inputs, malformed data. The happy path is the least interesting path.

---

## Evaluate Before Scale

Do not build a feature to completion and then discover it does not work. Validate incrementally:

1. After writing a function, test it in isolation.
2. After wiring components together, test the integration.
3. After deploying, test the live behavior.

Each layer catches different classes of failure. Skipping a layer means those failures reach the user.

---

## Pre-Commit Review

Before every commit, review the staged changes for:

1. **Auth and security** -- proper guards, no cross-tenant access, no exposed secrets.
2. **Error handling** -- explicit handling on every async path; user-facing errors are actionable, not cryptic.
3. **Integration** -- changed files work with their consumers (props match, API contracts hold, schemas align).
4. **Edge cases** -- null/undefined, empty states, malformed input, race conditions.

Fix issues before committing, not after. The commit should represent verified work.

---

## UX Validation After Builds

After building a new feature, redesigning a page, or changing a workflow, validate the user experience from multiple perspectives:

- **Non-technical user walkthrough:** Can someone unfamiliar with the system complete the workflow without getting stuck?
- **Domain expert perspective:** Does the feature make sense for the target user's actual workflow and vocabulary?
- **Content review:** Is all user-facing text appropriate for the audience? No placeholder text, no developer jargon, no orphaned labels.

Blocking and confusing findings must be fixed. Polish items can be deferred.

---

## Deployment Validation

A pull request is not done until it deploys successfully and the feature works in the deployed environment.

1. Wait for all status checks (CI and deployment).
2. If the deployment fails, fix it. A deployment failure caused by your changes is your bug.
3. Verify the deployed feature works as expected.
4. Never dismiss a failing check as "unrelated" without investigation.

The sequence is: commit, push, CI passes, deploy succeeds, feature verified, done.

---

## Purpose Validation

Before writing code, and again before marking a task complete, ask: **"Does this achieve its stated purpose under real conditions?"**

1. State the purpose in one sentence. The outcome, not the mechanism.
2. Validate against real inputs. What does the caller actually provide at runtime? What does the user actually see?

A function that compiles is not a function that works. A page that renders is not a page that helps. Validate purpose, not syntax.
