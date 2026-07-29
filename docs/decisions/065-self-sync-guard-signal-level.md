# 065 — self-sync guard: shared detection, carrier-specific signal level

**Date:** 2026-07-29
**Status:** Accepted
**Tier:** 2 (reversible: the presentation choice below can be flipped in one commit
without touching the detection primitives or any on-disk state)
**Context plan:** docs/plans/macos-portability-2026-07.md

## Decision

`session-start-auto-install.sh` gets the SAME SELF-SYNC-01 detection primitives as
`install.sh` (`resolve_real_path`, `_sync_self_check`, `_resolves_into_dir`), extracted
into one shared file, `adapters/claude-code/hooks/lib/self-sync-guard.sh`, sourced by
both. The two carriers deliberately DIFFER in how they PRESENT a detected self-sync:

- `install.sh` (operator-present, runs rarely): a full explanatory block printed to
  stdout per skipped call (`sync_is_self_sync()`, unchanged from 4e29dc6).
- `session-start-auto-install.sh` (unattended, runs on EVERY SessionStart): every skip
  folds into a counter, `N_SELF_SYNC_SKIPPED`, that appears UNCONDITIONALLY in the
  one-line stderr summary this hook already prints on every run, plus one detailed line
  per skip in the run log (`state/auto-install-log-*.txt`) for forensic replay.

## Why NOT one shared presentation too (the question this doc exists to answer)

The obvious follow-up: if the detection is shared, why isn't the message? Two carriers
with different audiences and different call frequencies need different loudness, and
picking the WRONG one for either is actively harmful:

- **install.sh's per-call block would be spam here.** On a symlink-based install (this
  Mac, by operator directive — `docs/plans/macos-portability-2026-07.md` "Why"), EVERY
  canonical file in EVERY synced subdir (hooks/scripts/agents/rules/templates/skills/
  doctrine) legitimately self-sync-skips on EVERY SessionStart, forever — that is the
  steady state, not an exceptional event. A multi-line explanatory block per file, every
  session, teaches the operator to skim past this hook's stderr entirely, which is worse
  than saying nothing: it burns the "loud" signal on noise so the one time it needs to
  carry real information (a genuine drift or a topology change), nobody reads it.
- **A pure silent skip (install.sh's own posture, unmodified) is ALSO wrong here, and
  the task instruction is right to worry about it.** install.sh's silence is safe
  because a human is watching stdout in real time for a ceremony that runs rarely — the
  operator IS the loud channel. `session-start-auto-install.sh` has no such human in the
  loop; if its skip were as quiet as install.sh's, the fact that "every deploy on this
  machine is now a no-op" (correct, given the topology, but exactly the kind of fact that
  used to be surfaced only via a stale hook nobody noticed) would have no routine signal
  at all.

## The chosen middle ground

Fold into the counter that is ALREADY part of the routine, always-printed summary line
(`$N_INSTALLED installed, $N_UPDATED updated, ..., $N_SELF_SYNC_SKIPPED self-sync-skipped`).
This is:
- **Always present**, not gated behind an if-nonzero check (unlike the log-file summary
  line, which only fires when something changed) — so "0 self-sync-skipped" and "12
  self-sync-skipped" are both routinely visible, at the fixed cost of one number, every
  run, forever. An operator who never reads this line was never going to read a verbose
  block either; an operator who glances at it occasionally now has a standing signal for
  "is this machine in symlinked-topology mode" without needing to go looking.
- **Cheap to add, cheap to keep**: it composes with the existing `N_REVIEW_SKIPPED`
  precedent in the same line (harness-review REFORMULATE, 2026-07-16), so this is not a
  new UI convention, it is the existing one extended by one field.
- **Not spam**: one number per run vs. N files' worth of explanatory text per run.

## Consequences

- A genuinely NEW self-sync condition (e.g. an operator just symlinked a subdir that
  used to be a real copy) is only distinguishable from "steady state, same as every
  other run" by watching the counter change between runs, not by a one-time alert. This
  is an accepted trade-off: the alternative (alerting on every transition) needs
  run-to-run state this hook does not currently keep, and is out of scope for the
  emergency fix this decision accompanies.
- Per-skip forensic detail is not lost — it lives in the run log
  (`state/auto-install-log-*.txt`), one line per file/prune/settings-skip, exactly
  parallel to how `N_UPDATED`'s per-file detail lives there today.
- If this trade-off proves wrong in practice (operators report the counter is never
  actually read either), the fix is a one-line change to also echo a single aggregate
  WARN when the counter is nonzero for the FIRST time in a run — cheap, reversible,
  deferred until there's evidence it's needed.

## Addendum (same day, second incident): a machine-local kill-switch

The guard above fixes the KNOWN self-sync hole. Between landing it and this addendum,
`session-start-auto-install.sh` overwrote committed branch work a SECOND time (~11:0x,
39 files — up from 27 at 09:41:43), same signature, while this fix was still being
built. There was no way for the operator watching it happen to turn the hook off short
of hand-editing `~/.claude/settings.json`'s `SessionStart` chain — machine-local config
this session cannot safely self-modify. That is a defect independent of whatever bug the
hook is currently running: a deploy carrier that can silently destroy work and cannot be
stopped by the person watching it happen needs an off-switch regardless of how well the
currently-known hole is patched.

