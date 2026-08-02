# Branch disposition sweep — 2026-08-01

Independent classification of all 74 local branches ahead of master with a non-empty
content diff. Produced during the takeover session; the fan-out phase of the workflow
silently produced zero classifications (args passed as a JSON string, not an object),
which the synthesis agent CAUGHT and reported rather than synthesizing air — it then
re-derived all 74 itself. Every row cites re-runnable evidence. master tip at time of
sweep: a99007f.

# Stale-branch disposition — neural-lace (`C:/Users/misha/dev/Pocket Technician/neural-lace`)

> **Input note (honesty, §1):** the orchestrator handed me **zero** classifications (`[]`) from the 8 classifiers — the fan-out produced nothing. Rather than synthesize air, I re-derived every classification myself from the repo. So this is not a synthesis of eight opinions; it is one independent pass over all **74** local branches that are ahead of `master` with a non-empty content diff. Every row below cites evidence I ran in this session. `master` tip = `a99007f2ae2e99e67d67e9f3587d5f508459e9b7` (2026-08-01).

## Summary

**55 SUPERSEDED · 1 ABANDONED · 6 SALVAGE-VALUE · 12 ACTIVE-LANE · 0 UNCLEAR.** The single most important thing: **this repo's squash-merge habit makes "non-empty diff" almost meaningless** — 40 of the 74 branches have ≥90 % of their added lines already present verbatim on master, and 24 have a commit subject that appears in master's log under a different SHA (e.g. `build/roadmap-t7` → master `133b8f4`, identical subject). The real yield of the whole sweep is **six branches** holding work master genuinely lacks — and two of them (`feat/sweep-squash-merge-visibility`, `docs/reclamation-proposal-amendment`) are *the tooling and the written policy for doing exactly this sweep safely*, sitting unmerged. Salvage those first. Two calls I downgraded during verification: `claude/dreamy-mclaren-6f2ac3` (looked landed; master still carries the exact broken `jq` pattern it fixes) and `feat/event-driven-heartbeat` (its tree-nesting half landed, its `--beat` half did not). One call I nearly got wrong in the other direction: `claude/lucid-lederberg-d0e3ae` looked like unlanded work because master's plan says "still-unfixed", but the fix itself landed as `55ba1bb (#104)` — it is SUPERSEDED, not salvage.

## Classifications

