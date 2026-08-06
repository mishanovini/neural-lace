# Cross-machine handoff — harness enforcement, the end-to-end process, and cockpit truth

Written 2026-08-06 from **Office_PC**, master `e246feeb`, for a Claude session on the **laptop**
or the **Mac mini** with zero context from the originating conversation.

Every claim is tagged **PROVEN** (independently re-verified by an adversarial verifier whose
default verdict was "refuted") or **OPEN** (not established — do not upgrade without doing the
work). Claims that an earlier draft got wrong are marked **CORRECTED**, with the wrong version
shown, because the wrong version may already have been repeated to you.

## Getting this file

`git pull` on master in the neural-lace checkout.

**PROVEN — the Mac mini is on a wip branch, not master**, so `git pull` alone will not deliver
this file there. Check first:

```bash
cd <your-neural-lace-checkout> && git rev-parse --abbrev-ref HEAD
git fetch origin master && git log --oneline -1 origin/master
```

If you are not on master, read the file from the fetched remote rather than switching branches
and disturbing in-flight work:

```bash
git show origin/master:docs/handoffs/2026-08-06-cross-machine-process-and-cockpit-handoff.md
```

---

# WORK QUEUED FOR THIS MACHINE (added 2026-08-06, operator-directed)

The operator explicitly delegated the three items below to a machine other than Office_PC,
because Office_PC is near its weekly token ceiling. Claim one by announcing it, do it, and
push to master. Items are ordered by value.

## Q1 — Design and build Stage 0: interpret-and-approve before design

**This is a standing operator directive that was never built at any layer.** Do not treat it as
a nice-to-have.

The operator's words, 2026-08-04 and restated 2026-08-06: *"I want you to always interpret my
requests and expand upon them to provide what you believe is your full understanding of what it
is that I am trying to accomplish. I then want you to share that back with me for me to modify
or approve before that gets turned into an initial design."*

What exists already, and must be read before designing:
- [`docs/designs/end-to-end-process.md`](../designs/end-to-end-process.md) defines this as
  **Stage 0 — Intent capture**, and its own honest-status table marks Stage 0 **"NO — being
  designed"**, not firing. That document is the design context; this work is its Stage 0.
- [`docs/plans/archive/intended-functionality-stage-0-2026-07-30.md`](../plans/archive/intended-functionality-stage-0-2026-07-30.md)
  is COMPLETED and builds the Intended-Functionality statement format plus its anti-restatement
  gate — but it contains **no share-back-for-approval step**. Verified by grep: there is none.
  So the format exists; the approval handshake does not.
- The **elaboration layer** on the operator-directives register is the same idea already built
  for *standing directives*: an optional `elaboration` object (intent, requirements,
  anti_patterns, applies_when, worked_example) rendered behind an *"Interpretation — correct me
  if wrong"* banner, shipping `reviewed_by: pending-operator` so no sign-off can be claimed.
  **Reuse this shape** — it is operator-approved and already proven. It lives on branch
  `worktree-agent-a25c1bcde68d67a0b` (commits `579b25bc` + `28608138`); if master's
  `docs/operator-directives.md` already contains OD-024, the merge landed and it is on master.

The gap to close: the same interpretation-and-approval handshake, applied to **any request**,
firing **before** a design is authored — not only to standing directives after the fact.

Author the design first and bring it to the operator before writing code. That is both the
correct process and a demonstration of the feature itself.

**Named residual to resolve while you are in this code:** the elaboration layer's
`doctrine-jit.sh` register walk is a hot path with a nominal <50ms budget. Its timing was
measured on Office_PC under heavy concurrent load — the *unmodified* code itself ran 45–65ms
against a quiet-machine baseline of 23–39ms, and the new code averaged 71.3ms across ten runs.
The delta is roughly 12–30ms but the measurement is not trustworthy. **Re-measure on your quieter
machine** and report a clean number. If it is genuinely over budget, that is a real defect to
fix, not a rounding error — this hook runs on every matching tool call.

## Q2 — Second-principal verify and merge the plan-inventory fix (the cockpit sync fix)

