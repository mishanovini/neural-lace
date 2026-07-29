# Incident Review — First-time NL install on macOS (2026-07-14)

Local-only (docs/reviews/* is gitignored). Full-detail root-cause + remediation
record for the first Neural Lace install on this machine. Source of the backlog
entries and the SETUP/README updates that accompany this session.

## Context

- Fresh macOS machine (Darwin 25.3.0, APFS). First NL install here.
- `gh repo clone Pocket-Technician/neural-lace` + `Circuit` into `~/Claude/`.
- Install path: `install.sh` (base) then `install.sh --replace-settings`.
- Node/gh/jq/bash/Claude Code all present. Not under iCloud. No 3rd-party AV.

## Issues encountered (5)

### I1 — `hooks/lib/` (15 files) missing after clone → ~40 gate hooks broken
The most serious. After clone, `adapters/claude-code/hooks/lib/` was empty; git
showed the 15 files as ` D` (present in index, absent from worktree). The
installer copied the empty dir into `~/.claude/hooks/lib/`, so every hook that
`source`s `lib/*.sh` (signal-ledger, nl-paths, waiver-purpose-clause,
hook-reentry-guard, stop-hook-retry-guard, workstreams-state-resolver, …) would
fail at runtime. `harness-doctor --quick` = 75 red (mostly `lib-deps`).
During setup the files flip-flopped (restored via `git restore`, gone again a
turn later) before stabilizing.

### I2 — `settings.json` not overwritten by default → harness installed but DORMANT
`install.sh` (base) intentionally does NOT touch an existing `settings.json`, but
NL's hooks live inside it. So a base-only install leaves the harness inert. Needs
`--replace-settings` (or a manual merge). This is documented in the installer's
loud warning and SETUP.md, but it's a sharp first-run edge.

### I3 — `needs-you.sh` and `session-resumer.sh` tracked as `100644` (non-executable)
`git ls-files -s` shows mode `100644`. Doctor flags both (`session-resumer`,
`wave-e-e6-needs-you`). Not local corruption — the repo commits them without the
exec bit.

### I4 — `manifest.json` malformed entry (`session-start-auto-install`)
Its `hooks[]` array wrongly includes the library path
`hooks/lib/sessionstart-singleflight.sh` alongside the real hook
`session-start-auto-install.sh`. That one element causes all 3 `manifest-check`
reds: (a) not a `.sh` basename (schema regex `^[A-Za-z0-9._-]+\.sh$`), (b)
resolves to a doubled `hooks/hooks/lib/…` path (hooks-exist), (c) a sourced lib
isn't wired in `settings.json.template` (wired-template). It is the ONLY hooks[]
element with a slash across the entire manifest. `manifest-check.sh` line 22
states the design intent: `lib/` is a subdirectory and lib files are never hooks.

### I5 — plugin drift (settings template vs prior user set) — minor/expected
`--replace-settings` installed the template's `enabledPlugins`
(added explanatory-output-style + security-guidance; dropped superpowers +
coderabbit). Operator chose to keep the template set as-is. Not a defect; noted
so the delta is on record.

## Root-cause analysis

### I1 — the deletions (the operator's central question)

**Confirmed eliminations (each tested):**
- NOT git config: `git ls-files -v` → all `H` (no skip-worktree/assume-unchanged);
  `git sparse-checkout list` → "not sparse"; no `.git/info/sparse-checkout`;
  `git reflog` → only the clone entry (no reset/checkout removed them).
- NOT iCloud: repo realpath is `~/Claude/…`, not under `~/Library/Mobile
  Documents`; `find -name '*.icloud'` → 0 placeholders.
- NOT third-party AV / EDR: none installed (only Apple TimeMachine + iCloud
  daemons present, neither of which deletes source files in a non-synced path).
- NOT a concurrent Claude session: exactly one `claude` CLI process.
- NOT the installer's backups: `.backup-*/` dirs contain 0 lib files.
- NOT XProtect: no `XProtectRemediator` activity in the window.
- NOT the files themselves: ordinary shell scripts, no self-delete logic; restored
  from byte-identical git blobs (4KB–164KB) and stable ever since.

**Cause (HYPOTHESIZED — stated honestly):** an incomplete/interrupted checkout of
the `hooks/lib/` subtree during `gh repo clone` (git shells out to `git clone`;
the checkout phase left those files present-in-index / absent-in-worktree — the
exact ` D` state observed). Repeated `install.sh` runs then propagated the empty
dir into `~/.claude`. The mid-setup "re-deletions" between turns are the part I
cannot forensically attribute: macOS does not log userland `unlink()` by default
and no `fs_usage`/dtrace tracer was running at the time, so no after-the-fact
process attribution is possible. What IS certain: no active/persistent deleter
was found, and the tree has been stable since the files were written from git
blobs (mtime 13:57, unchanged since; 0 `D` in status).
**Refuter (what would overturn this):** if `hooks/lib/` empties again on a quiet
machine with no install/clone running, then an active deleter exists and the
"transient checkout" theory is wrong — re-run the process/log capture with
`sudo fs_usage -w -f filesys | grep hooks/lib` live at the moment of deletion.

### I2 — dormant harness
Root cause: base install deliberately preserves an existing `settings.json`
(good — avoids clobbering user config), but NL's enforcement lives inside that
same file, so "installed" ≠ "active". Design tension between non-destructive
install and hook activation.

### I3 — exec bits
Root cause: the two scripts were committed without the exec bit (mode 100644).
On a clean POSIX checkout they stay non-executable, so the doctor flags them.
Authoring defect in the repo, not a local one.

### I4 — manifest entry
Root cause: authoring error — a lib dependency was hand-listed in the `hooks[]`
array. The manifest schema only accepts wired-hook basenames there; lib deps are
expressed by the `source` line in the hook and validated separately by the
doctor's `lib-deps` check. So the manifest entry duplicated (incorrectly) info
that is already covered elsewhere.

## What good fixes look like

### Immediate (this session)
- **I4:** remove `"hooks/lib/sessionstart-singleflight.sh"` from the
  `session-start-auto-install` `hooks[]` array → `["session-start-auto-install.sh"]`.
  Mirror `adapters/claude-code/manifest.json` → `~/.claude/manifest.json`.
  Verify: `manifest-check.sh` clean; doctor loses the `manifest-check` red.
- **I3:** `git update-index --chmod=+x` (and `chmod +x`) on both scripts so the
  tracked mode becomes `100755`; reinstall preserves it. Verify: doctor loses
  `session-resumer` + `needs-you` reds.

### Hardening (so I1 + I2 never recur) — the real prevention
- **H1 (clone integrity gate):** `install.sh` must, at start, run a completeness
  check — `git -C <repo> status --porcelain | grep '^ D'` (or compare
  `git ls-files` against the worktree) and **ABORT loudly** if any tracked file
  is missing, instead of silently copying gaps. "synced hooks/lib/ (0 files)"
  for a dir that has 15 tracked files must be a RED, not an OK line.
- **H2 (source from git, not just worktree):** for critical trees (`hooks/lib/`),
  install could fall back to `git show HEAD:<path>` when a worktree file is
  missing — this is exactly the manual workaround that fixed it and would make
  the install robust to a partial checkout.
- **H3 (post-clone verify in SETUP):** document a one-liner the user runs right
  after clone: `git status --short | grep '^ D' && echo "INCOMPLETE CHECKOUT —
  run: git restore ."`. Cheap, catches I1 before install.
- **H4 (doctor is the safety net — keep it):** the `lib-deps` check is what
  surfaced I1. It worked. Its existence is the reason this was caught, not shipped.
- **H5 (activation clarity for I2):** SETUP/README should make the "installed vs
  active" distinction unmissable and give the copy-paste activation command; the
  installer already warns — reinforce in docs + a first-run doctor line.
- **H6 (exec-bit lint):** a pre-commit/CI check that every `hooks/*.sh` and
  `scripts/*.sh` referenced as executable is tracked `100755` would have caught I3.

## Lessons learned
1. A fresh clone is not automatically a complete clone — verify tracked-file
   completeness before building on it, especially on macOS/APFS.
2. "Installed" and "active" are different states for a hook-based harness; the gap
   must be loud in docs and tooling.
3. The doctor's claimed-vs-actual philosophy paid off — the `lib-deps` check
   turned an invisible breakage into a visible red. More such integrity checks
   (H1, H6) are high-leverage.
4. Silent zero-count syncs ("0 files") are a code smell; make them fail.
5. Forensic honesty: when the OS can't tell you who deleted a file, say that —
   don't manufacture a culprit.

## How to report back (for permanent resolution)
- **Committed, prioritized:** add P1 entries to `docs/backlog.md` for I3
  (exec bits), I4 (manifest), H1 (install integrity gate), H6 (exec-bit lint),
  and a P2 for H2 (git-fallback install) + H5 (activation docs). Sanitized.
- **Machine-wide friction ledger:** `nl-issue.sh "<one line>"` per constitution §5
  for each defect noticed, so weekly triage picks them up.
- **This review** is the detailed backing record (local-only) the backlog entries
  point to.