| branch | disposition | reason (evidence) |
|---|---|---|
| backup/angry-hypatia-pre-reset | SUPERSEDED | 93 % of adds on master; subjects landed as `b51dab5 (#93)`, `6f91966 (#92)`; plan now `docs/plans/archive/nl-issues-sweep-2026-07-09.md` |
| build/adr061-phase1a-supervisor-core | SUPERSEDED | master `4fd706a` "adr061-P1a: supervisor core … (#98)"; master's `session-resumer.sh` function list is **identical** to the branch's (40/40) |
| build/adr061-phase1b-hoists-tick | SUPERSEDED | `scripts/health-tick.sh` on master is a superset (same 6 funcs + `_ht_resolve_sweep_root`); 97 % adds present |
| build/askp1-t12 | SUPERSEDED | master `411aa5a` same subject; plan archived (`docs/plans/archive/ask-rooted-workstreams-p1.md`) |
| build/cockpit-health-int | ACTIVE-LANE | branch currently checked out in this worktree; tip 2026-07-29 |
| build/nl-issue-22-56-doctor | SUPERSEDED | master's `obs-cockpit-fresh` check rewritten & extended — `harness-doctor.sh:1321,1443,1453,1474,1476` |
| build/nl-issue-23-35-38-63-doctrine | SUPERSEDED | 84 % of adds on master (orchestrator-pattern doctrine text) |
| build/nl-issue-24-sete-audit | SUPERSEDED | 100 % of added lines already on master |
| build/nl-issue-31-install-sync-skills | SUPERSEDED | 95 % of adds on master (1 novel line) |
| build/nl-issue-42-dispatcher-verdict | SUPERSEDED | 100 % of adds on master |
| build/nl-issue-45-53-end-manifest | SUPERSEDED | 100 % of adds on master; `_em_gap_resolved_by_recheck` present in master's `end-manifest.sh` |
| build/nl-issue-47-25-denylist | SUPERSEDED | 100 % of adds on master |
| build/nl-issue-48-digest-s2-sandbox | SUPERSEDED | 100 % of adds; `UNRESOLVED_GAPS_PATH` at `session-start-digest.sh:674` |
| build/nl-issue-49-consumer-map-info | SUPERSEDED | its single added line is on master |
| build/nl-issue-55-cockpit-lock | SUPERSEDED | 99 % of adds on master |
| build/nl-issue-59-prtemplate-gate | SUPERSEDED | 100 % of adds on master |
| build/roadmap-t2 | SUPERSEDED | all three subjects on master: `6769bbb`, `a948676`, `a567d59` |
| build/roadmap-t3 | SUPERSEDED | master `d50f6fc` same subject; `roadmap-routes.js` since rewritten through Round 17 (`91ce0a3`, `366a88b`) |
| build/roadmap-t3-int | SUPERSEDED | master `cf91268` same subject |
| build/roadmap-t4 | SUPERSEDED | master `62bb460` same subject; 96 % of 1 593 adds on master; `inbox-routes.js` shipped |
| build/roadmap-t5 | SUPERSEDED | master `ac461e2` same subject; `requests-routes.js` shipped |
| build/roadmap-t7 | SUPERSEDED | master `133b8f4` same subject; `coord-sync.sh` + `config/people.js` shipped |
| build/roadmap-t8 | SUPERSEDED | master `9f68fac` same subject |
| build/sweep-verifier-flips | SUPERSEDED | 100 % of adds on master (checkbox flips + evidence) |
| build/sweep-verifier-flips-2 | SUPERSEDED | 100 % of adds on master |
| build/wave-o-hb-perf-v2 | SUPERSEDED | same optimisation landed differently: master `d44d257` "batch heartbeat-classify forks … 15.8s → 3.9s" + `a524474`; `_OD_TRANSCRIPT_INDEX` referenced at `session-heartbeat-lib.sh:358` |
| claude/angry-hypatia-45f5b0 | SUPERSEDED | same S2 sandbox fix on master via the `build/nl-issue-48` variant |
| claude/busy-kare-3dba65 | ACTIVE-LANE | **open PR #106**, blocked on org billing per `docs/operator-todo.md:20`; deleting the branch would close the PR |
| claude/distracted-haslett-05e4f8 | SUPERSEDED | master `a94fbce` same subject (`agent:false` keep-alive fix) |
| claude/dreamy-mclaren-6f2ac3 | **SALVAGE-VALUE** | master still has the pre-fix `command -v jq` pattern in `emit_digest_feed`/`write_backoff_state` |
| claude/fable-continue | SUPERSEDED | 100 % of adds on master; handoff doc present |
| claude/goofy-faraday-5177b0 | SUPERSEDED | duplicate of the keep-alive fix landed as `a94fbce` (different impl, same defect) |
| claude/infallible-montalcini-26a8f0 | **SALVAGE-VALUE** | `docs/reviews/2026-07-13-operator-todo-fixture-pollution.md` absent from master; 0 % overlap |
| claude/interesting-lederberg-3ad04d | **ABANDONED** | 1-line manifest removal never adopted; master's `manifest.json` still lists `hooks/lib/` helpers in 32 places, and the helper file exists |
| claude/lucid-lederberg-d0e3ae | SUPERSEDED | master `55ba1bb (#104)` same subject; plan preserved at `docs/plans/deferred/ps51-emdash-parse-hotfix.md`; 100 % of adds on master |
| claude/modest-satoshi-150d97 | SUPERSEDED | plan archived on master with E.9 intact (`docs/plans/archive/nl-overhaul-program-2026-07.md`) |
| conv-tree-v4-accordion-adoption | SUPERSEDED | its entire target tree `neural-lace/conversation-tree-ui/` no longer exists (renamed `43be5c8`, unified `e99e4b6`); the design record survives at `docs/discoveries/2026-05-27-conv-tree-v4-design.md` |
| docs/reclamation-proposal-amendment | **SALVAGE-VALUE** | master's proposal is 92 lines, branch's is 216 — the amendment never landed; commits are ancestors of `feat/sweep-squash-merge-visibility` |
| feat/event-driven-heartbeat | **SALVAGE-VALUE** | tree-nesting half landed (`3da37b1`, plan archived); `--beat` event-driven mode absent from master's `workstreams-emit.sh` (only `--heartbeat` polling remains) |
| feat/sweep-squash-merge-visibility | **SALVAGE-VALUE** | master's `worktree-hygiene-sweep.sh` has **zero** matches for squash-merge visibility (`PROVEN-MERGED`/`merged_pr`/`squash`); 2 % overlap |
| findings-019-wig-scope-touch | SUPERSEDED | `docs/decisions/059-session-end-enforcement-redesign.md` on master; 88 % of adds present |
| fix/context-watermark-window-autodetect | SUPERSEDED | master `a335f5b (#105)` same subject |
| fix/spawn-cascade-guard | SUPERSEDED | master `a322365 (#91)`; 98 % of 996 adds; all 25 introduced functions on master |
| salvage/orphaned-worktree-guard-wip | SUPERSEDED | 94 % of adds on master; stranded-work detection live (70 files mention `stranded`) |
| salvage/pre-push-pii-patterns-20260702 | **SALVAGE-VALUE** | master's `pre-push-scan.sh` has no PII/SSN/allowlist matches; `sensitive-patterns-allowlist.local.example` and `docs/harness-improvements/001-*.md` both absent |
| worker-D.4 | SUPERSEDED | master `d6c0176` "Wave D: gate consolidation (#73)"; 99 % of 1 120 adds; all 24 funcs present |
| worker-E.2 | SUPERSEDED | E.2 landed as `6aa156a` (+`f2039dc`, `deddd86`); master isolates inline via `HARNESS_SELFTEST` (`workstreams-emit.sh:101-118`) and ships `purge-selftest-pollution.sh` — only the DRY `lib/selftest-sandbox.sh` extraction is unlanded |
| worker-E.6 | SUPERSEDED | `needs-you.sh` on master with later fixes (`ca35249`, `86e8264`); 97 % of adds |
| worktree-agent-a00fbc1bd925baace | ACTIVE-LANE | emitter lane, tip 2026-08-01 (~40 min old) |
| worktree-agent-a036322efcea02340 | SUPERSEDED | master `a82ebf3` + `ecc52a2` same subjects; plan archived |
| worktree-agent-a11b98bce0f07f613 | ACTIVE-LANE | runtime-verification lane, tip 2026-08-01 (~68 min old) |
| worktree-agent-a22a9a4ee6ce39659 | SUPERSEDED | master `23cd526` same subject; 100 % of adds |
| worktree-agent-a26ae095b53606699 | SUPERSEDED | master `4152838` + `295d703` same subjects |
| worktree-agent-a280503e1c0a385fc | SUPERSEDED | both gates on master and further evolved (`cfc6bc8` observe-first rollout); 99 % of adds |
| worktree-agent-a3225b2d87a13ab91 | SUPERSEDED | `scripts/supervisor-tick.sh` on master; 99 % of 1 103 adds |
| worktree-agent-a372ea9cef18a5dbd | SUPERSEDED | Round-9 checkpoint; master is at Round 17 (`91ce0a3`, `366a88b`); 93 % of adds |
| worktree-agent-a39847eeb52c6d3f6 | ACTIVE-LANE | tip 2026-07-29 (emitter lane); content 95 % on master (`8918f4e`, `8913dfd`) — safe to delete once the lane closes |
| worktree-agent-a3986fbd787c103c4 | SUPERSEDED | master `14568b2` + `26379e5` same subjects |
| worktree-agent-a3f79ba88292adf39 | ACTIVE-LANE | tip 2026-07-30 (<3 days); content landed as `f1217da` |
| worktree-agent-a44b06f2ae82cd4b8 | ACTIVE-LANE | tip 2026-07-30 (<3 days); all 7 subjects already on master |
| worktree-agent-a6b34650801e4ba38 | ACTIVE-LANE | tip 2026-07-29; landed as `4a3d264` |
| worktree-agent-a8d3f6ae277d5488b | ACTIVE-LANE | tip 2026-07-30 (<3 days); both subjects on master (`ca35249`, `86e8264`) |
| worktree-agent-a8e37f2caa55c1c76 | SUPERSEDED | Task 1 landed from a *different* branch: `cockpit-roadmap-redesign-evidence-t1.md` — "Builder commit `598dae8` (branch build/roadmap-t1) — cherry-picked to master as `f1488de`"; plan checkbox `- [x] 1.` |
| worktree-agent-aa7149eaa7e32e928 | SUPERSEDED | master `18e8f65` "R11 hierarchy renderer … (builder squash + orchestrator gap-closures)"; 90 % of adds |
| worktree-agent-aa850e02179a3efb0 | ACTIVE-LANE | learning-ledger lane, tip 2026-08-01 (~30 min old); 95 % novel |
| worktree-agent-ab441c9dc74ab7299 | ACTIVE-LANE | tip 2026-07-29; all 4 subjects on master (98 % adds) |
| worktree-agent-ac4dfd4e5725c3424 | SUPERSEDED | 98 % of 1 084 adds; `remap-placeholder-ask-events.sh` on master |
| worktree-agent-acab3cbc962b059b1 | ACTIVE-LANE | tip 2026-07-29; landed as `fd48741` (94 % adds) |
| worktree-agent-ace19d4a1edcb2958 | SUPERSEDED | master `b3ba920` + `79e2b47` same subjects; 99 % of adds |
| worktree-agent-adb7aab5b7756bd4c | SUPERSEDED | master `ccdd03d` same subject; `plan-parse.js` shipped |
| worktree-agent-adb983a17a95d7a09 | SUPERSEDED | 97 % of adds on master (ask SLA verbs in `ask-registry.sh`, `estate-brief.sh` panel) |
| worktree-agent-adf0ab260b6e3056b | SUPERSEDED | master `c72e9f3` same subject; 100 % of 652 adds |
| worktree-wf_d88db003-879-5 | SUPERSEDED | identical tip commit `a4b6876` to `salvage/orphaned-worktree-guard-wip`; 94 % of adds on master |