Branch `fix/cross-machine-plan-inventory-single-derivation`, built on Office_PC in worktree
`.claude/worktrees/wf_4671371c-69c-2`. **It is not pushed** — Office_PC must push it before you
can see it; if `git ls-remote origin` does not list it, ask.

What it does: the cockpit and the cross-machine exporter derived the plan inventory from two
different sources (the cockpit scanned `docs/plans/`; the exporter folded the ask registry, which
had 2 `plan_linked` records against hundreds of plans). The scan moved into `derive-lib.js` and
both consumers now call the **same function object** — verified by `===` identity, not by
comment. Cockpit and export agree at 99 plans, set-equal.

Three adversarial verifiers already ran on Office_PC: one CONFIRMED, two DOWNGRADE. **Do not
re-do that review.** Your job is second-principal verification — the same checks run by someone
who did not build it — plus the merge. Re-run every suite yourself and confirm these:
export-state 19/0, roadmap-routes 165/0, server 181/0, cockpit 593/0, peer-view 41/1 (#14 is a
pre-existing test-isolation leak), coord-sync 27/2 (pre-existing).

Known costs, disclosed rather than discovered: exporter wall time 0.476s → 6.579s, and
coordination-repo growth of roughly 6 MB/week across three hosts. A remediation round on
Office_PC is bounding these; check the branch head before assuming they are still open.

**This also closes gated-pipeline Task 8's second-principal review requirement**, which is the
one thing Office_PC structurally cannot do for itself.

## Q3 — The live `/api/asks` 500 (cockpit landing view is blank)

**PROVEN on master `24ccc3f1`.** `/api/asks` returns HTTP 500 against real data because
`server.js:1243-1246` turns any payload-schema failure into a 500, and three separate
diagnostics fire:
1. `unknown field (not in allowlist): $.peers.entries[0].plans[0].plan_doc.path` —
   `payload-schema.js` `LANDING_ALLOWED_KEYS` lists `plan_doc` but not its `{project, path}`
   members.
2. `gate/hook identifier leaked at ...plan_slug (matched /[a-z0-9_-]*-gate\b/i)` — the denylist
   matches plan slugs, which are filename stems that legitimately name mechanisms.
3. `$.groups[8].asks[0].summary` matches `/\.sh\b/i` on `"harness-doctor.sh"` — an ask summary
   legitimately naming a script.

The Office_PC remediation fixes all three; verify on your machine that `/api/asks` returns
`ok:true` **against a real running server with real data**, not by unit assertion. When you
change the denylist, prove what it still catches — construct a payload with a genuine
harness-internal leak and confirm it is still rejected. The denylist exists for a reason.

**The root cause that let this hide, and the more valuable fix:**
`server/server.selftest.js` **crashes at line 893** with
`TypeError: Cannot read properties of undefined (reading 'asks')` after 61 PASS / 8 FAIL — so
every scenario after it, including **S64 at line 1663 which tests exactly this**, has never run.
A suite that dies midway looked like a suite that was fine. Make a crashed suite fail loudly
with a count of scenarios that never executed. That defect class is the subject of Part D.

---

## Part A — Check your CLI version before trusting any gate

**What happened on Office_PC.** The `claude` CLI printed:

```
<your-home>\.claude\settings.json
└ hooks
  └ TaskCreated: Invalid key in record

Files with errors are skipped entirely, not just the invalid settings.
```

(The real banner prints your absolute home path; elided here because this file ships in the
harness repo, which must not carry machine-identifying paths.)

This is severe when it happens, because **all 81 hook commands live in
`~/.claude/settings.json`** across 10 event keys — the repo carries no project-level hooks
(`neural-lace/.claude/settings.json` does not exist; `.claude/settings.local.json` holds only
permissions). One rejected key disables every gate, every reviewer dispatch, every Stop check,
and every SessionStart hook in that client.

### CORRECTED — this is already resolved on Office_PC, and the obvious fix is wrong

An earlier draft of this handoff said the harness "is currently disabled in every CLI session"
and implied the `TaskCreated` key should be removed from the template. **Both were wrong.**

