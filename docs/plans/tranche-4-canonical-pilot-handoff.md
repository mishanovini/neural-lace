# Tranche 4 (canonical pilot) — Handoff doc

**Status:** HANDOFF — needs user decisions before any session can proceed.
**Authored:** 2026-05-06 by the autonomous Build Doctrine continuation session that shipped Tranches 2, 3, and 6-scaffolding.
**Reads:** `docs/build-doctrine-roadmap.md` Tranche 4 entry + this doc.

---

This is the structural wall I (the autonomous session) cannot cross alone. Tranche 4 — running the canonical pilot project end-to-end through the doctrine — requires several decisions only you can make. They're listed below in priority order, with what I need vs. what I can do once each is resolved.

## What needs to be true before any session can start Tranche 4

### 1. Pilot project identity (you decide)

The roadmap names "the canonical pilot project" but doesn't (correctly, harness-hygiene) say which project. This session does not know which project you intend.

**What I need from you:** the pilot project's identity. Either:
- Tell me in chat ("It's `<project-name>`, in `~/claude-projects/<org>/<project>/`").
- Edit this file with the pilot's name + path + repo URL.
- Or declare it in a new ADR (`docs/decisions/NNN-canonical-pilot-identity.md`) so the audit trail is intact.

Once known, downstream sessions can navigate to the pilot's repo and read its current state.

### 2. Pilot readiness assessment (you decide)

Per `08-project-bootstrapping.md`: "real product, real users in flight, harness mature enough to absorb doctrine layer." I cannot assess this — it's your judgment about the pilot's current shape and the team's bandwidth.

**What I need from you:** explicit confirmation that the pilot is at the right point in its lifecycle for doctrine application. Risk classes that should make you pause:
- Pilot is mid-launch (no time for structural rework).
- Pilot has 0 users (premature; the doctrine's value is empirical signal from real workflows).
- Pilot's team has bandwidth constraints (doctrine adoption is multi-day work, not a side task).

If any of these apply, defer Tranche 4 and revisit when ready. Tranches 5, 7, and 6 propagation-engine all wait on this signal.

### 3. Cross-repo access (logistics)

This Build Doctrine repo is at `~/claude-projects/neural-lace/`. The pilot project lives elsewhere. Tranche 4 work happens in BOTH repos:
- The pilot's repo: bootstrap state, conventions, design system, etc. authored per the doctrine + templates this session shipped.
- This repo: doctrine + templates revised based on observed friction.

**What I need from you:** confirmation that a Tranche 4 session can write to the pilot's repo (account permissions, branch protection, etc.). For account-switching: NL's harness auto-switches GitHub auth based on `~/claude-projects/<org>/` directory; the pilot project's directory should be set up correctly already, but verify before starting.

### 4. Python-equipped environment (logistics — for Tranche 6 scaffolding validation)

The Tranche 6 scaffolding shipped today (`build-doctrine-orchestrator/`) is correct-by-inspection only — no Python in this session's environment. Before any extension of the orchestrator (real builder-spawn integration, propagation engine, cross-tranche integration), the scaffolding must be validated.

**What I need from you (or from the next Tranche-6 session):** a Python 3.11+ environment available to a Claude Code session. Steps when validating:

```bash
cd ~/claude-projects/neural-lace/build-doctrine-orchestrator
pip install -e ".[dev]"
python -m py_compile src/build_doctrine_orchestrator/*.py tests/*.py
mypy src tests
ruff check src tests
pytest -v
```

All four steps must exit clean. If any fails, surface here BEFORE further Tranche 6 work proceeds.

If you don't have a Python environment locally on the same machine as this Claude Code install, options:
- Install Python 3.11+ (winget on Windows: `winget install Python.Python.3.12`).
- Use a cloud-remote (`claude --remote`) session — the cloud VM has Python.
- Use the canonical pilot project's existing Python environment (if it's a Python project) for cross-validation.

---

## What is ready for the Tranche 4 session to consume

When you (or whoever picks up Tranche 4) starts that session, the following substrate is in place + waiting:

| Substrate | Path | Status |
|---|---|---|
| Doctrine docs (8) | `build-doctrine/doctrine/` | ✅ shipped Tranche 0b |
| Template schemas (7) | `build-doctrine/template-schemas/` | ✅ shipped Tranche 2 (today) |
| Template content (29 files) | `build-doctrine-templates/conventions/` | ✅ shipped Tranche 3 (today) |
| Orchestrator scaffolding | `build-doctrine-orchestrator/` | 🟡 shipped Tranche 6-scaffolding (today); pytest validation deferred to Tranche 4 session |
| C-mechanisms (8 first-pass) | `~/.claude/{hooks,agents,rules}/` | ✅ shipped Tranche 1 |
| Architecture-simplification arc | (archived plans) | ✅ shipped Tranche 1.5 |
| Path A operational hardening | `~/.claude/scripts/{state-summary,close-plan,session-wrap,start-plan}.sh` | ✅ shipped 2026-05-06 |