## DELETE-ELIGIBLE (SUPERSEDED + ABANDONED)

```
backup/angry-hypatia-pre-reset
build/adr061-phase1a-supervisor-core
build/adr061-phase1b-hoists-tick
build/askp1-t12
build/nl-issue-22-56-doctor
build/nl-issue-23-35-38-63-doctrine
build/nl-issue-24-sete-audit
build/nl-issue-31-install-sync-skills
build/nl-issue-42-dispatcher-verdict
build/nl-issue-45-53-end-manifest
build/nl-issue-47-25-denylist
build/nl-issue-48-digest-s2-sandbox
build/nl-issue-49-consumer-map-info
build/nl-issue-51-coldreader-negation
build/nl-issue-55-cockpit-lock
build/nl-issue-59-prtemplate-gate
build/roadmap-t2
build/roadmap-t3
build/roadmap-t3-int
build/roadmap-t4
build/roadmap-t5
build/roadmap-t7
build/roadmap-t8
build/sweep-verifier-flips
build/sweep-verifier-flips-2
build/wave-o-hb-perf-v2
claude/angry-hypatia-45f5b0
claude/distracted-haslett-05e4f8
claude/fable-continue
claude/goofy-faraday-5177b0
claude/interesting-lederberg-3ad04d
claude/lucid-lederberg-d0e3ae
claude/modest-satoshi-150d97
conv-tree-v4-accordion-adoption
findings-019-wig-scope-touch
fix/context-watermark-window-autodetect
fix/spawn-cascade-guard
salvage/orphaned-worktree-guard-wip
worker-D.4
worker-E.2
worker-E.6
worktree-agent-a036322efcea02340
worktree-agent-a22a9a4ee6ce39659
worktree-agent-a26ae095b53606699
worktree-agent-a280503e1c0a385fc
worktree-agent-a3225b2d87a13ab91
worktree-agent-a372ea9cef18a5dbd
worktree-agent-a3986fbd787c103c4
worktree-agent-a8e37f2caa55c1c76
worktree-agent-aa7149eaa7e32e928
worktree-agent-ac4dfd4e5725c3424
worktree-agent-ace19d4a1edcb2958
worktree-agent-adb7aab5b7756bd4c
worktree-agent-adb983a17a95d7a09
worktree-agent-adf0ab260b6e3056b
worktree-wf_d88db003-879-5
```