**PROVEN.** The rejecting binary was CLI **2.1.71** (installed 2026-03-06), whose settings schema
is `partialRecord(enum(Xp), …)` with a 21-entry event list that omits `TaskCreated`. A zod
`invalid_key` on a record is ERROR severity and 2.1.71 has no unknown-key sanitizer, so the whole
file was skipped. At **07:55 on 2026-08-06 the updater replaced the PATH binary with 2.1.223**.

All four modern clients on that machine — 2.1.223 (PATH), 2.1.221 (desktop app, the engine that
ran this session), 2.1.219, and the VS Code extension's bundled 2.1.221 — carry an **md5-identical
31-entry hook-event enum that includes `TaskCreated`**, plus a pre-validator that *strips* unknown
event keys with `severity:"warning"` and loads the rest of the file normally. Verified empirically
with a negative control: a deliberately bogus event key IS flagged; `TaskCreated` is not.

**Therefore: do NOT delete `TaskCreated` from `settings.json` or from
[`settings.json.template`](../../adapters/claude-code/settings.json.template).** It is a
first-class event in every current client, and removing it would drop a real validator.

**PROVEN — `TaskCompleted` was never invalid.** It is member 15 of the 21-entry enum even in
2.1.71. Only `TaskCreated` was ever rejected, and only by that stale binary.

### What you must actually check

The risk transfers to you: if your machine's CLI predates the sanitizer, **you have the outage
right now** and every "the harness enforced this" claim from a terminal session there is false.

```bash
# 1. Which client is on your PATH, and how old?
claude --version
ls -la "$(command -v claude)"

# 2. Does YOUR client accept the settings file? This is the authoritative test —
#    it asks the client rather than inspecting the JSON.
claude doctor 2>&1 | grep -iA3 'invalid settings' || echo "clean: no settings rejection"

# 3. How many hook commands would be lost if the file were skipped?
node -e 'const j=require(process.env.HOME+"/.claude/settings.json");const h=j.hooks||{};let t=0;for(const k of Object.keys(h)){const n=(h[k]||[]).reduce((a,e)=>a+((e.hooks||[]).length),0);t+=n;console.log(k+": "+n)}console.log("TOTAL="+t)'
```

Windows laptop: same commands in Git Bash; in PowerShell use `$env:USERPROFILE\.claude\settings.json`.

**Healthy:** step 2 prints nothing / "clean". **Broken:** an `Invalid settings` block naming a
hook event. **The fix in that case is to update the client, not to edit the JSON.** Note that
`claude doctor` exits 0 either way, so its stdout must be read — an exit-code check will always
say healthy.

### Two live defects that are NOT version-dependent

**PROVEN — dead hook wiring.** `~/.claude/settings.json` lines ~352 and ~370 wire
`bash ~/.claude/hooks/workstreams-state-gate.sh`, which does not exist (retired at Wave O.4).
`harness-doctor` already RED-fires on this (`RED wiring-resolves`). It cannot self-heal:
`merge_settings()` in
[`session-start-auto-install.sh`](../../adapters/claude-code/hooks/session-start-auto-install.sh)
is **additive-only** and has no removal path, so every session re-merges and nothing ever
subtracts. This needs a manual reconcile on each machine.

```bash
grep -n 'workstreams-state-gate' ~/.claude/settings.json
ls -la ~/.claude/hooks/workstreams-state-gate.sh   # expect: No such file
```

**PROVEN — the push-side funnel does not run in this repo.** The neural-lace checkout has a
**local `core.hooksPath` in `.git/config` pointing at `<repo>/.git/hooks`**, which overrides the
global adapter hooks path. `.git/hooks` contains no `pre-push`, so the adapter's pre-push
dispatcher never executes. Demonstrated with `GIT_TRACE=1 git hook run --ignore-missing pre-push`
(no process spawned by default; `run_command: adapters/claude-code/git-hooks/pre-push` only when
forced to the adapter dir). Two gates are genuinely unenforced as a result:
`pre-push-divergence-check.sh` and **`review-record-push-gate.sh` — the authoritative
review-coverage funnel, stage 8 of the process below.** Check your own checkout:

