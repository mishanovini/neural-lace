# Anti-Vaporware Rule (Stub — enforcement is in hooks)

**Rule:** a feature is not done until the user's actual path has been exercised at runtime.

This file is intentionally short. The enforcement lives in hooks, not prose. If a rule below isn't backed by a hook, it's theater.

## Enforcement map (hook-backed)

Every row below points at an artifact that exists on disk. If you notice
a row whose File column doesn't resolve, STOP and either (a) create the
file or (b) delete the row. Advertising hallucinated enforcement was the
single biggest hole in the first Gen 4 pass.

| Rule | Hook / agent that enforces it | File |
|---|---|---|
| Runtime files require tests (new + modified) | `pre-commit-tdd-gate.sh` diff-symbol scan (Layer 1-2) | `~/.claude/hooks/pre-commit-tdd-gate.sh` |
| Integration tests cannot mock | `pre-commit-tdd-gate.sh` mock ban (Layer 3) | same |
| Tests cannot use trivial assertions alone | `pre-commit-tdd-gate.sh` trivial-assertion ban (Layer 4) | same |
| Plan checkboxes cannot be self-flipped | `plan-edit-validator.sh` evidence-first protocol | `~/.claude/hooks/plan-edit-validator.sh` |
| Runtime verification entries must be replayable commands | `runtime-verification-executor.sh` parser + executor | `~/.claude/hooks/runtime-verification-executor.sh` |
| Runtime verification must correspond to the feature | `runtime-verification-reviewer.sh` cross-reference hook | `~/.claude/hooks/runtime-verification-reviewer.sh` |
| Plans must have runtime verification specs | `plan-reviewer.sh` bash heuristics (invoked from pre-commit-gate) | `~/.claude/hooks/plan-reviewer.sh` |
| Plain-text manual verification is rejected | `task-verifier` agent + pre-stop-verifier Check 4 | `~/.claude/agents/task-verifier.md` |
| Session-end plan integrity sweep | `pre-stop-verifier.sh` + `plan-evidence-reviewer` agent | `~/.claude/hooks/pre-stop-verifier.sh` |
| Tool-call budget forces periodic audit | `tool-call-budget.sh` PreToolUse blocker (every 30 Edit/Write/Bash calls) | `~/.claude/hooks/tool-call-budget.sh` |
| Product Q&A claims need file:line citations | `claim-reviewer` agent + `verify-feature` skill (self-invoked, residual risk) | `~/.claude/agents/claim-reviewer.md` + `~/.claude/skills/verify-feature.md` |
| PRs with high docs/config volume but zero execution evidence are blocked | `vaporware-volume-gate.sh` PreToolUse on `gh pr create` (A8 — Gen 6) | `~/.claude/hooks/vaporware-volume-gate.sh` |
| First-message goal extraction with checksummed integrity (tamper-detected; covers UNHONORED user goals) | `goal-extraction-on-prompt.sh` UserPromptSubmit + `goal-coverage-on-stop.sh` Stop hook (A1 — Gen 6) | `~/.claude/hooks/goal-extraction-on-prompt.sh` + `~/.claude/hooks/goal-coverage-on-stop.sh` |
| Builder commits cannot extend scope beyond plan's declared `## Files to Modify/Create` section | `scope-enforcement-gate.sh` PreToolUse Bash blocker on `git commit` | `~/.claude/hooks/scope-enforcement-gate.sh` |
| Mode: design plans must show inline arithmetic for any comparative quantitative claim | `plan-reviewer.sh` Check 9 — comparative-phrase + paragraph-window arithmetic detection (FM-013 / FM-014) | `~/.claude/hooks/plan-reviewer.sh` |
| Tier 3+ plans cannot dispatch first Task invocation without DAG-approval waiver | `dag-review-waiver-gate.sh` PreToolUse Task blocker (per-session marker after first allow) | `~/.claude/hooks/dag-review-waiver-gate.sh` |
| Mid-process discovery capture | `bug-persistence-gate.sh` extended Stop hook accepts `docs/discoveries/YYYY-MM-DD-*.md` | `~/.claude/hooks/bug-persistence-gate.sh` + `~/.claude/rules/discovery-protocol.md` |
| Pending discoveries surfaced at session start | `discovery-surfacer.sh` SessionStart hook | `~/.claude/hooks/discovery-surfacer.sh` |

**Missing from the enforcement map (explicitly acknowledged as gaps):**
- `test-quality-reviewer` as a separate agent does NOT exist. The trivial-assertion ban lives inside `pre-commit-tdd-gate.sh` Layer 4. Test quality is not reviewed adversarially outside the gate.
- PostMessage verification for verbal vaporware does NOT exist. `claim-reviewer` is self-invoked and can be skipped.
- **`tool-call-budget.sh --ack` attestation is bypassable by direct file write.** The hook greps for `REVIEW COMPLETE` + `VERDICT:` sentinel lines in a fresh file under `~/.claude/state/reviews/`. A builder could Write that file directly without invoking `plan-evidence-reviewer`. Friction is raised (the bypass requires knowing the sentinel format and writing a plausible review body) but not cryptographically closed. Closing this requires either per-session HMAC signing the agent knows but the builder cannot easily extract, or Claude Code architectural support for observing Task-tool invocations. Accepted residual risk for Gen 4.

## Residual gap (honest)

**Verbal vaporware in conversation is not mechanically blocked.** Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. This is the single unclosed gap from Generation 4. The mitigation is behavioral: every feature claim must cite file:line, and the user retains interrupt authority when they see an uncited claim.

## Pattern recognition (stop if you catch yourself)

- "I built X and it typechecks, so task is done"
- "The code exists" as the only evidence of completion
- Describing a feature without citing the file
- Answering "yes it works" without exercising it in the current session
- Confusing "I planned this" with "I built this"
- "This should work" instead of "I verified this works"
- Marking a task complete because adjacent tasks are complete
- Skipping a runtime test because "typecheck passed"
- Rationalizing "this task is obvious, verification is overkill"

The correction is always: run the command, capture the output, cite the artifact.

## Cost

Every vaporware shipment costs user trust (slow to repair), cleanup work, regression risk, and harness credibility. A Playwright test is always cheaper.
