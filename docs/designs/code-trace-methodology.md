# Code-trace methodology — what a static trace actually catches

**Status:** design / operating procedure. **Written:** 2026-07-30.
**Basis:** all 14 defects below are real, shipped in this repo 2026-07-30/31. Each row
was re-derived at the commit where the defect existed and, where marked EXECUTED, the
pre-fix code was **run**, not read.

## The thesis under test

Operator, 2026-07-31, verbatim:

> "This is not a failure of reading code; it is a failure of a biased reader. Those are 2
> different things, and that is the whole point of using adversarial agents. A diligent
> review agent should be perfectly capable of catching these problems by tracing the code
> and determining exactly what would happen in every circumstance… trace the code all the
> way through to determine exactly what it would do in every condition and failure case.
> It is only in the cases where there is code that is not ours where we cannot determine
> everything we need."

This document tries to falsify that. It does not succeed. **Measured result: 12 of 14
defects are fully statically traceable; the remaining 2 each reduce to ONE command.**
Detail and the honest caveats are in §b.

Method note: bash traces were executed on **both** `/bin/bash` 3.2.57 and
`/opt/homebrew/bin/bash` 5.3.15 by absolute path, sequentially. Node traces used
`/opt/homebrew/bin/node` v25.6.1. Harness scripts live in
`/private/tmp/claude-501/-Users-misha-Claude-neural-lace/a3fcb6ea-7fab-460d-8506-e2a655016f09/scratchpad/`
(session-scoped; the commands that regenerate them are in each row).

---

## (a) Per-defect table

Verdict key: **YES** = a pure static trace reaches the defect with no runtime observation.
**PARTIAL** = the symptom is statically provable but one external fact is required to
name the cause. **NO** = not reachable statically.

### 1. Drag no-op — `performDrop` used `planRowContainer()` for both ends

| | |
|---|---|
| **Pre-fix** | `634cd12` · fixed by `b66f7e1` |
| **Site** | `neural-lace/workstreams-ui/web/roadmap.js:1188-1192` (guard), `:1102-1104` (helper) |
| **Verdict** | **YES** — EXECUTED |

**Trace, exactly:**

```bash
git show 634cd12:neural-lace/workstreams-ui/web/roadmap.js > /tmp/r.js
grep -n "planRowContainer" /tmp/r.js          # 1102 def, 1171/1188/1189 calls
sed -n '1102,1104p;1169,1194p' /tmp/r.js
```

Resolve what the helper returns — `rowEl.closest('.rm-project-group, .rm-children.rm-phase-series, .rm-tree')`,
i.e. the **group**, not the row. Then prove the guard `draggedRow !== targetRow` is
dead **from the function's own precondition**, with no DOM knowledge required:

1. `:1171` `container = planRowContainer(targetEl)`; `:1172` `rows = siblingPlanRows(container)`; `:1173` `ids = rows.map(...)`.
2. `:1174` `computeReorderSteps` returns non-null **only if** `ids.indexOf(draggedId) !== -1 && ids.indexOf(targetId) !== -1` (`:1159-1161`), and `:1175` `if (!move) return;`.
3. So past `:1175`, **both** rows are descendants of `container`.
4. `.closest()` from either therefore returns `container` — the intervening `.rm-phase-step` matches none of the three selectors.
5. ⟹ `draggedRow === targetRow` **always** ⟹ guard false ⟹ `insertBefore` never runs.

**Executed** (`trace1_drag.js`, extracts the real `planRowContainer` body from the
634cd12 blob and runs it against a synthetic DOM with real `closest` semantics), over
all 3 layouts × both `before` values:

```
layout=A .rm-project-group > .rm-phase-step > row  before=true  | draggedRow===targetRow: true | guard: false | order A,B,C -> A,B,C | MOVED: false
… 6 of 6 combinations identical …
```

**Why it was missed:** the fix commit `b66f7e1` says "PROVEN by live probe at :7733
(**not by reading**)". Reading was sufficient. No external fact needed.

---

### 2. Green "running" chip on task rows — membership treated as a truth claim

| | |
|---|---|
| **Pre-fix** | `ebc9a12` · fixed by `366a88b` |
| **Site** | `neural-lace/workstreams-ui/web/roadmap.js:724` |
| **Verdict** | **YES** — EXECUTED |

**Trace, exactly — one grep:**

```bash
git grep -n "live_sessions" ebc9a12 -- neural-lace/workstreams-ui
```

Two consumers derive "running" from the same field, and they **disagree**:

- `server/roadmap-routes.js:1357` (fixed in this very commit): `(child.live_sessions || []).some((s) => s && s.status && s.status.value === 'running')` — requires **member status**.
- `web/roadmap.js:724` (untouched): `if (item.live_sessions && item.live_sessions.length)` — merely **non-empty**.