```bash
git config --local --get core.hooksPath ; ls .git/hooks/ | grep -v sample
```

---

## Part B — The end-to-end process and gates conversation

### The document

**[`docs/designs/end-to-end-process.md`](../designs/end-to-end-process.md)** (commit `73ddc9b4`,
2026-07-30). Ten stages from intent capture to merge+deploy, each with an actor, a firing
trigger, and a required input/output artifact; the handoff contract that lets each stage refuse
its input; the cherry-pick laundering problem and its resolution. **It contains no gate
inventory** — that gap is the work.

### Gate state (PROVEN at `e246feeb`)

```
$ node adapters/claude-code/scripts/blocking-budget-check.js
blocking session-event units: 16/14   → RED
agent-teams · command-safety · commit-boundary · concurrent-ownership-gate
dispatch-chain-gate · find-disk-scan-gate · gh-merge-canonical
local-edit-authorization · model-availability · model-pin · no-test-skip
parallel-dev-migration-naming · plan-edit-validator · spec-freeze
stop-verdict-dispatcher · wire-check
```

**Framing agreed with the operator:** the budget number is not a principle. It began at 12
(ADR 058 D5) and was raised to 13 then 14, **each time after being exceeded**. A ceiling that
moves when it binds is a logbook, not a constraint, so "16/14 RED" carries no information and
arguing the count is the wrong frame. The replacement frame is to map each gate onto a stage.

### Findings from that mapping (PROVEN, adversarially verified)

- **Four of 16 units guard no stage of the 0–9 pipeline** (25% of the budget spent outside the
  process): `find-disk-scan-gate` (Windows/MSYS resource hygiene), `local-edit-authorization`
  (machine-config safety), and `model-pin` + `model-availability` (two units sharing one hook,
  `model-pin-gate.sh`, at the agent-spawn boundary). Not necessarily wrong — but they are not
  process gates and should not be budgeted as if they were.
- **Ungated stages: FOUR on the desktop app** (stages 4 failure-mode analysis, 5 functionality
  verification, 6 code review, 8 funnel) — **SIX on the CLI** if that client rejects the settings
  file, since stages 0 and 2 lose their carriers too. The doc's "five of ten" is stale in both
  directions. **Any "fires deterministically" claim must name the client.**
- **Consolidation 16 → 13 is PROVEN safe** (reproduced `13/14 … GREEN`, exit 0) via the
  `UNIT_MAP` in `blocking-budget-check.js` only — *not* by merging hook files:
  `model-availability → model-pin` (same hook, wired once), and
  `no-test-skip → commit-boundary` plus `parallel-dev-migration-naming → commit-boundary` (both
  hard-gate on a git-commit regex then read `git diff --cached`, definitionally inside the commit
  boundary). Zero guarded handoffs lost.

### Two unfixed gate defects (both PROVEN)

- **`dispatch-chain-gate.sh:206`** advertises "re-run with `--waive`", but `--waive` parses only
  under the `--check-wip-limit` subcommand (`:232-234`) while the PreToolUse call sites
  (`:696`, `:707`) pass only the plan file and the live wiring supplies no argv. **The escape is
  unreachable from the surface that prints it** — and the gate's own false-positive justification
  rests on it. Deeper problem found during verification: even the full CLI form would not unblock
  the denied task, because the waiver is per-invocation and nothing persists it.
- **`harness-doctor.sh:8005`** sets `EXPLICIT_REPO_ROOT="${2:-}"` unconditionally while `:8105`
  honours `--no-cache` and `:8126` advertises it — so `--quick --no-cache` bypasses the cache
  **and** rebases the repo root onto the literal string `--no-cache`. Mechanically reproduced.

---

## Part C — Cockpit inconsistency across machines

### The sync is healthy. The payload is nearly empty.

**PROVEN.** `coord-sync.sh → export-state.js → coord-push.sh → coord-pull.sh` runs green:
`export_rc=0 push_rc=0 pull_rc=0`, commits from all three hosts within minutes of each other.
And the per-host exports carry 1–2 plans each against **301 plan documents on disk**.

### Root cause #1 — the plan-selection rule (PROVEN, verifier CONFIRMED)