56 branches. Two operational cautions before running a delete: several of these names are still **checked-out worktrees** (`git worktree list` first — `git branch -D` on a checked-out branch fails, and pruning the worktree is the real prerequisite), and `worktree-wf_d88db003-879-5` shares its tip commit with the retained-by-name-only `salvage/orphaned-worktree-guard-wip` (both delete-eligible, no dependency).

## SALVAGE — backlog-ready rows

- **SWEEP-SQUASH-MERGE-VISIBILITY-01** — `feat/sweep-squash-merge-visibility` (tip `e7e10f3`, 2026-07-17) holds ~470 lines giving `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` the ability to recognise a branch whose commits were **squash-merged** (PROVEN-MERGED via merged-PR lookup: `load_merged_prs`, `lookup_merged_pr`) plus the 2026-07-17 harness-review fixes (1 Critical, 3 Major, 2 Minor). Master's sweep has none of this — which is precisely why this manual classification pass was necessary. Highest-value salvage in the set.
- **RECLAMATION-PROPOSAL-AMENDMENT-01** — the same branch (and, identically, `docs/reclamation-proposal-amendment`, whose 2 commits are ancestors of it) carries an unlanded **124-line amendment** to `docs/proposals/2026-07-08-worktree-branch-reclamation.md`: root-cause 1 refuted, operator decisions (keep the approval channel; expiry **surfaces**, never destroys) and 7 edge cases learned from the first real sweep. Master's copy is still the un-amended 92-line original. Salvaging the sweep branch covers both; `docs/reclamation-proposal-amendment` may be deleted **only after** that salvage lands.
- **PREPUSH-PII-PATTERN-CLASS-01** — `salvage/pre-push-pii-patterns-20260702` (tip `0a44e69`) adds a PII pattern class (~131 lines) to `adapters/claude-code/hooks/pre-push-scan.sh`, a `sensitive-patterns-allowlist.local.example`, and `docs/harness-improvements/001-stop-gate-reflective-escalation.md`. None of it is on master; the pre-push scanner still has no PII/SSN class. Security-relevant.
- **RESUMER-JQ-BROKEN-NOT-ABSENT-01** — `claude/dreamy-mclaren-6f2ac3` (tip `fbbfc19`) fixes a real latent defect master still has: `session-resumer.sh` trusts `command -v jq` as proof jq *works*, so a present-but-broken jq silently drops digest-feed lines and **truncates** `write_backoff_state`'s file (`jq … > "$path"` truncates before failing). The fix builds the line first, falls back to manual JSON on any failure.
- **EVENT-DRIVEN-HEARTBEAT-BEAT-MODE-01** — `feat/event-driven-heartbeat` (tip `9ff78f6`, 2026-06-02) holds an unlanded `--beat` event-driven heartbeat mode for `workstreams-emit.sh` (+ beat self-tests + a frozen spec) intended to replace the polling scheduled task; master still polls via `--heartbeat`. Treat as a design to re-evaluate against today's `session-heartbeat.sh`/`health-tick.sh`, not a patch to cherry-pick — the file has diverged 9 weeks. (Its other half, workstreams tree real-nesting, already landed as `3da37b1`.)
- **OPERATOR-TODO-FIXTURE-POLLUTION-REVIEW-01** — `claude/infallible-montalcini-26a8f0` (tip `2bb52d0`) holds a 64-line review, `docs/reviews/2026-07-13-operator-todo-fixture-pollution.md`, correcting an earlier misdiagnosis of operator-todo fixture pollution and describing the cleanup. Absent from master; cheap to preserve, and the correction is the kind of thing that gets re-learned expensively.

## UNCLEAR

None. Every branch resolved on citable evidence. Two judgment calls worth naming so the operator can overrule cheaply:

- `claude/interesting-lederberg-3ad04d` (ABANDONED) is a **one-line** manifest edit removing `hooks/lib/sessionstart-singleflight.sh` from a `hooks[]` array. I called it abandoned because master keeps `hooks/lib/` entries in 32 places and the referenced file exists, so the removal contradicts the shipped convention rather than closing a gap. If `harness-doctor.sh` actually flags that entry, this flips to SALVAGE — one doctor run settles it.
- The four ACTIVE-LANE branches with tips of exactly 2026-07-29 (`a39847…`, `a6b346…`, `ab441c9…`, `acab3cb…`) sit on the "< 3 days" boundary. Their content is 94-98 % on master already, so they cost nothing to keep and can be swept in the next pass.