The same commit's own comment at `server/roadmap-routes.js:1345-1346` *names the bug
class* — "the ORIGINAL check here was `child.live_sessions.length` alone — merely
NON-EMPTY, independent of whether those sessions are alive, stalled, or crashed" — while
leaving an instance of that exact class live in a sibling file.

**Executed** (`trace2_chip.js`, extracts the real `taskSpanCell` from the ebc9a12 blob):

```
FALSE-GREEN one STALLED session       members=[stalled]   anyMemberRunning=false greenChip=true
FALSE-GREEN one CRASHED session       members=[crashed]   anyMemberRunning=false greenChip=true
FALSE-GREEN one UNKNOWN-status session members=[unknown]  anyMemberRunning=false greenChip=true
FALSE-GREEN session with NO status object members=[NO-STATUS] anyMemberRunning=false greenChip=true
FALSE-GREEN stalled session AND is next  members=[stalled] anyMemberRunning=false greenChip=true
FALSE GREEN CHIPS: 5 of 9 cases
```

The fix commit found **four** client sites this way (724 / 813 / 1333 / 1979). The grep
finds all four; three needed the change, one was audited and deliberately left.

---

### 3. `task_started` emitted per prompt MENTION

| | |
|---|---|
| **Pre-fix** | `d0430ca^` · fixed by `d0430ca` |
| **Site** | `adapters/claude-code/hooks/workstreams-emit.sh:2712` (header), `:2658-2678` (free-text scrape), `:2958-2960` (the emit decision) |
| **Verdict** | **YES** — EXECUTED on both bash versions |

**Trace, exactly — a trust-boundary walk.** The input is a dispatch **prompt**: arbitrary
operator/agent free text. Ask what the parser requires of it:

```bash
git show d0430ca^:adapters/claude-code/hooks/workstreams-emit.sh > /tmp/e.sh
sed -n '2709,2735p' /tmp/e.sh    # _extract_nl_attribution
sed -n '2657,2679p' /tmp/e.sh    # _extract_plan_slug / _extract_task_id
sed -n '2949,2976p' /tmp/e.sh    # _emit_dispatch_provenance — the emit decision
```

Three unanchored reads of untrusted text:

- `:2712` `grep -oE 'NL-ATTRIBUTION:.*'` — **no `^`**. Any line *containing* the header matches.
- `:2660` `grep -oE 'docs/plans/[A-Za-z0-9_.-]+\.md'` — first plan path *anywhere*, including prose, code fences, diffs, negations.
- `:2675` falls back to the first bare `Task N` *anywhere*.

`:2959` `[[ -z "$slug" ]] && return 0` is the **only** suppression. A non-empty slug from
any position emits.

**Executed** (`trace3_attr.sh` + `trace3b_scrape.sh`), identical on 3.2.57 and 5.3.15:

```
MENTION mid-sentence (prose quoting the header)  -> widget|9|builder|1
MENTION inside a markdown code fence             -> widget|9|builder|1
MENTION in a NEGATION                            -> widget|9|builder|1
   (5 of 6 mention shapes attribute as a real dispatch)

MENTION: reviewer asked to READ the plan   -> EMIT task_started plan=widget task=3
MENTION: prose reporting a PAST dispatch   -> EMIT task_started plan=widget task=3
MENTION: a plan named only to be ARCHIVED  -> EMIT task_started plan=widget task=1
MENTION: NEGATION (do not touch)           -> EMIT task_started plan=widget task=4
   (7 of 8 scrape shapes emit a false task_started)
```