`derivePlanRecords()` in
[`neural-lace/workstreams-ui/server/export-state.js:105-126`](../../neural-lace/workstreams-ui/server/export-state.js)
folds **the ask registry**, not the plan directory. `foldAskRegistry()` populates `plan_slugs`
solely from records with `record_type:"plan_linked"` (`derive-lib.js:275-277`).

`~/.claude/state/ask-registry.jsonl` on Office_PC contains **exactly 2 `plan_linked` records
across 1,241 lines / 106 asks**. The export therefore contains at most 2 plans *by construction*,
and the two slugs match by identity, not merely by count.

The sole writer is `ask-registry.sh cmd_link_plan`, called from `start-plan.sh:403` guarded by
`[[ -n "${ASK_ID:-}" ]]` — so any plan started without an ask id is never linked and can never
be exported. **Meanwhile the cockpit derives its plan list by scanning `docs/plans/` on disk.**
Two independent derivations of one fact; that is the defect.

### CORRECTED — "every plan record is hollow" was wrong

**PROVEN.** The laptop's export carries a **fully populated** record (real repo, real
`plan_doc`, 18 tasks, progress 18/18), and the Mac's `review-independence` record carries 4
tasks. The population path demonstrably works end to end. Office_PC's two records are hollow for
a specific reason: both slugs are attached to sentinel ask ids (`"none"`) and **have no plan file
anywhere on disk**. That distinction is what isolates the failure modes — treat the earlier
blanket claim as retracted.

### Root cause #2 — silent absence (PROVEN, downgraded to an observability defect)

`derive-lib.js:574`'s `(planTasks || [])` launders an unresolvable *or* damaged plan file into a
task list byte-identical to a genuine zero-checkbox plan, and `aggregatePlanProgress` then
fabricates a healthy `0/0` that the exporter ships with rc 0. This is not why Office_PC's records
are empty, but it is why the emptiness looks healthy.

**REFUTED — an earlier draft blamed the Mac's `plan_doc: null` on the missing gitignored
`config/projects.json`.** That is false: `config/projects.js:119` sets the neural-lace entry
unconditionally before any config read. The reproduced cause is the exporter's module location
diverging from the canonical repo root (the projects map is keyed on a `__dirname`-derived root).

### Diagnostics for your machine

POSIX; on the Windows laptop run these in Git Bash.

```bash
# 1. Coordination clone present and current?
cd ~/claude-projects/workstreams-coordination && git log --oneline -5

# 2. What is YOUR machine publishing?
node -e 'const j=require("./plan-export/"+require("os").hostname()+".json");
console.log("plans:",j.plans.length,"sessions:",j.sessions.length);
console.log(JSON.stringify(j.plans[0]||null,null,1))'

# 3. THE DECIDING NUMBER — how many plan_linked records exist locally?
grep -c '"record_type":"plan_linked"' ~/.claude/state/ask-registry.jsonl

# 4. Against how many plans on disk?
ls <your-neural-lace-checkout>/docs/plans/*.md | wc -l

# 5. Is the sync cadence alive?
tail -5 ~/.claude/state/coord-sync/cycles.log
```

**Healthy:** step 3 is within range of step 4. **Broken (expected):** step 3 returns a
single-digit number against hundreds in step 4 — the same defect, confirmed on your machine.
Step 2's plan count should equal step 3 exactly; if it does, the diagnosis is reproduced.

If step 5 is empty or stale, your sync cadence is not running. On Office_PC it runs inside the
`NL-Maintenance` daemon rather than the `NL-CoordSync` scheduled task. Mac scheduling differs —
see [`install-maintenance-task-darwin.sh`](../../adapters/claude-code/scripts/install-maintenance-task-darwin.sh).

### What travels and what does not (PROVEN)

