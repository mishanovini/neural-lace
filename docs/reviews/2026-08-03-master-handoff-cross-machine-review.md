# Cross-machine review — `2026-08-03-MASTER-HANDOFF-process-integrity.md`

**Reviewer:** Misha-Laptop session `d3059d78` · **Date:** 2026-08-03 · **Master at review time:** `3a3994e`
**Subject:** `docs/handoffs/2026-08-03-MASTER-HANDOFF-process-integrity.md` (authored by the other machine)
**Verdict: ACCEPT the diagnosis, ACCEPT the Phase A→D sequencing, with ONE factual correction and three additions.**

This is the strongest handoff the estate has produced. Its central diagnosis is not a
restatement of the operator's complaint — it is a genuine root-cause finding that reframes
the problem. I verified its two load-bearing claims by execution rather than accepting them,
and both hold. One machine-state claim does not hold here, and that changes a risk
assumption the reader is asked to act on.

---

## 1. Claims I independently verified — both PROVEN

**"THE ONE THING" rests on a real, still-standing contrary law. PROVEN.**
The handoff's most valuable claim is that the pull-cockpit and TTL-cache dispatches were
*not* directive-ignoring — they were **compliant with a law the repo still teaches**, so two
actors made the "same mistake" in one hour because in the repo's own frame it was not a
mistake. I checked the citation rather than trusting it:

```
neural-lace/workstreams-ui/server/derive-cache.js:7-11
// Law 1 (DERIVE-DON'T-MAINTAIN, docs/reviews/2026-07-04-observability-design-
// sketch.md) says the cockpit must never render MAINTAINED state ...
```

The law is there, it is stated as binding, and nothing rescinds it. The operator's doctrine
flipped to push on 2026-08-02 and this header was never touched. **The conclusion follows: a
directives register WITHOUT supersession semantics would become the fifth store of directive
truth and fix nothing.** That is the correct design constraint and it is well argued.

**D3 — design-doc authoring is genuinely ungoverned. PROVEN.**
`adapters/claude-code/config/model-policy.json` maps the `design` category to
`["fable","opus"]`, but every agent in that category is a **reviewer or auditor**:
`architecture-reviewer`, `systems-designer`, `ux-designer`, `ux-ia-auditor`. There is no
authoring agent anywhere in the file. And the policy's own note is explicit: *"Fable is a
PREMIUM tier and MUST NEVER be reached by inherit/default — only by explicit pin."* So a
design doc written by an unpinned workflow agent could not have been Fable-authored. The
handoff's inference — that this is *why* the design read as assembled notes rather than a
specification — is sound.

## 2. The one factual correction — the machine-state claim does not hold here

The handoff's HARD STOP §0.1 states: *"Verified 2026-08-03: no `NL-Maintenance` task exists;
the five legacy `NL-*` tasks are **Disabled**."* and §0.4 concludes *"The machine is currently
calm (~7% CPU) partly because maintenance is OFF."*

**On Misha-Laptop, four of six legacy `NL-*` tasks are ACTIVE, not disabled** (`Get-ScheduledTaskInfo`, 2026-08-03):

| Task | State | Last run | Result |
|---|---|---|---|
| `NL-CoordSync` | Ready | 02:19:38 | `0` |
| `NL-EstateJanitor` | **Running** | 03:48:41 | `0x800710E0` (non-zero) |
| `NL-health-tick` | Ready | 01:30:04 | `0` |
| `NL-SupervisorTick` | **Running** | 02:18:39 | `0x41301` = still running |
| `NL-session-resumer` | Disabled | 2026-07-07 | `0xFFFFFFFF` |
| `NL-workstreams-heartbeat` | Disabled | 2026-07-08 | `0` |

**What survives the correction:** the HARD STOP itself. `NL-Maintenance` is genuinely absent
here, and F1/F2 live inside `nl-maintenance.sh`, which nothing else invokes — so those two
Criticals *are* dormant on this machine. **Do not register it.** That instruction stands
unqualified.

