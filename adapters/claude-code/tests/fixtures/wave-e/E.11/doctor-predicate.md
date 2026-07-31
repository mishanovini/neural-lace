# E.11 doctor predicate — stop-verdict-dispatcher + per-gate --report mode

Per `docs/plans/nl-overhaul-program-2026-07-specs-e.md` §E.0.1 rule 3: the E.11
builder does NOT edit `harness-doctor.sh` directly; this fragment is the exact
predicate for the E.10-class doctor-owning builder (or whoever lands §E.W) to
implement verbatim.

## Predicate 1 — dispatcher + all three member gates exist, are executable,
## and each supports `--report`

```bash
check_wave_e_e11_stop_verdict_dispatcher() {
  local repo_root="$1"
  local hooks_dir="${repo_root}/adapters/claude-code/hooks"
  local f

  for f in stop-verdict-dispatcher.sh work-integrity-gate.sh session-honesty-gate.sh bug-persistence-gate.sh; do
    if [[ ! -f "${hooks_dir}/${f}" ]]; then
      _red "wave-e-e11-dispatcher" "${f} missing from ${hooks_dir} -- run: bash install.sh (or restore from adapters/claude-code/hooks/)"
      continue
    fi
    if [[ ! -x "${hooks_dir}/${f}" ]]; then
      _red "wave-e-e11-dispatcher" "${f} present but not executable (chmod +x ${hooks_dir}/${f})"
    fi
  done

  for f in work-integrity-gate.sh session-honesty-gate.sh bug-persistence-gate.sh; do
    if [[ -f "${hooks_dir}/${f}" ]] && ! grep -q -- '--report' "${hooks_dir}/${f}"; then
      _red "wave-e-e11-dispatcher" "${f} has no --report mode (ADR 059 D1) -- the batched-verdict dispatcher cannot aggregate this gate's gaps"
    fi
  done

  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

- **RED conditions:** any of the four scripts missing or non-executable; any of
  the three member gates lacking a `--report` branch (grep-derived, not a live
  invocation — mirrors the manifest's own `selftest` field's grep-derived
  style).
- **GREEN when:** all four scripts present + executable, all three member
  gates contain `--report`.
- **Fixture for a synthetic RED:** copy `work-integrity-gate.sh` to a scratch
  path with its `--report` branch stripped (e.g. `sed '/--report/d'`);
  predicate must RED on that copy, GREEN on the real file.

## Predicate 2 — Stop-chain wiring (honest-status aware)

Until §E.W lands, the dispatcher is intentionally NOT wired into
`settings.json.template`'s `Stop` chain (this is documented as
`honest_status` in `manifest-entry.json`, not a defect). This predicate
therefore WARNs (not REDs) pre-§E.W, and flips to a RED check once the
manifest's `wired_template` for `stop-verdict-dispatcher` is `true` but the
template disagrees (drift, the same class `check_template_live_drift`
already catches elsewhere in this doctor).

```bash
check_wave_e_e11_stop_chain_wiring() {
  local repo_root="$1"
  local template="${repo_root}/adapters/claude-code/settings.json.template"
  local manifest="${repo_root}/adapters/claude-code/manifest.json"
  [[ -f "$template" && -f "$manifest" ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local claimed_wired
  claimed_wired=$(jq -r '.entries[] | select(.id == "stop-verdict-dispatcher") | .wired_template' "$manifest" 2>/dev/null)
  local actually_wired="false"
  grep -q 'stop-verdict-dispatcher\.sh' "$template" 2>/dev/null && actually_wired="true"

  if [[ "$claimed_wired" == "true" && "$actually_wired" == "false" ]]; then
    _red "wave-e-e11-stop-chain-wiring" "manifest claims stop-verdict-dispatcher is wired_template:true but settings.json.template does not reference stop-verdict-dispatcher.sh -- drift"
  elif [[ "$claimed_wired" != "true" && "$actually_wired" == "false" ]]; then
    _warn "wave-e-e11-stop-chain-wiring" "stop-verdict-dispatcher.sh built but not yet wired into the Stop chain -- expected pre-sec-E.W (see manifest-entry.json honest_status); orchestrator lands this at sec E.W"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}
```

- **RED condition:** manifest claims `wired_template: true` but the template
  doesn't actually reference the dispatcher (claim-vs-reality drift — the
  doctor's core mandate).
- **WARN condition (expected, pre-§E.W):** neither claims wiring nor has it —
  this is the CURRENT true state after this task, and is intentional per
  `manifest-entry.json`'s `honest_status` field.
- **GREEN when:** either the WARN case above, or both claimed AND actual
  wiring agree (post-§E.W).

## Predicate 3 (informational, not RED/GREEN gated) — manifest entry present

`manifest-entry.json` in this directory is the fragment the orchestrator
merges into `adapters/claude-code/manifest.json` at §E.W (per §E.0.1 rule 2,
this builder does not edit `manifest.json` directly). Once merged,
`manifest-check.sh` (existing tool) is the freshness oracle for "does the
manifest know about this surface."

## Notes for whoever implements these predicates

- Predicate 1's `--report` grep is deliberately a STRING match, not a
  behavioral probe — a doctor run should be fast (no subprocess spawns per
  gate); the *actual* correctness of each gate's `--report` mode is proven
  by that gate's own `--self-test` (33->40 for work-integrity, 30->37 for
  session-honesty, 8->12 for bug-persistence; see the E.11 part-1 commit).
- The dispatcher's own `--self-test` (15/15) already proves the aggregation
  mechanics end-to-end against COPIES of the three member gates inside a
  synthetic repo — the doctor predicates above are a much cheaper, static
  "is the surface present and wired" check, not a re-run of that suite.
- §E.W also needs to decide what happens to the three member gates' OWN
  pre-existing manifest entries (`bug-persistence-gate`, `work-integrity`,
  `session-honesty`) once the Stop chain no longer references them directly
  — see this fixture's `manifest-entry.json` `honest_status` field for the
  explicit call-out. This doctor-predicate deliberately does NOT prescribe
  the answer (retire vs. repoint vs. leave as-is with a note) since that is
  a §E.W integration decision, not a builder-scoped one.
