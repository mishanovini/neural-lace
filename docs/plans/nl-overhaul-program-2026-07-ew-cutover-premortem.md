# §E.W cutover pre-mortem + verbatim checklist (authored 2026-07-03, Fable, for the Wave-E orchestrator)

The §E.W integration is the program's SECOND live cutover. The first (D.5) failed
mid-run on a locked file and left a stale live manifest that produced 20 false doctor
REDs (NL-FINDING-017). This file is the executable protection. Run it top to bottom;
each step has a verify command; stop at any FAIL and use the rollback block.

## Known failure modes to design against (all observed, 2026-07-03)

1. **Locked-file install abort (NL-FINDING-017).** `install.sh` mv-backup dies on a
   held-open hook → PARTIAL live state. E.10 ships copy-then-verify; confirm it
   actually landed before cutover: `grep -n "copy" adapters/claude-code/install.sh`
   shows the new backup path, and the old `mv "$HOME/.claude/hooks"` form is gone.
2. **Stale live manifest** → doctor claim-honesty REDs. After install:
   `cmp <(git -C <repo> show master:adapters/claude-code/manifest.json) ~/.claude/manifest.json`.
3. **Sessions alive during cutover** snapshot the OLD chain (ADR 058 pin c): every
   retired/renamed live hook path gets an exit-0 shim for one release. For WRITER
   hooks a plain exit-0 shim SILENTLY DROPS WRITES and downstream gates then block
   honestly (observed class, NL-FINDING-024 diagnosis) — writer shims must EXEC the
   successor (`exec bash "$(dirname "$0")/<new-name>.sh" "$@"`), not exit 0.
4. **Writer→gate PreToolUse race (NL-FINDING-024).** Hooks on one matcher run
   CONCURRENTLY. If E.W rewires any writer+gate pair, do not rely on listed order;
   the gate needs its own write-then-verify or bounded re-read.
5. **Concurrent sessions racing master.** 4 ID collisions + 3 non-FF pushes on
   2026-07-03. Freeze window: announce in SCRATCHPAD coordination file BEFORE
   cutover ("E.W CUTOVER IN PROGRESS — no master pushes"), fetch+merge immediately
   before tagging, and verify `git log master..origin/master` is empty at tag time.
6. **PreCompact is a HYPOTHESIZED channel** (batch-1 note): E.9b's PreCompact hook
   fires only if the runtime supports the event. The manifest schema needs the enum
   BEFORE the doctor validates it; and the cutover must not claim the channel works —
   keep the snapshot+compact-echo fallback wording until a live compaction proves it.

## Verbatim checklist

```
# 0. Preconditions
git -C <repo> log master..origin/master   # -> empty
bash ~/.claude/hooks/harness-doctor.sh --quick   # -> GREEN before you start
# announce freeze in SCRATCHPAD (see §5 above)

# 1. Tag rollback point (repo) + snapshot live (machine)
git -C <repo> tag pre-wave-e-cutover && git -C <repo> push origin pre-wave-e-cutover
cp ~/.claude/settings.json ~/.claude/settings.json.bak-wavee
cp ~/.claude/manifest.json  ~/.claude/manifest.json.bak-wavee

# 2. Apply template/manifest/doctor/install edits ON A BRANCH, PR, merge to master
#    (never direct-to-live). Chain assertions BEFORE merge:
node -e "const s=require('<repo>/adapters/claude-code/settings.json.template'.replace(/\\\\/g,'/'));/*json.template needs readFileSync — use jq instead if require fails*/"
jq '.hooks.Stop|length, .hooks.SessionStart|length' <(sed 's/\r$//' adapters/claude-code/settings.json.template | grep -v '^\s*//')   # Stop<=6 (target 4), SessionStart<=8

# 3. Install to live; THEN verify independently (do not trust install exit code):
bash adapters/claude-code/install.sh
cmp <(git show master:adapters/claude-code/manifest.json) ~/.claude/manifest.json && echo MANIFEST-FRESH
for h in <every retired-or-renamed hook name>; do echo '{}' | bash ~/.claude/hooks/$h; echo "$h exit=$?"; done   # writers exec successor; gates exit 0

# 4. Post-install verification battery (all must pass before declaring):
bash ~/.claude/hooks/harness-doctor.sh --quick        # GREEN
for t in evals/golden/*.sh; do bash "$t" || echo FAIL:$t; done   # zero FAIL
bash ~/.claude/hooks/harness-doctor.sh --full </dev/null   # background; GREEN (1500s/hook budget; ~85 min)
# E.7 drill: register + kill a dummy session, assert resumer restarts it (specs-e §E.7)
# NL-FINDING-022: schtasks //query //fo LIST //v | grep -i <heartbeat task name>  -> present (or the mode was deleted; docs must match — specs-f §F.2)

# 5. Un-freeze, push both remotes (gh auth switch dance for personal), update
#    SCRATCHPAD, record evidence in the plan evidence file.
```

## Rollback (any FAIL above)

```
git -C <repo> reset --hard pre-wave-e-cutover   # ONLY if not yet pushed; if pushed, revert-commit instead (never force-push)
cp ~/.claude/settings.json.bak-wavee ~/.claude/settings.json
cp ~/.claude/manifest.json.bak-wavee  ~/.claude/manifest.json
bash adapters/claude-code/install.sh            # re-sync live from the rolled-back master
bash ~/.claude/hooks/harness-doctor.sh --quick  # must be GREEN again; file a finding for the failed step
```

Do not out-wait a red; do not declare on "targeted equivalent" for THIS cutover — the
full sweep is the bar (it is now proven achievable: GREEN 8/8 on 2026-07-03).
