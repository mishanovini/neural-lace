# Anti-Vaporware — full detail

> Companion to the compact: `doctrine/vaporware-prevention.md`. Carries the registry-vs-callsite invariant pattern behind the "decorative config control" class; the compact is the operative summary (capped at 3000 bytes).

## The registry-vs-callsite invariant

**Definition.** Any code that maintains a registry of capabilities — permission IDs, feature flags, event types — plus a separate UI to configure those entries MUST have a mechanical check that every registry entry is wired to enforcement. The registry declares "this is configurable"; only an enforce-mode call site makes the declaration true. A registry entry with no enforcement consumer is a **decorative config control**: it renders, it persists, and it lies.

The invariant is structural, not stylistic: the registry and the call sites drift independently (a new permission ID added to the registry, a role check hardcoded at the action instead of routed through the registry), and nothing in a per-PR review sees both sides at once. Only a standing check that walks the registry and demands an enforce-mode consumer per entry closes the seam.

## The originating case (a downstream product)

A downstream product's per-org permissions matrix rendered 16 permission toggles; **6 were decorative**. Each rendered as configurable, persisted its value on save, and changed nothing — hardcoded caller-role guards governed the behavior. The actions themselves worked and were access-controlled, so no error ever surfaced; the RBAC admin surface simply lied. An org admin could "revoke" a permission the system kept honoring, or "grant" one to no effect. Every component-level signal was green — the matrix rendered, the API persisted, unit tests passed — while the functionality (toggle → behavior change) did not exist for 6 of 16 entries.

## Instantiating a project-level drift check

A check-permission-drift-style script, run in CI or as a standing invariant:

1. **Enumerate the registry IDs.** Parse the canonical registry source (the permission-definitions file, the flag manifest, the event-type enum) into the full ID list — not the UI's copy of it.
2. **For each ID, find an enforce-mode call site.** Grep/trace for the enforcement helper invoked with that ID (`checkPermission('<id>')`, `requireFlag('<id>')`, string-keyed dispatch included — trace the helper's callers, not just the literal ID).
3. **Fail on any ID with no enforce-mode call site.** Log-only / shadow-mode consumers do not count as enforcement (see below). The failure message names the decorative IDs so the fix is per-entry.

Keep the check registry-driven so a newly added entry is covered the moment it lands; a hand-maintained allowlist of "known-wired" IDs recreates the drift the check exists to catch.

## Shadow-mode: the legitimate carve-out

Log-only (shadow-mode) wiring is a legitimate rollout state ONLY while it is **declared and time-bounded**: the shadow phase is named in a plan or ADR, carries an expiry or flip obligation, and someone owns flipping it to enforce. A shadow-mode entry with no flip obligation is vaporware — "we'll enforce it later" with no mechanism is the canonical vaporware deferral. A drift check may whitelist declared shadow-mode entries, but each whitelist row must cite its declaration and expiry.

## The two verification-time paths this enables

- **`agents/functionality-verifier.md` — the config-control protocol (per-task, forward).** On `Verification: full` tasks that claim a control governs behavior, the verifier exercises the control at ≥2 values the spec claims produce DIFFERENT behavior and observes the GOVERNED surface, not the settings page. Fires inside the blocking runtime-verification Stop chain.
- **`agents/functionality-auditor.md` — the registry-vs-callsite sweep (standing surfaces).** The auditor enumerates every registry entry on an audited surface as an auditable element and def-use traces each to an enforce-mode call site, routing every decorative verdict through the Chesterton's-fence / indirect-consumption checklist first.

## Cross-references

- `docs/failure-modes.md` FM-038 — Vaporware: decorative config control (renders but does not change behavior).
- `doctrine/vaporware-prevention.md` — the compact this file backs.
- `agents/functionality-verifier.md` — Config-control protocol (the per-task checked path).
- `agents/functionality-auditor.md` — registry-vs-callsite sweep (the standing-surface audit path).
