# Workstream-memory ecology — compact
> Enforcement: Pattern — self-applied
> Applies: every time a fact is observed and needs a place to live

Match capture to tier by scope of relevance, not by where the fact was
discovered:

- **T1 — Global behavioral** (`~/.claude/rules/constitution.md`,
  `~/.claude/doctrine/`): only if EVERY future session in EVERY project
  benefits. A universal discipline or a user-stated "always/never." Not project
  architecture, not time-bounded state.
- **T2 — Per-project persistent** (`docs/decisions/`, `docs/plans/`,
  `docs/findings.md`, `docs/backlog.md`): specific to one repo's product; a
  future session in THAT repo needs it.
- **T3 — Per-project auto-memory** (`~/.claude/projects/<slug>/memory/`):
  operator-as-collaborator facts scoped to one project, too operational to
  commit (per-project preferences, per-project feedback).
- **T4 — Per-session ephemeral** (SCRATCHPAD.md, in-conversation context): the
  current session's working state only; cleared at `/clear`/`/compact`.

**Cross-workstream gap (acknowledged, not solved).** A fact spanning 2+ but not
all repos has no dedicated tier yet. Stopgap: land the durable artifact in the
canonical repo for that workstream; place a one-line pointer (not a replica) in
each consumer repo's T2 naming the canonical artifact.

**Anti-pollution:** don't let one workstream's noise reach another's context.
SCRATCHPAD names ONE active workstream; per-project memory stays scoped to its
project; don't pull cross-project context into a session "in case it's
relevant" — that IS the pollution this discipline prevents.
