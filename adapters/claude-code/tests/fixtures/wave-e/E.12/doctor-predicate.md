# E.12 doctor predicate — session end-manifest + world-state assertion sweep

Per `docs/plans/nl-overhaul-program-2026-07-specs-e.md` §E.0.1 rule 3: the
E.12 builder does NOT edit `harness-doctor.sh` directly; this fragment is the
exact predicate for the E.10-class doctor-owning builder (or whoever lands
§E.W) to implement verbatim.

## Predicate 1 — schema + writer/validator scripts present, executable,
## self-test-covered

```bash
check_wave_e_e12_end_manifest() {
  local repo_root="$1"
  local schema="${repo_root}/adapters/claude-code/schemas/end-manifest.schema.json"
  local script="${repo_root}/adapters/claude-code/scripts/end-manifest.sh"

  if [[ ! -f "$schema" ]]; then
    _red "wave-e-e12-end-manifest" "schema missing: $schema"
  elif ! jq -e . "$schema" >/dev/null 2>&1; then
    _red "wave-e-e12-end-manifest" "schema is not valid JSON: $schema"
  fi

  if [[ ! -f "$script" ]]; then
    _red "wave-e-e12-end-manifest" "writer/validator script missing: $script"
  elif [[ ! -x "$script" ]]; then
    _red "wave-e-e12-end-manifest" "$script present but not executable (chmod +x)"
  elif ! grep -q -- '--self-test' "$script"; then
    _red "wave-e-e12-end-manifest" "$script has no --self-test entrypoint"
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

- **RED condition:** schema missing/invalid JSON, or script missing /
  non-executable / lacking `--self-test`.
- **GREEN when:** all four sub-checks pass.
- **Fixture for a synthetic RED:** `cp end-manifest.sh /tmp/red.sh && chmod -x
  /tmp/red.sh` — predicate must RED on that copy.

## Predicate 2 — manifest-scoping wiring in work-integrity-gate.sh

The manifest-scoping fix (this task's core deliverable) lives inside
`work-integrity-gate.sh` itself (that file is shared with task E.11 — same
builder cluster this wave). This predicate confirms the scoping function
exists and is actually CALLED from `_wig_main`, not just defined-and-orphaned.

```bash
check_wave_e_e12_manifest_scoping_wired() {
  local repo_root="$1"
  local wig="${repo_root}/adapters/claude-code/hooks/work-integrity-gate.sh"
  [[ -f "$wig" ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  if ! grep -q '_wig_manifest_touched_plans' "$wig"; then
    _red "wave-e-e12-manifest-scoping" "work-integrity-gate.sh has no _wig_manifest_touched_plans function -- manifest scoping (ADR 059 D6) not implemented"
  elif ! grep -q '_wig_resolve_manifest_path' "$wig"; then
    _red "wave-e-e12-manifest-scoping" "work-integrity-gate.sh defines manifest-touched-plans but has no _wig_resolve_manifest_path -- scoping function exists but cannot be reached"
  else
    # Confirm it's actually CALLED (not just defined) inside _wig_main.
    if ! awk '/^_wig_main\(\) \{/,/^\}/' "$wig" | grep -q '_wig_manifest_touched_plans\|_wig_resolve_manifest_path'; then
      _red "wave-e-e12-manifest-scoping" "manifest-scoping functions defined but never called from _wig_main -- orphaned code, not wired"
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

- **RED condition:** either function missing, or defined-but-never-called
  from `_wig_main` (the orphaned-code class of defect).
- **GREEN when:** both functions present and at least one is referenced
  inside `_wig_main`'s body.

## Predicate 3 (informational, not RED/GREEN gated) — manifest entry present

`manifest-entry.json` in this directory is the fragment the orchestrator
merges into `adapters/claude-code/manifest.json` at §E.W (kind: `writer`,
since `end-manifest.sh` itself never blocks — see that file's
`_fragment_note`).

## World-state assertion sweep — grep proof (Done-when requirement)

The spec requires: "grep the surviving Stop chain for transcript-derived
plan-touch/world-state logic; relocate each hit to digest/doctor/CI." The
**surviving Stop chain** (post-§E.W, 4 entries) is: `stop-verdict-dispatcher.sh`
(replaces the three collapsed gates), `workstreams-stop-writer.sh`,
`signal-ledger-flush.sh`, `session-wrap.sh refresh`.

Grep evidence recorded 2026-07-04 (this task):

```bash
$ grep -n "docs/plans\|plan-touch\|touched.plan" adapters/claude-code/hooks/workstreams-stop-writer.sh
(no output)

$ grep -n "docs/plans\|plan-touch\|touched.plan" adapters/claude-code/hooks/signal-ledger-flush.sh
(no output)

$ grep -n "docs/plans\|plan-touch\|touched.plan\|transcript_path" adapters/claude-code/scripts/session-wrap.sh
108:    | grep -E '^R[0-9]*\s+docs/plans/[^/]+\.md\s+docs/plans/archive/[^/]+\.md$' \
116:  if ! ls "$repo/docs/plans"/*.md >/dev/null 2>&1; then
...
204:  touched=$(plans_touched_this_session "$wt_repo")
```

**Disposition of the ONE hit (session-wrap.sh):** this is NOT the
transcript-derived world-state pattern the sweep targets. It derives
"touched" from `git log --since=4h` ARCHIVE-MOVE renames (not transcript
tool_use parsing), and the assertion it makes is "did THIS SESSION's own
SCRATCHPAD.md mention the plan it just archived" — a session-scoped
self-consistency invariant (ADR 059 D3's explicitly-permitted category: "Stop
gates assert what THIS SESSION did"), never a claim about the plan's own
completion/world-state (e.g. "are this plan's tasks done"). No fix needed
here; this is already D3-compliant by a different (and pre-existing,
non-transcript) mechanism.

**The ONE actual world-state-assertion hit requiring relocation** was
`work-integrity-gate.sh` checks (a)/(b) — NOT itself a member of the 4-entry
survivor list post-§E.W (it collapses into `stop-verdict-dispatcher.sh`), but
its transcript-derived plan-touch scoping is exactly the golden
counterexample named in the spec (NL-FINDING-019). This task's fix: manifest
scoping (see Predicate 2 above) REPLACES the transcript-derived derivation
_inside that same file_ whenever a session end-manifest exists, with the
transcript fallback preserved for manifest-less sessions (so this is
additive, not a breaking change for any session that never writes a
manifest — see the self-test's own regression coverage: 40 pre-existing
scenarios all still green after the change, plus 3 new manifest-scoping
scenarios).

**stop-verdict-dispatcher.sh itself** (task E.11, same builder) has no
INDEPENDENT plan-touch logic of its own — it only invokes the three member
gates in `--report` mode and aggregates their JSON output; grep-confirmed
(`grep -n "docs/plans\|plan-touch\|touched.plan" hooks/stop-verdict-dispatcher.sh`
returns only self-test fixture setup lines, e.g. `mkdir -p "$REPO/docs/plans"`
for synthetic test repos — no production-path logic).

**Conclusion:** the sweep found exactly one class of hit requiring a fix
(work-integrity-gate.sh's transcript-derived plan-touch scoping), it is now
fixed via manifest scoping, and the NL-FINDING-019 golden scenario passes
WITHOUT a waiver under manifest scoping (see `end-manifest.sh --self-test`
scenario 6, and `work-integrity-gate.sh --self-test` scenario 23 — both
green).
