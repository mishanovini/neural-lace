# Design — auto-compact at ~85% instead of at the context wall (2026-07-22)

Researcher: research agent (opus), read-only. Operator ask (verbatim, 2026-07-21): "add automatic
compaction once [the pre-compaction save] takes place so that we never actually run the risk of
hitting the limits." Persisted per constitution §5.

## 1. Current behavior (PROVEN)

- **Nothing in this harness triggers compaction, and nothing configures when the platform does.**
  `grep autoCompact|auto_compact` across the whole repo → ZERO matches.
- Live `~/.claude/settings.json` (700 lines) and `adapters/claude-code/settings.json.template`
  both have NO `env` block and no compaction key.
- `autoCompactEnabled` defaults TRUE → platform auto-compact is ON, at its DEFAULT trigger.
- **PROVEN (official docs, code.claude.com/docs/en/env-vars):** on a local session on Opus 4.8
  (this harness's main model) auto-compaction triggers when the conversation reaches **the
  model's context limit** — i.e. at the wall, which is exactly the operator's complaint.
- `context-watermark.sh:391-406` at ≥85% writes markers + runs `session-snapshot.sh` + injects a
  nag. It never touches compaction. `pre-compact-continuity.sh` is a PreCompact hook — it fires
  only AFTER something else already decided to compact.

## 2. What is possible

### IMPOSSIBLE — stated plainly
**No hook can trigger compaction.** Official hooks reference: there is no hook output field,
decision value, exit code, or JSON directive that can trigger or request compaction. Compaction
is initiated by Claude Code's internal logic or by the user via `/compact`. The asymmetry:
**PreCompact can BLOCK compaction** (`decision: block` / exit 2) but nothing can START it. So the
operator's literal framing (save → then compact) CANNOT be built as a causal chain.

### POSSIBLE — and it fully achieves the goal
Two documented environment variables move the platform's own trigger point:

| Variable | Effect |
|---|---|
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | context capacity in tokens used for auto-compaction math; **capped at the model's actual window** |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | percent (1-100) of that window at which auto-compaction fires; **can only LOWER** the threshold; applies to main conversations AND subagents |

LOAD-BEARING: the pct override "only causes earlier compaction when Claude Code compacts
PROACTIVELY: when `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set, in cloud sessions, and on
Sonnet 4.6/Opus 4.6 without extended context." **Setting the WINDOW var is what flips Opus 4.8
out of compact-at-the-limit into proactive mode. Both must be set — the percentage alone is a
no-op on this machine.**

NOTE: three open GitHub FRs (#66475, #41818, #34925) ask for a settings.json `autoCompactThreshold`
key. It does NOT exist — the env vars are the real surface. Don't hunt for a JSON key.

## 3. Recommended mechanism (no hook code change)

```jsonc
"env": {
  "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000",
  "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "85"
}
```
Why 1000000: the value is capped at the model's real window and the percentage applies to the
capped result — so ONE static value is correct for every model (85% of 1M on Opus 4.8; 85% of
200k = 170k on a Haiku subagent). It also keeps the compaction trigger aligned with
`context-watermark.sh`'s own 85% math.

**Exact files:**
1. `adapters/claude-code/settings.json.template` — add `env` as a top-level key (canonical).
2. `~/.claude/settings.json` — **MUST be edited directly too.** THE TRAP (PROVEN):
   `session-start-auto-install.sh:333-412` (`merge_settings`) merges ONLY `.hooks.<Event>[]`
   entries from a hardcoded event list — it never touches top-level keys, so an `env` block is
   INVISIBLE to it; and `install.sh:272` never overwrites settings.json by default. The only
   carrier is `install.sh --replace-settings`, which wholesale-replaces live settings (live has
   drifted: extra permissions, skipWorkflowUsageWarning; template has effortLevel: max) and
   would clobber that drift.
   → Either (a) apply the edit to BOTH files, or (b) **extend `merge_settings` to additively
   merge the `env` key** — the more durable fix, making this and every future `env` setting
   deployable the normal way. (b) preferred.

**Threshold = 85**: matches the operator's ask and the existing watermark exactly; leaves ~150k
headroom on a 1M window (more than one full 128k max-output turn). Higher (88-90%) would leave
less than a single max-output turn.

## 4. THE COUPLED FIX (do not ship without it)

**The snapshot is written but NEVER READ BACK.** PROVEN: the SessionStart `matcher: "compact"`
echo (`~/.claude/settings.json:640`) tells the model to read SCRATCHPAD.md, the plan, and the
backlog — it never mentions `~/.claude/state/session-handoff/`. `grep session-handoff` against
the template returns NO matches. This is the open orchestrator TODO at
`pre-compact-continuity.sh:76-80`. It is a ONE-LINE echo edit and it is what makes the whole
mechanism load-bearing instead of decorative.
**Shipping the env vars without this = more frequent compactions whose saved state nothing reads.**

## 5. Risks

- **In-flight orchestration** (HYPOTHESIZED): compaction rewrites the parent context only;
  spawned agents are separate sessions and keep running; `.claude/state/spawned-task-results/*.json`
  persists and `session-snapshot.sh:193-216` lists unacked task-ids. Refuter: compact with a live
  background agent, confirm its completion notification still lands.
- **What the save contains** (all mechanical/zero-token, `session-snapshot.sh:120-286`): git
  branch/HEAD/porcelain(head -100)/uncommitted count; worktree list; orchestrator+conversation-tree
  state; unacked spawned-task ids; ACTIVE plan + unchecked count + first unchecked task;
  NEEDS-YOU.md (head -80); full SCRATCHPAD.md verbatim if stale >30min.
- **Re-entrant child sessions save NOTHING** (`pre-compact-continuity.sh:251-265`): under
  `NL_HOOK_REENTRY=1` the hook writes only a heartbeat — automation-spawned children that compact
  get zero continuity artifact.
- **Judgment categories unprotected** (`session-snapshot.sh:41-50`): operator directives,
  decisions+rationale, hard-learned constraints, verified-vs-claimed are NOT mechanically
  reconstructable — they depend on the summarizer honoring the PreCompact instructions, a channel
  marked HYPOTHESIZED/never-verified. Compacting 5-10x more often multiplies exposure.
- **False-alarm lesson** (`docs/lessons/2026-07-20-context-watermark-window-and-context-pressure.md`):
  a session abandoned 28 of 34 work items misreading a watermark as a stop condition. Making
  compaction real at 85% is the CORRECT answer to that lesson; update
  `context-watermark.sh:389`'s "compaction handles overflow automatically" to say it fires at 85%.

## 6. Review requirement (PROVEN — hard-blocks if skipped)

`settings.json.template` is in-surface and review-gated: `install.sh:451,:1070` call
`_review_gate_check_file` and ABORT the whole install when uncovered;
`session-start-auto-install.sh:476-482` skips the merge with a loud warning. Needs a
`harness-change-review` PASS record matching the new blob_sha. Editing
`session-start-auto-install.sh` (option b) is in-surface too and needs the same.

## 7. Smallest correct build

1. Two env vars (template + live, or merge_settings extension).
2. Point the post-compact SessionStart echo at the snapshot file (§4).
3. One harness-change-review record.

## 8. Open caveat (HYPOTHESIZED)

Setting `CLAUDE_CODE_AUTO_COMPACT_WINDOW` EQUAL to the model window (rather than below it) may
not flip proactive mode — docs say "when set" and "capped at the model's actual context window"
but don't test the equal case. **Refuter: set both vars, run a session past 85%, confirm
compaction fires before the limit. If it doesn't, drop the window to 900000 and re-test.**

Sources: code.claude.com/docs/en/hooks · /settings · /env-vars · github.com/anthropics/claude-code/issues/66475
