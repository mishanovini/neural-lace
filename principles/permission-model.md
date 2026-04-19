# Permission Model: Risk-Based Action Classification

## What This Principle Covers

How an AI assistant decides whether to execute, confirm, or block an action. This model replaces brittle command-pattern matching with multi-dimensional risk scoring that adapts to context, accumulates trust, and handles unknown actions gracefully.

## Core Premise

Permission decisions should be based on **what could go wrong**, not on **what the command looks like**. A `git push` to a personal branch and a `git push --force` to main are superficially similar commands with fundamentally different risk profiles.

## Risk Dimensions

Every action is scored on six orthogonal dimensions, each on a 0-4 scale:

### D1: Reversibility — Can this be undone?

| Score | Meaning | Examples |
|-------|---------|----------|
| 0 | Fully reversible / read-only | File read, git status, test run |
| 1 | Easily reversible | Local file edit (git-tracked), stashable change |
| 2 | Reversible with effort | Git commit, branch operation, config change |
| 3 | Hard to reverse | Git push, npm publish, database migration with data loss |
| 4 | Irreversible | Force push over others' work, public exposure, secret leak, production data deletion |

### D2: Blast Radius — How much is affected?

| Score | Meaning | Examples |
|-------|---------|----------|
| 0 | Single file, no external effect | Edit one source file |
| 1 | Multiple files in one project | Refactor touching several modules |
| 2 | Project-wide | Build system change, root config, all routes |
| 3 | Cross-project or cross-account | Push to remote, shared infrastructure, CI config |
| 4 | Public / internet-facing | Public repo, published package, production deploy |

### D3: Sensitivity — Does this touch protected data?

| Score | Meaning | Examples |
|-------|---------|----------|
| 0 | No sensitive data | Normal source code, docs, tests |
| 1 | Near sensitive data | Same directory as credentials, config files |
| 2 | Reads sensitive data | Viewing env vars, reading credential files |
| 3 | Modifies sensitive data | Editing secrets, changing auth configuration |
| 4 | Exposes sensitive data | Committing secrets, logging PII, public upload |

### D4: Authority Escalation — Does this change permissions?

| Score | Meaning | Examples |
|-------|---------|----------|
| 0 | No permission change | Normal operations |
| 1 | Local permission change | chmod on owned files |
| 2 | Project permission change | gitignore, CI config, build settings |
| 3 | Account/service permission change | Repo visibility, IAM roles, API key rotation |
| 4 | Cross-boundary escalation | Granting public access, disabling security controls |

### D5: Novelty — Has this action been seen before?

| Score | Meaning |
|-------|---------|
| 0 | Common action (100+ observations) |
| 1 | Familiar (10+ observations) |
| 2 | Uncommon (3-9 observations) |
| 3 | Rare (1-2 observations) |
| 4 | Never observed |

Novelty decays naturally as telemetry accumulates. Unknown actions start cautious and relax with experience.

### D6: Velocity — Is this part of a rapid or anomalous sequence?

| Score | Meaning |
|-------|---------|
| 0 | Normal pace, isolated action |
| 1 | Slightly elevated (3-5 similar actions in 60s) |
| 2 | Elevated (5-10 similar actions in 60s) |
| 3 | High (10+ similar, or destructive following destructive) |
| 4 | Anomalous (dramatically different from session baseline) |

## Composite Risk Score

The composite score uses a **dominant dimension with amplifiers** model:

```
base_score = max(D1, D2, D3, D4)
novelty_multiplier = 1.0 + (D5 * 0.15)
velocity_multiplier = 1.0 + (D6 * 0.1)
composite = base_score * novelty_multiplier * velocity_multiplier
```

Design rationale:
- A single high-risk dimension is sufficient to flag an action (max, not average)
- Unknown things are treated more cautiously (novelty amplifies)
- Rapid sequences of similar actions get extra scrutiny (velocity amplifies)
- A known safe action at high velocity is still safe (0 * anything = 0)

## Permission Tiers

| Tier | Score Range | Response | User Experience |
|------|------------|----------|-----------------|
| **T0: Silent Allow** | 0.0 - 1.0 | Execute immediately | No interruption |
| **T1: Log & Allow** | 1.1 - 2.5 | Execute, log prominently | Brief status message |
| **T2: Confirm** | 2.6 - 4.0 | Pause, show risk summary, wait for approval | Inline confirmation |
| **T3: Block** | 4.1+ | Refuse, explain why | Error with remediation |

### Override Rules

- T2: User can approve. Can also grant session-scoped "allow all similar" for repeated patterns.
- T3: User can override with explicit authorization in the current message. Each override is logged and counts against trust.
- **Hard blocks** (sensitivity = 4): Never relaxed by trust or session-scoped rules. Each instance requires fresh confirmation. Secret exposure is always a one-way door.

## Trust Adjustment

Trust (0.0 to 1.0) adjusts tier boundaries:

```
effective_threshold = base_threshold - (trust * tier_flexibility)
```

At maximum trust, more actions auto-allow and fewer require confirmation — but hard blocks never move. See `progressive-autonomy.md` for the full trust model.

## Handling Unknown Actions

When no explicit risk profile matches:

1. **Classifier chain**: Walk fallback classifiers in order. First match wins.
2. **Dynamic sub-classifiers**: For dimensions marked "inherit" or "classify_path" or "classify_args", invoke sub-classifiers that check paths against sensitive patterns or scan arguments for tokens/credentials.
3. **Novelty injection**: Unknown actions get D5=4, amplifying the composite score.
4. **Fallback**: If nothing matches, default to R=2, B=2, S=1, A=1 with novelty=4 → composite ~3.2 → T2 (confirm). Unknown actions default to asking the user.
5. **Learning**: After 5 consistent user confirmations for the same pattern, propose a new profile.

## Dual-Run Migration

When transitioning from pattern-based to risk-based permissions:

1. Both systems run simultaneously — pattern hooks enforce, risk engine logs
2. Telemetry captures disagreements between the two systems
3. After N sessions with zero disagreements for a profile, that profile "graduates" — the pattern hook is removed
4. Pattern hooks remain as fallback if the risk engine crashes or times out

Never rip out working enforcement to install a new model. Run both, measure, graduate incrementally.

## Telemetry Contract

Every permission decision emits a telemetry event containing:
- Action descriptor (tool, command prefix, matched profile)
- Risk dimensions (all 6 scores)
- Composite score and trust level at decision time
- Tier and decision (allow/confirm/block)
- Whether user overrode the decision
- Decision latency

This telemetry feeds the learning loop: false positive detection, novelty decay, trust calibration, and profile proposals.