## What Tranche 4 actually does (per `08-project-bootstrapping.md` Stage 0)

1. **Karpathy test the pilot's architecture axis.** Compute → auto-research; verify behavioral → dark-factory at R5; human judgment → coding-harness with R1 default. Decide which family the pilot's primary work falls into.
2. **Generate the 7 per-project canon artifacts** for the pilot:
   - Project README profile
   - `docs/conventions.md` (from `build-doctrine-templates/conventions/`)
   - `docs/design-system.md` (UI projects only)
   - `docs/engineering-catalog.md` (work-shape inventory; populate as recurrences are observed)
   - `docs/observability.md`
   - `docs/prd.md` (project's PRD — substantive, not templated; the schema validates the shape, the substance is the team's)
   - `.bootstrap/state.yaml` (records which floors applied, which deferred, which overridden)
3. **Apply the gate stack** to actual pilot work (the reliability spine, stages 1-10 per `05-implementation-process.md`).
4. **Capture friction.** As the pilot exercises the doctrine, friction surfaces in:
   - Doctrine docs (this repo) — revise based on observation.
   - Template content (this repo) — revise based on observation.
   - C-mechanism authoring priority for Tranche 7 — pilot tells us which of the 14 second-pass mechanisms matter most.
   - Tranche 5 (knowledge-integration ritual) cadence specs — pilot tells us how often the doctrine wants to update.

## How long Tranche 4 takes

Per the roadmap: "the pilot itself is ~1 week of focused pilot-project work; doctrine revisions from findings are ~1-2 days."

The pilot work happens IN the pilot project's session, not here. This NL repo absorbs revisions when friction is documented.

## What blocks downstream tranches

| Tranche | Why it waits on Tranche 4 |
|---|---|
| **Tranche 5** (knowledge integration ritual) | Per doctrine §Q9: authoring without empirical signal risks specifying rituals that don't match how work actually unfolds. The doctrine explicitly says "build pilot first." |
| **Tranche 6 propagation engine (C12)** | Per doctrine §C12: the highest-leverage but observed-friction-prioritized mechanism. Building all 7 PT-1..PT-7 router slots cold = building infrastructure for problems we haven't observed. Pilot tells us which 1-2 actually matter. |
| **Tranche 7** (14 second-pass C-mechanisms) | Per doctrine: "prioritize from observed pilot friction. Don't attempt all 14 as a single tranche. Some C-mechanisms may never need to ship; the criterion is observed friction, not the count." |

This is why I (the autonomous session) stopped at Tranche 6-scaffolding rather than continuing through 5/7 and the full Tranche 6. Authoring those without pilot signal is the exact anti-pattern Tranche 1.5 (the architecture-simplification arc) was designed to prevent.

## Recommended pickup order when Tranche 4 begins

1. **Read this doc.** Confirm the four prerequisites (1-4 above) are resolved.
2. **Read `build-doctrine/doctrine/08-project-bootstrapping.md` Stage 0.** Refresh the Karpathy test + universal floors + bootstrap minimum.
3. **In a Python-equipped session, validate Tranche 6 scaffolding** (the four commands listed in §4 above). This unblocks all future Tranche 6 work.
4. **Navigate to the pilot project's repo.** Apply the doctrine + templates to its bootstrap.
5. **Capture friction in `docs/sessions/<date>-pilot-friction.md`** in the pilot's repo. Optionally cross-link from this repo's `docs/reviews/`.
6. **Revise this repo's doctrine + templates** based on the findings (in this repo's session, after the pilot session produces friction notes).

## Tranches 2 + 3 + 6-scaffolding completion record (2026-05-06 autonomous push)

For audit trail. All shipped + closed cleanly today via `close-plan.sh` (zero `--force` invocations):

| Tranche | Plan | Tasks | Commits |
|---|---|---|---|
| 2 (template schemas) | `docs/plans/archive/build-doctrine-tranche-2-template-schemas.md` | 10/10 PASS | `4ef51d6` (schemas) + closure |
| 3 (template content) | `docs/plans/archive/build-doctrine-tranche-3-template-content.md` | 15/15 PASS | `207d76a` (content) + closure |
| 6 scaffolding | `docs/plans/archive/build-doctrine-tranche-6-orchestrator-scaffolding.md` | 9/9 PASS | (this commit) |

Total files added: 29 schemas/examples + 29 template content files + 9 Python scaffolding files + 4 plans + 4 evidence dirs + roadmap updates + CHANGELOG bumps to v0.4. ~78 new files.

The substrate for Tranche 4 is ready. Over to you for the pilot-project decisions.
