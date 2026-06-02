# 048 — Auto-install harness changes on SessionStart (source-of-truth = fetched origin/master ref)

- **Date:** 2026-06-02
- **Status:** Accepted
- **Stakeholders:** Misha (operator across multiple machines), harness maintainers
- **Supersedes / relates:** complements `install.sh` (the one-time install ceremony); relates to `settings-divergence-detector.sh` (warns about the same drift this hook acts on) and `cross-repo-drift-warn.sh` (cross-repo drift). Decision 011 (cloud-remote harness inheritance) bounds where this applies.

## Context

The harness lives in a git repo (`neural-lace`); the live, executed copy lives at `~/.claude/`. `install.sh` copies repo → live, but it is a **one-time per-machine ceremony**, not a continuous sync. When a new hook/script/`settings.json` change merges to master, machines that `git pull` get the *repo source* updated while their *live `~/.claude/`* stays stale until someone manually re-runs `install.sh`. Observed consequences: the `broadcast-active-session.sh` hook sat on master for days without reaching this machine's live dir; Office_PC lacks every recent harness update; every machine requires manual install ceremony per NL change.

`install.sh` also carries a footgun (the HARNESS-GAP-44 family): it rebuilds live from **whatever checkout it runs in**. Run it from a stale checkout, or one sitting on a feature branch, and it *downgrades* live.

We want continuous, surgical, low-risk propagation: every session, bring live's executable surfaces into sync with the freshest canonical master, without clobbering legitimate machine-local state, and without the footgun.

## Decision

Ship a SessionStart hook `session-start-auto-install.sh`, wired first in the SessionStart `""` matcher, that on every session:

1. **Discovers** the canonical NL checkout (config `~/.claude/local/nl-checkout-path.txt` → candidate paths → cwd walk-up).
2. **Reads canonical file content from the fetched `origin/master` ref** (`git show origin/master:<path>`), fallback local `master`, fallback `HEAD` — after a best-effort bounded `git fetch origin master`. **Not the working tree.**
3. **Syncs `hooks/*.sh` + `scripts/*.sh` master-wins**: install if missing, install if content differs (comparing modulo CRLF/LF), backing up the prior live copy first.
4. **Additive-merges missing canonical `settings.json` hook-entries** (matched by `.command`; validate-before-atomic-swap; never removes/reorders live entries; self-wires its own entry at the front of SessionStart).
5. Logs to `~/.claude/state/auto-install-log-<ts>.txt` + a one-line stderr summary. Idempotent, fast in steady state, exits 0 always.

### Sub-decision A — Source from the fetched `origin/master` ref, not the working tree

The install footgun is "rebuild live from whatever checkout you run in." A SessionStart hook runs in checkouts that are frequently on feature branches (the machine that built this hook was permanently on `reconverge`, 63 commits ahead but 1 behind origin/master). Reading `git show origin/master:<path>` is **branch-independent** and always installs the freshest *fetched canonical* content. It sidesteps the footgun **by construction** (preemptive — Rule 6) and composes with the deliberate "don't auto-pull" posture (we never touch the working tree, so local uncommitted work is never at risk).

- *Rejected:* read the working tree — downgrades live on a stale/feature checkout (the footgun).
- *Rejected:* require checkout-on-master, else skip — the machine is permanently on a feature branch; would never sync.

### Sub-decision B — master-wins for hooks/scripts, additive-merge for settings.json

Per `rules/harness-maintenance.md`, canonical hooks/scripts have **no legitimate machine-local drift** (edit repo → sync to live; never keep divergent live copies). So a differing live hook is, by definition, stale — canonical always wins (after a backup). Only `settings.json` and `~/.claude/local/` carry legitimate machine-local state, so `settings.json` gets a **conservative additive-only** jq-merge that never removes a live entry, with **validate-before-atomic-swap** so corruption cannot arise.

- *Rejected:* additive-merge everything — would preserve a stale live hook forever, defeating the purpose.
- *Rejected:* blast `settings.json` from template — clobbers machine-local hook additions + local config (that is `install.sh --replace-settings`, intentionally explicit-only).

### Sub-decision C — compare content modulo CRLF/LF

`git show` emits LF blobs; `install.sh` `cp`s CRLF working-tree files on Windows (`core.autocrlf` checkout). A byte-`cmp` would treat those as perpetually-different and the two installers would re-update each other's files on every run. The hook compares modulo `\r`, so it only re-installs on a **genuine** content change.

### Sub-decision D — v1 scope: executable surfaces only; no prune

v1 syncs `hooks/` + `scripts/` + `settings.json` wiring. It does NOT sync `rules/`/`agents/`/`templates/`/`docs/` (read-by-the-model, degrade gracefully when slightly stale) and does NOT prune live files removed from canonical (avoids deleting an intentionally-kept local file). Executable surfaces are where staleness *silently breaks enforcement* — a missing hook just doesn't fire. Widening + prune deferred to v2.

## Consequences

**Enables:** future harness changes propagate to every machine's live `~/.claude/` automatically on next session; no per-machine `install.sh` for routine hook/script/settings changes. After one bootstrap install per new machine, the machine stays current — including future versions of the hook itself.

**Costs / residuals:**
- **Bootstrap:** the hook can't run on a brand-new machine until it is itself present + wired in live. One `install.sh` run per new machine lands it; every subsequent change self-propagates. Honest bootstrap, not a false promise (Rule 7).
- **Genuine cloud sessions** (`claude --remote`, Routines) load project `.claude/` only, not `~/.claude/` (Decision 011) — out of reach, as for every `~/.claude/` hook.
- **First run per machine** does a one-time line-ending normalization burst (CRLF→LF) for hooks `install.sh` last wrote; steady-state is a no-op thereafter (verified live: run 1 = 19 installed + 78 updated; run 2 = 0/0/111 unchanged).
- **v2 residuals (filed in backlog):** widen the synced directory set; prune live files removed from canonical; prune accumulated `.backup-auto-install-*` dirs (install.sh's pruner uses a different prefix).

## Refutation criterion

If the hook were *not* idempotent (a steady-state session reported nonzero installs/updates), the design would be refuted — it would churn live on every session. **Observed:** after the initial sync, two consecutive live runs reported `0 installed, 0 updated, 111 unchanged, 0 settings-entries added` — idempotency confirmed. The 13-scenario `--self-test` locks the behavior (including CRLF-identical-not-updated and feature-branch-reads-master).
