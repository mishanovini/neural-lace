# Runbook: nl-issue (cross-project self-improvement capture)

<!-- last-verified: 2026-07-05 (doctor-checked) -->

**What it is.** The ONE capture point for harness friction/ideas noticed in
ANY project, on this machine. Writes to a single machine-wide ledger so
feedback scattered across repos lands in one reviewable place instead of
evaporating in chat (constitution §5: "Harness friction or defects noticed in
ANY project: one line via `nl-issue.sh "<what>"`").

**The one command:**

```bash
bash adapters/claude-code/scripts/nl-issue.sh "<one line describing the friction/idea>"
```

Other verbs:

```bash
bash adapters/claude-code/scripts/nl-issue.sh --list [--untriaged]
bash adapters/claude-code/scripts/nl-issue.sh --triage <n> <backlog|task|wontfix> "<ref-or-reason>"
bash adapters/claude-code/scripts/nl-issue.sh --digest-feed   # what E.1's digest consumes
```

**Where its output lands.** `$HOME/.claude/state/nl-issues.jsonl` — one JSON
line per entry (`ts`, `project`, `session`, `text`, `count`, `triage_status`,
`triage_ref`, `triaged_ts`). Machine-local by construction (lives under
`$HOME`, not any single repo), which is what makes it cross-project.

**How it surfaces.** The session-start digest (`session-start-digest.sh`)
reads `--digest-feed`'s output once per session and shows an untriaged count +
oldest-entry age when non-zero. Nothing is silently dropped — an untriaged
backlog is visible every session until triaged.

**Triage.** `--list` prints every entry with its 1-based index; `--triage <n>
<verb> <reason>` stamps that entry `backlog` (goes to `docs/backlog.md`),
`task` (a plan already claims it — cite the plan), or `wontfix` (with a
substantive reason — bare "wontfix" with no reason is a placeholder, not a
disposition).