**What does not survive:** the inference that calm equals maintenance-off. This machine is
calm-ish while running four maintenance tasks, so the truce is broader than the handoff
assumes, and any future "we turned it off and got calm" reasoning must be re-derived
per-machine rather than estate-wide.

**New finding the other machine could not have seen:** `NL-EstateJanitor` fires every ~5
minutes and its last run returned `0x800710E0`, which `[Win32Exception]` cannot decode to a
standard system message. A task failing on a 5-minute cadence is not benign and is not in
anyone's inventory. Filed; not diagnosed here.

## 3. Four open operator asks were already satisfied — retired with evidence

The handoff carries the standing asks forward. Four of them are **done on this machine** and
were only still open because nobody re-checked. Retired in the NEEDS-YOU ledger with the
`Get-ScheduledTaskInfo` evidence inline:

- `NY-1784310684-5e29` — *register 3 harness scheduled tasks*. All three registered.
  `NeuralLace-HarnessEvaluator-Daily` **proven firing**: last run 2026-08-02 17:00:04, `rc=0`
  — the operator's 5PM daily eval, specified 2026-05-28, is live. The other two are
  registered with `rc=267011` (`SCHED_S_TASK_HAS_NOT_RUN`) and next run 2026-08-03 09:00 —
  scheduled, simply not yet due.
- `NY-1784327382-f3e8` — *register `NL-CoordSync`*. Registered, `rc=0`, 60-second cadence.
- `NY-1785556561-aaba` — *register the coordination publisher on this desktop*. **Duplicate**
  of the above; same task, same evidence.
- `NY-1783648801-4e1f` — *register `NL-health-tick`*. Registered, `rc=0`, hourly as designed.

This is the direct answer to the operator's *"there's still nothing in the operator-todo file
— what exactly do you need from me?"*: **less than the ledger claimed.** The ledger was
carrying satisfied asks because nothing re-verifies them, which is itself the defect below.

## 4. Additions to the Phase A→D plan

**Add to Phase B — the ledger cannot retire its own asks.** `needs-you.sh resolve` takes
**over two minutes per call** on a 70-item / 53 KB ledger (measured; Windows spawn tax across
the re-render). Any normal session that tries to close a stale ask times out and gives up.
That is the mechanical reason asks go stale, and it defeats B1's register before it ships — a
directives register with supersession is a *write* mechanism, and this ledger proves the
estate's existing write mechanism is unusable at interactive speed. Separately,
`needs-you.sh` with no arguments emits `line 2251: render: command not found` before its
usage text. Both filed.

**Add to Phase A — a per-machine activation preflight.** The correction in §2 exists because
one machine documented its own task state as the estate's. Phase A4 ("register
`NL-Maintenance`, re-enable, measure") will be executed on three machines with three different
starting states. It needs a preflight that *reads* each machine's actual task inventory
rather than assuming the handoff's.

**Endorse §5's reviewer recommendation, with the reasoning sharpened.** Extending
`plan-reviewer` and `architecture-reviewer` and adding exactly one `design-author` is right,
and the handoff's rationale is the correct one: *the failures were absent checks and absent
authorship, not absent capacity.* I would add the measurement that settles it — the
directive/fidelity reference count across reviewers (plan-reviewer **0**, harness-reviewer
**0**, plan-evidence-reviewer **0**, architecture-reviewer **1**). A fleet of reviewers that
each reference directives zero times does not get better by growing.

## 5. What I did not verify

- The `71 red` doctor count (cold doctor is a ~9-minute run; not spent inline).
- F1/F2/F5/F6 themselves — instead of re-deriving them I dispatched two builder lanes against
  them, each instructed that the review is *evidence, not scripture* and to report back if the
  defect is not what the review says it is.
- The `1,000,000 token` context-window claim (§6) — machine-local memory assertion, not
  checkable from here.
