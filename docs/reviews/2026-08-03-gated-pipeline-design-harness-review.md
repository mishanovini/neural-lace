# Harness Review: THE GATED PIPELINE — master design (PRE-BUILD design review)

**Reviewer:** harness-reviewer (model: fable, dispatched by session 4a470c8c)
**Reviewed:** docs/designs/gated-pipeline-master-2026-08-03.md @ working tree at HEAD `6e28a82c`
(byte-identical to the copy committed at `4fb1b234` — the reviewer read the file before the commit
landed; verified identical by the dispatching orchestrator via the commit introducing the file
unchanged.)
**Reviewed file(s):** the design (§0–§10) + verification reads of every load-bearing cited site (evidence trail below)
**Independent classification:** Hybrid — G1/G2/G3/review-chain-lib/no-addendum-lint/Phase-A fixes = Mechanism; directives register + two agents + templates = Pattern with Mechanism carriage edges; doctrine-jit second walk = Mechanism-class change to a writer hook
**Author's declared classification:** not per-artifact; framing is consistent with the above (gates as gates, agents as agents) — AGREE, with two overclaim exceptions (findings M-10, M-4)
**Failure mode / goal:** mechanically chain design→plan→build→deploy so a skipped review is blocked, not discouraged (D-15), after fixing F1/F2/F6/F9 first
**Reviewed at:** 2026-08-03

## Verdict: REFORMULATE

