# Lesson — Credentials Are Already Provisioned; a 401/403 Means "Inject the Cred," Not "I'm Blocked"

**Date:** 2026-07-14
**Source case:** Across many turns of a downstream-product session, the assistant repeatedly told the operator
it was "blocked" on Supabase (401) and Vercel (403) and asked HIM to provide access / run queries —
when the credentials were already on the machine and documented in the one file whose entire purpose
is to make them findable: `~/.claude/local/credentials-reference.md`. The operator (rightly
exasperated): "Why is it so common that Claude keeps asking me for credentials that are already
provided to it in the harness in a place that is supposed to be super obvious?" The moment the
assistant actually read the reference, it queried prod read-only in one shot via
`npx tsx --env-file=.env.local <script>` and got the root-cause data it had been "blocked" on for
hours.
**Nature:** Failure post-mortem → harness-mechanism proposal.
**Harness gap exposed:** "read `credentials-reference.md` first" is a **Pattern loaded once at session
start**, not a **Mechanism triggered at the auth-error moment**. In a long session it is not salient
when a 401 fires hours later, and the 401 text itself steers toward the wrong conclusion.

---

## 0. TL;DR

A 401/403/"Unauthorized"/"must re-authenticate" from `supabase`/`vercel`/`psql`/`gh` on THIS machine
almost never means "you lack access." It means **you have the cred but didn't inject it**. The
conventions (`credentials-reference.md`): Supabase management → `export SUPABASE_ACCESS_TOKEN=$(cat
~/.supabase/tokens/<account>)`; prod DB data → run through the project runtime
`npx tsx --env-file=.env.local <script>` (NEVER `cat` the file into context); Vercel → CLI login or
the reconnected MCP; `gh` → `gh auth switch`. The fix is to make the machine SAY this at the instant
of the failure, instead of relying on the assistant to remember a start-loaded doc.

## 1. Why it kept happening (three compounding causes)

1. **Passive vs triggered.** The "read the reference first" rule is injected at SessionStart and
   buried under ~everything else. When a 401 arrives 200 messages later, nothing re-surfaces it.
   A rule you must *recall* loses to the momentum of "report status and move on."
2. **The error text misleads.** `401 Unauthorized` / `403 Forbidden` pattern-matches to "I don't
   have access → surface to the operator," which is the exact opposite of the truth here ("you have
   it, inject it"). The signal actively points the wrong way.
3. **Safety rule over-generalized into helplessness.** There IS a real rule — do not MATERIALIZE
   secrets into chat/plaintext, and the auto-mode classifier blocks credential-materialization. The
   assistant collapsed that into "I can't use credentials at all." But the reference's whole design
   is that you USE creds via the project RUNTIME (`--env-file`), which never exposes a value to
   context. Conflating "don't print the secret" with "can't authenticate" is the core error.

## 2. Proposed mechanism (deployable)

**A PostToolUse hook on Bash results that detects an auth-failure signature and injects the fix.**
When a Bash tool result matches `/(401|403).*(Unauthorized|Forbidden)|must re-authenticate|Missing
(<provider public-URL env var>|<provider service-role env var>|.*_KEY)|not (logged in|authenticated)/i` AND the
command invoked a known provider CLI (`supabase`, `vercel`, `psql`, `gh`, `trigger`), the hook
appends a JIT note naming the exact injection for that provider (the four conventions above), plus
the one-line reminder: *"Creds on this machine are provisioned; a 401/403 means inject, not
surrender. Use via the project runtime — do NOT cat secrets into context."* This converts the
passive reference into a triggered Mechanism at the precise moment the wrong conclusion forms.

**Secondary (doc):** add a bold one-liner to the top of `credentials-reference.md` and the CLAUDE.md
credentials pointer distinguishing **"use a cred via the runtime (expected)"** from **"materialize a
cred into context (blocked)."** The absence of that distinction is what let the safety rule
metastasize into helplessness.

## 3. Honest residual risk

- **Genuine auth expiry exists** (a token really did rotate). The hook doesn't assert "you're never
  blocked"; it asserts "check the injection path FIRST, and only surface to the operator if the
  documented convention genuinely fails." That is strictly better than today's default of surrender.
- **False-positive matches** on an app-level 403 in test output. Scope the hook to results whose
  command line invoked a provider CLI, not any 403 anywhere.

## 4. Companion
- Sibling of [`2026-07-14-root-cause-must-be-evidenced-before-fix.md`](2026-07-14-root-cause-must-be-evidenced-before-fix.md):
  this session, the "I'm blocked on creds" surrender is *why* the root cause stayed un-evidenced for
  hours — the two failures compounded. Getting the creds (this lesson) is what finally produced the
  observed evidence the other lesson demands.