| Travels | Does not travel |
|---|---|
| git master: `adapters/claude-code/**` (146 hooks, 105 scripts, agents, doctrine, manifest, `settings.json.template`), all `docs/**`, **and the cockpit server code** `neural-lace/workstreams-ui/**` — so the exporter fix ships this way | `~/.claude/settings.json` — rebuilt per machine by the additive merge |
| the `workstreams-coordination` repo: hostnames, session records, and the near-empty plan payload above | `~/.claude/state/**` (324 entries) — **including the ask-registry the exporter reads** |
| | `~/.claude/local/**` — accounts and machine config |
| | `neural-lace/workstreams-ui/config/projects.json` — gitignored |
| | memory files; scheduled tasks / launchd jobs |

Git master is a **manual-pull** transport — nothing delivers the exporter fix automatically.
And **do not assume paths match across machines**: the laptop's checkout is at a different
filesystem path than Office_PC's. Resolve via `adapters/claude-code/hooks/lib/nl-paths.sh`,
never by hardcoding.

---

## Part D — The standing design principle (operator directive, 2026-08-06)

> **Make the wrong state unrepresentable, instead of detectable.** Prefer doing it right the
> first time over adding reviewers and checkers that find it afterward and tax every session.

Every defect here is the same shape — **one fact with two homes, allowed to disagree**, or **an
empty value allowed to exist and travel**:

| Defect | The duplicated fact | Proactive fix |
|---|---|---|
| unreachable `--waive`, swallowed `--no-cache` | the flag, in the message and in the parser | emit the message **from the parser's own table** |
| `TaskCreated` rejection | valid hook events, in the client and in our hand-typed template | **generate** the template's keys from the client's own list, which `claude doctor` prints |
| exporter ships 2 of 301 plans | the plan inventory, from the ask registry AND from a disk scan | one derivation, read by both |
| model chain not applied | the chain in `model-policy.json` vs. the model each agent gets | dispatch reads the chain; no second copy |

Each right-hand fix **removes** code rather than adding a gate — which matters with the budget
already RED.

### A worked example of holding this to evidence

The first control proposed for this class was a static check: extract every flag a script prints
and assert the script parses it. Prototyped over the real tree — 206 files, 21,876 emitted lines,
161 candidate flags — it found **7 violations, of which 0 were true positives, and it caught
neither golden scenario.** Both `--waive` and `--no-cache` *are* parsed; they fail on
**reachability**, not on absence of a parser. The check was discarded rather than shipped with an
impressive-looking number.

What survived, all as non-blocking `harness-doctor` predicates adding nothing to the budget:
an **advertised-escape reachability** check (catches the `--waive` defect at
`dispatch-chain-gate.sh:206`), a **positional-collision** check (catches the `--no-cache` defect
at `harness-doctor.sh:8005`; 18 candidates tree-wide), and a **zero-yield event detector** — of
31 event types declared in `observability-consumer-map.json`, 8 have never fired, of which one
(`soft-counter` / `tool-call-counter.sh`) is genuinely dead code with no caller anywhere.

A proposed **call-site parity** check measured 57 failures but verification traced most to
parser bugs in the prototype; it is **OPEN / HYPOTHESIZED**, not a result.

---

## Status of the originating session (Office_PC)

- master == origin/master == `e246feeb`; live harness byte-identical to repo (116/116 hooks,
  102/102 scripts) **on that machine** — verify yours independently.
- [`docs/plans/gated-pipeline-master-2026-08.md`](../plans/gated-pipeline-master-2026-08.md)
  (design: [`docs/designs/gated-pipeline-master-2026-08-03.md`](../designs/gated-pipeline-master-2026-08-03.md)):
  24 of 25 tasks verified. The remainder needs a **second-principal review runner** — a review
  executed on a machine other than the one that built the work. **That is a job for your
  machine**, and the one piece the originating session cannot do for itself.
- **Fable's weekly quota is exhausted** (100%, resets Sat 08:00). Do not pin `model: fable`.
  The declared chain is `["fable","opus"]`; the resolver that walks it is built and tested
  (72/72) but not yet on master.

**OPEN, in priority order:** remove the two dead `workstreams-state-gate.sh` wirings and give
`merge_settings()` a removal path; restore the pre-push funnel (`core.hooksPath`); give the plan
inventory a single derivation; land the three surviving doctor predicates; apply the 16→13
consolidation; fix `--waive` reachability and `--no-cache`.
