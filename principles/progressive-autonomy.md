# Progressive Autonomy: Trust That Grows With Its Host

## What This Principle Covers

How the system earns increasing autonomy through demonstrated reliability. The goal is full autonomous operation with minimal human check-ins — but trust must be earned, not assumed. This document defines the autonomy ladder, trust accumulation model, and the hard limits that never relax.

## The Autonomy Spectrum

Most AI coding systems operate at a fixed autonomy level. Neural Lace operates on a spectrum that shifts based on track record:

### Level 1: Guided
- Every significant action requires confirmation
- All commits reviewed before execution
- All pushes require explicit approval
- Suitable for: new projects, new tools, after incidents

### Level 2: Supervised
- Read operations and local edits auto-allowed
- Commits and pushes require confirmation
- Destructive operations blocked
- Suitable for: established projects with some history

### Level 3: Collaborative
- Most development actions auto-allowed
- Pushes to feature branches auto-allowed
- Pushes to main/protected branches require confirmation
- Destructive operations require confirmation
- Suitable for: mature projects with strong test coverage

### Level 4: Autonomous
- All standard development workflow auto-allowed
- Deploy and publish actions require confirmation
- Only irreversible or high-sensitivity actions need human input
- System proactively proposes improvements and executes after brief approval
- Suitable for: projects with comprehensive eval suites and CI/CD

### Level 5: Fully Autonomous
- System designs, builds, tests, and deploys with minimal human input
- Human provides goals and constraints; system handles execution
- Check-ins happen at milestones, not at each action
- Hard blocks still enforce on irreversible sensitive operations
- Suitable for: maximum trust, comprehensive safety net, mature eval coverage

## Trust Accumulation Model

### Trust Score

A floating-point value from 0.0 to 1.0 per project per tool combination.

**Starting trust**: 0.3 (Level 2: Supervised)

**Trust → Autonomy mapping**:
| Trust Range | Autonomy Level |
|-------------|---------------|
| 0.0 - 0.2 | Level 1: Guided |
| 0.2 - 0.4 | Level 2: Supervised |
| 0.4 - 0.6 | Level 3: Collaborative |
| 0.6 - 0.8 | Level 4: Autonomous |
| 0.8 - 1.0 | Level 5: Fully Autonomous |

### Trust-Building Events

| Event | Delta | Rationale |
|-------|-------|-----------|
| Session completes, no incidents | +0.02 | Consistent safe operation |
| User confirms T2 action (system correctly identified risk) | +0.005 | Calibrated risk assessment |
| Session with 50+ actions, 0 blocks | +0.03 | Extended autonomous operation |
| Pre-commit quality gates pass first try | +0.01 | Clean development cycle |
| Deploy succeeds and passes post-deploy validation | +0.02 | End-to-end reliability |
| Golden eval suite passes after changes | +0.01 | Self-verification working |

### Trust-Eroding Events

| Event | Delta | Rationale |
|-------|-------|-----------|
| User overrides T3 block | -0.10 | System was right to block; forced override |
| Credential detected in push | -0.30 | Serious security failure |
| User manually reverts AI-made change | -0.05 | AI judgment was wrong |
| Test suite fails after AI changes | -0.03 | Quality gate failure |
| 30 days of inactivity | decay to max(current - 0.1, 0.3) | Stale trust |
| New AI tool version | -0.15 | Model behavior may have changed |
| New tool added to harness | reset to 0.3 for that tool | Unknown tool capability |

### Trust Ceiling

Trust cannot exceed a ceiling determined by infrastructure maturity:

| Infrastructure | Max Trust |
|---------------|-----------|
| No tests, no CI | 0.4 (Level 2 max) |
| Tests exist, no CI | 0.6 (Level 3 max) |
| Tests + CI, no deploy validation | 0.8 (Level 4 max) |
| Tests + CI + deploy validation + eval suite | 1.0 (Level 5 possible) |

This ensures autonomy is backed by safety nets. You cannot reach Level 5 without comprehensive evaluation coverage — the system must be able to verify its own work.

## Hard Limits That Never Relax

Regardless of trust level, these actions ALWAYS require human confirmation:

1. **Credential exposure** (sensitivity = 4): Committing, logging, or transmitting secrets
2. **Public exposure**: Making repositories, packages, or data publicly accessible
3. **Account creation**: Creating accounts on external services
4. **Irreversible data operations**: Dropping tables, deleting production data, purging backups
5. **Financial transactions**: Any action involving payment or billing
6. **Security control changes**: Disabling hooks, bypassing gates, modifying permission policies

These represent one-way doors where the cost of a mistake exceeds any efficiency gain from automation.

## How Trust Transfers

- **Same project, new tool**: Trust starts at max(0.3, project_trust * 0.5). A trusted project gives a new tool a head start, but not full trust.
- **Same tool, new project**: Trust starts at max(0.3, tool_trust * 0.3). A trusted tool gets slight benefit on a new project.
- **New project, new tool**: Trust starts at 0.3 (default).
- **Trust never transfers between users**. Each person's trust ledger is independent.

## Relationship to Permission Tiers

Trust adjusts the boundaries between permission tiers (see `permission-model.md`):

At trust 0.3 (default): Standard tier boundaries apply.
At trust 1.0 (maximum): T0 expands (more auto-allows), T1 expands (more log-only), T2 shrinks (fewer confirmations). T3 boundary barely moves (hard blocks stay hard).

The effect: as trust grows, the system asks less and does more — but it never stops protecting against catastrophic actions.

## The Self-Reinforcing Loop

Progressive autonomy creates a virtuous cycle:

1. System operates safely → trust increases
2. Higher trust → fewer interruptions → more autonomous work
3. More autonomous work → more telemetry → better risk calibration
4. Better calibration → fewer false positives → higher trust
5. Higher trust → system can propose improvements → harness evolves

The inverse is also true: incidents reduce trust, which increases scrutiny, which catches more problems, which rebuilds trust on a stronger foundation.

## Measuring Autonomy

Track these metrics to evaluate autonomy health:

- **Interruption rate**: confirmations per session (should decrease over time)
- **Override rate**: how often users override blocks (should be low and stable)
- **Incident rate**: how often auto-allowed actions cause problems (should approach zero)
- **Time-to-trust**: how many sessions to reach each autonomy level
- **Trust stability**: how much trust fluctuates week-to-week (should be low)
