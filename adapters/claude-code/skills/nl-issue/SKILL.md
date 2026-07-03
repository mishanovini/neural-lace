---
name: nl-issue
description: Capture a one-line note of harness friction, a defect, or a self-improvement idea noticed in ANY project on this machine, into the machine-wide cross-project ledger consumed by the weekly triage loop. Use whenever a gate misfires, a hook's message is confusing or wrong, a doctrine file is stale, a script is missing a case it should handle, or any other "the harness itself should be better here" moment surfaces mid-session — in this repo or any other checkout on the machine. This operationalizes the constitution's §5 pointer ("Harness friction or defects noticed in ANY project: one line via nl-issue.sh"). Do not use for product/app bugs unrelated to the Claude Code harness itself — those go to the project's own backlog.
---

# nl-issue

Any harness friction noticed in ANY project, on this machine, gets one line
via `bash ~/.claude/scripts/nl-issue.sh "<what happened, in one line>"` — do
not just mention it in chat and move on (constitution §5 is explicit: "Chat
is ephemeral; anything not in a file is lost"). The script appends
`{ts, project, session, text}` to a single machine-wide ledger at
`~/.claude/state/nl-issues.jsonl`, so it works identically no matter which
repo the current session is rooted in, and it is what makes the friction
visible to the weekly triage loop instead of disappearing into a transcript.

## When to invoke

Invoke the moment friction surfaces — same turn, not "later":

- A gate blocked with a confusing or wrong message.
- A hook's self-test passed but its real-world behavior surprised you.
- Doctrine/docs contradicted what you just observed in the repo.
- A script lacked a case it obviously should have handled.
- Any "the harness should be better here" thought that isn't worth stopping
  the current task to fix immediately.

Do NOT invoke for:

- Product/application bugs unrelated to the Claude Code harness — those
  belong in the project's own backlog/issue tracker, not this ledger.
- Anything already tracked (this session already filed the same note, or an
  existing backlog/plan entry already covers it — check first, or just
  rely on the script's own 24h dedup for accidental repeats).

## How to invoke

```bash
bash ~/.claude/scripts/nl-issue.sh "<one line describing the friction>"
```

That is the entire capture step — one line, one command, in whatever project
directory the session happens to be in. No flags needed for the common case.

Related verbs (for triage sessions, not routine capture):

```bash
bash ~/.claude/scripts/nl-issue.sh --list                 # everything ever captured
bash ~/.claude/scripts/nl-issue.sh --list --untriaged     # only what needs triage
bash ~/.claude/scripts/nl-issue.sh --triage <n> backlog "<backlog-id-or-ref>"
bash ~/.claude/scripts/nl-issue.sh --triage <n> task "<plan-task-ref>"
bash ~/.claude/scripts/nl-issue.sh --triage <n> wontfix "<one-line reason>"
```

`<n>` is the 1-based entry number shown by `--list`. Triaging stamps that
entry in place with a disposition and reference/reason — it never deletes
history, so the ledger stays a durable record of what was noticed and what
became of it.

## What happens after capture (you don't need to do this part)

- The session-start digest surfaces an untriaged count + oldest-age line
  whenever there is something to say (silent when the ledger is empty or
  fully triaged).
- More than 5 untriaged entries, or the oldest untriaged entry aging past 7
  days, escalates: an extra digest line plus an idempotent dated backlog
  entry (`NL-ISSUES-TRIAGE-<yyyymmdd>`) prompting a triage pass.
- The weekly harness KPI report renders a triage section from the same
  ledger (untriaged list + this week's conversions).

## Example

Mid-session, a Stop-hook gate's block message referenced a doctrine file
that had been renamed two waves ago:

```
bash ~/.claude/scripts/nl-issue.sh "pre-stop-verifier block message cites doctrine/old-name.md which no longer exists"
```

That's it — capture, then continue the original task. Triage happens later,
in its own pass, against the accumulated ledger.