The architecture is sound: the review-chain artifact contract, the three-gate placement (Write-time / dispatch-time / push-funnel), the Phase-A-first sequencing, and the honest-residual discipline are all right, and REQ-A1–A5 faithfully transcribe my Stage-0/1 required-fix text almost verbatim. But two Criticals and a cluster of Majors mean building from this spec as written would ship (1) a regression into the live doctrine-JIT channel whose safety claim is false as specced, and (2) a dispatch gate whose FP model omits its single largest false-positive class — every pre-pipeline plan in the estate — which on activation day either blocks all legitimate builder traffic (training the escape hatch, D-04's defective-gate definition) or trips its own 3-FP/week demotion immediately (losing the D-15 acceptance bar either way). Plus: my F3 (a PROVEN Major) is silently dropped with no disposition — the exact requirement-drop class this design exists to make impossible.

---

## Evidence trail (commands run; all PROVEN claims below cite these)

- Full read of the design; full read of my prior review (`docs/reviews/2026-08-03-stage0-stage1-harness-review.md`), the exhaustive inventory, and the master handoff.
- Verified cited sites current at HEAD `6e28a82c`: `nl-maintenance.sh:488-528` (run_daemon/run_tick), `:537-581` (watchdog nohup-without-kill; `daemon.pid` written at 517, never read), `:790-791` (S11 `SF_DISABLE=1` mask), `:393` (friction default `gate-friction/ledger.jsonl`); `harness-doctor.sh:7363-7367` (sf-skip bare `exit 0`), `:7477-7489` (5-field write), `:296-321` (4-mtime+HEAD fingerprint); `session-start-digest.sh:505-538` (3-field writer, `verdict unavailable` fallback); `workaround-sensor-lib.sh:140-151,211` (`workaround-sensor.jsonl`, `bypass_kind` schema); `settings.json.template:332-358` (Task|Agent PreToolUse = teammate-spawn-validator + model-pin-gate + workstreams-emit only), `:34-40` (prd-validity-gate on matcher **Write** only); `plan-reviewer.sh:3304-3393` (Check 17; the 27.0% = 64/237 corpus measurement at :3333); `doctrine-jit.sh:49` ("Emit ONE hookSpecificOutput... blob"), `:278-285` (single emission + `return 0` first-match), `:295-333` (`_run_live` always `exit 0`), `:57` (writer exit-0 contract); `model-policy.json:10-15,47-50`; `git-hooks/pre-push:75-87` (review-record-push-gate as the funnel); `pre-commit-gate.sh:208-213` (hygiene-scan rides pre-commit).
- `grep -rn 'NL-ATTRIBUTION'` → convention defined in `orchestrator-pattern.md:11` as **WARN-only** (`workstreams-emit.sh`), with a documented quoted-header false-green quirk.
- `manifest-check.sh:555` → REDs any disk hook appearing in no manifest entry (backstop for finding Mi-2).
- FP corpus measurement for REQ-B10: `grep -rniE '^#+ .*(Addendum|Round [0-9]|Update:)' docs/designs/ docs/plans/` → **5 files fire**, including `docs/plans/review-gate-identity-anchor-2026-07-30.md:249,304` ("### Round 3 — harness-reviewer REJECT…", "## Round 4 — evidence") — legitimate review-round records, not addendum abuse.

## REQ-A fidelity check against my Stage-0/1 required-fix text (caller-mandated)

| My finding | Design disposition | Match? |
|---|---|---|
| F1 (Critical) | REQ-A1 | ✓ verbatim: sf_release + per-pass release + pid-kill + S11 unmasked + ≥2-real-ticks assert (see M-8 for a hardening my own fix text also lacked) |
| F2 (Critical) | REQ-A2 | ✓ all three modes addressed: skip serves cache / distinct code 3 + parseable line; full-schema-or-refuse, no ts re-stamp; refresher runs `DOCTOR_VERDICT_CACHE_DISABLE=1 SF_DISABLE=1`; two-writer self-test (see M-2 for the residual) |
| **F3 (Major)** | **ABSENT — no disposition anywhere in the design** | ✗ — finding M-1 |
| F4 (Major) | REQ-A4 zero-substrate WARN, RED after 14 days in data | ✓ |
| F5 (Major) | REQ-A2 fingerprint + live-hooks newest-mtime + dirty bit | ✓ verbatim |
| F6 (Major) | REQ-A3 | ✓ verbatim (one file+schema, bypass_kind mapping, block-writer decision, end-to-end test) |
| F7 (Major) | REQ-A5 flip dates in data + managed_by satisfied-by-construction | ✓ |
| F8 (Major) | folded into REQ-A2 | ✓ |
| F9 (Major) | REQ-A4 manifest entries + `--gen-index` | ✓ |
| **F10 (Minor, mine: test-name rename)** | **UNMAPPED — numbering collision: the design's "F10" is the inventory's CPU-methodology item** | ✗ — folded into M-1 |
| F11 (Minor) | REQ-A5 HALT canonical path | ✓ |
| F12 (Minor) | REQ-C3 census-not-subset | ✓ |

P-42's discharge (§1) is legitimate: the register's justification is re-derived on four independent PROVEN grounds without the Law-1 premise, and supersession is retained on the correct new framing. Accepted.

## §10 evidence-bar check per gate (substance, not presence)

- **G1:** golden ✓ (P-39's plan — but see M-5: the golden as specced catches only the derived-record half, not the accretion half). FP ✓ substantive (reuses the measured 27.0% Check-17 fire-rate — verified at `plan-reviewer.sh:3333`) but escalated cost unmodeled (Mi-3). Flip ✓ (config date — F7 lesson honored). Demotion condition: absent (Mi-6).
- **G2:** golden ✓ (P-39/P-40 verbatim). FP model **fails** — omits the dominant class (C-2). Retirement ✓ (data-file demotion condition).
- **G3:** golden ✓ for the harness class only; the product-code classes ride in with no golden, no FP measurement, no per-class calibration (M-6). Flip ✓.
- **No-addendum lint:** golden ✓ (the brief). FP: unmodeled and PROVEN non-trivial by my corpus grep; escape: declared "none needed," contradicting the design's own §2 {WHAT/WHY/FIX/ESCAPE} binding (M-9). **Fails the bar as specced.**

## Remedy-chain analysis (ADR 059 D5)

| Remedy prescribed | Tool call(s) it implies | Other gates that also match | Deadlock? |
|---|---|---|---|
| G1 block → add `design-ref:`/chain or `n/a` justification | Edit on `docs/plans/*.md` | plan-edit-validator (WARN-only), work-integrity plan-touch at Stop (has ADR 059 D4 waiver), G1 re-fires compliant | NO (waiver exists; friction noted) |
| G1/G2 block → dispatch missing reviewer | Task, role=reviewer | G2 itself (role≠builder → WARN pass ✓), model-pin-gate (reviewers pinned ✓), teammate-spawn-validator | NO — remedy reachable from the blocked actor (orchestrator has dispatch) |
| G2 block → commit plan w/ chain | Bash `git commit` | pre-commit-gate chain → plan-reviewer Checks 20–22 (same parser lib by design ✓), hygiene-scan + no-addendum (chain block matches no lint pattern ✓), NL-FINDING-016 EXIT trap inherited ✓ | NO — provided fix-edit and commit stay separate Bash calls |
| G3 block → dispatch reviewers, commit records, re-push | Task + Bash commit + push | review-record-commit-gate (advisory ✓), hygiene-scan (docs/reviews allow-listed ✓), G3 re-fires | NO **only if** G3 inherits rrg's same-push record honoring (ref-based read); design does not state this — make it explicit (folded into M-6) |
| No-addendum block → integrate addenda into body | Edit + recommit | none | NO for the golden case; **effectively exit-less for historical Round-N files** (remedy = rewriting a historical record's headings; no waiver) — M-9 |
| G2 block on a pre-pipeline plan → retroactive fidelity review + chain retrofit | per-plan review + edit + commit | work-integrity (waiver), Checks 20–22 | Not exit-less, but ×23 stale ACTIVE plans + every in-flight plan = the C-2 over-fire |

**Writer-then-gate race check (NL-FINDING-024 class):** G2 reads git state (HEAD/index), written by prior Bash calls, not by a same-matcher writer hook — no same-batch ordering dependency. The doctrine-jit second walk is a writer-writer composition inside ONE hook invocation — see C-1.

---

## Findings (class-aware, sorted Critical → Major → Minor)

```
- Line(s): design §4 "Directives register + carriage" channel (3) + REQ-B11, vs adapters/claude-code/hooks/doctrine-jit.sh:49,278-285,295-333
  Severity: Critical  [C-1]
  Confidence: PROVEN (doctrine-jit.sh:49 documents the single-JSON-blob channel and that non-JSON stdout "does NOT reach model context"; _compute_injection emits exactly one jq JSON object then returns; a second walk emitting a second object produces concatenated JSON = invalid JSON stdout = NEITHER injection reaches context)
  Defect: The "separate second walk (its own marker namespace, so it cannot compete with the doctrine walk's first-match-wins)" fixes MARKER competition but not EMISSION competition: on any Edit/Write matching both a doctrine trigger and a register surface glob, two hookSpecificOutput JSON objects on one stdout break parsing and silently kill BOTH injections — a regression into the live constitution-delivery channel — so the design's no-starvation claim is false as specced.
  Class: multi-emitter composition on a single-JSON-stdout hook channel (writer-writer collision inside one invocation)
  Sweep query: rg -n "hookSpecificOutput" adapters/claude-code/hooks/   # every emitter; verify each invocation path can emit at most ONE JSON object per event
  Required fix: Restructure as compute-both-walks-then-emit-ONCE: the register walk's matched content is appended into the SAME additionalContext payload (single jq emission), with per-walk markers written independently; the always-exit-0 writer contract statement must appear in the REQ text; self-test adds the both-match-same-event scenario asserting one valid JSON object containing both bodies.
  Required generalization: any hook gaining a second content source must prove single-emission by construction — a "second walk" on a JSON-stdout hook is a merge problem, not a loop problem.
```

```
- Line(s): design §4 G2 "*Expected FP:* ad-hoc non-plan builder dispatches" + §8 item 2 + REQ-B8; vs docs/handoffs/2026-08-03-MASTER-HANDOFF §4-D3 (23 stale ACTIVE plans) and the absence of any grandfather/transition clause in the design
  Severity: Critical  [C-2]
  Confidence: PROVEN for the coverage gap (no REQ, decision, or §8 pre-mortem addresses pre-pipeline plans; every existing plan is chain-less by construction; G2 ships BLOCKING — no WARN window is stated for it, deliberately, per D-15); HYPOTHESIZED for the erosion rate (refuted if calibration-fortnight ledger shows near-zero legacy-plan dispatches)
  Defect: G2's FP model omits its single largest FP class: every plan authored before the pipeline exists. From the moment G2 lands on master (session-start-auto-install syncs it live estate-wide), every self-declared builder dispatch against ANY existing plan — the 23 stale ACTIVE plans, all in-flight work on other machines, any emergency hotfix plan — blocks pending a retroactive fidelity review + chain retrofit. Outcome is lose-lose as specced: either routine escape-hatch use (D-04's definition of a defective gate) or the 3-FP/week demotion condition trips in week one and G2 demotes to WARN — losing the D-15 acceptance bar the gate exists to hold.
  Class: new blocking gate without a grandfather/transition story for the pre-existing artifact population (the review-record gates solved this same class with grandfather-manifest.json)
  Sweep query: rg -ln "grandfather" adapters/claude-code/hooks adapters/claude-code/config   # the in-estate precedent to mirror; then rg -c "Status: ACTIVE" docs/plans/*.md for the exposed population
  Required fix: Add an explicit transition clause to §4/REQ-B8: plans predating the gate's landing (by a recorded date or a grandfather list generated at install) pass with a ledgered WARN naming the retrofit path; sequence REQ-C2's stale-plan dispositioning BEFORE G2's block posture covers legacy plans; new-plan enforcement stays BLOCKING from day one (preserving the acceptance bar on the golden P-39 shape, which is a NEW plan).
  Required generalization: every new gate over a pre-existing artifact population must enumerate that population in its FP model and ship a transition mechanism in the same commit — activation-day over-fire is the highest-leverage trust-erosion moment a gate ever has.
```

```
- Line(s): design §6 Phase A (REQ-A1..A7) + §9 disposition map — no row mentions F3; my review's F3 (single-flight-lib.sh:183-192 TTL reclaim vs the 9m12s measured cycle) and my F10 (harness-doctor.sh:7069 / session-start-digest.sh:2443-2464 test-name rename)
  Severity: Major  [M-1]
  Confidence: PROVEN (text absence verified by full read; the design's "F10" at REQ-A5 is the inventory Part-6 CPU-methodology item, a numbering collision the design inherited without noticing my F10 is a different finding)
  Defect: F3 — a PROVEN Major wrong-ALLOW (the doctor-quick guard lapses mid-run because its 120s TTL is ~4.6× shorter than the guarded work's measured cycle) — receives no disposition anywhere in the design, and my F10 (Minor) is silently displaced by the colliding inventory item. This is the exact silent-requirement-drop class (P-32) the design's own fidelity contract (§6/§10) exists to make impossible, occurring inside that design.
  Class: upstream review finding dropped without disposition during design consolidation (D-12 violation)
  Sweep query: for each of F1..F12 in docs/reviews/2026-08-03-stage0-stage1-harness-review.md: rg -n "F<N>" docs/designs/gated-pipeline-master-2026-08-03.md — every miss needs a disposition row
  Required fix: Add F3's fix to REQ-A1 or REQ-A5 (raise doctor-quick TTL ≥2× measured cold cycle, or add owner-pid liveness to _sf_is_stale with TTL fallback) and map my F10 (rename the never-suppressed scenario labels) into REQ-A5, disambiguating the two F10s by source.
  Required generalization: the disposition map (§9) must cover the FULL id-space of every input review, not just S-/Q- items — and colliding id namespaces across input documents get disambiguated at consolidation time, since plan-fidelity-reviewer (REQ-B3) will otherwise string-match the wrong item as "covered."
```

```
- Line(s): design REQ-A2 ("refresh_doctor_cache writes the FULL 5-field schema...; a two-writer self-test runs BOTH writers against one file and asserts schema invariants"); vs harness-doctor.sh:296-321 (_doctor_compute_fingerprint is file-local, not a lib) and session-start-digest.sh:521-538
  Severity: Major  [M-2]
  Confidence: PROVEN for the spec gap (the fingerprint function exists only inside harness-doctor.sh; REQ-A2 requires the digest to write a 5-field record including "fingerprint" but names no shared implementation); HYPOTHESIZED for the failure (refuted if the builder happens to extract a shared lib unprompted)
  Defect: A builder can satisfy REQ-A2's letter by re-implementing fingerprint computation inside the digest; any algorithmic divergence (input order, cksum fallback, path resolution) yields records whose fingerprint never matches the doctor reader's own computation — permanent silent cache-miss, killing the measured 1.557s fast path: F2's mode-3 (fingerprint destruction) reborn as fingerprint MISMATCH. The specced self-test ("asserts schema invariants") passes on field presence and would not catch it.
  Class: shared-cache field whose derivation logic is duplicated per-writer instead of extracted to one implementation (the F2 schema-contract lesson applied one level deeper: same fields, same MEANING)
  Sweep query: rg -n "_doctor_compute_fingerprint|fingerprint" adapters/claude-code/hooks/harness-doctor.sh adapters/claude-code/hooks/session-start-digest.sh adapters/claude-code/hooks/lib/
  Required fix: REQ-A2 must mandate extracting _doctor_compute_fingerprint into a shared lib sourced by both writers (or, simpler and preferred: digest becomes serve-only — the doctor's own write path at :7477-7489 is the sole writer, which is what "single writer + schema contract" in the master handoff meant); the two-writer self-test must assert fingerprint EQUALITY for identical inputs, not just field presence.
  Required generalization: a schema contract for multi-writer state covers derivation semantics, not field names — any derived field written by two actors requires one shared derivation function.
```

```
- Line(s): design §4 "Directives register" format spec + REQ-B1 vs its three machine consumers (plan-reviewer Check 21 per REQ-B7, scripts/dispatch-directives.sh per §4 channel 2, doctrine-jit second walk per channel 3)
  Severity: Major  [M-3]
  Confidence: PROVEN (the design specifies entry CONTENT — "id | status | surfaces (globs) | supersedes | instruction ≤5 lines" — but no file grammar: markdown table? per-entry sections? front-matter? Multi-line instructions with pipes/globs inside a markdown table are unparseable by naive bash/jq; three independent consumers will each improvise a parse)
  Defect: The design that fixes F6 (writer/consumer schema pointing past each other, REQ-A3) creates a new 1-writer/3-consumer surface with no specified shared grammar or parser — the same class, with three consumers instead of one, on the artifact the whole directive-carriage architecture depends on.
  Class: writer/consumer pair (here: trio) shipped without an executed schema-agreement step (my F6's exact class tag)
  Sweep query: rg -n "operator-directives" docs/designs/gated-pipeline-master-2026-08-03.md   # every consumer named; then verify the plan gives them ONE parser
  Required fix: Specify the register's machine format in the design (recommended: human-readable md body + a generated/validated structured block per entry, or a sidecar JSON the md is rendered from) and mandate ONE shared parser lib (mirror REQ-B6's review-chain-lib precedent — same problem, same solution) used by Check 21, dispatch-directives.sh, and the JIT walk, with a shared fixture round-trip test.
  Required generalization: any artifact with ≥2 machine consumers gets its grammar specified at design time and exactly one parser implementation — REQ-B6 already does this for review chains; the register deserves the identical treatment.
```

```
- Line(s): design §4 G1 ("extends the existing PreToolUse-Write precedent on docs/plans/ ... *Flip:* ships BLOCKING at Write-time for the design-ref: n/a justification length"); vs settings.json.template:34-40 (prd-validity-gate matcher is the Write TOOL only) and start-plan.sh (plan scaffold written via bash heredoc/cat — never traverses the Write tool; the design's own §1 cites start-plan.sh:444 writing Status: ACTIVE)
  Severity: Major  [M-4]
  Confidence: PROVEN (matcher read from the template; start-plan.sh writes the plan file from inside a Bash-tool invocation, invisible to any PreToolUse Write matcher; Edit/MultiEdit also uncovered by a Write-only matcher)
  Defect: G1's "ships BLOCKING at Write-time" overclaims its moment of enforcement: the estate's own sanctioned plan-creation path (start-plan.sh) and all Edit/MultiEdit modifications bypass the Write-tool matcher entirely, so the Write-time layer is an early-warning convenience, not a barrier — the commit-time twin (Checks 20–22) and G2 are the real floor, and the design does not say so.
  Class: tool-matcher gate claimed as path coverage (gate on the TOOL, failure on the FILE — bash-script writes are the standing hole in every PreToolUse file gate)
  Sweep query: rg -n '"matcher": "Write"' adapters/claude-code/settings.json.template   # every Write-only gate; for each, ask which bash-script path writes the same files
  Required fix: Name the residual explicitly in §4 (Write-layer = advisory early warning; commit-time = enforcement floor), widen the matcher to Edit|Write|MultiEdit, and have start-plan.sh invoke the same check (or its --check mode) at scaffold time so the sanctioned path gets the same early warning.
  Required generalization: every PreToolUse file gate names its bash-write bypass as a documented residual and states which downstream layer (commit/push) is the actual floor — coverage claims are made per-path, not per-tool.
```

```
- Line(s): design §4 review-chain parsing rules ("SHA-anchoring (@<sha>) makes a chain entry cover specific bytes") + G1/G2 chain-parse requirements + REQ-B6
  Severity: Major  [M-5]
  Confidence: PROVEN for the spec gap (the parsing rules validate record-exists + verdict-parses + reviewer-named; nothing specified compares the anchored design SHA to the design's CURRENT blob, and plan-review entries have no anchoring semantics at all — the chain lives inside the plan, so a plan-review record cannot cite the plan's own post-edit SHA without a self-reference paradox the design never resolves)
  Defect: The accretion half of the golden scenario escapes: a design honestly reviewed at sha1 that then accretes to sha2 (P-39's actual pathology — "built from an accreting design") yields a plan declaring design-ref@sha1 whose chain parses valid under every specified rule; likewise a plan revised AFTER its fidelity review keeps a valid chain forever. The pipeline as specced verifies reviews RAN, not that they cover the bytes being built.
  Class: review-artifact freshness unbound to reviewed-artifact bytes (linked-vs-performed's successor defect: performed-vs-still-current)
  Sweep query: rg -n "design-ref|@<sha|blob" docs/designs/gated-pipeline-master-2026-08-03.md   # every anchoring claim; verify each has a comparison site
  Required fix: (a) Check 20/G1 must verify design-ref's anchored SHA equals the design file's blob at HEAD (drift → re-review required, which is the correct behavior for an accreting design); (b) specify plan-side anchoring in REQ-B6 — e.g. the record cites a blob SHA computed over the plan MINUS its Review Chain section, or a rule that any post-review content edit (excluding the chain block and In-flight scope updates) invalidates the entry; (c) if either is deliberately deferred, name post-review drift as an accepted residual in §8 — silence is not an option for the design whose golden case IS accretion.
  Required generalization: a chain entry asserts "review R covers bytes B" — every chain consumer must compare B to the bytes actually feeding the gated transition, or the chain degrades to "a review happened once," the P-30 defect with extra steps.
```

```
- Line(s): design §4 G3 + DEC-5 (product code → architecture + security + functionality + domain per surface) + REQ-B9; vs review-record-push-gate.sh's current harness-surface-only scope (rrg_in_surface) and its hard-won hardening history
  Severity: Major  [M-6]
  Confidence: PROVEN for the evidence-bar gap (G3's stated golden and FP model — "the three merged-without-review stages"; "mixed-class pushes — class union" — both address the harness class only; no golden case, no measured would-have-blocked baseline, and no per-class calibration exists for the product classes, which multiply the gated surface from one repo's harness paths to every product push); HYPOTHESIZED for the erosion outcome (refuted if the WARN-week ledger shows low product-class fire rates)
  Defect: The product-code half of DEC-5 rides into the authoritative push funnel without its own §10 evidence bar — the constitution's per-gate bar, which this design itself restates as binding in §2. This is where --no-verify training is likeliest: a routine product push blocked pending functionality + domain + security records is the highest-frequency, highest-friction surface of the three gates, and it is the one with zero measured baseline. Additionally, REQ-B9 does not state that class coverage inherits the lib's same-push record honoring (ref-based read) — without it, "commit the missing record and re-push" would not clear the block it prescribes.
  Class: gate extension inheriting an existing gate's evidence bar while multiplying its enforced surface (per-class gates need per-class golden/FP/flip)
  Sweep query: git log --oneline --since="30 days ago" -- '<product paths>' | wc -l   # per class in DEC-5's table, compute the would-have-blocked rate before choosing its posture
  Required fix: Scope REQ-B9's BLOCK flip to the harness + docs classes (which have the golden and the P-40 evidence); product classes ship WARN with their own measured baseline (would-have-blocked over the last N pushes, computed during the calibration week) and their own data-file flip condition; state explicitly that class verification reads records AS OF local-sha (same-push honoring, the lib's existing precedent).
  Required generalization: every ROW of a per-class enforcement table is its own gate under §10 — golden, FP rate, and flip condition per class, not per table.
```

```
- Line(s): design §4 G2 trigger ("if the dispatch prompt's NL-ATTRIBUTION: line says role=builder and names plan=<slug>"); vs adapters/claude-code/doctrine/orchestrator-pattern.md:11 (NL-ATTRIBUTION is WARN-only, and a QUOTED header in the first 5 joined lines fires a documented false green in workstreams-emit.sh)
  Severity: Major  [M-7]
  Confidence: PROVEN (convention text read; WARN-only status and the quoted-header quirk are both documented in the doctrine line cited)
  Defect: G2's teeth ride a self-declared, WARN-only line: the momentum-pressured orchestrator — P-39's exact actor — bypasses the gate by omitting or mis-roling the attribution, and the design frames this pass-with-WARN as FP mitigation without naming it as the gate's PRIMARY bypass, without stating the WARN is ledgered, and without addressing the known quoted-header parse quirk G2's parser could inherit from workstreams-emit.
  Class: blocking gate triggered by self-declaration the same actor controls (enforcement conditioned on the honesty it exists to replace)
  Sweep query: rg -n "NL-ATTRIBUTION" adapters/claude-code/hooks adapters/claude-code/doctrine   # every parser of the line; G2 must share ONE parse with workstreams-emit or fix the quirk in both
  Required fix: (a) Name the omitted-attribution bypass as G2's honest residual alongside the Workflow-spawn residual; (b) ledger it: when a role-less/plan-less dispatch prompt textually references a docs/plans/ path, G2's WARN writes a workaround-sensor row (cheap heuristic, no block) so the calibration fortnight measures evasion, not just FPs; (c) after calibration, consider BLOCK on plan-path-referencing prompts lacking attribution — that is the D-15 direction of travel; (d) share or fix the first-5-lines parse.
  Required generalization: when a gate's trigger is a self-declared marker, the un-declared case must be measured from day one — a bypass you cannot see in a ledger is a bypass you will discover the P-39 way.
```

```
- Line(s): design REQ-A1 ("run_watchdog reads daemon.pid, kills a live stale daemon before relaunch"); vs D-11 (force-kill only provably-orphaned processes) and the master handoff §6's own safe-sweep rule (kill only bash whose parent is dead or cmdline empty)
  Severity: Major  [M-8]
  Confidence: PROVEN for the gap (REQ-A1 text requires no identity check before kill; Windows reuses PIDs aggressively, so a stale daemon.pid can name an innocent unrelated process); noting honestly that my own F1 required-fix text ("kill the pid in daemon.pid") carried the same gap — this is a hardening of my fix, not a deviation from it
  Defect: A watchdog killing by pid-file value alone can kill an unrelated live process after PID reuse — violating D-11's provably-orphaned bar in the exact mechanism being built to end the process-accumulation class.
  Class: pid-file kill without process-identity verification (pid-reuse hazard on Windows)
  Sweep query: rg -n "kill |taskkill" adapters/claude-code/scripts adapters/claude-code/hooks   # every kill site; each must verify identity (cmdline match) or provable orphanhood first
  Required fix: REQ-A1's kill step verifies the target's command line contains nl-maintenance --daemon (MSYS2: /proc/<pid>/cmdline, fallback ps -p) before killing; on identity mismatch, log-and-skip (the relaunch still proceeds; two daemons briefly coexisting is bounded by the new sf_release semantics, killing an innocent process is not bounded by anything).
  Required generalization: no harness mechanism ever kills by stored pid alone — identity or provable orphanhood is checked at kill time, per the estate's own safe-sweep doctrine.
```

```
- Line(s): design REQ-B10 ("reject ^#+.*(Addendum|Round [0-9]|Update:) headings ...; escape = none needed"); vs the corpus measurement in my evidence trail (5 files fire today, incl. docs/plans/review-gate-identity-anchor-2026-07-30.md:249,304 — legitimate review-round records) and the design's own §2 binding (every new/extended gate emits {WHAT/WHY/FIX/ESCAPE})
  Severity: Major  [M-9]
  Confidence: PROVEN (grep -rniE over docs/designs/ + docs/plans/ at HEAD; the Round-N review-record heading convention is live practice — my own prior reviews are recorded that way inside plans)
  Defect: The lint's regex fires on the estate's established review-round record headings ("### Round 3 — harness-reviewer REJECT on 34e69fc"), and REQ-B10 ships it with NO escape hatch — contradicting the design's own §2 gate contract and 2.8's escape bar — so the only remedy for touching a historical file is rewriting the historical record's headings: a false positive whose "fix" damages record fidelity. Case-sensitivity is also unstated (it changes the fire set materially).
  Class: content lint whose pattern collides with an established legitimate convention + block-mode gate shipped escape-less
  Sweep query: rg -rniE '^#+ .*(Addendum|Round [0-9]|Update:)' docs/designs/ docs/plans/   # rerun per candidate pattern revision until the fire set is exactly the abuse class
  Required fix: Narrow the pattern (exclude "Round [0-9]+ —" review-record shapes, or scope Round-matching to docs/designs/** only — the golden case lives there), state case-sensitivity, add the standard fresh-waiver escape (lib/waiver-purpose-clause.sh shape, ledgered), and add a negative self-test case using the review-gate-identity-anchor headings verbatim.
  Required generalization: every content lint's pattern is measured against the live corpus BEFORE it ships, and the measured legitimate hits become its negative self-test fixtures — the design already did exactly this for Check 17's keyword set (the 27% measurement); the same discipline applies to its own new lint.
```

```
- Line(s): design §7 net-score row ("−1 practice-ban enforced") + design-author displacement row ("the blank-slate/workflow-agent authoring path (P-31) — banned for design docs")
  Severity: Major  [M-10]
  Confidence: PROVEN (no REQ, gate, or check in the design fires on the authoring path of docs/designs/*.md; G1's chain requirements verify design REVIEWS, not authorship; nothing blocks a workflow agent from writing a design doc)
  Defect: "Banned ... enforced" is a Mechanism-class claim with no mechanism — constitution §10's cardinal defect (documented enforcement that does not fire) written into the design's own anti-bloat scorecard. The review-requirement partially compensates (an unreviewed design cannot feed a chained plan), but the ban itself is a convention.
  Class: enforcement claimed in prose for a surface no mechanism covers (§10 theater, at design time)
  Sweep query: rg -n "banned|enforced|impossible" docs/designs/gated-pipeline-master-2026-08-03.md   # every enforcement verb; each needs a mechanism citation or a rewrite to convention language
  Required fix: Either wire a minimal authorship check (the design-template's Review Chain stub carries an authored-by line naming design-author + model, verified by G1's chain parse when design-ref is required), or rewrite the claim honestly: "displaced by convention + the review requirement (a design no reviewer passed cannot feed a plan); authoring-path enforcement is a named residual."
  Required generalization: the D-07 displacement ledger obeys §1's claim discipline like any other artifact — "enforced" in the ledger requires a mechanism citation, exactly as it would in doctrine.
```

```
- Line(s): design §8 item 1 (bootstrap) + REQ-B3/REQ-B8 ordering
  Severity: Major  [M-11]
  Confidence: PROVEN for the sequencing gap (the plan's plan-reviews chain entries require a plan-fidelity-reviewer record; that agent is created BY this plan at REQ-B3; G2 ships blocking and goes live estate-wide on merge via session-start-auto-install; no REQ sequences the self-review before G2 activation — "§8: this design + its two reviews satisfy G1/G2's intent manually" conflates manual intent-satisfaction with mechanical parse-satisfaction, which is the P-30 distinction this design exists to enforce)
  Defect: If REQ-B8 lands before plan-fidelity-reviewer has reviewed THIS plan and its chain entry is committed, every remaining builder dispatch of the pipeline's own plan blocks. The remedy is reachable in-session (dispatch the new reviewer, commit the entry) so this is not exit-less — but the pipeline's own birth should not be its first unplanned block.
  Class: gate activation ordered before its own satisfying artifact can exist (bootstrap sequencing left implicit)
  Sweep query: rg -n "REQ-B3|REQ-B8" docs/designs/gated-pipeline-master-2026-08-03.md   # the plan must carry an explicit ordering edge between them
  Required fix: Add an explicit sequencing REQ: (1) REQ-B3 agent lands → (2) plan-fidelity-reviewer reviews THIS plan, record committed, chain entry added (this step is currently NO REQ — make it one) → (3) REQ-B8/G2 lands. State it in §8 item 1 in mechanical terms, replacing "satisfy intent manually."
  Required generalization: every self-hosting gate's design states the exact commit-ordering that makes its own build legal under it — "the plan carries the chain from birth" must be literally true of every chain FIELD the gate parses, not just the block's presence.
```

**Minor findings (summary form):**

- **Mi-1 (D-07 ledger undercount):** §7's additions row omits `scripts/dispatch-directives.sh` (REQ-B11) and leaves G1's status (new hook file vs prd-validity-gate extension) ambiguous — if new, "+1 gate" undercounts. The honesty ledger should count every new file. PROVEN by cross-reading §4/§6 vs §7.
- **Mi-2 (manifest entries for Phase-B mechanisms not REQ'd):** no REQ mandates manifest.json entries for G1/G2/G3-ext/no-addendum/jit-walk/review-chain-lib — the F9 class recurring — but `manifest-check.sh:555` REDs disk hooks absent from the manifest, so it is self-catching. Add "manifest entry in the same commit" to each REQ's verification line anyway (the F9 generalization: same merge train, not a follow-up).
- **Mi-3 (G1 routine-escape threshold):** at a 27% keyword base-rate, `design-ref: n/a` justifications become routine for small plans; per D-04, state the n/a-rate above which the trigger set gets recalibrated (weekly ledger review is named; the acting threshold is not).
- **Mi-4 (frontmatter pin wording):** REQ-B2/B3 say "pinned fable/opus in frontmatter"; the frontmatter `model:` field holds a single value (chain[0]) with the chain in model-policy.json (its own note says so). Wording fix so the builder doesn't invent a two-value frontmatter.
- **Mi-5 (G2 repo resolution):** `docs/plans/<slug>.md` relative to which repo root for cross-repo dispatches is unspecified; state the resolution rule (session cwd's toplevel, with the no-repo case passing WARN).
- **Mi-6 (G1 demotion condition absent):** G2 has one; G1 states flip dates but no FP-driven demotion condition. Add the same ledgered-FP data-file condition for symmetry with §2's own bar.

## Universal checks

- Hallucinated/unverified infrastructure: **PASS** — every load-bearing citation I checked (14 sites) is accurate at HEAD `6e28a82c`; gate-contract-lib, workaround-sensor, NL-ATTRIBUTION, hygiene-scan pre-commit chain, and the pre-push funnel all exist as claimed.
- Causal attribution: **PASS** — P-29/P-30/P-31/P-32/P-39/P-40 attributions verified against the inventory; P-42's re-derivation is honest.
- Conflicts with existing rules: **REJECT as specced** — REQ-B10's "escape = none needed" conflicts with the design's own §2 {WHAT/WHY/FIX/ESCAPE} binding (M-9); "banned ... enforced" conflicts with §10's theater prohibition (M-10).
- New failure modes introduced: **REJECT as specced** — C-1 (JIT channel regression), C-2 (activation-day estate-wide over-fire), M-8 (pid-reuse kill).
- Two-layer-config / docs coupling: **PASS with Mi-2** — repo-canonical flow assumed throughout; manifest coupling under-specified but mechanically backstopped.

## What is genuinely good (do not regress it in reformulation)

The review-chain parse-by-construction defeat of derived records; gate placement at the three correct moments with the push funnel kept authoritative; every REQ-A item transcribing my required-fix text nearly verbatim (F5, F6, F7 verbatim); the F7 lesson mechanized everywhere (every flip is a data-file date); G2 riding Task|Agent with zero per-Bash cost and the JIT walk riding an existing hook (no new spawns — the P-04/P-05 lesson held); DEC-8's overengineering cuts; REQ-A6's honest predecessor closure; §8.6's forgery residual named rather than overclaimed.

## Summary for the author

REFORMULATE, not REJECT: the chain architecture, gate placement, and Phase-A fidelity are sound, and most reformulation items are additive spec lines rather than redesigns. The single most important fix is **C-2**: give G2 a grandfather/transition story for the estate's existing chain-less plans, or activation day will either train routine escape use or trip the gate's own demotion condition in week one — both of which forfeit the D-15 acceptance bar this entire design exists to hold. Fix **C-1** by restructuring the doctrine-jit register walk as compute-both-emit-once (the current spec's no-starvation claim is false on a single-JSON-stdout channel). Then restore the dropped **F3** with a disposition (M-1) — a silently dropped PROVEN Major inside the design that exists to make silent drops impossible is the finding your own plan-fidelity-reviewer must never be able to make again.
