# Anti-Vaporware — compact
> Enforcement: the full mechanism inventory lives in `manifest.json` (one entry per gate/writer/surfacer/pattern/convention, with `hooks`, `wired_template`, `blocking`, `honest_status`). This file is not the enforcement map — the manifest is.
> Applies: always — a feature is not done until the user's actual path has been exercised at runtime.

A feature is not done until the user's actual path has been exercised at runtime. If a claimed mechanism isn't in `manifest.json`, stop and either add the entry or delete the claim — advertising hallucinated enforcement is the failure this exists to prevent.

**Residual gap (honest):** verbal vaporware in conversation is not mechanically blocked. Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. The mitigation is behavioral: every feature claim must cite file:line, and the user retains interrupt authority when they see an uncited claim.

**Decorative config control (named class):** a toggle / feature flag / setting / permission-matrix cell that renders as configurable while hardcoded logic (or nothing) governs behavior. Done-criterion: changing the control provably changes observable behavior at the GOVERNED surface, not the settings page. Renders + persists + no effect = vaporware. Shadow-mode never flipped to enforce = vaporware; a DECLARED, time-bounded shadow-mode rollout is legitimate. Registry-vs-callsite invariant + drift-check recipe: `doctrine/vaporware-prevention-full.md`.

**Pattern recognition (stop if you catch yourself):**
- "I built X and it typechecks, so task is done"
- "The code exists" as the only evidence of completion
- Describing a feature without citing the file
- Answering "yes it works" without exercising it in the current session
- Confusing "I planned this" with "I built this"
- "This should work" instead of "I verified this works"
- Marking a task complete because adjacent tasks are complete
- Skipping a runtime test because "typecheck passed"
- Rationalizing "this task is obvious, verification is overkill"
- "The toggle renders and saves, so the permission works"

The correction is always: run the command, capture the output, cite the artifact with file:line.

**Cost:** every vaporware shipment costs user trust (slow to repair), cleanup work, regression risk, and harness credibility. A runtime test is always cheaper.
