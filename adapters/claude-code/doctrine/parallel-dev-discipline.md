# Parallel-Dev Discipline — compact
> Enforcement: migration-naming-gate.sh (Practice 7); Practices 5–6 operator-executed once via documented `gh` commands; rest Pattern — self-applied. Full: doctrine/parallel-dev-discipline-full.md
> Applies: any repo worked from multiple machines or concurrent sessions.

Trunk-based CI/CD defaults — eight practices:
1. Short-lived branches off master; integrate same-day; too big to land same-day → split it.
2. one authoritative remote (`origin`) — all pushes go there; mirrors update one-way from it; never push the same branch to two remotes.
3. pull-before-work (`git fetch && git pull --ff-only` at session start), push-before-switch (commit + push before any machine or branch switch), never two machines live on the same branch at once.
4. PR-even-solo: land through a PR, not direct master pushes — the PR is where CI, the merge queue, and branch protection apply. Substantial work and anything touching migrations, always.
5. Branch protection on master — PRs required, checks green and up-to-date with base. Operator runs the documented `gh` commands once per repo; agents never run them (shared-contract change).
6. merge queue on master — serialize approved green PRs one at a time, re-testing each against post-merge trunk; catches "green in isolation, broken in combination".
7. NEVER a shared incrementing counter for names that must be unique-and-ordered across machines. Migrations use a UTC timestamp prefix: `$(date -u +%Y%m%d%H%M%S)_<slug>.sql`. migration-naming-gate.sh BLOCKS newly-added bare-integer-prefixed migrations at commit; existing integer-named ones are grandfathered.
8. One item = one branch = one machine — claim the item on the shared work board (workstreams UI / backlog / active plan) before building, so a second machine sees the claim before duplicating the work.

Failure classes prevented: silent migration skip on duplicate numbers, diverged remotes, uncommitted-work loss on machine switch, duplicate diagnosis on two machines.
