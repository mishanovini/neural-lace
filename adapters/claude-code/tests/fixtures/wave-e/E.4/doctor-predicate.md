# E.4 doctor predicate — synthetic-runner completion + CI wiring

Per `docs/plans/nl-overhaul-program-2026-07-specs-e.md` §E.0.1 rule 3: the E.4
builder does NOT edit `harness-doctor.sh` directly; this fragment is the exact
predicate for the E.10 builder to implement verbatim.

## Predicate 1 — CI workflow file exists

```bash
test -f "$REPO_ROOT/.github/workflows/synthetic-runner.yml"
```

- **RED condition:** `.github/workflows/synthetic-runner.yml` is missing —
  the design-skip companion plan
  (`docs/plans/nl-overhaul-synthetic-ci-2026-07.md`) landed without its
  authorized artifact, or a later edit deleted the workflow.
- **GREEN when:** the file is present on disk.
- **Fixture for a synthetic RED:** point `REPO_ROOT` at a scratch copy of the
  repo tree with `.github/workflows/synthetic-runner.yml` removed; predicate
  must report RED against that copy.
  ```bash
  SCRATCH=$(mktemp -d)
  mkdir -p "$SCRATCH/.github/workflows"
  # (deliberately do NOT copy synthetic-runner.yml into $SCRATCH)
  test -f "$SCRATCH/.github/workflows/synthetic-runner.yml" && echo "unexpected GREEN" || echo "RED confirmed"
  rm -rf "$SCRATCH"
  ```

## Predicate 2 — `evals/synthetic/run-all.sh` reports 8/8 PASS, zero SKIPPED

```bash
OUT=$(bash "$REPO_ROOT/evals/synthetic/run-all.sh" 2>&1)
RC=$?
echo "$OUT" | grep -qE '^passed:  8$' \
  && echo "$OUT" | grep -qE '^failed:  0$' \
  && echo "$OUT" | grep -qE '^skipped: 0 \(deferred\)$' \
  && [[ "$RC" -eq 0 ]]
```

- **RED condition:** any of — the runner exits non-zero, `passed:` is not 8,
  `failed:` is not 0, or `skipped:` is not 0. A non-zero `skipped:` count means
  `evals/synthetic/deferred.txt` was resurrected (regression of this task's
  own Done-when — the file was deleted when the 3 previously-deferred
  scenarios landed) or a new scenario was added to `deferred.txt` without
  being built.
- **GREEN when:** the exact summary block `passed:  8` / `failed:  0` /
  `skipped: 0 (deferred)` appears and the runner's own exit code is 0.
- **Fixture for a synthetic RED:** re-create `deferred.txt` naming one
  existing scenario, confirming the runner reports a nonzero skip count
  against that fixture, then remove the fixture (never leave a stray
  `deferred.txt` in the real tree — this is a scratch-only reproduction, not
  a live edit).
  ```bash
  SCRATCH=$(mktemp -d)
  cp -r "$REPO_ROOT/evals/synthetic" "$SCRATCH/synthetic"
  echo "scenario-marker-missing — synthetic RED fixture for doctor predicate 2" > "$SCRATCH/synthetic/deferred.txt"
  OUT=$(bash "$SCRATCH/synthetic/run-all.sh" 2>&1)
  echo "$OUT" | grep -qE '^skipped: 0 \(deferred\)$' && echo "unexpected GREEN" || echo "RED confirmed (skipped > 0)"
  rm -rf "$SCRATCH"
  ```

## Predicate 3 (informational, not RED/GREEN gated) — manifest entry present

`manifest-entry.json` in this directory is the fragment E.10 merges into
`adapters/claude-code/manifest.json` at §E.W. Once merged, `manifest-check.sh`
(existing tool) is the freshness oracle for "does the manifest know about
this surface" — no NEW doctor logic needed for that half; only predicates 1
and 2 above are E.4-specific additions to `harness-doctor.sh --full`.

## Scope note (what this predicate does NOT cover)

This predicate does not re-verify a LIVE GitHub Actions run (the workflow
actually going green on `ubuntu-latest` in CI) — that is CI-side proof,
outside `harness-doctor.sh`'s local-checkout remit. The companion plan's own
Closure Contract (`docs/plans/nl-overhaul-synthetic-ci-2026-07.md`) is where
the live-run URL is cited as completion evidence. Predicates 1+2 here are the
LOCAL, doctor-checkable subset: the workflow file exists, and the command it
invokes (`bash evals/synthetic/run-all.sh`) is green on this checkout right
now.