**Decision:** `main()` checks `$LIVE_DIR/local/no-auto-install` as its FIRST action —
before discovering a checkout, fetching, or touching anything — and returns immediately
if it exists, logging one line naming why and where. A MARKER FILE, not an env var:
an env var set interactively does not survive into this hook's own separately-invoked
SessionStart process, and an operator reacting mid-incident is not "mid-session" in a
shell that could export one for them. `~/.claude/local/` is real per-machine state
(gitignored, never synced by this hook, never a symlink target of anything it touches),
so the marker is exactly as durable and exactly as scoped as it needs to be.

This is a seatbelt, not a substitute for the guard above: it does not detect or prevent
anything, it only gives the operator a lever the incident proved does not otherwise
exist. Self-tested (scenarios 23-24): marker present -> zero files/dirs created
(asserted on the filesystem, not the log line — a log-only assertion is exactly the
false-green class already caught elsewhere this session); marker absent -> unchanged
normal behavior, paired explicitly against scenario 23.

## Judgment call declined: a general "live is newer, don't overwrite" refusal

Raised alongside the kill-switch: should syncing origin/master over locally-newer
content be refused independent of the symlink question, since on any machine (not just
a symlinked one) overwriting uncommitted-or-newer local work is destructive — the
symlink topology just made it unmissable here?

**Declined, with reasons:**
1. **It contradicts this file's own, already-deliberate design.** The header's own "WHY
   master-wins FOR HOOKS/SCRIPTS" section states the operating premise: canonical
   hooks/scripts have NO legitimate machine-local drift, so canonical is SUPPOSED to
   overwrite a differing live copy, always. That premise is what makes the hook's
   entire reason for existing (propagate harness changes across machines without a
   manual install.sh) actually work. A general "maybe don't" would partially undo the
   one thing this hook is FOR.
2. **It would break already-correct, already-tested behavior.** Scenario 4
   (`modified-canonical-hook-master-wins-with-backup`) explicitly encodes "an operator's
   local hand-edit to a live hook gets overwritten by master, with a backup" as the
   INTENDED outcome, not a bug. A general newer-wins refusal would need to distinguish
   that case from the self-sync case, and nothing in the available signal does.
3. **There is no reliable signal to build it from outside the self-sync case.** The
   comparison here is git blob content (no mtime) vs. a live file (mtime exists but is
   not evidence of SEMANTIC recency — a fresh checkout can carry arbitrary mtimes, and a
   deliberate machine-local hack can be older by clock time than an unrelated master
   change and still be the thing the operator wants kept). The self-sync guard doesn't
   need this signal because it asks a different, answerable question: "is the target
   the exact same file as the source," not "which content is newer."
4. **The actual defect is narrower than "master-wins is sometimes wrong."** It is
   specifically that a symlinked topology collapses "sync FROM canonical, TO live" into
   "overwrite the file you just read as canonical, with itself" — nonsensical
   regardless of any wins-policy, and exactly what the guard above detects and skips.
   Solving the broader "is this content genuinely newer" question is a real question,
   but it is not the question this incident asked, and building it without a reliable
   signal risks a DIFFERENT failure mode: master-wins silently stops propagating
   legitimate fixes because some unrelated live drift always looks "newer."

If this reasoning is wrong, the concrete alternative is content-hash provenance
tracking (record the blob_sha of what was last INSTALLED per file, refuse to overwrite
only when live differs from BOTH the last-installed blob_sha AND canonical — i.e., a
real 3-way merge-base check, not a 2-way newer/older guess). That is a materially
bigger change (new per-file state, a new failure mode of its own if the tracking state
itself goes stale) and is out of scope for this fix; tracked as a design question, not
implemented.

## Related, NOT done here (scope boundary, stated explicitly)

`install.sh`'s own SELF-SYNC-01 implementation (4e29dc6, landed ~2 hours before this
decision) is NOT refactored to source the new shared lib in this change. The shared
primitives were extracted fresh for `session-start-auto-install.sh`'s use — satisfying
"don't fork a second copy" for the NEW code — but `install.sh`'s already-shipped,
already-tested (12/12 on both interpreters) inline copy is left as-is. Reasoning:
`install.sh` is the emergency fix for TODAY's incident, verified only hours old, and this
session is expressly forbidden from running `install.sh` itself (it is the script that
caused the data loss being responded to), which removes the most direct way to confirm a
refactor of it didn't regress its own end-to-end flow. Retrofitting it to source
`hooks/lib/self-sync-guard.sh` is tracked as a follow-up in `docs/backlog.md` rather than
bundled into this urgent fix — low risk, but not zero, and not worth taking today when
the alternative (two implementations of ~130 lines, one of them frozen and proven) costs
nothing but a `docs/backlog.md` line until that follow-up lands.
