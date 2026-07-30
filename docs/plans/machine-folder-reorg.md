# Plan — Machine folder reorganization: three roots, every project home

Status: ACTIVE
Key: ORG
Mode: code
rung: 1
Owner: 2026-07-30 operator directive (verbatim below)
parent-thread: estate hygiene (worktree-hygiene-sweep, estate-registration)

## Operator requirement (verbatim, 2026-07-30 — the spec)

"I want Claude to clean up the organization of the dev/claude folders on all my
computers. It has created such a mess on my Windows machines creating folders and
worktrees scattered all over the place. The organization should be simple: 3 top level
folders organized by GH account plus NL (Personal, Pocket Technician, Neural Lace),
with all the projects organized into those appropriate folders. I haven't worked on
PT/Circuit on this machine lately so there's probably not much there."

## Target layout (every machine)

```
<dev root>/
  Personal/           <- projects on the personal GH account
  Pocket Technician/  <- projects on the work/PT GH account (incl. Circuit)
  Neural Lace/        <- the harness repo + its satellites
```

Dev root stays each machine's existing convention (`~/Claude` on the Mac; the
Windows machines' root is confirmed during inventory, not assumed). Worktrees stay
INSIDE their repo's `.claude/worktrees/` — scattered external worktrees are the named
mess and get graduated (close-worktree.sh) or removed, never orphaned.

## Hazards (why this is a migration, not a `mv`)

- On the Mac, `~/.claude/*` are SYMLINKS into the neural-lace repo; LaunchAgents
  (cockpit :7733, coord-sync, limit-resume) carry absolute paths; gh account
  auto-switching keys on `$PWD`; live worktrees carry absolute gitdir pointers.
  Moving the repo mid-flight strands all of it — Mac execution is gated on THE MERGE
  landing and all in-flight worktrees graduating first.
- Windows machines need on-machine inventory before any move plan is real.

## Tasks

- [ ] ORG1 — Mac inventory + mapping: enumerate every directory under the dev root
  (plus any strays outside it), map each to its target folder, name every
  path-bearing dependency (symlinks, LaunchAgents, configs, worktrees). Output:
  `docs/reviews/machine-folder-reorg-mac-inventory.md`. Verification: full.
- [ ] ORG2 — Migration script `adapters/claude-code/scripts/estate-relocate.sh`:
  dry-run default, move + rewrite symlinks/LaunchAgent plists/config paths +
  post-move `harness-doctor.sh --quick` gate; `--self-test` sandboxed. Verification: full.
- [ ] ORG3 — Mac execution (GATED: post-merge, zero live worktrees): run ORG2,
  doctor GREEN, cockpit + coord-sync verified running from new paths. Verification: full.
- [ ] ORG4 — Windows inventory: same as ORG1 per Windows machine, produced by a
  session on that machine (or an operator-run inventory script if no session
  reachable); includes the scattered-worktree census. Verification: full.
- [ ] ORG5 — Windows migration: per-machine execution of the mapping with the same
  post-move verification (Windows carrier: install.sh copy model, no symlinks).
  Verification: full.
- [ ] ORG6 — Anti-scatter guard: hygiene check (doctor or worktree-hygiene-sweep)
  WARNs on any project checkout outside the three roots so the mess cannot silently
  return. Verification: full.

## Files to Modify/Create

- docs/reviews/machine-folder-reorg-mac-inventory.md (ORG1)
- adapters/claude-code/scripts/estate-relocate.sh (ORG2, new)
- docs/reviews/machine-folder-reorg-windows-inventory.md (ORG4)
- adapters/claude-code/scripts/worktree-hygiene-sweep.sh or
  adapters/claude-code/hooks/harness-doctor.sh (ORG6 — whichever the guard fits;
  decided at ORG6 build time)
- ~/.claude/local per-machine configs + LaunchAgent plists (ORG3/ORG5 execution
  surface, rewritten by ORG2's script, not hand-edited)

## Decisions Log

- D1 (2026-07-30, decide-and-go): folder names exactly as the operator gave them —
  `Personal`, `Pocket Technician`, `Neural Lace` (spaces preserved). Circuit files
  under `Pocket Technician` (operator groups "PT/Circuit"). Reversible by rename.
- D2 (2026-07-30, decide-and-go): Mac execution sequenced AFTER the harness-hardening
  merge + worktree graduation — relocating the repo under 4 in-flight worktree lanes
  would strand them (hazards above). Reversible: it is an ordering, not a design.
- D3 (2026-07-30, decide-and-go): worktrees live inside `.claude/worktrees/` of their
  repo on every machine — that is the existing Mac convention and the sweep tooling
  already assumes it; the Windows scatter is the deviation being repaired.