The re-fire half (PreToolUse walking the ledger from index 0) is the same trace applied
to lifetime: the replay gate's state file is `opened-${sid}.jsonl` (`:645`), and `rm -f
"$ledger"` at `:949` (`_run_on_stop`) plus the `--heartbeat` path (`:1120-1121`) delete
it — see Move 5 in §c.

---

### 4. Watchdog never armed — marker consumed by a script, written by nobody

| | |
|---|---|
| **Pre-fix** | `~/.claude/state/limit-resume/resume.sh` (machine-local, **never in this repo**) · superseded by `aa10a8a` + `334901d` |
| **Verdict** | **YES, with a scope precondition** (see caveat) |

**Trace, exactly — producer/consumer scan for a lever.** The consumer is a file-presence
test at the top of `resume.sh`. The question is one grep over the **deployed artifact
set**: *who writes this path?*

```bash
grep -rn "<marker-path>" ~/.claude/ /Users/misha/Claude/neural-lace/adapters
# consumers: 1 (the test in resume.sh).  producers: 0.
```

Zero producers ⟹ the guard is permanently false ⟹ the body is unreachable. No external
fact, no runtime, no timing. This repo already **mechanizes** exactly this scan:
`adapters/claude-code/scripts/config-control-producer-scan.sh` (classifies every consumed
`NL_*` lever PRODUCED / MARKED / ALLOWLISTED / FLAGGED), built for the sibling case
`NL_PROTECTED_ORCHESTRATOR` (backlog HARNESS-GAP-57). And
`adapters/claude-code/doctrine/deterministic-process.md:50-55` Rule 3 names *this exact
defect* as its golden case: "the limit-resume watchdog's marker — consumed by a script,
written by nobody".

**Honest caveat — this is the one row where the trace surface, not the trace, is the
gap.** The defective file was generated machine-local and never version-controlled, so a
**repo-only** scan cannot see it: `config-control-producer-scan.sh` scopes to `hooks/` +
`scripts/` under the adapter. The lesson is not "tracing is insufficient" but "the trace
surface must be the DEPLOYED artifact set (`~/.claude/**` included), not the checkout".
Verified this session: the old `resume.sh` no longer exists (`ls ~/.claude/state/limit-resume/`
→ `armed/`, `log.txt` only), so this row is derived from the fix commits' own root-cause
statements plus the still-live doctrine golden case, **not** from re-reading the defective file.

---

### 5. `env: node` under launchd

| | |
|---|---|
| **Site** | LaunchAgent `ProgramArguments` pointing at a `#!/usr/bin/env node` script |
| **Verdict** | **PARTIAL** — one external fact; EXECUTED |

**Static half (free):** the shebang resolves `node` via `PATH`. The plist supplies no
`EnvironmentVariables.PATH`. Both facts are in files we own.

**The ONE external fact:** *launchd's default PATH for user agents excludes `/opt/homebrew/bin`.*
That is behaviour of code we do not own. **How to check it — two commands, no experiment:**

```bash
launchctl getenv PATH     # empty  -> no override; jobs get launchd's built-in default
command -v node           # /opt/homebrew/bin/node
ls /usr/bin/node /bin/node  # both: No such file or directory
```

**Executed** — reproduced the exact failure deterministically from those two facts:

```
$ env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin ./envnode.js
env: node: No such file or directory
exit=127
```

Fixed shape, live on this machine today —
`~/Library/LaunchAgents/local.neurallace.workstreams-cockpit.plist` uses the absolute
`/opt/homebrew/bin/node`, not a shebang script.

---

### 6. Inbox `file://` links silently blocked

| | |
|---|---|
| **Pre-fix** | `8ee5a5a^` · fixed by `8ee5a5a` |
| **Site** | `neural-lace/workstreams-ui/web/inbox.js:575,577` |
| **Verdict** | **YES** — EXECUTED. The browser fact was **already in the repo**. |

This is the most instructive row. It *looks* like it needs live browser observation. It
does not, because a prior fix **wrote the browser's behaviour into the source tree**.

**Trace, exactly — one grep:**

```bash
git grep -n "file://" 8ee5a5a^ -- neural-lace/workstreams-ui/web
```

Output at the pre-fix commit contains, simultaneously:

- `roadmap.js:937` — the recorded fact: *"the OLD `file:///` href was a DEAD link from this http-served page (confirmed live at :7733 — no navigation, no network activity on click)"*
- `app.css:1827` — the same fact again
- `inbox.js:575,577` — **unfixed**, identical idiom
- `asks.js:96,98` and `backlog.js:47,49` — **also unfixed**, identical idiom

The reviewer needs no browser: the repo already asserts that `file://` from this
http-served page is dead, and the grep shows three panes still emitting it.

**New finding, filed this session.** The same grep against **HEAD (`366a88b`)** shows
`asks.js` and `backlog.js` **still emit `file://` today** — only `roadmap.js` (Round 15)
and `inbox.js` (Round 17) were ever cured. Call-graph reachability confirmed to a real
DOM `href` in both: `asks.js:94-100 → :122-128` (`fa.href`), reached from `:484`, `:506`,
`:573`, `:732`; `backlog.js:45-56 → :484-492` (`openLink.href`). **Executed**
(`trace6_filehref.js`, real function bodies from the working tree):

```
DEAD-HREF asks.js absoluteLinkNode    -> file:///Users/misha/Claude/neural-lace/docs/backlog.md
DEAD-HREF backlog.js absoluteLinkHref -> file:///Users/misha/Claude/neural-lace/NEEDS-YOU.md
…
file:// anchors emitted from an http-served page: 6
```

Filed as `COCKPIT-DEAD-FILE-HREF-RESIDUAL-01` in `docs/backlog.md`.

---

### 7. Classifier hung — 0 of 114 classified

| | |
|---|---|
| **Site** | `adapters/claude-code/scripts/ask-registry.sh:513-521` (the fork), `:3036-3037` (its only test) |
| **Verdict** | **PARTIAL** — symptom fully static, cause needs one bounded probe |

**Statically provable, no runtime, two independent ways:**

1. **Outcome data.** One query over the state ledger proves the lane produced nothing:
   ```bash
   grep -c "amendment_candidate"   ~/.claude/state/ask-registry.jsonl
   grep -c "candidate_classified"  ~/.claude/state/ask-registry.jsonl
   ```
   At the time: 114 and 0. (Today, post-fix + backfill: **141 and 122** — the query is
   the same, the answer moved, which is what a working fix looks like.)
2. **The test seam is shape-only.** `:509-511` documents `AR_DRYRUN_ARGV=1` — "prints the
   argv instead of forking… the suite asserts the real invocation shape **without ever
   risking a live model call**" — and `:3036` asserts exactly that string. So *no test
   ever exercised the real binary*, which is statically visible and is defect 10's class.

**The ONE external fact:** *does `claude --model haiku -p`, invoked from a hook inside an
already-live Claude Code session, return promptly or hang?* That is third-party binary
behaviour. **How to check it — one bounded command:**

```bash
timeout 25 env -u CLAUDECODE claude --model haiku -p "ping" </dev/null; echo $?   # 124 = hung
```

A trace cannot tell you *hang* vs *fail-fast*; it **can** tell you the lane is untested
against the real binary and has produced zero output in 114 attempts — which is enough to
reject it without ever knowing why.

---

### 8. Cockpit outside the review surface

| | |
|---|---|
| **Site** | `adapters/claude-code/hooks/lib/review-record-gate-lib.sh:83-111` |
| **Verdict** | **YES** — EXECUTED on both bash versions |

**Trace, exactly — branch enumeration over a closed `case` list, plus one data query.**
The predicate is a `case` statement with a `*) return 1` default: the admitted set is
finite and readable. Enumerate it against the real file list:

```bash
# what the predicate admits, run against every tracked cockpit file
awk '/^rrg_in_surface\(\) \{/,/^\}/' adapters/claude-code/hooks/lib/review-record-gate-lib.sh > /tmp/f.sh
. /tmp/f.sh
git ls-files 'neural-lace/workstreams-ui/*' | while read -r p; do rrg_in_surface "$p" || echo "OUT $p"; done
```

And the corroborating data query the doctrine itself cites:

```bash
jq -r '.entries[].path' docs/reviews/records/index.json | grep -c workstreams-ui   # was 0 of 255
```

**Executed** (`trace8_surface.sh`), identical on 3.2.57 and 5.3.15, at HEAD:

```
tracked cockpit files IN surface : 28
tracked cockpit files OUT of surface: 54
  … 29 of the OUT files are behaviour-bearing .js/.html/.css, incl.
  state/reconciler.js, state/store.js, state/reducer.js, web/app.css, web/index.html
```

Pre-fix the two cockpit arms (`:92-93`) did not exist, so the IN count was **0**. The
residual above is already **named honestly** in
`adapters/claude-code/doctrine/review-before-deploy-full.md` — this row confirms the
named residual is accurate, it does not discover a new one.

---

### 9. Learning agents never fired — `/calibrate`, `harness-evaluator`

| | |
|---|---|
| **Verdict** | **YES** — EXECUTED |

**Trace, exactly — producer/consumer scan applied to the TRIGGER.** For any "runs
periodically" claim, enumerate the things that can fire it. There are exactly four on
this machine, all statically enumerable:

```bash
grep -n "harness-evaluator" adapters/claude-code/settings.json.template   # (nothing)
ls ~/Library/LaunchAgents/ | grep -iE "eval|calib|harness"                # (nothing)
crontab -l                                                                # no crontab for misha
ls adapters/claude-code/scripts/install-daily-harness-eval-task.ps1       # WINDOWS-only installer
```

Zero triggers on a macOS machine; the only installer is PowerShell. And the output side:

```bash
ls ~/.claude/state/calibration/     # No such file or directory
find ~/.claude/state/calibration -type f | wc -l   # 0
```

The directory the skill writes to **has never been created**. Same class as defect 4, and
again named by `deterministic-process.md:50-55` Rule 3 as its own golden case:
"`/calibrate` — zero entries ever."

---

### 10. Shape-only tests — `R17-DRAG-2` regexed source while the feature was dead

| | |
|---|---|
| **Site** | `neural-lace/workstreams-ui/web/cockpit.selftest.js:2467-2468` |
| **Verdict** | **YES** — MEASURED |

**Trace, exactly — read the assertion's predicate and ask what it is a function of.**

```js
ok('R17-DRAG-2 (…): performDrop moves the dragged row in the DOM OPTIMISTICALLY …',
  /performDrop[\s\S]{0,2000}?insertBefore\(draggedRow, targetRow\)[\s\S]{0,400}?sequentialMove\(/.test(roadmapJsNoComments));
```

The predicate is a function of **source text only**. It cannot distinguish "this code
runs and moves the row" from "this code is present and never executes" — which is exactly
defect 1. The suite's own replacement `R17-DRAG-3` (`:2470-2510`) says so in its header.

**Sweep for the class:**

```bash
grep -cE "\.test\((roadmapJs|roadmapJsNoComments|inboxJs|asksJs|backlogJs|src)\b" \
  neural-lace/workstreams-ui/web/cockpit.selftest.js     # 279
grep -c "^ok(" neural-lace/workstreams-ui/web/cockpit.selftest.js   # 437
```

279 regex-over-source occurrences against 437 top-level `ok()` assertions. (Indicator,
not an exact ratio — some assertions combine several `.test()` calls.) Suite state at
commit time: **cockpit.selftest.js 513 passed, 0 failed.**

---

### 11. Commit-gate stage-and-commit fail-open

| | |
|---|---|
| **Site** | `adapters/claude-code/hooks/pre-commit-gate.sh:158-172`, wired at `adapters/claude-code/settings.json.template:373` |
| **Verdict** | **YES** — EXECUTED on both bash versions |

**Trace, exactly — three static facts compose:**

1. **Event timing.** `settings.json.template:14` opens `"PreToolUse"`; `:387` opens
   `"PostToolUse"`. The gate's wiring sits at `:373`, i.e. **PreToolUse** — it runs
   *before* the Bash command executes.
2. **What it reads.** `:158` `git diff --cached --name-only --diff-filter=ACMR` — the
   index **as of hook time**.
3. **Failure direction.** `:159` `if [[ -n "$STAGED_PLANS" ]]` — empty ⟹ the whole
   plan-reviewer block is skipped ⟹ allow.

⟹ any command that stages *within the same tool call* presents an empty index at
decision time.

**Executed** (`trace11_index.sh`, uses the gate's own `:158` predicate verbatim in a real
git repo), identical on 3.2.57 and 5.3.15:

```
SHAPE A — separate calls:  index holds: docs/plans/sneaky.md
  -> plan-reviewer RUNS on: docs/plans/sneaky.md
SHAPE B — one compound call 'git add … && git commit -m x':
  index holds: ''  (empty)
  -> plan-reviewer SKIPPED (predicate empty) -> gate is a no-op
  committed? 1 commit(s) touching the plan.  the gate never saw it.
```

---

### 12. Push-gate bypass — `command -v jq` returns 0 when jq is absent

| | |
|---|---|
| **Site** | `adapters/claude-code/hooks/review-record-push-gate.sh:319` |
| **Verdict** | **YES** — EXECUTED on both bash versions |

**Trace, exactly — enumerate every early return and label each ALLOW or DENY.**

```bash
sed -n '312,331p' adapters/claude-code/hooks/review-record-push-gate.sh
sed -n '685,690p' adapters/claude-code/hooks/review-record-push-gate.sh   # dispatcher
```

`_rrpg_main` opens with **eleven** guards (`:315-330`), every one of the form
`… || return 0`. The dispatcher is `_rrpg_main "$@"; exit $?`, so `return 0` **is the
ALLOW verdict**. `:319 command -v jq >/dev/null 2>&1 || return 0` therefore converts a
missing dependency into a pass — and `PATH` is caller-controlled.

**Executed** (`trace12_jq.sh` — builds a shim dir containing only a `git` symlink and
runs the **real gate** against the **real repo**), identical on 3.2.57 and 5.3.15:

```
jq PRESENT   (normal operator PATH)  -> rc=1  BLOCK
jq ABSENT    (shim PATH, git only)   -> rc=0  ALLOW (push proceeds)
```

The gate genuinely blocks today and is genuinely defeated by a one-line `PATH` prefix.

---

### 13. Review verified the WORKTREE while the INDEX held the rejected draft

| | |
|---|---|
| **Site** | `adapters/claude-code/hooks/lib/review-record-gate-lib.sh:119-124`; cure at `review-record-commit-gate.sh:413-419` |
| **Verdict** | **YES** — EXECUTED |

**Trace, exactly — "what does this read?" against "what does the action commit?"**

```bash
sed -n '117,124p' adapters/claude-code/hooks/lib/review-record-gate-lib.sh
```

`rrg_blob_sha_of_file` is `git hash-object "$path"` — it hashes the **filesystem**.
`git commit` commits the **index**. Two different objects; nothing keeps them equal. The
fixed gate now reads `git rev-parse ":$path"` (`review-record-commit-gate.sh:419`) and its
own comment states the consequence: *"The reviewer staged unreviewed content, restored the
worktree to a covered blob, and the commit sailed through rc=0 — the gate attested to bytes
it never read."*

**Executed** (`trace13_index.sh`, real `rrg_blob_sha_of_file` body, real git repo):

```
approved blob:                    7a116f27…
rrg_blob_sha_of_file (worktree) : 7a116f27…    worktree matches approved? YES
git rev-parse :<path> (index)   : 7b2d66ce…    index    matches approved? NO
what git ACTUALLY committed     : 7b2d66ce…    committed == index? YES
committed content:  # REJECTED DRAFT — never reviewed
```

---

### 14. `deterministic-process.md` fabricated Enforcement header

| | |
|---|---|
| **Site** | `adapters/claude-code/doctrine/deterministic-process.md:57-68` |
| **Verdict** | **YES** — MEASURED |

**Trace, exactly — read the claim, then measure it.** Every clause in an Enforcement
header is a testable proposition.

```bash
python3 -c "import json;m=json.load(open('adapters/claude-code/manifest.json'));\
b=[e for e in m['entries'] if e.get('blocking') is True];\
print(len(b), sum('chokepoint' in e for e in b), sum('bypass_paths' in e for e in b))"
grep -n "chokepoint" adapters/claude-code/schemas/manifest.schema.json
grep -n "check_deterministic_process_proof" adapters/claude-code/hooks/harness-doctor.sh
```

At the time all three clauses were false in the same direction (0 of 39 units; schema
`additionalProperties:false` rejected the keys; no doctor check).

**Measured today** — the claim is *still* false, now in the **opposite** direction, which
the same three commands catch:

| Doctrine claim (`:59-62`) | Measured |
|---|---|
| "the schema rejects them" | **False** — `manifest.schema.json:180,185` define both as optional |
| "no doctor check exists" | **False** — `harness-doctor.sh:2450` `check_deterministic_process_proof`, called at `:3530` |
| "0 of 39 blocking units carry these fields" | 40 blocking units; **1** carries both |

And the enforcement is near-vacuous by construction: of 40 blocking units, **38** are on
the closed `DETERMINISTIC_PROCESS_GRANDFATHERED` list (`harness-doctor.sh:2473-2494`), 0
are date-exempt, leaving **2 in scope** — of which `review-record-push-gate` complies and
`intended-functionality-if-statement` declares neither. Already tracked by the open tasks
"Shrink grandfather list + restore deterministic-process.md header honestly" and "Backfill
chokepoint + bypass_paths for priority blocking units".

---

## (b) The honest tally

**12 of 14 fully statically traceable. 2 PARTIAL. 0 untraceable.**

| Verdict | Count | Defects |
|---|---|---|
| **YES** — pure static trace suffices | **12** | 1, 2, 3, 4\*, 6, 8, 9, 10, 11, 12, 13, 14 |
| **PARTIAL** — one external fact, each reducible to ONE command | **2** | 5 (launchd PATH), 7 (third-party binary hang) |
| **NO** — genuinely unreachable | **0** | — |

\* Defect 4 is YES on the trace and *scoped* on the surface: the artifact was machine-local,
outside the checkout. See its caveat.

**The thesis is stronger than the orchestrator credited.** Three specific corrections:

1. **"Needs a live browser" was wrong for defect 6.** It reads like the archetypal
   runtime-only defect. It is not: a *previous* fix had already written the browser's
   behaviour into `roadmap.js` and `app.css`, so one grep surfaces the recorded fact
   **and** the three unfixed siblings together. A fixed external behaviour, once
   observed, becomes a repo fact — and stays one.
2. **Four defects were fixed with "PROVEN by live probe, not by reading" (1, 2, 6, 7).**
   For 1, 2 and 6 the reading was fully sufficient; the live probe was how the defect was
   *noticed*, not what was *required* to find it. Conflating those two is precisely the
   "biased reader" failure the operator names.
3. **The corpus is dominated by one move.** Nine of fourteen (2, 3, 4, 6, 8, 9, 10, 12, 14)
   fall to *producer/consumer or admitted-set enumeration* — a grep plus a question about
   direction. These are not hard traces; they are cheap ones nobody ran.

**Where the thesis genuinely bites** (stated plainly, not softened): defects 5 and 7 turn
on behaviour of launchd and of the `claude` binary respectively. No amount of reading
*our* code determines them. But — §d — a trace still narrows each to a single closed
question with a one-command answer. That is categorically different from "go test it at
runtime and see."

**What a trace does NOT give you:** the *prior* that a given lever matters. Nothing in the
source of defect 2 says "the operator will notice green chips". Tracing tells you what the
code does in every condition; it does not rank which conditions the user cares about.
Operator reports remain the input that *aims* the trace. The claim being defended here is
narrower and holds: **once aimed, the trace is sufficient in 12 of 14 cases.**

---

## (c) The generalized trace protocol

Derived from the corpus; ordered by yield. Each move is a command plus a question, not an
aspiration. This is the failure-mode agent's operating procedure.

### Move 1 — Producer/consumer scan for every lever
*Catches 2, 4, 6, 9. Highest yield in the corpus.*

For each field, flag, env var, marker file, or state path the change reads or writes:

```bash
git grep -n "<lever>" -- <surface>
```

Then split the hits into **producers** (write it) and **consumers** (read it) and check
three things:

- **Zero producers, ≥1 consumer** ⟹ dead branch (defects 4, 9). Mechanized for `NL_*` by `scripts/config-control-producer-scan.sh`.
- **Zero consumers, ≥1 producer** ⟹ decorative control (HARNESS-GAP-45's class).
- **≥2 consumers deriving the SAME claim with DIFFERENT predicates** ⟹ one of them is wrong (defect 2: server required member status, client took non-empty).

**Non-negotiable corollary:** when you fix one instance, re-run the grep and dispose of
**every** hit explicitly — fixed, or audited-and-left-with-a-reason. Defect 6's residual
exists because two prior fixes cured the reported pane and left the siblings.

### Move 2 — Resolve what the helper actually returns
*Catches 1, 13.*

Never accept a helper's **name** as its contract. Open it and write down the concrete
value:

```bash
grep -n "function <helper>" -A 10 <file>
```

- `planRowContainer` → *the group*, not the row (defect 1).
- `rrg_blob_sha_of_file` → *the filesystem*, not the index (defect 13).

Then re-read every call site substituting the real value. Defect 1 dies on sight the
moment you write "group" into both sides of `draggedRow !== targetRow`.

### Move 3 — Enumerate every early return and label its DIRECTION
*Catches 11, 12.*

```bash
grep -nE "return 0|return 1|exit 0|exit 1|\|\| return|&& return" <gate>
```

For **each**, answer two questions: *what condition reaches it?* and — the one that
matters — ***does it ALLOW or DENY?*** A guard of the form
`command -v <dep> >/dev/null 2>&1 || return 0` in a function whose `return 0` means allow
is a **fail-open on a caller-controllable dependency** (defect 12: `PATH` is the input).
Any missing-dependency, missing-file, or unparseable-input path that lands on ALLOW is a
finding, whether or not you can name an attacker.

### Move 4 — Branch enumeration against the real input set
*Catches 1, 2, 8.*

When the predicate is a closed set (a `case` list, a `switch`, a small enum), do not
reason about it — **run it over the actual corpus**:

```bash
awk '/^<fn>\(\) \{/,/^\}/' <lib> > /tmp/f.sh && . /tmp/f.sh
git ls-files '<glob>' | while read -r p; do <fn> "$p" || echo "OUT $p"; done
```

That is how defect 8's 28-in / 54-out split was produced. For value predicates, enumerate
the states the field can actually hold — defect 2's `running / stalled / crashed /
unknown / no-status-object / absent` — and evaluate each. The *interesting* states are
the non-happy ones; that is where 5 of 9 cases were wrong.

### Move 5 — Trust-boundary walk for anything a gate or emitter reads
*Catches 3, and the replay half of 3.*

For every input, name its **origin** and its **lifetime**:

- **Origin.** Is it operator/agent-authored free text? Then unanchored `grep -oE 'X.*'`
  matches a *mention*, not a *declaration* (defect 3). Anchor it (`^`), or require a
  position (opens the prompt), or both.
- **Lifetime.** Does anything **delete or reset** the state between the write and the
  read? Grep for it:
  ```bash
  grep -n "rm -f .*<state>\|> *<state>\|truncate\|reset" <file>
  ```
  A "first fire only" gate keyed on a file that another path `rm -f`s (defect 3:
  `opened-${sid}.jsonl` written at `:645`, deleted at `:949` and `:1120-1121`) is a gate
  whose guarantee expires silently at every turn boundary.

### Move 6 — Index-vs-worktree, and hook-time-vs-action-time
*Catches 11, 13. Apply to anything that commits, stages, or fires before an action.*

Two distinct questions, both mandatory:

1. **Which object?** `git hash-object <path>` (worktree) ≠ `git rev-parse :<path>` (index)
   ≠ `git rev-parse HEAD:<path>` (committed). `git commit` commits the **index**. A gate
   attesting to any other object is attesting to bytes that will not land (defect 13).
2. **Which moment?** Locate the wiring and confirm the event:
   ```bash
   grep -n '"PreToolUse"\|"PostToolUse"' adapters/claude-code/settings.json.template
   grep -n "<gate>.sh" adapters/claude-code/settings.json.template
   ```
   A **PreToolUse** hook observes state *before* the command runs. If the command both
   mutates that state and is judged on it — `git add X && git commit` — the gate judged a
   world that no longer exists by the time it matters (defect 11).

### Move 7 — Test-predicate audit: what is this assertion a function of?
*Catches 7, 10.*

```bash
grep -nE "\.test\((<sourceVar>)\)" <suite>          # regex over source text
grep -nE "DRYRUN|_CMD_OVERRIDE|inject|fake|stub" <script>   # test seams that skip the real path
```

An assertion whose predicate is a function of **source text** (defect 10) or of an
**injected fake** (defect 7's `AR_DRYRUN_ARGV`) proves the code is *present*, never that
it *works*. Both defects shipped green. Replace with a real-execution assertion that
extracts the actual function and asserts the observable output changed — the pattern
`R17-DRAG-3` uses, and the pattern every trace script in this document uses.

### Move 8 — Trigger enumeration for every "runs periodically" claim
*Catches 4, 9.*

"Runs weekly", "the model calls it when appropriate", "the operator triggers it" are
**non-triggers** (`deterministic-process.md:50-55` Rule 3). Enumerate the complete,
finite set of real firing mechanisms on the target platform:

```bash
grep -n "<script>" adapters/claude-code/settings.json.template   # hook event
ls ~/Library/LaunchAgents/                                       # macOS
crontab -l                                                       # cron
ls adapters/claude-code/scripts/install-*-task.ps1               # Windows-only? then macOS has nothing
```

Then check the **output side** — if the artifact the mechanism should produce has never
been created (`ls ~/.claude/state/calibration/` → *No such file or directory*), the
mechanism has never run. Zero triggers or zero outputs ⟹ vaporware regardless of how good
the script is.

### Move 9 — Claim-vs-measurement on every Enforcement header
*Catches 14.*

Every clause in a doctrine/manifest Enforcement block is a testable proposition. Test each
one, in both directions — the header may **understate** the mechanism (defect 14 today) as
easily as overstate it (defect 14 originally):

```bash
python3 -c "…count the manifest units the claim quantifies over…"
grep -n "<claimed key>"   adapters/claude-code/schemas/manifest.schema.json
grep -n "<claimed check>" adapters/claude-code/hooks/harness-doctor.sh
```

Then check the **exemption list**: an enforcement covering 2 of 40 units because 38 are
grandfathered is a claim about 5% of the surface. State the in-scope count, never the
nominal one.

### The closing question — the one that fails a review

After the nine moves, answer in one sentence, with a `file:line`:

> **"What is the observable difference between this code and the same code deleted?"**

If the answer is "none" for any input class the user actually produces, the change is
vaporware. Defects 1, 4, 9 and 10 all answer "none". Defect 1's `insertBefore` block could
have been deleted with zero behavioural change — which is exactly what the execution in §a
row 1 shows.

---

## (d) The irreducible residual

Two classes in this corpus genuinely require observing code we do not own. Both remain
external — **and both narrow to a single closed question with a one-command answer.** The
distinction matters operationally: "run one command and read the exit code" is not
"open-ended runtime testing", and it belongs in a trace, not in a QA cycle.

| Class | Corpus | Why irreducible | The ONE question | The command | Answer today |
|---|---|---|---|---|---|
| **Host-environment contract** (launchd, systemd, Task Scheduler, CI runner) | 5 | The supervisor's default environment is defined by the OS, not by us; a plist that sets no `PATH` inherits a value we cannot read from our own source | *Is the interpreter on the supervisor's default PATH?* | `launchctl getenv PATH` + `command -v node` | empty + `/opt/homebrew/bin/node` ⟹ **no** ⟹ `env: node`, exit 127 |
| **Third-party binary behaviour under re-entrancy** (`claude`, any CLI invoked from inside itself) | 7 | Whether a foreign process blocks, fails fast, or deadlocks is not derivable from our call site | *Does it return within the bound when invoked re-entrantly?* | `timeout 25 env -u CLAUDECODE claude --model haiku -p "ping" </dev/null; echo $?` | `124` ⟹ **hangs** |
| **Browser navigation/security policy** — *candidate, but NOT irreducible here* | 6 | Would be external in a fresh codebase | — | — | **Already a repo fact**: `roadmap.js:1014`, `app.css:613,1892` record it; one `git grep "file://"` suffices |

Three rules follow, and they are the operational payload of this section:

1. **An external fact, once observed, must be written into the repo at the fix site** —
   as `roadmap.js:1014` does. That is what demoted defect 6 from "needs a browser" to
   "needs one grep", and it is the cheapest permanent win available. Every fix that
   required a live probe should end by recording the probe's *finding* next to the code,
   so the next reader inherits it.
2. **Never let an external fact justify skipping the static half.** Defect 7's symptom
   (114 candidates, 0 verdicts; the only test asserts an argv string) was fully provable
   without knowing the binary hung. The static half is sufficient to **reject**; the
   external probe is needed only to **explain**.
3. **A trace that cannot resolve something must terminate in a named question, not a
   shrug.** "I could not determine X; the check is `<command>`; I have not run it" is a
   complete, actionable trace result. "Needs runtime verification" is not — it is the
   phrase that let defects 1, 2 and 6 ship with a live probe standing in for a read.

---

## Cross-references

- `adapters/claude-code/doctrine/deterministic-process.md` — Rules 1-3; Rule 3's golden cases are defects 4 and 9.
- `adapters/claude-code/scripts/config-control-producer-scan.sh` — Move 1, mechanized for `NL_*` levers.
- `adapters/claude-code/doctrine/review-before-deploy-full.md` — defect 8's surface and its named residual.
- `docs/backlog.md` — `COCKPIT-DEAD-FILE-HREF-RESIDUAL-01` (filed this session, from Move 1 applied to defect 6); `DETERMINISTIC-PROCESS-PROOF-OBLIGATION-UNWIRED-01` (defect 14).
- `docs/reviews/cockpit-ui-requirements-ledger.md` rows 70, 87 — the two prior `file://` cures.
